import Foundation

// MARK: - Stats Models

struct DailyActivity: Codable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int
}

struct DailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]
}

struct StatsCache: Codable {
    let version: Int
    let dailyActivity: [DailyActivity]
    let dailyModelTokens: [DailyModelTokens]
    let totalSessions: Int
    let totalMessages: Int
}

// MARK: - StatsReader

/// Reads and parses Claude Code's usage statistics from ~/.claude/stats-cache.json.
class StatsReader {

    private let statsPath: String

    init(claudeDir: String = NSHomeDirectory() + "/.claude") {
        self.statsPath = claudeDir + "/stats-cache.json"
    }

    func read() -> StatsCache? {
        guard let data = FileManager.default.contents(atPath: statsPath) else { return nil }
        return try? JSONDecoder().decode(StatsCache.self, from: data)
    }

    /// Returns stats formatted for the dashboard web UI (last 7 days).
    func dashboardJSON() -> [String: Any]? {
        guard let stats = read() else { return nil }

        let last7Activity = stats.dailyActivity.suffix(7).map { day -> [String: Any] in
            [
                "date": day.date,
                "messages": day.messageCount,
                "sessions": day.sessionCount,
                "tools": day.toolCallCount
            ]
        }

        let last7Tokens = stats.dailyModelTokens.suffix(7).map { day -> [String: Any] in
            let total = day.tokensByModel.values.reduce(0, +)
            return ["date": day.date, "tokens": total]
        }

        return [
            "totalSessions": stats.totalSessions,
            "totalMessages": stats.totalMessages,
            "dailyActivity": last7Activity,
            "dailyTokens": last7Tokens
        ]
    }
}
