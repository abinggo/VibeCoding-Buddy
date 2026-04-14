import AppKit

// Single-instance check: if another VibeBuddy is already running, activate it and exit.
let myBundleId = Bundle.main.bundleIdentifier ?? "com.vibebuddy.app"
let myPID = ProcessInfo.processInfo.processIdentifier
let running = NSRunningApplication.runningApplications(withBundleIdentifier: myBundleId)
    .filter { $0.processIdentifier != myPID }
if !running.isEmpty {
    // Also check by process name for debug builds (no bundle ID match)
    print("[VibeBuddy] Another instance is already running (PID \(running.first!.processIdentifier)). Exiting.")
    exit(0)
}

// Fallback: check by process name for non-bundled debug builds
let processName = ProcessInfo.processInfo.processName
let allApps = NSWorkspace.shared.runningApplications
let dupes = allApps.filter { $0.localizedName == processName && $0.processIdentifier != myPID }
if !dupes.isEmpty {
    print("[VibeBuddy] Another instance '\(processName)' is already running. Exiting.")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
