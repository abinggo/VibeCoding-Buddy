import Foundation

/// Manages installation and removal of Vibe Buddy hook scripts in Claude Code's settings.json.
///
/// Hook flow:
///   Claude Code event -> hook script (bash) -> HTTP POST to HookServer -> Vibe Buddy UI
class HookInstaller {

    private let settingsPath: String
    private let hookScriptPath: String
    private static let hookMarker = "vibe-buddy-hook"

    init(claudeDir: String = NSHomeDirectory() + "/.claude") {
        self.settingsPath = claudeDir + "/settings.json"
        self.hookScriptPath = claudeDir + "/vibe-buddy-hook.sh"
    }

    // MARK: - Install

    /// Installs hook script and configures Claude Code settings.json if not already done.
    func installIfNeeded(port: UInt16 = 19816) {
        writeHookScript(port: port)
        installSettingsHooks()
    }

    // MARK: - Uninstall

    /// Removes Vibe Buddy hooks from settings.json and deletes the hook script.
    func uninstall() {
        removeSettingsHooks()
        try? FileManager.default.removeItem(atPath: hookScriptPath)
        print("[HookInstaller] Uninstalled")
    }

    // MARK: - Hook Script

    private func writeHookScript(port: UInt16) {
        let script = """
        #!/bin/bash
        # Vibe Buddy hook — forwards Claude Code events to the companion app.
        # Reads hook payload from stdin, POSTs to local server.

        VIBE_BUDDY_PORT="${VIBE_BUDDY_PORT:-\(port)}"
        HOOK_TYPE="$1"

        INPUT=$(cat)

        RESPONSE=$(curl -s --max-time 10 -X POST "http://127.0.0.1:${VIBE_BUDDY_PORT}/hook/${HOOK_TYPE}" \\
          -H "Content-Type: application/json" \\
          -d "$INPUT" 2>/dev/null)

        # For PreToolUse, output the response (approval decision)
        if [ "$HOOK_TYPE" = "PreToolUse" ] && [ -n "$RESPONSE" ]; then
          echo "$RESPONSE"
        fi
        """

        try? script.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)

        // Make executable
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: hookScriptPath)
    }

    // MARK: - Settings.json Manipulation

    private func installSettingsHooks() {
        var settings = readSettings()

        // Check if already installed
        if let hooks = settings["hooks"] as? [[String: Any]],
           hooks.contains(where: { entryContainsVibeBuddyHook($0) }) {
            print("[HookInstaller] Hooks already installed")
            return
        }

        let hookCommand = "bash \(hookScriptPath)"
        let hookEntries: [[String: Any]] = [
            ["matcher": "PreToolUse",   "hooks": [["type": "command", "command": "\(hookCommand) PreToolUse"]]],
            ["matcher": "PostToolUse",  "hooks": [["type": "command", "command": "\(hookCommand) PostToolUse"]]],
            ["matcher": "Notification", "hooks": [["type": "command", "command": "\(hookCommand) Notification"]]],
            ["matcher": "Stop",         "hooks": [["type": "command", "command": "\(hookCommand) Stop"]]]
        ]

        var existingHooks = settings["hooks"] as? [[String: Any]] ?? []
        existingHooks.append(contentsOf: hookEntries)
        settings["hooks"] = existingHooks

        writeSettings(settings)
        print("[HookInstaller] Hooks installed to \(settingsPath)")
    }

    private func removeSettingsHooks() {
        var settings = readSettings()
        guard var hooks = settings["hooks"] as? [[String: Any]] else { return }

        hooks.removeAll { entryContainsVibeBuddyHook($0) }
        settings["hooks"] = hooks

        writeSettings(settings)
    }

    private func entryContainsVibeBuddyHook(_ entry: [String: Any]) -> Bool {
        guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains { item in
            (item["command"] as? String)?.contains(Self.hookMarker) ?? false
        }
    }

    // MARK: - JSON I/O

    private func readSettings() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func writeSettings(_ settings: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: URL(fileURLWithPath: settingsPath))
    }
}
