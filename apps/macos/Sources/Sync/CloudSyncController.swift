import Combine
import Foundation

/// What Settings › Cloud sync talks to. Keeps the token in the Keychain, passes settings to the
/// repository and shows a replaced workspace (cloud copy) in the task store.
@MainActor
final class CloudSyncController: ObservableObject {
    static let shared = CloudSyncController(
        repository: .shared,
        store: TaskStore.shared,
        secrets: KeychainSecretStore()
    )

    @Published private(set) var status = CloudSyncStatus()
    /// A button's work is running (Sync now, Use cloud copy…)
    @Published private(set) var isWorking = false
    /// The last button's error, when it failed
    @Published var actionError: String?

    let repository: SyncingWorkspaceRepository
    private let store: TaskStore
    private let secrets: SecretStore

    init(repository: SyncingWorkspaceRepository, store: TaskStore, secrets: SecretStore) {
        self.repository = repository
        self.store = store
        self.secrets = secrets
        let update: @Sendable (CloudSyncStatus) -> Void = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        Task { await repository.setStatusHandler(update) }
    }

    var token: String { secrets.secret(for: SyncingWorkspaceRepository.tokenAccount) ?? "" }

    /// Saves the settings and token. Turning sync on (or changing where it goes) syncs right away.
    func apply(settings: CloudSyncSettings, token newToken: String) async {
        actionError = nil
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenChanged = trimmed != token
        if tokenChanged, !secrets.setSecret(trimmed, for: SyncingWorkspaceRepository.tokenAccount) {
            actionError = "Couldn't save the token in the Keychain."
            return
        }
        let wasEnabled = status.state.settings.enabled
        let serverChanged = status.state.settings.serverURL != settings.serverURL
        await repository.updateSettings(settings)
        if tokenChanged { await repository.credentialsChanged() }
        if settings.enabled, !wasEnabled || serverChanged || tokenChanged {
            await syncNow()
        }
    }

    func testConnection(serverURL: String, token: String) async throws -> CloudMe {
        try await repository.testConnection(
            serverURL: serverURL,
            token: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func syncNow() async {
        await run {
            // Write what's on screen first, so the comparison sees the latest edits
            await self.store.flush()
            if let cloud = await self.repository.syncNow() {
                await self.store.showSyncedWorkspace(cloud)
            }
        }
    }

    func useCloudCopy() async {
        await run {
            await self.store.discardPendingSave()
            let cloud = try await self.repository.useCloudCopy()
            await self.store.showSyncedWorkspace(cloud)
        }
    }

    func keepThisMacCopy() async {
        await run {
            await self.store.flush()
            try await self.repository.keepThisMacCopy()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
