import Foundation

/// Stores the workspace as JSON at ~/Library/Application Support/FlowMate/workspace.json
/// (FLOWMATE_DATA_DIR or FLOWMATE_WORKSPACE_FILE move it for a test copy of the app).
///
/// - Writes are atomic.
/// - After every successful load the file is copied to workspace.json.bak (the last good file).
/// - If the main file can't be decoded it is moved aside (workspace.corrupt-<time>.json) and the
///   .bak is tried instead, so a bad write never silently wipes the user's data.
actor LocalJSONWorkspaceRepository: WorkspaceRepository {
    enum RepositoryError: LocalizedError {
        case unreadable(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case let .unreadable(url, underlying):
                return "Could not read \(url.lastPathComponent): \(underlying.localizedDescription)"
            }
        }
    }

    let fileURL: URL
    private let fileManager = FileManager.default
    private var recovery: WorkspaceLoadRecovery?

    nonisolated var location: URL? { fileURL }

    func lastLoadRecovery() async -> WorkspaceLoadRecovery? { recovery }

    var backupURL: URL { fileURL.appendingPathExtension("bak") }

    init(fileURL: URL = LocalJSONWorkspaceRepository.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Set this environment variable to a file path to run against other data (smoke tests, a
    /// second copy of the app) without touching the real workspace.
    static let fileOverrideKey = "FLOWMATE_WORKSPACE_FILE"

    static var defaultFileURL: URL {
        if let path = ProcessInfo.processInfo.environment[fileOverrideKey], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        // Application Support/FlowMate, or FLOWMATE_DATA_DIR when set
        return AppDataLocation.directory.appendingPathComponent("workspace.json")
    }

    func load() async throws -> Workspace? {
        recovery = nil
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Main file missing but a backup exists: recover from it, and say so
            guard let backup = try? decode(at: backupURL) else { return nil }
            recovery = WorkspaceLoadRecovery(movedAsideURL: nil, usedBackup: true)
            return backup
        }
        do {
            let workspace = try decode(at: fileURL)
            keepBackup()
            return workspace
        } catch {
            let aside = moveAsideCorruptFile()
            if let backup = try? decode(at: backupURL) {
                recovery = WorkspaceLoadRecovery(movedAsideURL: aside, usedBackup: true)
                return backup
            }
            recovery = WorkspaceLoadRecovery(movedAsideURL: aside, usedBackup: false)
            throw RepositoryError.unreadable(fileURL, underlying: error)
        }
    }

    func save(_ workspace: Workspace) async throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(workspace)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Helpers

    private func decode(at url: URL) throws -> Workspace {
        let data = try Data(contentsOf: url)
        return try Self.makeDecoder().decode(Workspace.self, from: data).migrated()
    }

    private func keepBackup() {
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.copyItem(at: fileURL, to: backupURL)
    }

    /// Moves the unreadable file out of the way (or, when it can't be moved, copies it), so later
    /// saves never overwrite the only copy. Returns where it went, or nil if neither worked.
    private func moveAsideCorruptFile() -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        if (try? fileManager.moveItem(at: fileURL, to: aside)) != nil { return aside }
        if (try? fileManager.copyItem(at: fileURL, to: aside)) != nil { return aside }
        return nil
    }

    /// Dates are written as ISO 8601 with fractional seconds so timer start times round-trip exactly.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter().string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Accepts ISO 8601 with or without fractional seconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalFormatter().date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return decoder
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
