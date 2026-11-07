import Foundation

/// Persistence boundary for the task feature. The UI and TaskStore only talk to this protocol,
/// so the local JSON store can later be swapped for a backend-backed implementation.
protocol WorkspaceRepository: Sendable {
    /// Returns the stored workspace, or nil when nothing has been saved yet (first launch).
    func load() async throws -> Workspace?
    /// Replaces the stored workspace.
    func save(_ workspace: Workspace) async throws
    /// What happened during the last `load()` when the stored data couldn't be read as is
    /// (for the "Couldn't read your tasks" banner). nil when the load was clean.
    func lastLoadRecovery() async -> WorkspaceLoadRecovery?
    /// The file the data lives in, for "Show file". nil when the data isn't a local file.
    var location: URL? { get }
}

extension WorkspaceRepository {
    func lastLoadRecovery() async -> WorkspaceLoadRecovery? { nil }
    var location: URL? { nil }
}

/// The stored data couldn't be read and was set aside, so nothing is silently overwritten.
struct WorkspaceLoadRecovery: Equatable, Sendable {
    /// Where the unreadable file was moved, if it could be moved.
    var movedAsideURL: URL?
    /// True when the last good copy (the backup) was loaded instead.
    var usedBackup: Bool
}

/// A load or save problem the UI shows as a banner ("Couldn't save · Retry · Show file").
struct PersistenceIssue: Equatable {
    enum Kind: Equatable {
        /// The last save failed; the changes are still in memory. Retry saves again.
        case saveFailed
        /// The file couldn't be read and there was no good backup: FlowMate started empty.
        case loadFailed
        /// The file couldn't be read; the last good copy was loaded instead.
        case recoveredFromBackup
    }

    var kind: Kind
    /// The underlying error, for the banner's help text and the log.
    var detail: String
    /// The file "Show file" reveals: the moved-aside file after a bad load, else the data file.
    var fileURL: URL?

    var title: String {
        switch kind {
        case .saveFailed: return "Couldn't save your tasks"
        case .loadFailed: return "Couldn't read your tasks file"
        case .recoveredFromBackup: return "Your tasks file couldn't be read"
        }
    }

    var message: String {
        switch kind {
        case .saveFailed:
            return "Your changes are kept while FlowMate is open. Retry, or check the file's folder."
        case .loadFailed:
            return fileURL == nil
                ? "FlowMate started with no data. Nothing was overwritten."
                : "FlowMate started with no data. The damaged file was kept next to it, so nothing was lost."
        case .recoveredFromBackup:
            return "FlowMate loaded the last good copy instead. Nothing was overwritten."
        }
    }
}

/// Keeps the workspace in memory only. For tests and SwiftUI previews.
actor InMemoryWorkspaceRepository: WorkspaceRepository {
    private(set) var stored: Workspace?
    private(set) var saveCount = 0

    init(_ workspace: Workspace? = nil) {
        stored = workspace
    }

    func load() async throws -> Workspace? { stored }

    func save(_ workspace: Workspace) async throws {
        stored = workspace
        saveCount += 1
    }

    nonisolated var location: URL? { nil }
}
