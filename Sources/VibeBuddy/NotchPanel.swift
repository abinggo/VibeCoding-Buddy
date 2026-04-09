import AppKit

/// A transparent, borderless NSPanel that positions itself over the MacBook Notch area.
/// Supports hover-to-expand and click-to-collapse interactions.
///
/// On non-notch Macs, it positions itself at top-center of the screen with a default menu bar height.
class NotchPanel: NSPanel {

    // MARK: - Layout Constants

    static let collapsedHeight: CGFloat = 38
    static let expandedHeight: CGFloat = 280
    static let panelWidth: CGFloat = 420

    // MARK: - State

    private(set) var isExpanded = false

    // MARK: - Notifications

    static let didExpandNotification = Notification.Name("NotchPanelDidExpand")
    static let didCollapseNotification = Notification.Name("NotchPanelDidCollapse")

    // MARK: - Init

    /// Creates the panel. Returns nil via the static factory if no screen is available.
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        configureWindowBehavior()
        setupTrackingArea()
    }

    /// Factory method that safely creates a NotchPanel positioned at the notch.
    static func create() -> NotchPanel? {
        guard let screen = NSScreen.main else { return nil }

        let notchHeight = detectNotchHeight(screen: screen)
        let panelRect = collapsedFrame(screen: screen, height: notchHeight)

        return NotchPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    // MARK: - Window Configuration

    private func configureWindowBehavior() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    // MARK: - Tracking Area

    private func setupTrackingArea() {
        guard let contentView = contentView else { return }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        expand()
    }

    override func mouseExited(with event: NSEvent) {
        collapse()
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded, let screen = NSScreen.main else { return }
        isExpanded = true

        let newFrame = NSRect(
            x: screen.frame.midX - Self.panelWidth / 2,
            y: screen.frame.maxY - Self.expandedHeight,
            width: Self.panelWidth,
            height: Self.expandedHeight
        )

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }

        NotificationCenter.default.post(name: Self.didExpandNotification, object: self)
    }

    func collapse() {
        guard isExpanded, let screen = NSScreen.main else { return }
        isExpanded = false

        let notchHeight = Self.detectNotchHeight(screen: screen)
        let newFrame = Self.collapsedFrame(screen: screen, height: notchHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }

        NotificationCenter.default.post(name: Self.didCollapseNotification, object: self)
    }

    // MARK: - Geometry Helpers

    static func detectNotchHeight(screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0 {
            return screen.safeAreaInsets.top
        }
        return collapsedHeight
    }

    static func collapsedFrame(screen: NSScreen, height: CGFloat) -> NSRect {
        NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.maxY - height,
            width: panelWidth,
            height: height
        )
    }
}
