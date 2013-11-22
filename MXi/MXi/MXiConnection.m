//
//  MXiConnection.m
//  MXi
//
//  Created by Richard Wotzlaw on 18.04.13.
//  Copyright (c) 2013 TU Dresden. All rights reserved.
//

#import "MXiConnection.h"

#import "MXiMultiUserChatMessage.h"
#import "XMPPRoomMemoryStorage.h"
#import "MXiBeanDelegateDictionary.h"
#import "MXiDelegateSelectorMapping.h"
#import "MXiStanzaDelegateDictionary.h"
#import "MXiServiceTypeDiscovery.h"
#import "MXiErrorDelegateDictionary.h"

@interface MXiConnection () <XMPPRoomDelegate>

@property (strong, nonatomic) NSMutableArray *connectedMUCRooms;
@property dispatch_queue_t room_queue;

- (BOOL)isIncomingIQBeanContainer:(XMPPIQ *)incomingIQ;
- (void)notifyBeanDelegates:(MXiBean<MXiIncomingBean> *)bean;
- (void)notifyStanzaDelegates:(NSXMLElement *)stanza;
- (void)notifyErrorDelegates:(NSXMLElement *)error;

@end

@implementation MXiConnection {
    __strong MXiBeanDelegateDictionary *_beanDelegateDictionary;
    __strong MXiStanzaDelegateDictionary *_stanzaDelegateDictionary;
    __strong MXiErrorDelegateDictionary *_errorDelegateDictionary;
}

+ (id)connectionWithJabberID:(NSString *)aJabberID password:(NSString *)aPassword hostName:(NSString *)aHostName port:(NSInteger)port coordinatorJID:(NSString *)theCoordinatorJID serviceNamespace:(NSString *)theServiceNamespace serviceType:(ServiceType)serviceType listeningForIncomingBeans:(NSArray *)theIncomingBeanPrototypes connectionDelegate:(id<MXiConnectionDelegate>)delegate
{
	return [[self alloc] initWithJabberID:aJabberID password:aPassword hostName:aHostName port:port coordinatorJID:theCoordinatorJID serviceNamespace:theServiceNamespace serviceType:serviceType listeningForIncomingBeans:theIncomingBeanPrototypes connectionDelegate:delegate ];
}

- (id)initWithJabberID:(NSString *)aJabberID password:(NSString *)aPassword hostName:(NSString *)aHostName port:(NSInteger)port coordinatorJID:(NSString *)theCoordinatorJID serviceNamespace:(NSString *)theServiceNamespace serviceType:(ServiceType)serviceType listeningForIncomingBeans:(NSArray *)theIncomingBeanPrototypes connectionDelegate:(id<MXiConnectionDelegate>)connectionDelegate
{
    self = [super init];
    if (self) {
        XMPPJID* tempJid = [XMPPJID jidWithString:aJabberID];
        [self setJabberID:tempJid];
        [self setPassword:aPassword];
        [self setServiceType: serviceType];
        if (aHostName && ![aHostName isEqualToString:@""]) {
            [self setHostName:aHostName];
        } else {
            [self setHostName:[tempJid domain]];
        }
        [self setPort:port];
        [self setCoordinatorJID:theCoordinatorJID];
        [self setServiceNamespace:theServiceNamespace];
        [self setIncomingBeanPrototypes:theIncomingBeanPrototypes];

        self.delegate = connectionDelegate;

        [self setupDelegateDictionaries];
        [self setupStream];
        [self connect];
    }
    return self;
}
- (void)setupDelegateDictionaries
{
    _beanDelegateDictionary = [MXiBeanDelegateDictionary new];
    _stanzaDelegateDictionary = [MXiStanzaDelegateDictionary new];
    _errorDelegateDictionary = [MXiErrorDelegateDictionary new];
}

- (BOOL)reconnectWithJabberID:(NSString *)aJabberID
					 password:(NSString *)aPassword
					 hostname:(NSString *)aHostname
						 port:(NSInteger )thePort
				   coordinatorJID:(NSString *)theCoordinatorJID
			 serviceNamespace:(NSString *)theServiceNamespace {
	[self disconnect];
	
	[self setJabberID:[XMPPJID jidWithString:aJabberID]];
	[self setPassword:aPassword];
	if (aHostname && ![aHostname isEqualToString:@""]) {
		[self setHostName:aHostname];
	}
	[self setPort:thePort];
	[self setCoordinatorJID:theCoordinatorJID];
	[self setServiceNamespace:theServiceNamespace];
	
	return [self connect];
}

#pragma mark - XEP-0045: Multi-User-Chat

- (void)connectToMultiUserChatRoom:(NSString *)roomJID
{
    if (!_connectedMUCRooms) {
        self.connectedMUCRooms = [NSMutableArray arrayWithCapacity:5];
        _room_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    }
    XMPPRoom *room = [[XMPPRoom alloc] initWithRoomStorage:[[XMPPRoomMemoryStorage alloc] init]
                                                       jid:[XMPPJID jidWithString:roomJID]
                                             dispatchQueue:_room_queue];
    [room activate:self.xmppStream];
    [room addDelegate:self delegateQueue:_room_queue];
    [room joinRoomUsingNickname:@"acdsense_bot_DG" history:nil];
}

- (void)leaveMultiUserChatRoom:(NSString *)roomJID
{
    XMPPRoom *roomToLeave = nil;
    for (XMPPRoom *room in _connectedMUCRooms) {
        if ([[room.roomJID full] isEqualToString:roomJID]) {
            [room leaveRoom];
            roomToLeave = room;
            break;
        }
    }
    [_connectedMUCRooms removeObject:roomToLeave];
}

- (void)sendMessage:(NSString *)message toRoom:(NSString *)roomJID;
{
    XMPPJID *outgoingJID = [XMPPJID jidWithString:roomJID];
    for (XMPPRoom *room in _connectedMUCRooms) {
        if ([[room.roomJID full] isEqualToString:[outgoingJID bare]]) {
            [room sendMessage:[MXiMultiUserChatMessage messageWithBody:message]];
        }
    }
}

#pragma mark - XMPPStreamDelegate

- (void)xmppStreamDidConnect:(XMPPStream* )sender {
	NSError* error = nil;
	[self.xmppStream authenticateWithPassword:self.password error:&error];
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error {
	[self.delegate connectionDidDisconnect:error];
}

- (void)xmppStreamDidAuthenticate:(XMPPStream* )sender {
	[self goOnline];
}

- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error {
    [self.delegate connectionAuthenticationFinished:error];
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq {
    [self notifyStanzaDelegates:iq];

    NSLog(@"Received iq: %@", [iq prettyXMLString]);

    // Did we get an incoming mobilis bean?
    if ([self isIncomingIQBeanContainer:iq]) {
        NSXMLElement* childElement = [iq childElement];
        for (MXiBean<MXiIncomingBean>* prototype in self.incomingBeanPrototypes) {
            if ([[[prototype class] elementName] isEqualToString:[childElement name]] &&
                    [[[prototype class] iqNamespace] isEqualToString:[childElement xmlns]] &&
                    [[MXiIQTypeLookup stringValueForIQType:[prototype beanType]]
                        isEqualToString:[iq attributeStringValueForName:@"type"]]) {
                // parse the iq data into the bean object
                [MXiBeanConverter beanFromIQ:iq intoBean:prototype];
                // inform the app about this incoming bean
                [self notifyBeanDelegates:prototype];
            }
        }
        return YES;
    }

	return YES;
}

- (BOOL)isIncomingIQBeanContainer:(XMPPIQ *)incomingIQ
{
    BOOL isBean = NO;
    NSXMLElement *childElement = [incomingIQ childElement];
    for (MXiBean<MXiIncomingBean>* prototype in self.incomingBeanPrototypes) {
        if ([[[prototype class] elementName] isEqualToString:[childElement name]] &&
                [[[prototype class] iqNamespace] isEqualToString:[childElement xmlns]] &&
                [[MXiIQTypeLookup stringValueForIQType:[prototype beanType]]
                        isEqualToString:[incomingIQ attributeStringValueForName:@"type"]]) {
            isBean = YES;
            break;
        }
    }
    return isBean;
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message {
    [self notifyStanzaDelegates:message];
}

- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence {
	[self notifyStanzaDelegates:presence];
}

- (void)xmppStream:(XMPPStream *)sender didReceiveError:(NSXMLElement *)error {
	[self notifyErrorDelegates:error];
}

/*
 * Preparing and closing the xmpp stream
 */

- (void)setupStream {
    _xmppStream = [[XMPPStream alloc] init];
	// inform this very object about stream events
	[self.xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
}

- (void)goOnline {
	XMPPPresence* presence = [XMPPPresence presence];
	[self.xmppStream sendElement:presence];

    [self.delegate connectionAuthenticationFinished:nil];
}

- (void)goOffline {
	XMPPPresence* presence = [XMPPPresence presenceWithType:@"unavailable"];
	[self.xmppStream sendElement:presence];
}

- (BOOL)connect {
	if ([self.xmppStream isConnected]) {
		return YES;
	}
	
	[self.xmppStream setMyJID:[self jabberID]];
	[self.xmppStream setHostName:[self hostName]];
    [self.xmppStream setHostPort:(UInt16) [self port]];
	
	XMPPReconnect* reconnect = [[XMPPReconnect alloc] init];
	[reconnect activate:self.xmppStream];
	
	/*
	NSLog(@"Trying to connect with:");
	NSLog(@" - myJid: %@", [xmppStream myJID]);
	NSLog(@" - myPassword: %@", password);
	NSLog(@" - hostname: %@", [xmppStream hostName]);
	NSLog(@" - port: %d", [xmppStream hostPort]);
	*/
	
	NSError* error = nil;
	if (![self.xmppStream connectWithTimeout:30.0 error:&error]) {
		NSLog(@"Couldn't connect because of error: %@", [error localizedDescription]);
		return NO;
	}
	
	return YES;
}

- (void)sendTestMessageWithContent:(NSString *)content
								to:(NSString *)to {
	NSXMLElement *body = [NSXMLElement elementWithName:@"body"];
	[body setStringValue:content];
	
	NSXMLElement *message = [NSXMLElement elementWithName:@"message"];
	[message addAttributeWithName:@"type" stringValue:@"chat"];
	[message addAttributeWithName:@"to" stringValue:to];
	[message addAttributeWithName:@"from" stringValue:[self.jabberID full]];
	[message addChild:body];
	
	[self.xmppStream sendElement:message];
}

- (void)sendElement:(NSXMLElement* )element {
	NSLog(@"Sent: %@", [element prettyXMLString]);
	
	[self.xmppStream sendElement:element];
}

- (void)sendBean:(MXiBean<MXiOutgoingBean>* )bean {
    NSAssert(bean.to != nil, @"No addresse of the outgoing bean!");
	[bean setFrom:self.jabberID];
	[self sendElement:[MXiBeanConverter beanToIQ:bean]];
}

- (void)sendBean:(MXiBean <MXiOutgoingBean> *)bean toJid:(XMPPJID *)jid
{
    [bean setTo:jid];
    [self sendBean:bean];
}

- (void)disconnect {
	[self goOffline];
	[self.xmppStream disconnect];
}

#pragma mark - Manage Bean & Stanza Delegation

- (void)addBeanDelegate:(id)delegate withSelector:(SEL)selector forBeanClass:(Class)beanClass
{
    [_beanDelegateDictionary addDelegate:delegate withSelector:selector forBeanClass:beanClass];
}

- (void)addStanzaDelegate:(id)delegate withSelector:(SEL)selector forStanzaElement:(StanzaElement)stanzaElement
{
    [_stanzaDelegateDictionary addDelegate:delegate withSelector:selector forStanzaElement:stanzaElement];
}

- (void)addErrorDelegate:(id)delegate withSelecor:(SEL)selector
{
    [_errorDelegateDictionary addErrorDelegate:delegate withSelector:selector];
}

- (void)removeBeanDelegate:(id)delegate forBeanClass:(Class)beanClass
{
    [_beanDelegateDictionary removeDelegate:delegate forBeanClass:beanClass];
}

- (void)removeStanzaDelegate:(id)delegate forStanzaElement:(StanzaElement)element
{
    [_stanzaDelegateDictionary removeDelegate:delegate forStanzaElement:element];
}

- (void)removeErrorDelegate:(id)delegate
{
    [_errorDelegateDictionary removeErrorDelegate:delegate];
}

#pragma mark - Delegate Notification

- (void)notifyBeanDelegates:(MXiBean <MXiIncomingBean> *)bean
{
    NSArray *registeredDelegates = nil;
    @synchronized (_beanDelegateDictionary) {
        registeredDelegates = [NSArray arrayWithArray:[_beanDelegateDictionary delegatesForBeanClass:[bean class]]];
    }
    for (MXiDelegateSelectorMapping *mapping in registeredDelegates) {
        if ([mapping.delegate respondsToSelector:[mapping selector]]) {
            [mapping.delegate performSelector:[mapping selector] withObject:bean]; // Warning can be ignored.
        }
    }
}

- (void)notifyStanzaDelegates:(NSXMLElement *)stanza
{
    NSArray *registeredDelegates = nil;
    StanzaElement stanzaElement = [self stanzaElementFromStanza:stanza];
    if (stanzaElement == UNKNOWN_STANZA)
        return;
    @synchronized (_stanzaDelegateDictionary) {
        registeredDelegates = [NSArray arrayWithArray:[_stanzaDelegateDictionary delegatesforStanzaElement:stanzaElement]];
    }
    for (MXiDelegateSelectorMapping *mapping in registeredDelegates) {
        if ([mapping.delegate respondsToSelector:[mapping selector]]) {
            [mapping.delegate performSelector:[mapping selector] withObject:stanza]; // Warning can be ignored.
        }
    }
}
- (StanzaElement)stanzaElementFromStanza:(NSXMLElement *)stanza
{
    if ([[stanza name] isEqualToString:@"iq"]) return IQ;
    if ([[stanza name] isEqualToString:@"message"]) return MESSAGE;
    if ([[stanza name] isEqualToString:@"presence"]) return PRESENCE;

    return UNKNOWN_STANZA;
}

- (void)notifyErrorDelegates:(NSXMLElement *)error
{
    NSArray *registeredDelegates = nil;
    @synchronized (_errorDelegateDictionary) {
        registeredDelegates = [NSArray arrayWithArray:[_errorDelegateDictionary delegates]];
    }
    for (MXiDelegateSelectorMapping *mapping in registeredDelegates) {
        if ([mapping.delegate respondsToSelector:[mapping selector]]) {
            [mapping.delegate performSelector:[mapping selector] withObject:error];
        }
    }
}

#pragma mark - XMPPRoomDelegate

- (void)xmppRoomDidJoin:(XMPPRoom *)sender
{
    [self.connectedMUCRooms addObject:sender];
    if (_mucDelegate && [_mucDelegate respondsToSelector:@selector(connectionToRoomEstablished:)]) {
        [_mucDelegate performSelector:@selector(connectionToRoomEstablished:) withObject:[sender.roomJID bare]];
    }
}

- (void)xmppRoom:(XMPPRoom *)sender didReceiveMessage:(XMPPMessage *)message fromOccupant:(XMPPJID *)occupantJID
{
    if (_mucDelegate && [_mucDelegate respondsToSelector:@selector(didReceiveMultiUserChatMessage:fromUser:publishedInRoom:)]) {
        [_mucDelegate didReceiveMultiUserChatMessage:[[message elementForName:@"body"] stringValue]
                                            fromUser:occupantJID.full
                                     publishedInRoom:sender.roomJID.full];
    }
}

- (void)xmppRoom:(XMPPRoom *)sender occupantDidJoin:(XMPPJID *)occupantJID withPresence:(XMPPPresence *)presence
{
    if (_mucDelegate && [_mucDelegate respondsToSelector:@selector(userWithJid:didJoin:room:)]) {
        [_mucDelegate userWithJid:occupantJID.full didJoin:presence.status room:[sender.roomJID full]];
    }
}

- (void)xmppRoom:(XMPPRoom *)sender occupantDidLeave:(XMPPJID *)occupantJID withPresence:(XMPPPresence *)presence
{
    if (_mucDelegate && [_mucDelegate respondsToSelector:@selector(userWithJid:didLeaveRoom:)]) {
        [_mucDelegate userWithJid:occupantJID.full didLeaveRoom:[sender.roomJID full]];
    }
}

- (void)xmppRoom:(XMPPRoom *)sender occupantDidUpdate:(XMPPJID *)occupantJID withPresence:(XMPPPresence *)presence
{
    if (_mucDelegate && [_mucDelegate respondsToSelector:@selector(userWithJid:didUpdate:inRoom:)]) {
        [_mucDelegate userWithJid:occupantJID.full didUpdate:presence.status inRoom:[sender.roomJID full]];
    }
}

@end
