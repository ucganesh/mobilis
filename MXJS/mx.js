/** File: mx.js
*  Mobilis XMPP for Javascript Framework
*
*  This file contains just the object of framework. It is designed to be extensible 
*  with plug-ins. The core functionality is also a plugin located in the file 
*     -  mx.core.js
*  The framework also builds on top of the following essential librarys:
*     -  DOM Manipulation Framework jQuery 
*     -  Javascript BOSH client Library Strophe.js
*/

(function($) {
    if ( typeof window.MX === 'undefined') {

        /** Class: MX
         *  Prototype for the Mobilis XMPP object that holds the framework
         */
        MX = function() {

            if ( typeof $ === 'undefined' || $ !== window.jQuery) {
                console.log('jQuery Library missing');
            } else {

                this.plugins = {};

                /** Function: extend
                 *  Extends MX with the provided functionality encapsulated in the object that is passed.
                 *
                 *  The plug-in adapter of MX. Plug-in objects are used by calling MX.namespace
                 *
                 *  Parameters:
                 *    (String) namespace - Namespace for the plug-in.
                 *    (Object) object - Plug-in object that holds the functionality.
                 */
                this.extend = function(namespace, object) {
                    if ( typeof this[namespace] === 'undefined') {
                        if ( typeof this.plugins[namespace] === 'undefined' && typeof this[namespace] === 'undefined') {
                            jQuery.extend(object, this.plugins.extFN);
                            this.plugins[namespace] = object;
                            this[namespace] = this.plugins[namespace];
                            if ( typeof this[namespace].init === 'function') {
                                this[namespace].init();
                            }
                        } else {
                            console.log('The namespace ' + namespace + ' is already used.');
                        }
                    }
                };

                this.addHandlers = function() {
                    for (a in this.plugins) {
                        if ( typeof this.plugins[a].addHandlers !== 'undefined') {
                            this.plugins[a].addHandlers();
                        }
                    }
                };
            }
        };

        window.MX = new MX();

        window.MX.extFN = window.MX.plugins.extFN = {

            _cache : {},

            setConfig : function(settings) {
                window.MX.setObjectData(this.settings, settings);
                return this;
            },

            _toString : function() {
                if ( typeof this._cache['_toString'] === 'undefined') {
                    this._cache['_toString'] = '';
                    for (var k in window.MX.plugins) {
                        if (window.MX.plugins[k] === this) {
                            this._cache['_toString'] = 'MX.' + k;
                            break;
                        }
                    }
                }
                return this._cache['_toString'];
            }
        };
    }
})(jQuery);
