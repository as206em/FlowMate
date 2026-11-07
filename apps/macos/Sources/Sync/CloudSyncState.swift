import CryptoKit
import Foundation

/// What the user set in Settings › Cloud sync. The token is not here: it lives in the Keychain.
struct CloudSyncSettings: Codable, Equatable, Sendable {
    var enabled = false
    var serverURL = ""
    /// Shown on the server as who pushed last. Empty means this Mac's name.
    var deviceName = ""

    static var defaultDeviceName: String { Host.current().localizedName ?? "Mac" }
    var effectiveDeviceName: String {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Self.defaultDeviceName : name
    }

    init(enabled: Bool = false, serverURL: String = "", deviceName: String = "") {
        self.enabled = enabled
        self.serverURL = serverURL
        self.deviceName = deviceName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
    }
}

/// Saved as sync-state.json next to workspace.json. Only written once sync has been set up, so a
/// Mac that never turns sync on has no such file.
struct CloudSyncState: Codable, Equatable, Sendable {
    var settings = CloudSyncSettings()
    /// The server `workspaceId` and `lastSyncedVersion` belong to (normalized URL). A different
    /// server means starting over.
    var syncedServerURL: String?
    var workspaceId: String?
    var workspaceName: String?
    /// The cloud version this Mac's data matched last. 0: never synced with this workspace.
    var lastSyncedVersion = 0
    /// SHA-256 of the workspace as last synced. The local data is "changed" when its hash differs,
    /// which also catches edits made while sync was off or the app quit before a push.
    var lastSyncedHash: String?
    var lastSyncAt: Date?
    var lastError: String?
    /// Both sides changed: waiting for "Use cloud copy" or "Keep this Mac's copy".
    var conflict: CloudConflict?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(CloudSyncSettings.self, forKey: .settings) ?? CloudSyncSettings()
        syncedServerURL = try c.decodeIfPresent(String.self, forKey: .syncedServerURL)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        lastSyncedVersion = try c.decodeIfPresent(Int.self, forKey: .lastSyncedVersion) ?? 0
        lastSyncedHash = try c.decodeIfPresent(String.self, forKey: .lastSyncedHash)
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        conflict = try c.decodeIfPresent(CloudConflict.self, forKey: .conflict)
    }

    static func read(from url: URL) -> CloudSyncState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? LocalJSONWorkspaceRepository.makeDecoder().decode(CloudSyncState.self, from: data)
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LocalJSONWorkspaceRepository.makeEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// What Settings shows: the saved state plus what's happening right now.
struct CloudSyncStatus: Equatable, Sendable {
    var state = CloudSyncState()
    var hasToken = false
    var isSyncing = false
    /// The last attempt couldn't reach the server
    var isOffline = false
    /// This Mac has changes the cloud doesn't have yet (nil: unknown, sync is off)
    var localDirty: Bool?

    var isActive: Bool {
        state.settings.enabled && hasToken && CloudSyncClient.baseURL(from: state.settings.serverURL) != nil
    }
}

enum WorkspaceHash {
    /// The workspace's hash as the local file would store it (sorted keys, so stable).
    static func of(_ workspace: Workspace) -> String? {
        guard let data = try? LocalJSONWorkspaceRepository.makeEncoder().encode(workspace) else { return nil }
        return of(data)
    }

    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
