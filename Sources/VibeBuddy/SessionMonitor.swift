import Foundation

// MARK: - Model

/// Represents an active Claude Code session, deserialized from ~/.claude/sessions/<pid>.json
struct AgentSession: Codable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Double       // Unix timestamp in milliseconds
    let kind: String            // "interactive", "headless", etc.
    let entrypoint: String      // "cli"
    let name: String?

    var startDate: Date {
        Date(timeIntervalSince1970: startedAt / 1000)
    }
}

// MARK: - Delegate Protocol

protocol SessionMonitorDelegate: AnyObject {
    func sessionMonitor(_ monitor: SessionMonitor, didUpdateSessions sessions: [AgentSession])
}

// MARK: - SessionMonitor

/// Watches ~/.claude/sessions/ to detect running Claude Code instances.
/// Uses DispatchSource file system events + periodic polling (fallback for process death).
class SessionMonitor {

    weak var delegate: SessionMonitorDelegate?

    private let sessionsDir: String
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private(set) var activeSessions: [AgentSession] = []

    init(claudeDir: String = NSHomeDirectory() + "/.claude") {
        self.sessionsDir = claudeDir + "/sessions"
    }

    func start() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)

        scanSessions()
        startWatching()
        startPolling()
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        pollTimer?.cancel()
        pollTimer = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - File System Watching

    private func startWatching() {
        fileDescriptor = open(sessionsDir, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[SessionMonitor] Cannot watch \(sessionsDir)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.scanSessions()
        }
        source.setCancelHandler { [weak self] in
            guard let fd = self?.fileDescriptor, fd >= 0 else { return }
            close(fd)
            self?.fileDescriptor = -1
        }
        source.resume()
        self.dispatchSource = source
    }

    // MARK: - Polling (fallback for process death without file cleanup)

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.scanSessions()
        }
        timer.resume()
        self.pollTimer = timer
    }

    // MARK: - Scan

    private func scanSessions() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            updateIfChanged([])
            return
        }

        var sessions: [AgentSession] = []
        for file in files where file.hasSuffix(".json") {
            let path = sessionsDir + "/" + file
            guard let data = fm.contents(atPath: path),
                  let session = try? JSONDecoder().decode(AgentSession.self, from: data) else {
                continue
            }
            // Verify the process is still alive
            if kill(Int32(session.pid), 0) == 0 {
                sessions.append(session)
            } else {
                // Stale session file — process is dead
                try? fm.removeItem(atPath: path)
            }
        }

        updateIfChanged(sessions)
    }

    private func updateIfChanged(_ sessions: [AgentSession]) {
        let oldIds = Set(activeSessions.map(\.sessionId))
        let newIds = Set(sessions.map(\.sessionId))

        guard oldIds != newIds else { return }

        activeSessions = sessions
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.sessionMonitor(self, didUpdateSessions: sessions)
        }
    }
}
