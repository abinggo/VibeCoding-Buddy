import AppKit
import WebKit

/// Handles the WKWebView lifecycle and bidirectional JS <-> Swift communication.
///
/// Usage:
///   let bridge = WebViewBridge(frame: rect)
///   bridge.loadPage(name: "index")        // loads Resources/web/index.html
///   bridge.sendToJS(event: "foo", data: ...) // Swift -> JS
///   bridge.delegate = self                // JS -> Swift via delegate
protocol WebViewBridgeDelegate: AnyObject {
    /// Called when JS sends an action via `window.vibe.send(action, data)`.
    func webViewBridge(_ bridge: WebViewBridge, didReceiveAction action: String, data: [String: Any])
}

class WebViewBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {

    let webView: WKWebView
    weak var delegate: WebViewBridgeDelegate?
    private let contentController: WKUserContentController

    // MARK: - Init

    init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        // Disable developer extras to remove "Reload / Inspect Element" context menu
        config.preferences.setValue(false, forKey: "developerExtrasEnabled")

        let cc = WKUserContentController()
        config.userContentController = cc
        self.contentController = cc

        webView = WKWebView(frame: frame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        super.init()

        // Use weak proxy to break WKUserContentController -> WebViewBridge retain cycle
        cc.add(WeakScriptMessageHandler(self), name: "vibe")
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Removes the message handler to break the retain cycle on teardown.
    func teardown() {
        contentController.removeScriptMessageHandler(forName: "vibe")
    }

    // MARK: - Load Pages

    /// Loads an HTML file from the bundled Resources/web/ directory.
    func loadPage(name: String) {
        let bundle = Self.resourceBundle
        // SPM copies Resources/ into the bundle; try both subdirectory layouts
        let resourceURL = bundle.url(forResource: name, withExtension: "html", subdirectory: "Resources/web")
            ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "web")
            ?? bundle.url(forResource: name, withExtension: "html")

        guard let url = resourceURL else {
            print("[WebViewBridge] Could not find \(name).html in \(bundle.bundlePath)")
            return
        }
        let webDir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: webDir)
    }

    /// Resolves the correct bundle for SPM resources.
    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    // MARK: - Swift -> JS

    /// Dispatch an event to JS handlers registered via `window.vibe.on(event, callback)`.
    func sendToJS(event: String, data: [String: Any] = [:]) {
        // JSON-encode both event name and data to prevent JS injection
        let envelope: [String: Any] = ["event": event, "data": data]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[WebViewBridge] Failed to serialize data for event: \(event)")
            return
        }
        let js = "(function(){ var e = \(jsonString); window.vibe._dispatch(e.event, e.data); })();"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[WebViewBridge] JS error for '\(event)': \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - JS -> Swift (WKScriptMessageHandler)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            print("[WebViewBridge] Received malformed message from JS")
            return
        }
        delegate?.webViewBridge(self, didReceiveAction: action, data: body)
    }

    // MARK: - WKUIDelegate (JS prompt/alert/confirm support)

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completionHandler(input.stringValue)
        } else {
            completionHandler(nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

// MARK: - Weak Proxy for WKScriptMessageHandler

/// Prevents retain cycle: WKUserContentController strongly retains its message handlers.
/// This proxy holds a weak reference back to the real handler.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var handler: WKScriptMessageHandler?

    init(_ handler: WKScriptMessageHandler) {
        self.handler = handler
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}
