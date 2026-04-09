import AppKit

class AppDelegate: NSObject, NSApplicationDelegate,
                   WebViewBridgeDelegate, HookServerDelegate,
                   SessionMonitorDelegate, MenuBarControllerDelegate {

    // MARK: - Properties

    private var panel: NotchPanel?
    private var bridge: WebViewBridge?
    private var hookServer: HookServer?
    private var sessionMonitor: SessionMonitor?
    private var menuBar: MenuBarController?
    private var statsReader: StatsReader?

    private var dashboardWindow: NSWindow?
    private var dashboardBridge: WebViewBridge?

    /// Tracks pending PreToolUse approval callbacks keyed by UUID.
    private var pendingApprovals: [String: (Data) -> Void] = [:]

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotchPanel()
        setupHookServer()
        setupSessionMonitor()
        self.statsReader = StatsReader()

        print("[VibeBuddy] Ready — all systems go")
    }

    // MARK: - Setup

    private func setupMenuBar() {
        let mb = MenuBarController()
        mb.delegate = self
        mb.setup()
        self.menuBar = mb
    }

    private func setupNotchPanel() {
        guard let panel = NotchPanel.create() else {
            print("[VibeBuddy] Failed to create NotchPanel")
            return
        }
        self.panel = panel

        let bridge = WebViewBridge(frame: panel.contentView!.bounds)
        bridge.delegate = self
        self.bridge = bridge

        panel.contentView = bridge.webView
        panel.orderFrontRegardless()
        bridge.loadPage(name: "index")

        // Wire panel expand/collapse -> web UI
        NotificationCenter.default.addObserver(
            forName: NotchPanel.didExpandNotification, object: nil, queue: .main
        ) { [weak bridge] _ in bridge?.sendToJS(event: "expand") }

        NotificationCenter.default.addObserver(
            forName: NotchPanel.didCollapseNotification, object: nil, queue: .main
        ) { [weak bridge] _ in bridge?.sendToJS(event: "collapse") }
    }

    private func setupHookServer() {
        // Install hooks into Claude Code settings
        let installer = HookInstaller()
        installer.installIfNeeded()

        let server = HookServer()
        server.delegate = self
        self.hookServer = server

        do {
            try server.start()
        } catch {
            print("[VibeBuddy] Hook server failed to start: \(error)")
        }
    }

    private func setupSessionMonitor() {
        let monitor = SessionMonitor()
        monitor.delegate = self
        monitor.start()
        self.sessionMonitor = monitor
    }

    // MARK: - Dashboard

    private func openDashboard() {
        if let existing = dashboardWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vibe Buddy Dashboard"
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1)
        window.isReleasedWhenClosed = false
        window.center()

        let db = WebViewBridge(frame: window.contentView!.bounds)
        db.delegate = self
        window.contentView = db.webView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        db.loadPage(name: "dashboard")
        self.dashboardWindow = window
        self.dashboardBridge = db

        // Send stats after page loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendStatsToDashboard()
        }
    }

    private func sendStatsToDashboard() {
        guard let data = statsReader?.dashboardJSON() else { return }
        dashboardBridge?.sendToJS(event: "statsUpdate", data: data)
    }

    // MARK: - WebViewBridgeDelegate

    func webViewBridge(_ bridge: WebViewBridge, didReceiveAction action: String, data: [String: Any]) {
        switch action {
        case "ready":
            print("[VibeBuddy] Web UI ready (\(bridge === self.bridge ? "notch" : "dashboard"))")

        case "dashboardReady":
            sendStatsToDashboard()

        case "agentClicked":
            handleAgentClicked(data)

        case "approve":
            handleApprovalResponse(data, decision: "allow")

        case "deny":
            handleApprovalResponse(data, decision: "deny")

        case "setTheme":
            if let theme = data["theme"] as? String {
                UserDefaults.standard.set(theme, forKey: "selectedTheme")
                self.bridge?.sendToJS(event: "setTheme", data: ["theme": theme])
            }

        default:
            print("[VibeBuddy] Unhandled JS action: \(action)")
        }
    }

    // MARK: - HookServerDelegate

    func hookServer(_ server: HookServer, didReceive event: HookEvent, respond: @escaping (Data) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if event.hookType == "PreToolUse" {
                let approvalId = UUID().uuidString
                self.pendingApprovals[approvalId] = respond

                // Auto-expand the notch panel to show the approval UI
                self.panel?.expand()

                self.bridge?.sendToJS(event: "approvalRequest", data: [
                    "approvalId": approvalId,
                    "toolName": event.payload["tool_name"] as? String ?? "Unknown",
                    "toolInput": event.payload["tool_input"] as? [String: Any] ?? [:],
                    "sessionId": event.sessionId
                ])

                // Timeout: auto-allow after 30 seconds if no response
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    if let respond = self?.pendingApprovals.removeValue(forKey: approvalId) {
                        respond("{}".data(using: .utf8)!)
                        self?.bridge?.sendToJS(event: "approvalTimeout", data: ["approvalId": approvalId])
                    }
                }
            } else {
                self.bridge?.sendToJS(event: "hookEvent", data: [
                    "type": event.hookType,
                    "sessionId": event.sessionId,
                    "payload": event.payload
                ])
                respond("{}".data(using: .utf8)!)
            }
        }
    }

    // MARK: - SessionMonitorDelegate

    func sessionMonitor(_ monitor: SessionMonitor, didUpdateSessions sessions: [AgentSession]) {
        let agentData: [[String: Any]] = sessions.map { session in
            [
                "sessionId": session.sessionId,
                "pid": session.pid,
                "cwd": session.cwd,
                "name": session.name ?? "Claude Code",
                "startedAt": session.startedAt,
                "status": "working"
            ]
        }
        bridge?.sendToJS(event: "agentsUpdate", data: ["agents": agentData])
    }

    // MARK: - MenuBarControllerDelegate

    func menuBarDidSelectTogglePanel() {
        if panel?.isVisible ?? false {
            panel?.orderOut(nil)
        } else {
            panel?.orderFrontRegardless()
        }
    }

    func menuBarDidSelectDashboard() {
        openDashboard()
    }

    func menuBarDidSelectQuit() {
        hookServer?.stop()
        sessionMonitor?.stop()
        HookInstaller().uninstall()
        NSApp.terminate(nil)
    }

    // MARK: - Private Handlers

    private func handleAgentClicked(_ data: [String: Any]) {
        guard let sessionId = data["sessionId"] as? String,
              let session = sessionMonitor?.activeSessions.first(where: { $0.sessionId == sessionId }) else {
            return
        }
        bridge?.sendToJS(event: "showAgentDetail", data: [
            "sessionId": session.sessionId,
            "name": session.name ?? "Claude Code",
            "cwd": session.cwd,
            "startedAt": session.startedAt,
            "pid": session.pid,
            "kind": session.kind
        ])
    }

    private func handleApprovalResponse(_ data: [String: Any], decision: String) {
        guard let approvalId = data["approvalId"] as? String,
              let respond = pendingApprovals.removeValue(forKey: approvalId) else { return }

        let response: [String: Any]
        if decision == "deny" {
            response = ["decision": "block", "reason": "Denied via Vibe Buddy"]
        } else {
            response = [:]  // Empty = allow
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: response) {
            respond(jsonData)
        } else {
            respond("{}".data(using: .utf8)!)
        }
    }
}
