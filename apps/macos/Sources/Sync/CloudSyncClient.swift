import Foundation

/// Talks to the FlowMate API (services/api, v1). Every call sends `Authorization: Bearer <token>`.
/// The workspace travels as raw JSON: the server stores it as is and never reads it.
struct CloudSyncClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = CloudSyncClient.defaultSession

    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// "https://api.example.com" or "https://api.example.com/" → a usable base URL; nil when it isn't one.
    static func baseURL(from string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    // MARK: - Calls

    /// GET /v1/me: who the token belongs to and which workspaces it can reach.
    func me() async throws -> CloudMe {
        let (data, _) = try await send(request("v1/me", method: "GET"))
        do {
            return try JSONDecoder().decode(CloudMe.self, from: data)
        } catch {
            throw CloudSyncError.badResponse
        }
    }

    /// GET /v1/workspaces/{id}/snapshot. nil when nothing has been pushed yet.
    func snapshot(workspaceId: String) async throws -> CloudSnapshot? {
        do {
            let (data, _) = try await send(request("v1/workspaces/\(workspaceId)/snapshot", method: "GET"))
            return try CloudSnapshot.decode(data)
        } catch CloudSyncError.noSnapshot {
            return nil
        }
    }

    /// PUT /v1/workspaces/{id}/snapshot. `workspaceJSON` is the encoded workspace, sent byte for byte.
    /// Throws `.conflict` when the server's version isn't `baseVersion` (unless `force`).
    func push(
        workspaceId: String,
        workspaceJSON: Data,
        schemaVersion: Int,
        baseVersion: Int,
        deviceName: String,
        force: Bool = false
    ) async throws -> CloudPushResult {
        var request = request("v1/workspaces/\(workspaceId)/snapshot", method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.pushBody(
            workspaceJSON: workspaceJSON,
            schemaVersion: schemaVersion,
            baseVersion: baseVersion,
            deviceName: deviceName,
            force: force
        )
        let (data, _) = try await send(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (object["version"] as? NSNumber)?.intValue else {
            throw CloudSyncError.badResponse
        }
        return CloudPushResult(version: version, updatedAt: CloudDate.parse(object["updatedAt"] as? String))
    }

    /// The PUT body, built by hand so the workspace bytes go out exactly as encoded.
    static func pushBody(workspaceJSON: Data, schemaVersion: Int, baseVersion: Int, deviceName: String, force: Bool) -> Data {
        let name = (try? JSONEncoder().encode(deviceName)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"Mac\""
        var body = Data("{\"baseVersion\":\(baseVersion),\"schemaVersion\":\(schemaVersion),\"deviceName\":\(name),\"force\":\(force),\"data\":".utf8)
        body.append(workspaceJSON)
        body.append(Data("}".utf8))
        return body
    }

    // MARK: - Plumbing

    private func request(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CloudSyncError.offline(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw CloudSyncError.badResponse }
        if (200..<300).contains(http.statusCode) { return (data, http) }
        throw CloudSyncError.from(status: http.statusCode, body: data)
    }
}

// MARK: - Responses

struct CloudMe: Decodable, Equatable, Sendable {
    struct User: Decodable, Equatable, Sendable {
        var id: String
        var email: String?
        var displayName: String?
    }

    struct WorkspaceInfo: Decodable, Equatable, Sendable {
        var id: String
        var name: String
        var role: String
        var snapshotVersion: Int?

        var canWrite: Bool { role == "owner" || role == "editor" }
    }

    var user: User
    var workspaces: [WorkspaceInfo]

    /// The workspace this Mac syncs with: the first one it can write to, else the first.
    var primaryWorkspace: WorkspaceInfo? { workspaces.first(where: \.canWrite) ?? workspaces.first }
}

struct CloudSnapshot: Sendable {
    var version: Int
    var schemaVersion: Int
    var updatedAt: Date?
    var updatedByDevice: String?
    /// The workspace JSON as the server returned it
    var data: Data

    static func decode(_ body: Data) throws -> CloudSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let version = (object["version"] as? NSNumber)?.intValue,
              let payload = object["data"], JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw CloudSyncError.badResponse
        }
        return CloudSnapshot(
            version: version,
            schemaVersion: (object["schemaVersion"] as? NSNumber)?.intValue ?? 0,
            updatedAt: CloudDate.parse(object["updatedAt"] as? String),
            updatedByDevice: object["updatedByDevice"] as? String,
            data: data
        )
    }

    /// The workspace, decoded and migrated the same way the local file is.
    func workspace() throws -> Workspace {
        do {
            return try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: data).migrated()
        } catch {
            throw CloudSyncError.unreadableSnapshot(error.localizedDescription)
        }
    }
}

struct CloudPushResult: Equatable, Sendable {
    var version: Int
    var updatedAt: Date?
}

/// The cloud copy changed since this Mac last synced (a 409 from the server).
struct CloudConflict: Codable, Equatable, Sendable {
    var cloudVersion: Int
    var updatedAt: Date?
    var updatedByDevice: String?
}

enum CloudSyncError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    /// A 404 that didn't come from the FlowMate API (wrong address, or the proxy has no route)
    case notAPI
    case noSnapshot
    case tooLarge
    case conflict(CloudConflict)
    case server(Int, String)
    case offline(String)
    case badResponse
    case unreadableSnapshot(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add a server address and token first."
        case .invalidURL: return "The server address isn't a valid http(s) URL."
        case .unauthorized: return "The server didn't accept the token."
        case .forbidden: return "This token can't change that workspace."
        case .notFound: return "The server doesn't know that workspace."
        case .notAPI: return "No FlowMate server answers at that address. Check the server address."
        case .noSnapshot: return "Nothing has been synced yet."
        case .tooLarge: return "Your data is too large for the server (25 MB at most)."
        case .conflict: return "The cloud copy changed on another device."
        case let .server(status, message): return message.isEmpty ? "Server error \(status)." : "Server error \(status): \(message)"
        case let .offline(message): return "Can't reach the server. \(message)"
        case .badResponse: return "The server sent something FlowMate can't read."
        case let .unreadableSnapshot(message): return "The cloud copy can't be read: \(message)"
        }
    }

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    static func from(status: Int, body: Data) -> CloudSyncError {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let code = object?["error"] as? String ?? ""
        switch (status, code) {
        case (401, _): return .unauthorized
        case (403, _): return .forbidden
        case (404, "no_snapshot"): return .noSnapshot
        case (404, _) where object == nil: return .notAPI
        case (404, _): return .notFound
        case (409, _):
            return .conflict(CloudConflict(
                cloudVersion: (object?["currentVersion"] as? NSNumber)?.intValue ?? 0,
                updatedAt: CloudDate.parse(object?["updatedAt"] as? String),
                updatedByDevice: object?["updatedByDevice"] as? String
            ))
        case (413, _): return .tooLarge
        default:
            let message = object?["message"] as? String ?? code
            return .server(status, message)
        }
    }
}

enum CloudDate {
    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
