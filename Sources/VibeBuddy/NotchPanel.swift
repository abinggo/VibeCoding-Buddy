import AppKit

/// A draggable floating bubble window that shows Claude Code agent status.
/// Click to expand into a detail panel; click outside or press Escape to collapse.
/// Remembers its position across sessions via UserDefaults.
class NotchPanel: NSPanel {

    // MARK: - Layout Constants

    static let bubbleSize: CGFloat = 72
    static let expandedWidth: CGFloat = 420
    static let expandedHeight: CGFloat = 480

    // MARK: - State

    private(set) var isExpanded = false
    private var isDragging = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var globalClickMonitor: Any?

    // MARK: - Notifications

    static let didExpandNotification = Notification.Name("NotchPanelDidExpand")
    static let didCollapseNotification = Notification.Name("NotchPanelDidCollapse")
    static let openDashboardNotification = Notification.Name("NotchPanelOpenDashboard")
    static let quitRequestedNotification = Notification.Name("NotchPanelQuitRequested")

    // MARK: - Init

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style,
                   backing: backingStoreType, defer: flag)
        configureWindowBehavior()
    }

    /// Factory method — creates a floating bubble at the saved position (or top-right default).
    static func create() -> NotchPanel? {
        guard let screen = NSScreen.main else { return nil }

        let origin = savedOrigin(for: screen)
        let rect = NSRect(x: origin.x, y: origin.y,
                          width: bubbleSize, height: bubbleSize)

        return NotchPanel(contentRect: rect,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
    }

    // MARK: - Window Configuration

    private func configureWindowBehavior() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    // MARK: - Event Interception

    /// Intercept mouse events before WKWebView consumes them.
    /// In collapsed (bubble) mode: handle drag and click ourselves.
    /// In expanded mode: let WKWebView handle everything (buttons etc).
    override func sendEvent(_ event: NSEvent) {
        // Right-click anywhere → show context menu
        if event.type == .rightMouseDown {
            showContextMenu(at: event)
            return
        }

        if !isExpanded {
            switch event.type {
            case .leftMouseDown:
                isDragging = false
                initialMouseLocation = NSEvent.mouseLocation
                initialWindowOrigin = frame.origin
                return  // eat the event

            case .leftMouseDragged:
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - initialMouseLocation.x
                let dy = currentMouse.y - initialMouseLocation.y

                // Consider it a drag after 3px of movement
                if !isDragging && (abs(dx) > 3 || abs(dy) > 3) {
                    isDragging = true
                }

                if isDragging {
                    setFrameOrigin(NSPoint(
                        x: initialWindowOrigin.x + dx,
                        y: initialWindowOrigin.y + dy
                    ))
                }
                return  // eat the event

            case .leftMouseUp:
                if isDragging {
                    saveOrigin()
                    isDragging = false
                } else {
                    // It was a click — toggle
                    expand()
                }
                return  // eat the event

            default:
                break
            }
        }

        // Expanded mode or non-mouse events — let WKWebView handle
        super.sendEvent(event)
    }

    // MARK: - Context Menu

    private func showContextMenu(at event: NSEvent) {
        let menu = NSMenu()

        if isExpanded {
            let collapseItem = NSMenuItem(title: "Collapse", action: #selector(menuCollapse), keyEquivalent: "")
            collapseItem.target = self
            menu.addItem(collapseItem)
        } else {
            let expandItem = NSMenuItem(title: "Expand", action: #selector(menuExpand), keyEquivalent: "")
            expandItem.target = self
            menu.addItem(expandItem)
        }

        menu.addItem(NSMenuItem.separator())

        let dashboardItem = NSMenuItem(title: "Dashboard", action: #selector(menuDashboard), keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Vibe Buddy", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Position menu at the mouse click location
        let locationInWindow = event.locationInWindow
        menu.popUp(positioning: nil, at: locationInWindow, in: contentView)
    }

    @objc private func menuExpand() { expand() }
    @objc private func menuCollapse() { collapse() }
    @objc private func menuDashboard() {
        NotificationCenter.default.post(name: Self.openDashboardNotification, object: self)
    }
    @objc private func menuQuit() {
        NotificationCenter.default.post(name: Self.quitRequestedNotification, object: self)
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded, let screen = NSScreen.main else { return }
        isExpanded = true

        // Expand from the bubble's center, clamped to screen
        let cx = frame.midX
        let cy = frame.midY
        var newX = cx - Self.expandedWidth / 2
        var newY = cy - Self.expandedHeight / 2

        let vis = screen.visibleFrame
        newX = max(vis.minX + 8, min(newX, vis.maxX - Self.expandedWidth - 8))
        newY = max(vis.minY + 8, min(newY, vis.maxY - Self.expandedHeight - 8))

        let newFrame = NSRect(x: newX, y: newY,
                              width: Self.expandedWidth, height: Self.expandedHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }

        // Collapse when clicking outside this window
        removeGlobalMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.collapse()
        }

        NotificationCenter.default.post(name: Self.didExpandNotification, object: self)
    }

    func collapse() {
        guard isExpanded, let screen = NSScreen.main else { return }
        isExpanded = false
        removeGlobalMonitor()

        let origin = Self.savedOrigin(for: screen)
        let newFrame = NSRect(x: origin.x, y: origin.y,
                              width: Self.bubbleSize, height: Self.bubbleSize)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }

        NotificationCenter.default.post(name: Self.didCollapseNotification, object: self)
    }

    private func removeGlobalMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    // MARK: - Escape to close

    override func cancelOperation(_ sender: Any?) {
        if isExpanded { collapse() }
    }

    override var canBecomeKey: Bool { isExpanded }

    // MARK: - Position Persistence

    private static let posXKey = "bubblePosX"
    private static let posYKey = "bubblePosY"

    private func saveOrigin() {
        UserDefaults.standard.set(Double(frame.origin.x), forKey: Self.posXKey)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: Self.posYKey)
    }

    static func savedOrigin(for screen: NSScreen) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: posXKey) != nil {
            return NSPoint(x: defaults.double(forKey: posXKey),
                           y: defaults.double(forKey: posYKey))
        }
        // Default: top-right corner, below menu bar
        let vis = screen.visibleFrame
        return NSPoint(x: vis.maxX - bubbleSize - 16,
                       y: vis.maxY - bubbleSize - 16)
    }
}
