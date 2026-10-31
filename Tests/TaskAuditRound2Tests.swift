import XCTest
@testable import FlowMate

/// Audit round 2: Keep answers survive a relaunch (schema 5), the window restores collapsed groups
/// and expanded sidebar projects, a second sidebar click opens the project panel, and the data
/// file's recovery paths.
@MainActor
final class TaskAuditRound2Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Round2Tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    // MARK: - #26 Keep is saved

    func testKeepAnswerIsSavedAndClearedWhenTheTimerStops() async throws {
        let url = tempDir.appendingPathComponent("workspace.json")
        let repo = LocalJSONWorkspaceRepository(fileURL: url)
        let store = TaskStore(repository: repo, saveDelay: 0.01)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        let id = store.addTask(title: "Long", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        store.clearUndoHistory()

        let later = t0.addingTimeInterval(3 * 3600 + 1)
        XCTAssertEqual(store.longRunningTasks(now: later).map(\.id), [id])
        store.keepRunning(id, now: later)
        XCTAssertFalse(store.canUndo, "Keep isn't an undo step")
        XCTAssertTrue(store.longRunningTasks(now: later.addingTimeInterval(3600)).isEmpty)
        await store.flush()

        // Relaunch: the answer is still there
        let reloaded = TaskStore(repository: LocalJSONWorkspaceRepository(fileURL: url), saveDelay: 0.01)
        await reloaded.load()
        XCTAssertEqual(reloaded.longRunAcknowledged[id]?.timeIntervalSince1970 ?? 0, later.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertTrue(reloaded.longRunningTasks(now: later.addingTimeInterval(3600)).isEmpty, "doesn't ask early after a relaunch")
        XCTAssertEqual(reloaded.longRunningTasks(now: later.addingTimeInterval(3 * 3600 + 1)).map(\.id), [id])

        // Pausing ends the session, so the answer goes
        reloaded.pauseTimer(id, now: later.addingTimeInterval(60))
        XCTAssertNil(reloaded.longRunAcknowledged[id])
    }

    func testVersion4FileLoadsAndKeepAnswersDecodeTolerantly() throws {
        let pid = UUID(), tid = UUID(), stale = UUID()
        let json = """
        {"schemaVersion": 4, "projects": [{"id": "\(pid.uuidString)", "name": "Old"}],
         "milestones": [], "tasks": [{"id": "\(tid.uuidString)", "projectId": "\(pid.uuidString)", "title": "T"}],
         "runningTimers": {"\(tid.uuidString)": "2026-10-01T10:00:00Z"},
         "preferences": {"showsMenuBarClock": true}}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(Workspace.currentSchemaVersion, 8)
        XCTAssertEqual(ws.schemaVersion, 8)
        XCTAssertEqual(ws.tasks.count, 1)
        XCTAssertEqual(ws.preferences.longRunKeptAt, [:])
        XCTAssertTrue(ws.preferences.showsMenuBarClock)

        let withAnswers = """
        {"schemaVersion": 5, "projects": [{"id": "\(pid.uuidString)", "name": "Old"}],
         "tasks": [{"id": "\(tid.uuidString)", "projectId": "\(pid.uuidString)", "title": "T"}],
         "runningTimers": {"\(tid.uuidString)": "2026-10-01T10:00:00Z"},
         "preferences": {"longRunKeptAt": {"\(tid.uuidString)": "2026-10-01T13:00:00.250Z",
                                           "\(stale.uuidString)": "2026-10-01T13:00:00Z",
                                           "not-a-uuid": "2026-10-01T13:00:00Z",
                                           "\(UUID().uuidString)": 12}}}
        """
        let loaded = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(withAnswers.utf8)).migrated()
        XCTAssertEqual(Array(loaded.preferences.longRunKeptAt.keys), [tid], "bad, stale and non-running entries are dropped")

        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(loaded)
        let back = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(back.preferences, loaded.preferences)
    }

    func testUndoKeepsKeepAnswers() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Long", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        store.setPriority(id, .high)
        store.keepRunning(id, now: t0.addingTimeInterval(4 * 3600))
        store.undo(now: t0.addingTimeInterval(4 * 3600))
        XCTAssertNotNil(store.longRunAcknowledged[id], "settings aren't undone")
    }

    // MARK: - #40 Window state

    func testWindowRestoresCollapsedGroupsAndExpandedProjects() async throws {
        let (store, pid) = await makeStore()
        let suite = "FlowMateRound2-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TasksViewModel(defaults: defaults)
        XCTAssertTrue(model.isCollapsed(TaskGroupValue.status(.done).key), "Done starts collapsed")
        model.toggleGroup(TaskGroupValue.status(.done).key)
        model.toggleGroup(TaskGroupValue.status(.todo).key)
        model.toggleProjectExpanded(pid)

        let restored = TasksViewModel(defaults: defaults)
        XCTAssertFalse(restored.isCollapsed(TaskGroupValue.status(.done).key))
        XCTAssertTrue(restored.isCollapsed(TaskGroupValue.status(.todo).key))
        XCTAssertTrue(restored.isProjectExpanded(pid))

        // A deleted project is forgotten
        store.deleteProject(pid)
        restored.dropStaleIds(store)
        XCTAssertFalse(restored.isProjectExpanded(pid))
        XCTAssertFalse(TasksViewModel(defaults: defaults).isProjectExpanded(pid))
    }

    func testOlderWindowStateKeepsDefaultCollapsedGroups() throws {
        let suite = "FlowMateRound2-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"scope": "all", "tabs": {"all": "list"}}"#.utf8), forKey: TasksViewModel.windowStateKey)
        let model = TasksViewModel(defaults: defaults)
        XCTAssertEqual(model.tab, .list)
        XCTAssertTrue(model.isCollapsed(TaskGroupValue.status(.done).key))
        XCTAssertTrue(model.expandedProjects.isEmpty)
    }

    // MARK: - #1 Sidebar click

    func testSecondSidebarClickOpensProjectPanel() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.clickSidebarProject(pid)
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertNil(model.openDetail, "the first click shows the project")
        model.clickSidebarProject(pid)
        XCTAssertEqual(model.openDetail, .project(pid), "a second click opens its panel")
        model.clickSidebarProject(pid)
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertNil(model.openDetail, "with the panel open, a click closes it again")

        let other = store.addProject(name: "Beta", now: t0)!
        model.openProject(pid)
        model.clickSidebarProject(other)
        XCTAssertEqual(model.scope, .project(other))
        XCTAssertNil(model.openDetail, "another project switches and closes the panel")
    }

    func testUnarchiveFromTheWindowShowsUndoToast() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.archiveProject(pid, store: store)
        model.unarchiveProject(pid, store: store)
        XCTAssertFalse(store.isArchived(pid))
        XCTAssertEqual(model.toast?.message, "Project unarchived")
        model.undoFromToast(store)
        XCTAssertTrue(store.isArchived(pid))
    }

    // MARK: - #31 Recovery paths

    func testMissingFileWithBackupLoadsBackupAndSaysSo() async throws {
        let url = tempDir.appendingPathComponent("workspace.json")
        let repo = LocalJSONWorkspaceRepository(fileURL: url)
        var ws = Workspace.sample(now: t0)
        ws.preferences.sampleProjectIds = []
        try await repo.save(ws)
        _ = try await repo.load() // keeps workspace.json.bak
        try FileManager.default.removeItem(at: url)

        let store = TaskStore(repository: repo, saveDelay: 0.01)
        await store.load()
        XCTAssertEqual(store.workspace.projects.map(\.name), ["FlowMate"], "not sample data over the backup")
        XCTAssertEqual(store.persistenceIssue?.kind, .recoveredFromBackup)
        XCTAssertEqual(store.persistenceError, "The file was missing; loaded the backup.")
    }
}
