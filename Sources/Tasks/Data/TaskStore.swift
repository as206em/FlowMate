import AppKit
import Combine
import Foundation

/// Which tasks a view shows: every project, or one.
enum TaskScope: Hashable, Sendable {
    case all
    case project(UUID)

    var projectId: UUID? {
        if case let .project(id) = self { return id }
        return nil
    }
}

/// Owns the task workspace for the whole app. Views read `workspace` (or the query helpers)
/// and change data only through the mutation methods, which save through the repository.
@MainActor
final class TaskStore: ObservableObject {
    /// App-wide instance backed by the local JSON file. Created on first use.
    static let shared: TaskStore = {
        let store = TaskStore(repository: LocalJSONWorkspaceRepository())
        Task { await store.load() }
        return store
    }()

    @Published private(set) var workspace: Workspace {
        didSet { ticker.setActive(!workspace.runningTimers.isEmpty) }
    }
    /// False until the first load finishes; UI should avoid editing before then.
    @Published private(set) var isLoaded = false
    /// Last load or save problem, shown as a banner ("Couldn't save · Retry · Show file").
    @Published private(set) var persistenceIssue: PersistenceIssue?
    /// The underlying message of `persistenceIssue`.
    var persistenceError: String? { persistenceIssue?.detail }
    /// True after a load failure that left the unreadable file in place: saving would overwrite
    /// it, so nothing is written until a reload works.
    private(set) var savesBlocked = false

    /// Ticks once a second while any timer runs. Observe it only in views that show live clocks.
    let ticker = TimerTicker()

    private let repository: WorkspaceRepository
    private let saveDelay: TimeInterval
    private var pendingSave: Task<Void, Never>?
    private var saveChain: Task<Void, Never>?
    private(set) var hasUnsavedChanges = false

    // Undo (TaskStore+Undo.swift)
    /// Snapshots to go back to, oldest first. Each holds the workspace from before one user action.
    @Published var undoStack: [UndoEntry] = []
    /// Snapshots undone, to redo, oldest first. Cleared by any new undoable change.
    @Published var redoStack: [UndoEntry] = []
    var undoGroupDepth = 0
    var undoGroupStart: (name: String, before: Workspace)?
    var undoGroupHasChanges = false
    /// Hand time adjustments made inside the open undo group
    var undoGroupTimeDelta: [UUID: TimeInterval] = [:]
    /// Set by an "Adjust time" edit just before its mutation, so the undo step can take it back out.
    var pendingTimeDelta: [UUID: TimeInterval] = [:]
    /// After an undo or redo, the next edit starts a new step even if it would coalesce.
    var undoCoalescingBlocked = false
    /// Clock for coalescing rapid edits; tests replace it.
    var clock: () -> Date = Date.init

    /// "Still working on X?": when you last answered Keep, per running task. Stored with the
    /// workspace preferences so it survives a relaunch; the prompt comes back one interval later.
    var longRunAcknowledged: [UUID: Date] { workspace.preferences.longRunKeptAt }

    init(repository: WorkspaceRepository, workspace: Workspace = .empty, saveDelay: TimeInterval = 0.5) {
        self.repository = repository
        self.workspace = workspace
        self.saveDelay = saveDelay
        ticker.setActive(!workspace.runningTimers.isEmpty)
    }

    /// A store with sample data and no disk access, for SwiftUI previews.
    static func preview(_ workspace: Workspace = .sample()) -> TaskStore {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(workspace), workspace: workspace)
        store.isLoaded = true
        return store
    }

    // MARK: - Loading and saving

    /// Loads the workspace from the repository. On first launch, seeds sample data (marked as such,
    /// so a banner can offer to clear it) and saves it. An unreadable file never turns into sample
    /// data: the store starts empty (or with the last good copy) and reports it as a banner.
    func load() async {
        savesBlocked = false
        do {
            if let stored = try await repository.load() {
                workspace = stored.migrated()
                if let recovery = await repository.lastLoadRecovery(), recovery.usedBackup {
                    persistenceIssue = PersistenceIssue(
                        kind: .recoveredFromBackup,
                        detail: recovery.movedAsideURL == nil
                            ? "The file was missing; loaded the backup."
                            : "The file couldn't be decoded and was kept as \(recovery.movedAsideURL?.lastPathComponent ?? "a copy"); loaded the backup.",
                        fileURL: recovery.movedAsideURL ?? repository.location
                    )
                } else {
                    persistenceIssue = nil
                }
            } else {
                workspace = .sample()
                persistenceIssue = nil
                hasUnsavedChanges = true
                await flush()
            }
        } catch {
            Logger.shared.error("Failed to load task workspace", error: error)
            let recovery = await repository.lastLoadRecovery()
            // Start empty rather than with sample data, and never write over a file still in place.
            workspace = .empty
            hasUnsavedChanges = false
            savesBlocked = recovery?.movedAsideURL == nil && repository.location != nil
            persistenceIssue = PersistenceIssue(
                kind: .loadFailed,
                detail: error.localizedDescription,
                fileURL: recovery?.movedAsideURL ?? repository.location
            )
        }
        clearUndoHistory()
        isLoaded = true
    }

    /// The data file, for "Show file" (nil when the repository isn't a local file).
    var dataFileURL: URL? { repository.location }

    /// The banner's Retry: saves again after a failed save, or reloads after a failed load that
    /// left the file in place.
    func retryPersistence() async {
        guard let issue = persistenceIssue else { return }
        switch issue.kind {
        case .saveFailed:
            hasUnsavedChanges = true
            await flush()
        case .loadFailed where savesBlocked:
            await load()
        case .loadFailed, .recoveredFromBackup:
            persistenceIssue = nil
        }
    }

    /// Hides the banner (load notices only; a failed save stays until a save works).
    func dismissPersistenceIssue() {
        guard let issue = persistenceIssue, issue.kind != .saveFailed else { return }
        persistenceIssue = nil
    }

    /// Saves now if there are unsaved changes (also cancels a pending debounced save).
    func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges, !savesBlocked else {
            await saveChain?.value
            return
        }
        hasUnsavedChanges = false
        let snapshot = workspace
        let previous = saveChain
        let repository = repository
        // Inherits the main actor; only the repository call runs elsewhere.
        let save = Task { [weak self] in
            await previous?.value
            do {
                try await repository.save(snapshot)
                if self?.persistenceIssue?.kind == .saveFailed { self?.persistenceIssue = nil }
            } catch {
                self?.persistenceIssue = PersistenceIssue(
                    kind: .saveFailed,
                    detail: error.localizedDescription,
                    fileURL: repository.location
                )
                self?.hasUnsavedChanges = true
                Logger.shared.error("Failed to save task workspace", error: error)
            }
        }
        saveChain = save
        await save.value
    }

    /// Synchronous save for app termination, when the run loop won't wait for async work.
    /// Must not hop back to the main actor, which this call blocks for up to `timeout`.
    func flushBlocking(timeout: TimeInterval = 3) {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges, !savesBlocked else { return }
        hasUnsavedChanges = false
        let snapshot = workspace
        let repository = repository
        let done = DispatchSemaphore(value: 0)
        // Logger is main-actor bound and the main thread is blocked here, so the error is
        // carried back and logged after the wait.
        let failure = SaveFailureBox()
        Task.detached {
            do {
                try await repository.save(snapshot)
            } catch {
                failure.error = error
            }
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            Logger.shared.error("Saving tasks on quit timed out after \(timeout)s; the last changes may be lost")
        } else if let error = failure.error {
            Logger.shared.error("Failed to save tasks on quit; the last changes are lost", error: error)
        }
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Applies a change to the workspace and schedules a debounced save.
    /// - Parameters:
    ///   - action: Name of the undo step ("Delete task"), shown in the undo toast.
    ///   - coalesce: Edits with the same key in quick succession (typing a title) share one undo step.
    ///   - recordsUndo: False for changes that undo must not revert on their own (timers).
    func mutate(
        _ action: String = "Edit",
        coalesce: String? = nil,
        recordsUndo: Bool = true,
        _ change: (inout Workspace) -> Void
    ) {
        // While the unreadable file is still in place nothing can be saved, so an edit would only
        // be lost on Retry or quit. Keep the data as it is until a reload works (see the banner).
        guard !savesBlocked else { return }
        var copy = workspace
        change(&copy)
        // Every task keeps a status of its own project's workflow, whatever the change did
        copy.normalizeStatuses()
        guard copy != workspace else { return }
        let before = workspace
        workspace = copy
        if recordsUndo { recordUndo(action, before: before, coalesce: coalesce) }
        scheduleSave()
    }

    /// Replaces the workspace without touching undo history (undo and redo themselves).
    func replaceWorkspace(_ workspace: Workspace) {
        guard workspace != self.workspace else { return }
        self.workspace = workspace
        scheduleSave()
    }

    /// Changes one task and stamps `updatedAt`.
    func updateTask(
        _ id: UUID,
        now: Date = Date(),
        action: String = "Edit task",
        coalesce: String? = nil,
        _ change: (inout TaskItem) -> Void
    ) {
        mutate(action, coalesce: coalesce) { ws in
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { return }
            var task = ws.tasks[i]
            change(&task)
            guard task != ws.tasks[i] else { return }
            task.updatedAt = now
            ws.tasks[i] = task
        }
    }
}

/// Hands an error from the detached quit-time save back to the blocked main thread.
private final class SaveFailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    var error: Error? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Publishes the current time once a second, only while active, so idle views don't redraw.
@MainActor
final class TimerTicker: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?

    var isActive: Bool { timer != nil }

    func setActive(_ active: Bool) {
        if active, timer == nil {
            now = Date()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.now = Date() }
            }
            timer.tolerance = 0.1
            // .common keeps it ticking while menus are open
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !active, let timer {
            timer.invalidate()
            self.timer = nil
            now = Date()
        }
    }
}
