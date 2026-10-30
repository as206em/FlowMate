import XCTest
@testable import FlowMate

/// Menu bar and polish: save and load problems, sample data, empty states, the menu's project
/// tasks and keyboard rows, the quick-add target and global shortcut, and restoring the window.
@MainActor
final class TaskMenuPolishBatch5Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Batch5Tests-\(UUID().uuidString)")
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

    /// Saves fail while `failing` is true
    private actor FlakyRepository: WorkspaceRepository {
        var failing = true
        private(set) var stored: Workspace?

        struct Failure: LocalizedError { var errorDescription: String? { "Disk full" } }

        func setFailing(_ value: Bool) { failing = value }
        func load() async throws -> Workspace? { .empty }
        func save(_ workspace: Workspace) async throws {
            if failing { throw Failure() }
            stored = workspace
        }
        nonisolated var location: URL? { URL(fileURLWithPath: "/tmp/flowmate-test/workspace.json") }
    }

    // MARK: - #31 Save and load problems

    func testFailedSaveShowsIssueAndRetrySaves() async {
        let repo = FlakyRepository()
        let store = TaskStore(repository: repo, saveDelay: 0.01)
        await store.load()
        XCTAssertNil(store.persistenceIssue)

        _ = store.addProject(name: "Alpha", now: t0)
        await store.flush()
        XCTAssertEqual(store.persistenceIssue?.kind, .saveFailed)
        XCTAssertEqual(store.persistenceIssue?.title, "Couldn't save your tasks")
        XCTAssertEqual(store.persistenceIssue?.fileURL?.lastPathComponent, "workspace.json")
        XCTAssertEqual(store.persistenceError, "Disk full")
        XCTAssertTrue(store.hasUnsavedChanges, "the changes wait for the next save")

        store.dismissPersistenceIssue()
        XCTAssertNotNil(store.persistenceIssue, "a failed save can't be dismissed, only fixed")

        await repo.setFailing(false)
        await store.retryPersistence()
        XCTAssertNil(store.persistenceIssue)
        let saved = await repo.stored
        XCTAssertEqual(saved?.projects.map(\.name), ["Alpha"])
    }

    func testCorruptFileWithoutBackupStartsEmptyNotSample() async throws {
        let url = tempDir.appendingPathComponent("workspace.json")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        let repo = LocalJSONWorkspaceRepository(fileURL: url)
        let store = TaskStore(repository: repo, saveDelay: 0.01)
        await store.load()

        XCTAssertTrue(store.workspace.projects.isEmpty, "no sample data over a damaged file")
        XCTAssertEqual(store.persistenceIssue?.kind, .loadFailed)
        let aside = try XCTUnwrap(store.persistenceIssue?.fileURL)
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("workspace.corrupt-"))
        XCTAssertEqual(try String(contentsOf: aside), "{ not json", "the damaged file is kept")
        XCTAssertFalse(store.savesBlocked, "the file was moved aside, so saving is safe")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing written until you change something")

        store.dismissPersistenceIssue()
        XCTAssertNil(store.persistenceIssue)
    }

    func testCorruptFileWithBackupLoadsItAndSaysSo() async throws {
        let url = tempDir.appendingPathComponent("workspace.json")
        let repo = LocalJSONWorkspaceRepository(fileURL: url)
        var ws = Workspace.sample(now: t0)
        ws.preferences.sampleProjectIds = []
        try await repo.save(ws)
        _ = try await repo.load() // keeps workspace.json.bak
        try Data("garbage".utf8).write(to: url)

        let store = TaskStore(repository: repo, saveDelay: 0.01)
        await store.load()
        XCTAssertEqual(store.workspace.projects.map(\.name), ["FlowMate"])
        XCTAssertEqual(store.persistenceIssue?.kind, .recoveredFromBackup)
        XCTAssertTrue(store.persistenceIssue?.fileURL?.lastPathComponent.hasPrefix("workspace.corrupt-") ?? false)

        // The next clean load has nothing to report
        try await repo.save(ws)
        await store.load()
        XCTAssertNil(store.persistenceIssue)
    }

    // MARK: - #32 Sample data

    func testFirstLaunchMarksSampleDataAndClearIsUndoable() async {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(nil), saveDelay: 0.01)
        await store.load()
        XCTAssertTrue(store.showsSampleDataBanner)
        XCTAssertEqual(store.sampleProjects.map(\.name), ["FlowMate"])
        let sample = store.sampleProjects[0]
        store.startTimer(store.tasks(of: sample.id)[0].id, now: t0)
        let mine = store.addProject(name: "Mine", now: t0)!

        let model = TasksViewModel()
        model.select(.project(sample.id))
        model.clearSampleData(store)
        XCTAssertEqual(store.projects.map(\.id), [mine])
        XCTAssertTrue(store.workspace.runningTimers.isEmpty)
        XCTAssertFalse(store.showsSampleDataBanner)
        XCTAssertEqual(model.scope, .all, "left the cleared project")
        XCTAssertEqual(model.toast?.message, "Sample data cleared")

        model.undoFromToast(store)
        XCTAssertNotNil(store.project(sample.id))
        XCTAssertTrue(store.showsSampleDataBanner, "undo brings the sample back as sample")

        store.keepSampleData()
        XCTAssertFalse(store.showsSampleDataBanner)
        XCTAssertNotNil(store.project(sample.id), "Keep it leaves the projects")
        store.undo()
        XCTAssertFalse(store.showsSampleDataBanner, "Keep isn't undone by an older step")
    }

    func testVersion3FileLoadsWithoutSampleMarker() throws {
        let pid = UUID()
        let json = """
        {"schemaVersion": 3, "projects": [{"id": "\(pid.uuidString)", "name": "Old"}],
         "milestones": [], "tasks": [], "runningTimers": {},
         "preferences": {"lastProjectId": "\(pid.uuidString)", "sampleProjectIds": ["\(UUID().uuidString)", 7, "\(pid.uuidString)"]}}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertGreaterThanOrEqual(Workspace.currentSchemaVersion, 4)
        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(ws.preferences.sampleProjectIds, [pid], "bad and dangling ids are dropped")
        XCTAssertEqual(ws.preferences.lastProjectId, pid)

        let plain = """
        {"schemaVersion": 3, "projects": [], "preferences": {"showsMenuBarClock": true}}
        """
        let old = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(plain.utf8)).migrated()
        XCTAssertEqual(old.preferences.sampleProjectIds, [])
        XCTAssertTrue(old.preferences.showsMenuBarClock)

        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(ws)
        let back = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(back.preferences, ws.preferences)
        XCTAssertEqual(back.schemaVersion, Workspace.currentSchemaVersion)
    }

    // MARK: - #33 Empty states

    func testEmptyReasonsExplainWhyNothingShows() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.select(.project(pid))
        XCTAssertEqual(model.listEmptyReason(store), .noTasks)
        XCTAssertEqual(model.boardEmptyReason(store), .noTasks)

        let task = store.addTask(title: "Later", projectId: pid, sprintSlot: .backlog, now: t0)!
        XCTAssertNil(model.listEmptyReason(store))
        XCTAssertEqual(model.boardEmptyReason(store), .sprintEmpty(waiting: 1))

        model.filter.query = "nothing like it"
        XCTAssertEqual(model.listEmptyReason(store), .noMatches)
        XCTAssertEqual(model.boardEmptyReason(store), .noMatches)
        model.filter = TaskFilter()

        store.setSprintSlot(task, .active)
        XCTAssertNil(model.boardEmptyReason(store))
    }

    // MARK: - #34 Menu project tasks and #35 keyboard rows

    func testMenuProjectTasksAndExpansion() async {
        let (store, pid) = await makeStore()
        let later = store.addTask(title: "Later", projectId: pid, sprintSlot: .next, now: t0)!
        let idea = store.addTask(title: "Idea", projectId: pid, sprintSlot: .backlog, now: t0)!
        var listed = store.menuProjectTasks(pid)
        XCTAssertFalse(listed.fromSprint)
        XCTAssertEqual(listed.tasks.map(\.id), [later, idea], "with an empty sprint: Next, then Backlog")

        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let done = store.addTask(title: "Done", projectId: pid, now: t0)!
        store.setStatus(done, .done)
        listed = store.menuProjectTasks(pid)
        XCTAssertTrue(listed.fromSprint)
        XCTAssertEqual(listed.tasks.map(\.id), [a], "open sprint tasks only")

        var expansion = MenuExpansion()
        XCTAssertFalse(expansion.isExpanded(pid, running: false))
        XCTAssertTrue(expansion.isExpanded(pid, running: true), "a running project starts open")
        expansion.toggle(pid, running: false)
        XCTAssertTrue(expansion.isExpanded(pid, running: false))
        expansion.toggle(pid, running: true)
        XCTAssertFalse(expansion.isExpanded(pid, running: true), "you can close a running one")
        expansion.set(pid, expanded: true, running: true)
        XCTAssertTrue(expansion.isExpanded(pid, running: true))
    }

    func testMenuBrowseRowsAndHighlight() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.startTimer(b, now: t0)

        // Alpha runs, so it's open; Beta is closed
        var browse = store.menuBrowseItems(expansion: MenuExpansion())
        XCTAssertEqual(browse.items, [.running(b), .project(pid), .task(a), .task(b), .project(other)])

        XCTAssertEqual(browse.moving(nil, by: 1), .running(b), "↓ from nothing starts at the top")
        XCTAssertEqual(browse.moving(nil, by: -1), .project(other), "↑ from nothing starts at the bottom")
        XCTAssertEqual(browse.moving(.task(a), by: 1), .task(b))
        XCTAssertEqual(browse.moving(.project(other), by: 1), .project(other), "clamped")
        XCTAssertNil(browse.validated(.task(UUID())))

        var expansion = MenuExpansion()
        expansion.set(pid, expanded: false, running: true)
        browse = store.menuBrowseItems(expansion: expansion, taskLimit: 1)
        XCTAssertEqual(browse.items, [.running(b), .project(pid), .project(other)])
        expansion.set(pid, expanded: true, running: true)
        browse = store.menuBrowseItems(expansion: expansion, taskLimit: 1)
        XCTAssertEqual(browse.items, [.running(b), .project(pid), .task(a), .project(other)], "only the shown rows")
        XCTAssertEqual(MenuRowItem.running(b).taskId, b)
        XCTAssertEqual(MenuRowItem.project(pid).projectId, pid)
    }

    // MARK: - #36 Quick-add target

    func testMenuQuickAddTargetIsTheLastProjectUsed() async {
        let (store, pid) = await makeStore()
        let beta = store.addProject(name: "Beta", now: t0)!
        let running = store.addTask(title: "Run", projectId: beta, now: t0)!
        store.startTimer(running, now: t0)
        XCTAssertEqual(store.menuQuickAddTarget?.id, pid, "not the running timer's project")

        store.rememberProject(beta)
        XCTAssertEqual(store.menuQuickAddTarget?.id, beta)
        let outcome = store.quickAddTask("Ship it !high ~90m", projectId: pid, now: t0)
        XCTAssertEqual(outcome?.applied, ["High", "1h 30m"])
        XCTAssertEqual(store.menuQuickAddTarget?.id, pid, "adding remembers the project")

        XCTAssertEqual(store.quickAddPreview("Fix !low ~1h @nope", projectId: pid, now: t0),
                       ["Low", "◆ No milestone “nope”", "1h"])
        XCTAssertEqual(store.quickAddPreview("Plain", projectId: pid), [])
    }

    // MARK: - #37 Global quick-add shortcut

    private final class MockShortcuts: KeyboardShortcutManagerProtocol {
        var current: String?
        func setupShortcut(_ shortcut: String, handler: @escaping () -> Void) -> Bool {
            guard KeyboardShortcutManager.isValidShortcut(shortcut) else { return false }
            current = shortcut
            return true
        }
        func removeShortcut() { current = nil }
    }

    func testQuickAddShortcutIsConfigurableAndNeverClashesWithProofreading() {
        XCTAssertTrue(KeyboardShortcutManager.isSameShortcut("cmd+.", "command+period"))
        XCTAssertFalse(KeyboardShortcutManager.isSameShortcut("command+.", "control+option+n"))
        XCTAssertFalse(KeyboardShortcutManager.isSameShortcut("", ""))

        let url = tempDir.appendingPathComponent("config.json")
        let config = ConfigurationManager(configURL: url)
        let proofreading = MockShortcuts()
        let quickAdd = MockShortcuts()
        let appState = AppState(configurationManager: config, statusManager: StatusManager(),
                                keyboardShortcutManager: proofreading, quickAddShortcutManager: quickAdd)
        XCTAssertEqual(appState.quickAddShortcut, AppSettings.defaultQuickAddShortcut)
        XCTAssertEqual(quickAdd.current, "control+option+n")
        XCTAssertEqual(QuickAddPanel.shortcutKeys, ["⌃", "⌥", "N"])

        XCTAssertFalse(appState.updateQuickAddShortcut("cmd+."), "the proofreading shortcut is taken")
        XCTAssertNotNil(appState.quickAddShortcutError)
        XCTAssertEqual(quickAdd.current, "control+option+n", "the old one stays active")
        XCTAssertFalse(appState.updateQuickAddShortcut("n"), "a bare letter would fire while typing")

        XCTAssertTrue(appState.updateQuickAddShortcut("control+shift+space"))
        XCTAssertNil(appState.quickAddShortcutError)
        XCTAssertEqual(config.getAppSettings().quickAddShortcut, "control+shift+space")

        appState.updateKeyboardShortcut("control+shift+space")
        XCTAssertNotNil(appState.shortcutError, "proofreading can't take quick add's keys either")
        XCTAssertEqual(appState.keyboardShortcut, "command+.")

        XCTAssertTrue(appState.updateQuickAddShortcut(""))
        XCTAssertNil(quickAdd.current, "off")
        XCTAssertNil(QuickAddPanel.shortcutKeys)
        XCTAssertEqual(AppState.keyCaps("command+shift+p"), ["⇧", "⌘", "P"])
    }

    func testQuickAddBoxAddsWithTokensAndRemembersProject() async {
        let (store, pid) = await makeStore()
        let beta = store.addProject(name: "Beta", now: t0)!
        let box = QuickAddBoxModel()
        box.prepare(store: store)
        XCTAssertEqual(box.projectId, pid)
        box.projectId = beta
        box.text = "Write notes !high"
        let id = box.add(store: store)
        XCTAssertEqual(store.task(id!)?.projectId, beta)
        XCTAssertEqual(store.task(id!)?.priority, .high)
        XCTAssertEqual(box.added, "Added to Beta · High")
        XCTAssertEqual(box.text, "")
        XCTAssertEqual(store.preferences.lastProjectId, beta)

        box.prepare(store: store)
        XCTAssertNil(box.added)
        XCTAssertEqual(box.projectId, beta)
        box.text = "   "
        XCTAssertNil(box.add(store: store), "nothing to add")
    }

    // MARK: - #40 Restore the window and #41 the project's own tab and filters

    func testWindowStateIsRestoredPerProject() async throws {
        let suite = "FlowMateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, pid) = await makeStore()
        let beta = store.addProject(name: "Beta", now: t0)!

        let model = TasksViewModel(defaults: defaults)
        model.select(.project(pid))
        model.tab = .sprints
        model.filter.priorities = [.high]
        model.filter.query = "draft"
        model.select(.project(beta))
        XCTAssertEqual(model.tab, .sprints, "a project never opened keeps the current tab")
        model.tab = .list
        model.sort = TaskSort(key: .due, ascending: true)
        model.select(.all)
        XCTAssertEqual(model.tab, .list, "All projects has no Sprints tab")
        model.tab = .milestones

        // #41: opening a project brings back its own tab and filters
        model.select(.project(pid))
        XCTAssertEqual(model.tab, .sprints)
        XCTAssertEqual(model.filter.priorities, [.high])
        model.select(.project(beta))
        XCTAssertEqual(model.tab, .list)
        XCTAssertEqual(model.sort.key, .due)

        // #40: a new launch restores the scope, the tabs and the filters, but not the search text
        let restored = TasksViewModel(defaults: defaults)
        XCTAssertEqual(restored.scope, .project(beta))
        XCTAssertEqual(restored.tab, .list)
        XCTAssertEqual(restored.sort.key, .due)
        restored.select(.project(pid))
        XCTAssertEqual(restored.tab, .sprints)
        XCTAssertEqual(restored.filter.priorities, [.high])
        XCTAssertEqual(restored.filter.query, "")
        restored.select(.all)
        XCTAssertEqual(restored.tab, .milestones)

        // A deleted project's scope and settings are forgotten
        restored.select(.project(beta))
        store.deleteProject(beta)
        restored.dropStaleIds(store)
        XCTAssertEqual(restored.scope, .all)
        XCTAssertNil(restored.optionsByScope[beta.uuidString])
        XCTAssertNil(TasksViewModel(defaults: defaults).optionsByScope[beta.uuidString])

        // Unreadable or missing state starts fresh
        defaults.set(Data("nope".utf8), forKey: TasksViewModel.windowStateKey)
        let fresh = TasksViewModel(defaults: defaults)
        XCTAssertEqual(fresh.scope, .all)
        XCTAssertEqual(fresh.tab, .board)
    }

    func testWindowStateDecodingIsTolerant() throws {
        let pid = UUID()
        let json = """
        {"scope": "\(pid.uuidString)", "tabs": {"\(pid.uuidString)": "list", "all": "weird"},
         "options": {"\(pid.uuidString)": {"grouping": "milestone"}, "all": 5}}
        """
        let state = try JSONDecoder().decode(TasksViewModel.WindowState.self, from: Data(json.utf8))
        XCTAssertEqual(state.scope, pid.uuidString)
        XCTAssertEqual(state.options[pid.uuidString]?.grouping, .milestone)
        XCTAssertNil(state.options["all"])

        let suite = "FlowMateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(json.utf8), forKey: TasksViewModel.windowStateKey)
        let model = TasksViewModel(defaults: defaults)
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(model.tab, .list)
        XCTAssertEqual(model.grouping, .milestone)
    }
}
