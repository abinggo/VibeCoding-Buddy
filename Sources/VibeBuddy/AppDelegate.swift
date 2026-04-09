import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, WebViewBridgeDelegate {

    // MARK: - Properties

    var panel: NotchPanel?
    var bridge: WebViewBridge?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupNotchPanel()
        print("[VibeBuddy] Ready")
    }

    // MARK: - Setup

    private func setupNotchPanel() {
        guard let panel = NotchPanel.create() else {
            print("[VibeBuddy] Failed to create NotchPanel — no screen available")
            return
        }
        self.panel = panel

        let bridge = WebViewBridge(frame: panel.contentView!.bounds)
        bridge.delegate = self
        self.bridge = bridge

        panel.contentView = bridge.webView
        panel.orderFrontRegardless()
        bridge.loadPage(name: "index")

        // Wire panel expand/collapse to web UI
        NotificationCenter.default.addObserver(
            forName: NotchPanel.didExpandNotification, object: nil, queue: .main
        ) { [weak bridge] _ in bridge?.sendToJS(event: "expand") }

        NotificationCenter.default.addObserver(
            forName: NotchPanel.didCollapseNotification, object: nil, queue: .main
        ) { [weak bridge] _ in bridge?.sendToJS(event: "collapse") }
    }

    // MARK: - WebViewBridgeDelegate

    func webViewBridge(_ bridge: WebViewBridge, didReceiveAction action: String, data: [String: Any]) {
        switch action {
        case "ready":
            print("[VibeBuddy] Web UI ready")
        default:
            print("[VibeBuddy] Unhandled JS action: \(action)")
        }
    }
}
