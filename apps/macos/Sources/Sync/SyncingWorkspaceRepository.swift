import Foundation

/// The local JSON file plus an optional copy on the FlowMate server.
///
/// The local file stays the source of truth: every save goes there first, exactly as without sync.
/// With sync on, a save also pushes the workspace to the server a moment later, and a launch pulls
/// the cloud copy when it is newer and this Mac has no changes of its own. When both sides changed
/// nothing is overwritten: the conflict waits for the user (Settings › Cloud sync).
///
/// With sync off (the default) this only passes calls through to the local file.
actor SyncingWorkspaceRepository: WorkspaceRepository {
    /// Keychain account of the server token
    static let tokenAccount = "cloudSyncToken"

    /// The app's repository: the default data file, the token from this channel's Keychain entry.
    static let shared = SyncingWorkspaceRepository(
        local: LocalJSONWorkspaceRepository(),
        tokenProvider: { KeychainSecretStore().secret(for: SyncingWorkspaceRepository.tokenAccount) }
    )

    nonisolated let local: LocalJSONWorkspaceRepository
    nonisolated let stateURL: URL
    private let tokenProvider: @Sendable () -> String?
    private let session: URLSession
    private let pushDelay: TimeInterval
    private let launchTimeout: TimeInterval

    private var state: CloudSyncState
    /// The workspace as last loaded or saved, and its hash (only kept while sync is on)
    private var latest: Workspace?
    private var latestHash: String?
    private var pendingPush: Task<Void, Never>?
    private var isSyncing = false
    private var isOffline = false
    private var statusHandler: (@Sendable (CloudSyncStatus) -> Void)?

    nonisolated var location: URL? { local.location }

    init(
        local: LocalJSONWorkspaceRepository,
        stateURL: URL? = nil,
        tokenProvider: @escaping @Sendable () -> String?,
        session: URLSession = CloudSyncClient.defaultSession,
        pushDelay: TimeInterval = 2,
        launchTimeout: TimeInterval = 4
    ) {
        self.local = local
        let stateURL = stateURL ?? local.fileURL.deletingLastPathComponent().appendingPathComponent("sync-state.json")
        self.stateURL = stateURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.pushDelay = pushDelay
        self.launchTimeout = launchTimeout
        state = CloudSyncState.read(from: stateURL) ?? CloudSyncState()
    }

    // MARK: - WorkspaceRepository

    func lastLoadRecovery() async -> WorkspaceLoadRecovery? {
        await local.lastLoadRecovery()
    }

    func load() async throws -> Workspace? {
        let stored = try await local.load()
        latest = stored
        guard isActive else {
            latestHash = nil
            return stored
        }
        latestHash = stored.flatMap(WorkspaceHash.of)
        // Don't hold the launch up for long: offline or slow means just the local data
        let replacement = await withTaskGroup(of: Workspace??.self) { group -> Workspace? in
            group.addTask { await self.reconcile(local: stored) }
            group.addTask { [launchTimeout] in
                try? await Task.sleep(nanoseconds: UInt64(launchTimeout * 1_000_000_000))
                return .some(nil)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
        publish()
        return replacement ?? stored
    }

    func save(_ workspace: Workspace) async throws {
        try await local.save(workspace)
        latest = workspace
        guard isActive else {
            latestHash = nil
            return
        }
        latestHash = WorkspaceHash.of(workspace)
        publish()
        guard state.conflict == nil, latestHash != state.lastSyncedHash else { return }
        schedulePush()
    }

    // MARK: - Settings and status

    func currentStatus() -> CloudSyncStatus {
        CloudSyncStatus(
            state: state,
            hasToken: !(tokenProvider() ?? "").isEmpty,
            isSyncing: isSyncing,
            isOffline: isOffline,
            localDirty: isActive ? (latestHash == nil ? nil : latestHash != state.lastSyncedHash) : nil
        )
    }

    func setStatusHandler(_ handler: @escaping @Sendable (CloudSyncStatus) -> Void) {
        statusHandler = handler
        handler(currentStatus())
    }

    /// Saves the settings. A different server address means a first sync with it.
    func updateSettings(_ settings: CloudSyncSettings) {
        if normalized(settings.serverURL) != normalized(state.settings.serverURL) {
            state.syncedServerURL = nil
        }
        state.settings = settings
        if !settings.enabled {
            pendingPush?.cancel()
            pendingPush = nil
            isOffline = false
        }
        persistState()
        publish()
    }

    /// The token changed: ask the server again which workspace it reaches.
    func credentialsChanged() {
        state.syncedServerURL = nil
        persistState()
        publish()
    }

    // MARK: - Actions

    /// Pushes this Mac's changes, or pulls the cloud copy when it is newer and nothing changed
    /// here. Returns the workspace to show when the cloud copy replaced the local one.
    func syncNow() async -> Workspace? {
        pendingPush?.cancel()
        pendingPush = nil
        if latest == nil { latest = try? await local.load() }
        latestHash = latest.flatMap(WorkspaceHash.of)
        return await reconcile(local: latest)
    }

    /// Conflict: replace this Mac's data with the cloud copy (the old file is kept next to it).
    func useCloudCopy() async throws -> Workspace {
        let client = try requireClient()
        setSyncing(true)
        defer { setSyncing(false) }
        do {
            let workspaceId = try await resolveWorkspace(client)
            guard let snapshot = try await client.snapshot(workspaceId: workspaceId) else { throw CloudSyncError.noSnapshot }
            let cloud = try snapshot.workspace()
            try await adopt(cloud, from: snapshot)
            return cloud
        } catch {
            record(error)
            throw error
        }
    }

    /// Conflict: overwrite the cloud copy with this Mac's data.
    func keepThisMacCopy() async throws {
        let client = try requireClient()
        if latest == nil { latest = try await local.load() }
        guard let workspace = latest else { throw CloudSyncError.noSnapshot }
        setSyncing(true)
        defer { setSyncing(false) }
        do {
            let workspaceId = try await resolveWorkspace(client)
            try await push(workspace, client: client, workspaceId: workspaceId, force: true)
        } catch {
            record(error)
            throw error
        }
    }

    /// Settings › Test connection: who the token belongs to. Changes nothing.
    nonisolated func testConnection(serverURL: String, token: String) async throws -> CloudMe {
        guard let url = CloudSyncClient.baseURL(from: serverURL) else { throw CloudSyncError.invalidURL }
        guard !token.isEmpty else { throw CloudSyncError.notConfigured }
        return try await CloudSyncClient(baseURL: url, token: token, session: session).me()
    }

    // MARK: - Sync

    private var isActive: Bool {
        state.settings.enabled && makeClient() != nil
    }

    private func makeClient() -> CloudSyncClient? {
        guard state.settings.enabled,
              let url = CloudSyncClient.baseURL(from: state.settings.serverURL),
              let token = tokenProvider(), !token.isEmpty else { return nil }
        return CloudSyncClient(baseURL: url, token: token, session: session)
    }

    private func requireClient() throws -> CloudSyncClient {
        guard let client = makeClient() else { throw CloudSyncError.notConfigured }
        return client
    }

    private func normalized(_ serverURL: String) -> String? {
        CloudSyncClient.baseURL(from: serverURL)?.absoluteString.lowercased()
    }

    /// Compares this Mac's data with the cloud copy and does the one safe thing: push, pull,
    /// nothing, or record a conflict. Returns the cloud workspace when it replaced the local one.
    private func reconcile(local localWorkspace: Workspace?) async -> Workspace? {
        guard let client = makeClient() else { return nil }
        setSyncing(true)
        defer { setSyncing(false) }
        do {
            let workspaceId = try await resolveWorkspace(client)
            let localHash = localWorkspace.flatMap(WorkspaceHash.of)
            let localChanged = localHash != nil && localHash != state.lastSyncedHash

            guard let snapshot = try await client.snapshot(workspaceId: workspaceId) else {
                // Nothing in the cloud yet: this Mac's data becomes the first copy
                if let localWorkspace {
                    try await push(localWorkspace, client: client, workspaceId: workspaceId, baseVersion: 0)
                }
                return nil
            }
            let cloud = try snapshot.workspace()
            let cloudHash = WorkspaceHash.of(cloud)

            if cloudHash != nil, cloudHash == localHash {
                markSynced(version: snapshot.version, hash: localHash, at: snapshot.updatedAt)
                return nil
            }
            if state.lastSyncedVersion > 0, snapshot.version == state.lastSyncedVersion {
                // The cloud hasn't moved: send what changed here
                if localChanged, let localWorkspace {
                    try await push(localWorkspace, client: client, workspaceId: workspaceId, baseVersion: snapshot.version)
                }
                return nil
            }
            if snapshot.version > state.lastSyncedVersion, !localChanged {
                guard !Task.isCancelled else { return nil }
                try await adopt(cloud, from: snapshot)
                return cloud
            }
            // Both changed (or a first sync with data on both sides): let the user choose
            state.conflict = CloudConflict(
                cloudVersion: snapshot.version,
                updatedAt: snapshot.updatedAt,
                updatedByDevice: snapshot.updatedByDevice
            )
            state.lastError = nil
            isOffline = false
            persistState()
            return nil
        } catch {
            record(error)
            return nil
        }
    }

    /// The workspace id on the server. Asks /v1/me the first time and after the server or token
    /// changed; a different workspace than before starts over at version 0.
    private func resolveWorkspace(_ client: CloudSyncClient) async throws -> String {
        let server = client.baseURL.absoluteString.lowercased()
        if let id = state.workspaceId, state.syncedServerURL == server { return id }
        let me = try await client.me()
        guard let workspace = me.primaryWorkspace else { throw CloudSyncError.notFound }
        // The same workspace again (token re-entered) keeps its sync position
        if workspace.id != state.workspaceId {
            state.lastSyncedVersion = 0
            state.lastSyncedHash = nil
            state.lastSyncAt = nil
            state.conflict = nil
        }
        state.workspaceId = workspace.id
        state.workspaceName = workspace.name
        state.syncedServerURL = server
        persistState()
        return workspace.id
    }

    private func push(
        _ workspace: Workspace,
        client: CloudSyncClient,
        workspaceId: String,
        baseVersion: Int? = nil,
        force: Bool = false
    ) async throws {
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(workspace)
        let result = try await client.push(
            workspaceId: workspaceId,
            workspaceJSON: data,
            schemaVersion: workspace.schemaVersion,
            baseVersion: baseVersion ?? state.lastSyncedVersion,
            deviceName: state.settings.effectiveDeviceName,
            force: force
        )
        markSynced(version: result.version, hash: WorkspaceHash.of(data), at: result.updatedAt)
    }

    /// Makes the cloud copy this Mac's data: keeps the current file as
    /// workspace.before-cloud-<time>.json, then saves the cloud workspace locally.
    private func adopt(_ cloud: Workspace, from snapshot: CloudSnapshot) async throws {
        let fileURL = local.fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let copy = fileURL.deletingPathExtension().appendingPathExtension("before-cloud-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: copy)
        }
        try await local.save(cloud)
        latest = cloud
        latestHash = WorkspaceHash.of(cloud)
        markSynced(version: snapshot.version, hash: latestHash, at: snapshot.updatedAt)
    }

    private func schedulePush() {
        pendingPush?.cancel()
        let delay = pushDelay
        pendingPush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.pushLatest()
        }
    }

    /// The debounced push after a save. A 409 here means another device pushed: a conflict.
    private func pushLatest() async {
        pendingPush = nil
        guard let client = makeClient(), state.conflict == nil, let workspace = latest else { return }
        guard WorkspaceHash.of(workspace) != state.lastSyncedHash else { return }
        setSyncing(true)
        defer { setSyncing(false) }
        do {
            let workspaceId = try await resolveWorkspace(client)
            try await push(workspace, client: client, workspaceId: workspaceId)
        } catch {
            record(error)
        }
    }

    private func markSynced(version: Int, hash: String?, at date: Date?) {
        state.lastSyncedVersion = version
        state.lastSyncedHash = hash
        state.lastSyncAt = Date()
        state.lastError = nil
        state.conflict = nil
        isOffline = false
        persistState()
    }

    private func record(_ error: Error) {
        if error is CancellationError { return }
        switch error as? CloudSyncError {
        case let .conflict(conflict):
            state.conflict = conflict
            state.lastError = nil
            isOffline = false
        case let .some(syncError) where syncError.isOffline:
            isOffline = true
            state.lastError = syncError.localizedDescription
        default:
            isOffline = false
            state.lastError = error.localizedDescription
        }
        let message = error.localizedDescription
        Task { @MainActor in Logger.shared.warning("Cloud sync: \(message)") }
        persistState()
    }

    private func setSyncing(_ value: Bool) {
        isSyncing = value
        publish()
    }

    private func persistState() {
        do {
            try state.write(to: stateURL)
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in Logger.shared.error("Couldn't save the cloud sync state: \(message)") }
        }
        publish()
    }

    private func publish() {
        statusHandler?(currentStatus())
    }
}
