import Foundation
import Network

// MARK: - Hook Event Model

/// Represents a single event received from a Claude Code hook script.
struct HookEvent {
    let hookType: String    // "PreToolUse", "PostToolUse", "Notification", "Stop"
    let sessionId: String
    let payload: [String: Any]
}

// MARK: - Delegate Protocol

protocol HookServerDelegate: AnyObject {
    /// Called when a hook event is received.
    /// For `PreToolUse` events, the `respond` closure must be called with the decision JSON.
    /// For other events, `respond` is called automatically.
    func hookServer(_ server: HookServer, didReceive event: HookEvent, respond: @escaping (Data) -> Void)
}

// MARK: - HookServer

/// Lightweight HTTP server using Network.framework.
/// Listens on localhost for Claude Code hook events (POST /hook/<type>).
class HookServer {

    weak var delegate: HookServerDelegate?
    private var listener: NWListener?
    private(set) var port: UInt16
    private let portRange: ClosedRange<UInt16>

    init(port: UInt16 = 19816, fallbackRange: ClosedRange<UInt16> = 19816...19826) {
        self.port = port
        self.portRange = fallbackRange
    }

    func start() throws {
        // Try the preferred port first, then fall back through the range
        var lastError: Error?
        for candidate in portRange {
            do {
                try startOnPort(candidate)
                self.port = candidate
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NWError.posix(.EADDRINUSE)
    }

    private func startOnPort(_ targetPort: UInt16) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: targetPort) else {
            throw NWError.posix(.EINVAL)
        }
        // Restrict to IPv4 loopback — only accept connections from localhost
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        let newListener = try NWListener(using: params, on: nwPort)
        newListener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var startupError: Error?

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[HookServer] Listening on 127.0.0.1:\(targetPort)")
                semaphore.signal()
            case .failed(let error):
                startupError = error
                semaphore.signal()
            default:
                break
            }
        }
        newListener.start(queue: .global(qos: .userInteractive))

        // Wait briefly for the listener to report ready or failed
        _ = semaphore.wait(timeout: .now() + 1)

        if let error = startupError {
            newListener.cancel()
            throw error
        }

        self.listener = newListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        accumulateHTTPRequest(connection: connection, buffer: Data())
    }

    /// Accumulates data until we have the full HTTP body (based on Content-Length).
    private func accumulateHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }

            var accumulated = buffer
            if let data = data {
                accumulated.append(data)
            }

            // Check if we have the full HTTP request (headers + body per Content-Length)
            if let raw = String(data: accumulated, encoding: .utf8),
               let headerEnd = raw.range(of: "\r\n\r\n") {
                let headerSection = String(raw[raw.startIndex..<headerEnd.lowerBound])
                let bodyStart = accumulated.count - raw[headerEnd.upperBound...].utf8.count
                let bodyData = accumulated[bodyStart...]

                // Parse Content-Length
                var contentLength = 0
                for line in headerSection.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }

                if bodyData.count >= contentLength || isComplete || error != nil {
                    // Full request received
                    self.processHTTPRequest(data: accumulated, connection: connection)
                    return
                }
            }

            // Guard against unbounded accumulation (max 1MB)
            if accumulated.count > 1_048_576 || isComplete || error != nil {
                self.processHTTPRequest(data: accumulated, connection: connection)
                return
            }

            // Need more data
            self.accumulateHTTPRequest(connection: connection, buffer: accumulated)
        }
    }

    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let raw = String(data: data, encoding: .utf8) else {
            respond(to: connection, status: 400, body: #"{"error":"invalid encoding"}"#)
            return
        }

        // Split HTTP headers from body
        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else {
            respond(to: connection, status: 400, body: #"{"error":"malformed request"}"#)
            return
        }

        let headerSection = parts[0]
        let bodyString = parts.dropFirst().joined(separator: "\r\n\r\n")

        // Parse request line: "POST /hook/PreToolUse HTTP/1.1"
        guard let firstLine = headerSection.components(separatedBy: "\r\n").first else {
            respond(to: connection, status: 400, body: #"{"error":"no request line"}"#)
            return
        }
        let tokens = firstLine.components(separatedBy: " ")
        guard tokens.count >= 2 else {
            respond(to: connection, status: 400, body: #"{"error":"bad request line"}"#)
            return
        }

        let method = tokens[0]
        let path = tokens[1]

        // Route
        switch (method, path) {
        case ("POST", let p) where p.hasPrefix("/hook/"):
            let hookType = String(p.dropFirst("/hook/".count))
            routeHookPost(hookType: hookType, body: bodyString, connection: connection)
        case ("GET", "/health"):
            respond(to: connection, status: 200, body: #"{"status":"ok","port":\#(port)}"#)
        default:
            respond(to: connection, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    private func routeHookPost(hookType: String, body: String, connection: NWConnection) {
        let payload: [String: Any]
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = json
        } else {
            payload = ["raw": body]
        }

        let sessionId = payload["session_id"] as? String ?? "unknown"
        let event = HookEvent(hookType: hookType, sessionId: sessionId, payload: payload)

        if hookType == "PreToolUse" {
            // Block until delegate responds (for approval workflow)
            delegate?.hookServer(self, didReceive: event) { [weak self] responseData in
                let body = String(data: responseData, encoding: .utf8) ?? "{}"
                self?.respond(to: connection, status: 200, body: body)
            }
        } else {
            // Fire-and-forget for non-blocking events
            delegate?.hookServer(self, didReceive: event) { _ in }
            respond(to: connection, status: 200, body: #"{"ok":true}"#)
        }
    }

    // MARK: - HTTP Response

    private func respond(to connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default:  statusText = "Error"
        }

        let response = "HTTP/1.1 \(status) \(statusText)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.utf8.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n" +
            body

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
