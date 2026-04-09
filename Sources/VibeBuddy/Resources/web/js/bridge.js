/**
 * bridge.js — JS <-> Swift communication layer
 *
 * Swift -> JS: calls window.vibe._dispatch(event, data)
 * JS -> Swift: calls window.webkit.messageHandlers.vibe.postMessage(...)
 */
window.vibe = {
    /** @type {Object<string, Function[]>} */
    _handlers: {},

    /**
     * Send a message to the Swift host.
     * @param {string} action - Action identifier
     * @param {Object} [data] - Optional payload
     */
    send: function(action, data) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vibe) {
            window.webkit.messageHandlers.vibe.postMessage(
                Object.assign({ action: action }, data || {})
            );
        } else {
            console.warn('[bridge] No Swift host available, action:', action);
        }
    },

    /**
     * Register a handler for events dispatched from Swift.
     * @param {string} event - Event name
     * @param {Function} callback - Handler function receiving data object
     */
    on: function(event, callback) {
        if (!this._handlers[event]) this._handlers[event] = [];
        this._handlers[event].push(callback);
    },

    /**
     * Remove all handlers for an event.
     * @param {string} event
     */
    off: function(event) {
        delete this._handlers[event];
    },

    /**
     * Called by Swift via evaluateJavaScript to dispatch events to JS handlers.
     * @param {string} event
     * @param {Object} data
     */
    _dispatch: function(event, data) {
        var handlers = this._handlers[event] || [];
        for (var i = 0; i < handlers.length; i++) {
            try {
                handlers[i](data);
            } catch (e) {
                console.error('[bridge] Handler error for event:', event, e);
            }
        }
    }
};
