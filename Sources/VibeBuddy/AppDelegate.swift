import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let panel = NotchPanel.create() else {
            print("[VibeBuddy] Failed to create NotchPanel — no screen available")
            return
        }
        self.panel = panel
        panel.orderFrontRegardless()
        print("[VibeBuddy] NotchPanel visible at notch area")
    }
}
