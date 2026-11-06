import Foundation
import Network

/// A temporary, local-only MCP server (Streamable HTTP, JSON responses) so an agent such as Claude
/// Code can read and change tasks while there is no backend. It runs inside the app, on 127.0.0.1,
/// and calls the same TaskStore methods the UI does, so every change shows up live, is saved
/// normally and can be undone with ⌘Z. When a backend exists, point the tools at it instead.
///
/// Connect: `claude mcp add --transport http flowmate http://127.0.0.1:47821/mcp`
/// (the dev build listens on 47822; FLOWMATE_MCP_PORT overrides; FLOWMATE_MCP=0 turns it off).
@MainActor
final class MCPServer {
    static let shared = MCPServer()

    static var port: UInt16 {
        if let text = ProcessInfo.processInfo.environment["FLOWMATE_MCP_PORT"], let port = UInt16(text) { return port }
        return AppChannel.current == .production ? 47821 : 47822
    }

    private var listener: NWListener?
    private var store: TaskStore?
    private var tools: MCPTaskTools?

    func start(store: TaskStore) {
        guard listener == nil, ProcessInfo.processInfo.environment["FLOWMATE_MCP"] != "0" else { return }
        self.store = store
        self.tools = MCPTaskTools(store: store)
        do {
            let parameters = NWParameters.tcp
            // Loopback only: nothing off this Mac can connect
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state { NSLog("FlowMate MCP: listener failed: \(error)") }
            }
            listener.start(queue: .main)
            self.listener = listener
            NSLog("FlowMate MCP: listening on http://127.0.0.1:\(Self.port)/mcp")
        } catch {
            NSLog("FlowMate MCP: could not start: \(error)")
        }
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if error != nil { connection.cancel(); return }
                switch HTTPRequest.parse(buffer) {
                case .incomplete:
                    if isComplete || buffer.count > 4 << 20 { connection.cancel() } else { self.receive(connection, buffer: buffer) }
                case .invalid:
                    self.send(connection, status: 400, body: nil)
                case let .complete(request):
                    self.handle(request, on: connection)
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        // A web page in a browser must not be able to drive the app: browsers always send Origin
        // on cross-site requests, and the host has to be this machine (DNS rebinding).
        let host = (request.headers["host"] ?? "").split(separator: ":").first.map(String.init) ?? ""
        guard request.headers["origin"] == nil, ["127.0.0.1", "localhost", "[::1]"].contains(host) else {
            return send(connection, status: 403, body: nil)
        }
        guard request.path == "/mcp" || request.path == "/" else { return send(connection, status: 404, body: nil) }
        guard request.method == "POST" else { return send(connection, status: 405, body: nil) }
        guard (request.headers["content-type"] ?? "").lowercased().hasPrefix("application/json") else {
            return send(connection, status: 415, body: nil)
        }
        guard let json = try? JSONSerialization.jsonObject(with: request.body) else {
            return send(connection, status: 400, body: Self.encode(Self.error(id: NSNull(), code: -32700, "Parse error")))
        }
        // Batches are allowed by JSON-RPC; answer each request in them
        if let batch = json as? [[String: Any]] {
            let replies = batch.compactMap { respond(to: $0) }
            return replies.isEmpty ? send(connection, status: 202, body: nil) : send(connection, status: 200, body: Self.encode(replies))
        }
        guard let message = json as? [String: Any] else {
            return send(connection, status: 400, body: Self.encode(Self.error(id: NSNull(), code: -32600, "Invalid request")))
        }
        if let reply = respond(to: message) { send(connection, status: 200, body: Self.encode(reply)) } else { send(connection, status: 202, body: nil) }
    }

    private func send(_ connection: NWConnection, status: Int, body: Data?) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                      405: "Method Not Allowed", 415: "Unsupported Media Type"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body?.count ?? 0)\r\nConnection: close\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        if status == 405 { head += "Allow: POST\r\n" }
        var data = Data((head + "\r\n").utf8)
        if let body { data.append(body) }
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - JSON-RPC

    /// The reply to one JSON-RPC message; nil for notifications.
    private func respond(to message: [String: Any]) -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        guard let id = message["id"] else { return nil } // a notification, e.g. notifications/initialized
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? "2025-03-26"
            return Self.result(id: id, [
                "protocolVersion": requested,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "flowmate", "version": "0.1"],
                "instructions": MCPTaskTools.instructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": MCPTaskTools.definitions])
        case "tools/call":
            guard let tools, let name = params["name"] as? String else {
                return Self.error(id: id, code: -32602, "Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try tools.call(name, arguments)
                return Self.result(id: id, ["content": [["type": "text", "text": text]]])
            } catch let failure as MCPToolError {
                // Tool failures are results the agent can read and correct, not protocol errors
                return Self.result(id: id, ["content": [["type": "text", "text": failure.message]], "isError": true])
            } catch {
                return Self.error(id: id, code: -32603, error.localizedDescription)
            }
        default:
            return Self.error(id: id, code: -32601, "Method not found: \(method)")
        }
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any, code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}

/// One parsed HTTP/1.1 request (headers lowercased).
struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    enum Parsed { case incomplete, invalid, complete(HTTPRequest) }

    static func parse(_ data: Data) -> Parsed {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= 4 << 20 else { return .invalid }
        let bodyStart = separator.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        let body = data[bodyStart..<(bodyStart + length)]
        return .complete(HTTPRequest(method: String(start[0]), path: String(start[1]).components(separatedBy: "?")[0],
                                     headers: headers, body: Data(body)))
    }
}
