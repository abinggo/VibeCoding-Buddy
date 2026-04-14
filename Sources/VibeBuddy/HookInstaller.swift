import Foundation

/// Manages installation and removal of Vibe Buddy hook scripts in Claude Code's settings.json.
///
/// Correct hooks format (object keyed by event type, matcher is regex on tool name):
/// ```json
/// {
///   "hooks": {
///     "PreToolUse":  [{"matcher": ".*", "hooks": [{"type": "command", "command": "..."}]}],
///     "PostToolUse": [{"matcher": ".*", "hooks": [{"type": "command", "command": "..."}]}],
///     "Stop":        [{"matcher": "",   "hooks": [{"type": "command", "command": "..."}]}],
///     "Notification":[{"matcher": "",   "hooks": [{"type": "command", "command": "..."}]}]
///   }
/// }
/// ```
class HookInstaller {

    private let settingsPath: String
    private let hookScriptPath: String
    private static let hookMarker = "vibe-buddy-hook"

    /// The event types we install hooks for.
    private static let toolEvents = ["PreToolUse", "PostToolUse"]
    private static let nonToolEvents = ["Stop", "Notification", "UserPromptSubmit"]

    init(claudeDir: String = NSHomeDirectory() + "/.claude") {
        self.settingsPath = claudeDir + "/settings.json"
        self.hookScriptPath = claudeDir + "/vibe-buddy-hook.sh"
    }

    // MARK: - Install

    func installIfNeeded(port: UInt16 = 19816) {
        writeHookScript(port: port)
        installSettingsHooks()
    }

    // MARK: - Uninstall

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
        # Reads hook payload from stdin, POSTs to local server via stdin piping.

        VIBE_BUDDY_PORT="${VIBE_BUDDY_PORT:-\(port)}"
        HOOK_TYPE="$1"

        # Pipe stdin directly to curl to avoid shell injection via variable expansion
        RESPONSE=$(curl -s --max-time 10 -X POST "http://127.0.0.1:${VIBE_BUDDY_PORT}/hook/${HOOK_TYPE}" \
          -H "Content-Type: application/json" \
          -d @- 2>/dev/null)

        # For PreToolUse, output the response (approval decision)
        if [ "$HOOK_TYPE" = "PreToolUse" ] && [ -n "$RESPONSE" ]; then
          printf '%s\\n' "$RESPONSE"
        fi
        """

        try? script.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)

        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: hookScriptPath)
    }

    // MARK: - Settings.json Manipulation

    private func installSettingsHooks() {
        var settings = readSettings()

        // hooks must be a dictionary keyed by event type, NOT an array
        var hooksDict = settings["hooks"] as? [String: Any] ?? [:]

        // If old format (array) exists, remove it first
        if settings["hooks"] is [[String: Any]] {
            print("[HookInstaller] Removing old array-format hooks, converting to correct object format")
            hooksDict = [:]
        }

        // Check if already installed
        if isAlreadyInstalled(in: hooksDict) {
            print("[HookInstaller] Hooks already installed")
            return
        }

        let escapedPath = hookScriptPath.replacingOccurrences(of: "'", with: "'\\''")
        let hookCommand = "bash '\(escapedPath)'"

        // Install hooks for each event type
        let allEvents = Self.toolEvents + Self.nonToolEvents
        for eventType in allEvents {
            let isToolEvent = Self.toolEvents.contains(eventType)
            // matcher: ".*" for tool events (match all tools), "" for non-tool events
            let matcher = isToolEvent ? ".*" : ""
            let entry: [String: Any] = [
                "matcher": matcher,
                "hooks": [
                    ["type": "command", "command": "\(hookCommand) \(eventType)"]
                ]
            ]

            var eventHooks = hooksDict[eventType] as? [[String: Any]] ?? []

            // Remove any existing vibe-buddy entries for this event type
            eventHooks.removeAll { entryContainsVibeBuddyHook($0) }

            eventHooks.append(entry)
            hooksDict[eventType] = eventHooks
        }

        settings["hooks"] = hooksDict
        writeSettings(settings)
        print("[HookInstaller] Hooks installed to \(settingsPath)")
    }

    private func removeSettingsHooks() {
        var settings = readSettings()

        // Handle old array format — just remove the key
        if settings["hooks"] is [[String: Any]] {
            settings.removeValue(forKey: "hooks")
            writeSettings(settings)
            return
        }

        guard var hooksDict = settings["hooks"] as? [String: Any] else { return }

        let allEvents = Self.toolEvents + Self.nonToolEvents
        for eventType in allEvents {
            guard var eventHooks = hooksDict[eventType] as? [[String: Any]] else { continue }
            eventHooks.removeAll { entryContainsVibeBuddyHook($0) }
            if eventHooks.isEmpty {
                hooksDict.removeValue(forKey: eventType)
            } else {
                hooksDict[eventType] = eventHooks
            }
        }

        if hooksDict.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooksDict
        }

        writeSettings(settings)
    }

    private func isAlreadyInstalled(in hooksDict: [String: Any]) -> Bool {
        let allEvents = Self.toolEvents + Self.nonToolEvents
        for eventType in allEvents {
            guard let eventHooks = hooksDict[eventType] as? [[String: Any]] else { return false }
            if !eventHooks.contains(where: { entryContainsVibeBuddyHook($0) }) { return false }
        }
        return true
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
        try? data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }
}
