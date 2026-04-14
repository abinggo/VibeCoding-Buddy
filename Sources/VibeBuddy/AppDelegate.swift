import AppKit

class AppDelegate: NSObject, NSApplicationDelegate,
                   WebViewBridgeDelegate, HookServerDelegate,
                   SessionMonitorDelegate, MenuBarControllerDelegate,
                   NSWindowDelegate {

    // MARK: - Properties

    private var panel: NotchPanel?
    private var bridge: WebViewBridge?
    private var hookServer: HookServer?
    private var sessionMonitor: SessionMonitor?
    private var menuBar: MenuBarController?
    private var statsReader: StatsReader?
    private var liveStats: LiveStats?

    private var dashboardWindow: NSWindow?
    private var dashboardBridge: WebViewBridge?
    /// True once the notch bubble web UI has sent "ready".
    private var bubbleUIReady = false

    /// Tracks pending PreToolUse approval callbacks keyed by UUID.
    private var pendingApprovals: [String: (Data) -> Void] = [:]
    /// Tracks timeout work items so they can be cancelled on approve/deny.
    private var approvalTimers: [String: DispatchWorkItem] = [:]
    /// Tracks hook-derived status per sessionId. Values: "working", "waiting"
    private var sessionStatus: [String: String] = [:]
    /// Tracks the last tool used per sessionId.
    private var sessionLastTool: [String: String] = [:]
    /// Tracks the timestamp of the last PostToolUse hook per session (for activity timeout).
    private var sessionLastActivity: [String: Date] = [:]
    /// Timer that checks for idle sessions and flips them to "waiting".
    private var activityTimer: DispatchSourceTimer?
    /// How many seconds of no PostToolUse before a session is considered "waiting".
    private let idleTimeout: TimeInterval = 30
    /// Pending Stop transitions — debounce Stop hook so brief gaps between turns don't flash "Done".
    private var pendingStopTimers: [String: DispatchWorkItem] = [:]
    /// Whether a session has had at least one tool use (vs. just UserPromptSubmit).
    private var sessionHadToolUse: [String: Bool] = [:]

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotchPanel()
        setupHookServer()
        setupSessionMonitor()
        setupActivityTimer()
        self.statsReader = StatsReader()
        self.liveStats = LiveStats()

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
            print("[VibeBuddy] Failed to create floating bubble")
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
        ) { [weak self, weak bridge] _ in
            if let panel = self?.panel, let webView = bridge?.webView {
                webView.frame = panel.contentView?.bounds ?? panel.frame
            }
            bridge?.sendToJS(event: "expand")
            // Clear badge when user opens the panel
            self?.menuBar?.clearBadge()
        }

        NotificationCenter.default.addObserver(
            forName: NotchPanel.didCollapseNotification, object: nil, queue: .main
        ) { [weak self, weak bridge] _ in
            if let panel = self?.panel, let webView = bridge?.webView {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    webView.frame = panel.contentView?.bounds ?? panel.frame
                }
            }
            bridge?.sendToJS(event: "collapse")
        }

        // Wire right-click menu actions
        NotificationCenter.default.addObserver(
            forName: NotchPanel.openDashboardNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openDashboard()
        }

        NotificationCenter.default.addObserver(
            forName: NotchPanel.quitRequestedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.menuBarDidSelectQuit()
        }
    }

    private func setupHookServer() {
        let server = HookServer()
        server.delegate = self
        self.hookServer = server

        do {
            try server.start()
        } catch {
            print("[VibeBuddy] Hook server failed to start: \(error)")
        }

        let installer = HookInstaller()
        installer.installIfNeeded(port: server.port)
    }

    private func setupSessionMonitor() {
        let monitor = SessionMonitor()
        monitor.delegate = self
        monitor.start()
        self.sessionMonitor = monitor
    }

    /// Periodically checks if any session has gone idle (no PostToolUse for `idleTimeout` seconds).
    /// If so, flips its status to "waiting" and pushes a UI update.
    private func setupActivityTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.checkActivityTimeouts()
        }
        timer.resume()
        self.activityTimer = timer
    }

    private func checkActivityTimeouts() {
        let now = Date()
        var changed = false

        for (sessionId, lastActivity) in sessionLastActivity {
            // Only timeout sessions that have had at least one tool use.
            // If only UserPromptSubmit fired, Claude is still thinking — don't timeout.
            guard sessionHadToolUse[sessionId] == true else { continue }

            if now.timeIntervalSince(lastActivity) > idleTimeout,
               sessionStatus[sessionId] != "waiting" {
                sessionStatus[sessionId] = "waiting"
                print("[VibeBuddy] Session \(sessionId.prefix(8))… idle for >\(Int(idleTimeout))s → waiting")
                changed = true
            }
        }

        if changed {
            pushAgentUpdate()
        }
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
        window.delegate = self
        window.center()

        let db = WebViewBridge(frame: window.contentView!.bounds)
        db.delegate = self
        window.contentView = db.webView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        db.loadPage(name: "dashboard")
        self.dashboardWindow = window
        self.dashboardBridge = db

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendStatsToDashboard()
        }
    }

    private func sendStatsToDashboard() {
        guard let data = liveStats?.dashboardJSON() else { return }
        dashboardBridge?.sendToJS(event: "statsUpdate", data: data)
    }

    private func sendStatsToNotch() {
        guard let live = liveStats?.dashboardJSON() else { return }
        bridge?.sendToJS(event: "statsUpdate", data: live)
    }

    // MARK: - Push agent state to JS

    /// Builds agent data from SessionMonitor + hook-tracked status and sends to JS.
    private func pushAgentUpdate() {
        guard bubbleUIReady else { return }
        guard let sessions = sessionMonitor?.activeSessions else { return }

        let activeIds = Set(sessions.map(\.sessionId))
        sessionStatus = sessionStatus.filter { activeIds.contains($0.key) }
        sessionLastTool = sessionLastTool.filter { activeIds.contains($0.key) }
        sessionLastActivity = sessionLastActivity.filter { activeIds.contains($0.key) }
        sessionHadToolUse = sessionHadToolUse.filter { activeIds.contains($0.key) }
        // Cancel pending stop timers for gone sessions
        for id in pendingStopTimers.keys where !activeIds.contains(id) {
            pendingStopTimers[id]?.cancel()
            pendingStopTimers.removeValue(forKey: id)
        }

        let agentData: [[String: Any]] = sessions.map { session in
            // Default to "idle" for newly detected sessions (no hooks received yet).
            // "working" / "waiting" are set by hooks only.
            let status = self.sessionStatus[session.sessionId] ?? "idle"
            var data: [String: Any] = [
                "sessionId": session.sessionId,
                "pid": session.pid,
                "cwd": session.cwd,
                "name": session.name ?? "Claude Code",
                "startedAt": session.startedAt,
                "status": status
            ]
            if let lastTool = self.sessionLastTool[session.sessionId] {
                data["lastTool"] = lastTool
            }
            return data
        }
        bridge?.sendToJS(event: "agentsUpdate", data: ["agents": agentData])
    }

    // MARK: - WebViewBridgeDelegate

    func webViewBridge(_ bridge: WebViewBridge, didReceiveAction action: String, data: [String: Any]) {
        switch action {
        case "ready":
            print("[VibeBuddy] Web UI ready (\(bridge === self.bridge ? "bubble" : "dashboard"))")
            if bridge === self.bridge {
                bubbleUIReady = true
                pushAgentUpdate()
            }

        case "dashboardReady":
            sendStatsToDashboard()

        case "agentClicked":
            handleAgentClicked(data)

        case "approve":
            handleApprovalResponse(data, decision: "allow")

        case "deny":
            handleApprovalResponse(data, decision: "deny")

        case "requestStats":
            sendStatsToNotch()

        case "openDashboard":
            openDashboard()

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

            print("[VibeBuddy] Hook: \(event.hookType) session=\(event.sessionId.prefix(8))…")

            // Any activity cancels pending Stop transition
            self.pendingStopTimers[event.sessionId]?.cancel()
            self.pendingStopTimers.removeValue(forKey: event.sessionId)

            if event.hookType == "PreToolUse" {
                // Mark as working immediately
                self.sessionStatus[event.sessionId] = "working"
                self.sessionLastActivity[event.sessionId] = Date()
                self.sessionHadToolUse[event.sessionId] = true
                self.pushAgentUpdate()

                let toolName = event.payload["tool_name"] as? String ?? ""

                // Bash commands → show approval UI in bubble; everything else → auto-allow
                if toolName == "Bash" {
                    let approvalId = UUID().uuidString
                    self.pendingApprovals[approvalId] = respond

                    // Extract command preview from tool_input
                    var detail = ""
                    if let input = event.payload["tool_input"] as? [String: Any] {
                        detail = input["command"] as? String ?? ""
                    }

                    self.bridge?.sendToJS(event: "approvalRequest", data: [
                        "approvalId": approvalId,
                        "toolName": toolName,
                        "toolInput": ["command": detail]
                    ])

                    // Auto-expand the panel so user sees the approval
                    if !(self.panel?.isExpanded ?? false) {
                        self.panel?.expand()
                    }

                    // Timeout: auto-allow after 30 seconds if no response
                    let timer = DispatchWorkItem { [weak self] in
                        guard let self = self,
                              let cb = self.pendingApprovals.removeValue(forKey: approvalId) else { return }
                        self.approvalTimers.removeValue(forKey: approvalId)
                        self.bridge?.sendToJS(event: "approvalTimeout")
                        // Auto-allow on timeout (don't block Claude Code)
                        cb("{}".data(using: .utf8)!)
                    }
                    self.approvalTimers[approvalId] = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timer)
                } else {
                    // Non-Bash tools: auto-allow
                    respond("{}".data(using: .utf8)!)
                }
            } else {
                // Track status from hooks
                if event.hookType == "PostToolUse" {
                    self.sessionStatus[event.sessionId] = "working"
                    self.sessionLastActivity[event.sessionId] = Date()
                    self.sessionHadToolUse[event.sessionId] = true
                    if let toolName = event.payload["tool_name"] as? String {
                        self.sessionLastTool[event.sessionId] = toolName
                    }
                    self.liveStats?.recordToolCall(sessionId: event.sessionId)
                } else if event.hookType == "Stop" {
                    // Record tokens from Stop payload (Claude Code sends total_tokens_in/out)
                    let tokensIn = event.payload["total_tokens_in"] as? Int ?? 0
                    let tokensOut = event.payload["total_tokens_out"] as? Int ?? 0
                    if tokensIn + tokensOut > 0 {
                        self.liveStats?.recordTokens(sessionId: event.sessionId, tokensIn: tokensIn, tokensOut: tokensOut)
                    }

                    // Debounce Stop: wait 1 second before switching to "waiting".
                    let sid = event.sessionId
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.sessionStatus[sid] = "waiting"
                        self.sessionHadToolUse[sid] = false
                        self.pendingStopTimers.removeValue(forKey: sid)
                        print("[VibeBuddy] Session \(sid.prefix(8))… → done (Stop hook, debounced)")
                        self.pushAgentUpdate()
                        // Badge: notify user with agent info
                        let session = self.sessionMonitor?.activeSessions.first(where: { $0.sessionId == sid })
                        self.menuBar?.addNotification(
                            agentName: session?.name ?? "Claude Code",
                            cwd: session?.cwd ?? "",
                            pid: Int32(session?.pid ?? 0)
                        )
                    }
                    self.pendingStopTimers[sid] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
                } else if event.hookType == "UserPromptSubmit" {
                    // User sent a new message → immediately mark as working
                    self.sessionStatus[event.sessionId] = "working"
                    self.sessionLastActivity[event.sessionId] = Date()
                    self.sessionHadToolUse[event.sessionId] = false  // reset; wait for actual tool use
                    self.liveStats?.recordMessage(sessionId: event.sessionId)
                    // Clear badge — user is actively working
                    self.menuBar?.clearBadge()
                    print("[VibeBuddy] Session \(event.sessionId.prefix(8))… → working (user prompt)")
                }

                self.bridge?.sendToJS(event: "hookEvent", data: [
                    "type": event.hookType,
                    "sessionId": event.sessionId,
                    "payload": event.payload
                ])
                respond("{}".data(using: .utf8)!)

                // Push updated status to JS immediately (except Stop, which is debounced)
                if event.hookType != "Stop" {
                    self.pushAgentUpdate()
                    self.sendStatsToNotch()
                }
            }
        }
    }

    // MARK: - SessionMonitorDelegate

    func sessionMonitor(_ monitor: SessionMonitor, didUpdateSessions sessions: [AgentSession]) {
        pushAgentUpdate()
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
        activityTimer?.cancel()
        activityTimer = nil
        pendingStopTimers.values.forEach { $0.cancel() }
        pendingStopTimers.removeAll()
        bridge?.teardown()
        dashboardBridge?.teardown()
        hookServer?.stop()
        sessionMonitor?.stop()
        HookInstaller().uninstall()
        NSApp.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === dashboardWindow else { return }
        dashboardBridge?.teardown()
        dashboardBridge = nil
        dashboardWindow = nil
    }

    // MARK: - Private Handlers

    private func handleAgentClicked(_ data: [String: Any]) {
        guard let sessionId = data["sessionId"] as? String,
              let session = sessionMonitor?.activeSessions.first(where: { $0.sessionId == sessionId }) else {
            return
        }
        let status = sessionStatus[session.sessionId] ?? "working"
        bridge?.sendToJS(event: "showAgentDetail", data: [
            "sessionId": session.sessionId,
            "name": session.name ?? "Claude Code",
            "cwd": session.cwd,
            "startedAt": session.startedAt,
            "pid": session.pid,
            "kind": session.kind,
            "status": status,
            "lastTool": sessionLastTool[session.sessionId] ?? ""
        ])
    }

    private func handleApprovalResponse(_ data: [String: Any], decision: String) {
        guard let approvalId = data["approvalId"] as? String,
              let respond = pendingApprovals.removeValue(forKey: approvalId) else { return }

        approvalTimers.removeValue(forKey: approvalId)?.cancel()

        let response: [String: Any]
        if decision == "deny" {
            response = ["decision": "block", "reason": "Denied via Vibe Buddy"]
        } else {
            response = ["decision": "allow"]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: response) {
            respond(jsonData)
        } else {
            respond("{}".data(using: .utf8)!)
        }
    }
}
