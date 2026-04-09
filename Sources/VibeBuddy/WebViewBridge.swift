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

class WebViewBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    let webView: WKWebView
    weak var delegate: WebViewBridgeDelegate?

    // MARK: - Init

    init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let contentController = WKUserContentController()
        config.userContentController = contentController

        webView = WKWebView(frame: frame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        super.init()

        contentController.add(self, name: "vibe")
        webView.navigationDelegate = self
    }

    // MARK: - Load Pages

    /// Loads an HTML file from the bundled Resources/web/ directory.
    func loadPage(name: String) {
        guard let resourceURL = Bundle.main.url(
            forResource: name,
            withExtension: "html",
            subdirectory: "Resources/web"
        ) else {
            print("[WebViewBridge] Could not find \(name).html in bundle")
            return
        }
        let webDir = resourceURL.deletingLastPathComponent()
        webView.loadFileURL(resourceURL, allowingReadAccessTo: webDir)
    }

    // MARK: - Swift -> JS

    /// Dispatch an event to JS handlers registered via `window.vibe.on(event, callback)`.
    func sendToJS(event: String, data: [String: Any] = [:]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[WebViewBridge] Failed to serialize data for event: \(event)")
            return
        }
        let js = "window.vibe._dispatch('\(event)', \(jsonString));"
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
}
