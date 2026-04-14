import AppKit
import Darwin

// MARK: - Delegate Protocol

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidSelectTogglePanel()
    func menuBarDidSelectDashboard()
    func menuBarDidSelectQuit()
}

// MARK: - Agent Notification

/// A notification entry for a completed agent task.
private struct AgentNotification {
    let agentName: String
    let cwd: String
    let pid: Int32
    let time: Date
}

// MARK: - MenuBarController

/// Manages the system status bar item (menu bar icon) with a dropdown menu.
class MenuBarController {

    weak var delegate: MenuBarControllerDelegate?
    private var statusItem: NSStatusItem?
    private var notifications: [AgentNotification] = []

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = " VB "
            button.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        }

        rebuildMenu()
    }

    // MARK: - Badge & Notifications

    /// Adds a completion notification and updates the badge.
    func addNotification(agentName: String, cwd: String, pid: Int32) {
        notifications.append(AgentNotification(
            agentName: agentName, cwd: cwd, pid: pid, time: Date()
        ))
        updateTitle()
        rebuildMenu()
    }

    /// Clears all notifications and the badge.
    func clearBadge() {
        guard !notifications.isEmpty else { return }
        notifications.removeAll()
        updateTitle()
        rebuildMenu()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let count = notifications.count
        if count > 0 {
            button.title = " VB \(count) "
        } else {
            button.title = " VB "
        }
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        let menu = NSMenu()

        // Notification items at the top
        if !notifications.isEmpty {
            let header = NSMenuItem(title: "Completed:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for (index, notif) in notifications.enumerated() {
                let timeStr = formatTime(notif.time)
                let shortCwd = shortenPath(notif.cwd)
                let title = "\(notif.agentName) — \(shortCwd)  \(timeStr)"

                let item = NSMenuItem(title: title, action: #selector(notificationClicked(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.toolTip = "Click to open terminal (PID \(notif.pid))"
                menu.addItem(item)
            }

            let clearItem = NSMenuItem(title: "Clear All", action: #selector(clearAllNotifications), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Standard items
        menu.addItem(withTitle: "Toggle Notch Panel", action: #selector(togglePanel), keyEquivalent: "t")
        menu.addItem(withTitle: "Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Vibe Buddy", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func notificationClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0 && index < notifications.count else { return }
        let notif = notifications[index]
        activateTerminal(forPid: notif.pid)
    }

    @objc private func clearAllNotifications() {
        clearBadge()
    }

    @objc private func togglePanel() {
        delegate?.menuBarDidSelectTogglePanel()
    }

    @objc private func openDashboard() {
        delegate?.menuBarDidSelectDashboard()
    }

    @objc private func quit() {
        delegate?.menuBarDidSelectQuit()
    }

    // MARK: - Activate Terminal

    /// Walks up the process tree from a Claude Code PID to find and activate its parent terminal app.
    private func activateTerminal(forPid pid: Int32) {
        print("[VibeBuddy] Activating terminal for PID \(pid)")

        // 1. Walk up the process tree to find a GUI application
        if pid > 0 {
            var currentPid = pid
            while currentPid > 1 {
                if let app = NSRunningApplication(processIdentifier: currentPid),
                   app.activationPolicy == .regular,
                   let name = app.localizedName {
                    print("[VibeBuddy] Found terminal app: \(name) (PID \(currentPid))")
                    openAppByName(name)
                    return
                }
                let ppid = parentPid(of: currentPid)
                if ppid == currentPid || ppid <= 1 { break }
                currentPid = ppid
            }
        }

        // 2. Fallback: find any running terminal and open it
        let terminalBundleIds = [
            "com.mitchellh.ghostty",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable"
        ]
        for bundleId in terminalBundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
               let name = app.localizedName {
                print("[VibeBuddy] Fallback: opening \(name)")
                openAppByName(name)
                return
            }
        }
    }

    /// Uses `open -a` to reliably bring an app to the front (works from accessory apps).
    private func openAppByName(_ name: String) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", name]
        try? task.run()
    }

    private func parentPid(of pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return pid }
        return info.kp_eproc.e_ppid
    }

    // MARK: - Helpers

    private func shortenPath(_ p: String) -> String {
        let parts = p.split(separator: "/")
        if parts.count > 2 {
            return "…/" + parts.suffix(2).joined(separator: "/")
        }
        return p
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
