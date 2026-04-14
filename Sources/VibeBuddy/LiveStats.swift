import Foundation

/// Tracks real-time usage statistics from hook events.
/// Persists daily counters to ~/Library/Application Support/VibeBuddy/live-stats.json.
class LiveStats {

    struct DayStats: Codable {
        var date: String            // "2026-04-10"
        var toolCalls: Int = 0
        var messages: Int = 0
        var tokens: Int = 0         // total tokens (in + out)
        var sessions: Set<String> = []

        var sessionCount: Int { sessions.count }
    }

    struct Store: Codable {
        var days: [DayStats] = []
        var allTimeSessions: Set<String> = []
        var allTimeMessages: Int = 0
        var allTimeToolCalls: Int = 0
        var allTimeTokens: Int = 0
    }

    private var store: Store
    private let filePath: String
    private let queue = DispatchQueue(label: "com.vibebuddy.livestats")

    init() {
        let supportDir = NSHomeDirectory() + "/Library/Application Support/VibeBuddy"
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        self.filePath = supportDir + "/live-stats.json"
        self.store = Self.load(from: filePath)
    }

    // MARK: - Record Events

    func recordToolCall(sessionId: String) {
        queue.sync {
            ensureToday()
            store.days[store.days.count - 1].toolCalls += 1
            store.days[store.days.count - 1].sessions.insert(sessionId)
            store.allTimeToolCalls += 1
            store.allTimeSessions.insert(sessionId)
            save()
        }
    }

    func recordMessage(sessionId: String) {
        queue.sync {
            ensureToday()
            store.days[store.days.count - 1].messages += 1
            store.days[store.days.count - 1].sessions.insert(sessionId)
            store.allTimeMessages += 1
            store.allTimeSessions.insert(sessionId)
            save()
        }
    }

    func recordSession(sessionId: String) {
        queue.sync {
            ensureToday()
            store.days[store.days.count - 1].sessions.insert(sessionId)
            store.allTimeSessions.insert(sessionId)
            save()
        }
    }

    func recordTokens(sessionId: String, tokensIn: Int, tokensOut: Int) {
        let total = tokensIn + tokensOut
        guard total > 0 else { return }
        queue.sync {
            ensureToday()
            store.days[store.days.count - 1].tokens += total
            store.days[store.days.count - 1].sessions.insert(sessionId)
            store.allTimeTokens += total
            store.allTimeSessions.insert(sessionId)
            save()
        }
    }

    // MARK: - Query

    func dashboardJSON() -> [String: Any] {
        queue.sync {
            ensureToday()

            let today = store.days.last!
            let last7 = Array(store.days.suffix(7))

            let dailyActivity: [[String: Any]] = last7.map { day in
                [
                    "date": day.date,
                    "messages": day.messages,
                    "sessions": day.sessionCount,
                    "tools": day.toolCalls,
                    "tokens": day.tokens
                ]
            }

            return [
                "todayMessages": today.messages,
                "todayToolCalls": today.toolCalls,
                "todaySessions": today.sessionCount,
                "todayTokens": today.tokens,
                "totalMessages": store.allTimeMessages,
                "totalSessions": store.allTimeSessions.count,
                "totalToolCalls": store.allTimeToolCalls,
                "totalTokens": store.allTimeTokens,
                "dailyActivity": dailyActivity
            ]
        }
    }

    // MARK: - Internal

    private static var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func ensureToday() {
        let today = Self.todayString
        if store.days.last?.date != today {
            store.days.append(DayStats(date: today))
            // Keep last 30 days
            if store.days.count > 30 {
                store.days = Array(store.days.suffix(30))
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }

    private static func load(from path: String) -> Store {
        guard let data = FileManager.default.contents(atPath: path),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        return store
    }
}
