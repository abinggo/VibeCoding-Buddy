import AppKit

// MARK: - Delegate Protocol

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidSelectTogglePanel()
    func menuBarDidSelectDashboard()
    func menuBarDidSelectQuit()
}

// MARK: - MenuBarController

/// Manages the system status bar item (menu bar icon) with a dropdown menu.
class MenuBarController {

    weak var delegate: MenuBarControllerDelegate?
    private var statusItem: NSStatusItem?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Pixel-style "VB" text as the menu bar icon
            button.title = " VB "
            button.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Notch Panel", action: #selector(togglePanel), keyEquivalent: "t")
        menu.addItem(withTitle: "Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Vibe Buddy", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        delegate?.menuBarDidSelectTogglePanel()
    }

    @objc private func openDashboard() {
        delegate?.menuBarDidSelectDashboard()
    }

    @objc private func quit() {
        delegate?.menuBarDidSelectQuit()
    }
}
