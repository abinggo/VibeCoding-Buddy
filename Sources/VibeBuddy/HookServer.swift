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
    let port: UInt16

    init(port: UInt16 = 19816) {
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("[HookServer] Invalid port: \(port)")
            return
        }

        listener = try NWListener(using: params, on: nwPort)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener?.stateUpdateHandler = { [port] state in
            switch state {
            case .ready:
                print("[HookServer] Listening on 127.0.0.1:\(port)")
            case .failed(let error):
                print("[HookServer] Failed: \(error)")
            default:
                break
            }
        }
        listener?.start(queue: .global(qos: .userInteractive))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        // Read up to 256KB to handle large payloads
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, _, _ in
            guard let self = self, let data = data else {
                connection.cancel()
                return
            }
            self.processHTTPRequest(data: data, connection: connection)
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
