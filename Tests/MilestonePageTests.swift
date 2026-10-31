import XCTest
@testable import FlowMate

/// Milestone pages (TaskScope.milestone), milestone colors (schema 8), create-and-open for projects
/// and milestones, and ⌘N's composer at the top of its group.
@MainActor
final class MilestonePageTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    // MARK: - Scope

    func testMilestoneScopeShowsOnlyItsTasks() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta")!
        let other = store.addMilestone(projectId: pid, name: "Gamma")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, milestoneId: m, sprintSlot: .backlog, now: t0)!
        store.addTask(title: "C", projectId: pid, milestoneId: other, now: t0)
        store.addTask(title: "D", projectId: pid, now: t0)

        let scope = store.scope(ofMilestone: m)!
        XCTAssertEqual(scope, .milestone(m, projectId: pid))
        XCTAssertEqual(scope.projectId, pid)
        XCTAssertEqual(scope.milestoneId, m)
        XCTAssertEqual(store.tasks(in: scope).map(\.id), [a, b])
        XCTAssertEqual(store.milestones(in: scope).map(\.id), [m])
        XCTAssertEqual(store.statuses(in: scope), store.project(pid)!.statuses, "the project's workflow")
        XCTAssertNil(store.scope(ofMilestone: UUID()))

        let model = TasksViewModel()
        model.select(scope)
        model.tab = .board
        // Board columns are the project's statuses; a milestone's board shows its backlog tasks too
        XCTAssertEqual(model.boardColumns(store), store.project(pid)!.statuses.map { .status($0) })
        XCTAssertEqual(Set(model.allBoardTasks(store).map(\.id)), [a, b])
        XCTAssertNil(model.boardCaption(store))
        model.tab = .list
        XCTAssertEqual(Set(model.listGroups(store).flatMap(\.tasks).map(\.id)), [a, b])
    }

    func testMilestonePageTabsAndGroupings() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta")!
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .sprints
        model.showMilestone(m, store: store)

        XCTAssertEqual(model.tabs, [.board, .list])
        XCTAssertEqual(model.tab, .list, "a milestone page opens on List the first time")
        model.tab = .milestones
        XCTAssertEqual(model.effectiveTab, .list)
        XCTAssertEqual(TaskGrouping.available(in: model.scope), [.status, .priority, .sprint])
        model.options.grouping = .milestone
        XCTAssertEqual(model.grouping, .status, "Milestone grouping falls back to Status on its own page")
        XCTAssertTrue(model.expandedProjects.contains(pid), "the sidebar lists the project's milestones")
    }

    func testScopeKeysKeepFiltersAndTabPerMilestone() async {
        let (store, pid) = await makeStore()
        let m1 = store.addMilestone(projectId: pid, name: "One")!
        let m2 = store.addMilestone(projectId: pid, name: "Two")!
        let suite = "MilestonePageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TasksViewModel(defaults: defaults, stateKey: "state")
        model.showMilestone(m1, store: store)
        model.tab = .board
        model.filter.priorities = [.high]
        model.showMilestone(m2, store: store)
        XCTAssertTrue(model.filter.isEmpty, "each milestone keeps its own filters")
        XCTAssertEqual(model.tab, .list)
        model.select(.project(pid))
        XCTAssertTrue(model.filter.isEmpty, "the project's filters are separate too")
        model.showMilestone(m1, store: store)
        XCTAssertEqual(model.tab, .board)
        XCTAssertEqual(model.filter.priorities, [.high])
        XCTAssertEqual(TasksViewModel.scopeKey(model.scope), "milestone-\(m1.uuidString)")

        // Restored after a relaunch, before the data has loaded
        let restored = TasksViewModel(defaults: defaults, stateKey: "state")
        XCTAssertEqual(restored.scope, .milestone(m1, projectId: pid))
        XCTAssertEqual(restored.tab, .board)
        XCTAssertEqual(restored.filter.priorities, [.high])
    }

    func testStorageKeyRoundTrips() {
        let m = UUID(), p = UUID()
        for scope in [TaskScope.all, .project(p), .milestone(m, projectId: p)] {
            XCTAssertEqual(TaskScope(storageKey: scope.storageKey), scope)
        }
        XCTAssertNil(TaskScope(storageKey: "milestone-nonsense"))
        XCTAssertNil(TaskScope(storageKey: "garbage"))
    }

    func testDeletingTheMilestoneOnScreenGoesBackToItsProject() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta")!
        let model = TasksViewModel()
        model.showMilestone(m, store: store)
        model.deleteMilestone(m, store: store)
        XCTAssertEqual(model.scope, .project(pid))

        // Deleted elsewhere (undo of its creation): dropStaleIds notices
        store.undo()
        let again = store.addMilestone(projectId: pid, name: "Gamma")!
        model.showMilestone(again, store: store)
        store.undo()
        model.dropStaleIds(store)
        XCTAssertEqual(model.scope, .project(pid))
    }

    func testArchivingTheProjectOfTheMilestoneOnScreenGoesToAllProjects() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta")!
        let model = TasksViewModel()
        model.showMilestone(m, store: store)
        model.archiveProject(pid, store: store)
        XCTAssertEqual(model.scope, .all)
    }

    func testSidebarClicksAndKeyboardWalk() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta")!
        let model = TasksViewModel()
        model.clickSidebarMilestone(m, store: store)
        XCTAssertEqual(model.scope.milestoneId, m)
        XCTAssertFalse(model.isPanelOpen)
        model.clickSidebarMilestone(m, store: store)
        XCTAssertEqual(model.openDetail, .milestone(m), "a second click opens its panel")

        // ⌥⌘↑ / ⌥⌘↓ walk All projects, the project and its listed milestone
        model.select(.all)
        XCTAssertEqual(model.sidebarScopes(store), [.all, .project(pid), .milestone(m, projectId: pid)])
        XCTAssertTrue(model.perform(.nextScope, store: store))
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertTrue(model.perform(.nextScope, store: store))
        XCTAssertEqual(model.scope, .milestone(m, projectId: pid))
        XCTAssertFalse(model.perform(.nextScope, store: store), "stops at the end")
        XCTAssertTrue(model.perform(.previousScope, store: store))
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(TasksShortcut.match(keyCode: 125, characters: "", modifiers: [.command, .option]), .nextScope)
        XCTAssertEqual(TasksShortcut.match(keyCode: 126, characters: "", modifiers: [.command, .option]), .previousScope)
    }

    func testMilestoneTimeAndMenuSearch() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta launch")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, milestoneId: m, now: t0)!
        store.setExpectedMinutes(a, 120)
        store.setExpectedMinutes(b, 60)
        _ = store.addTimeEntry(taskId: a, start: t0, end: t0.addingTimeInterval(3_600))
        let time = store.milestoneTime(m, now: t0.addingTimeInterval(7_200))
        XCTAssertEqual(time.tracked, 3_600, accuracy: 0.5)
        XCTAssertEqual(time.expectedMinutes, 180)

        let results = store.menuSearchResults("beta", canAdd: true)
        XCTAssertEqual(results.milestones, [m])
        XCTAssertEqual(results.items.first { $0 != .add }, .milestone(m))
        store.completeMilestone(m)
        XCTAssertEqual(store.menuSearchResults("beta", canAdd: true).milestones, [], "completed ones are left out")
    }

    // MARK: - Composer defaults

    func testComposerOnAMilestonePageAddsToThatMilestone() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "Beta")!
        let doing = store.project(pid)!.statuses[1]
        var draft = ComposerDraft()
        draft.apply(preset: .status(doing), in: .milestone(m, projectId: pid))
        XCTAssertEqual(draft.milestoneId, m)
        XCTAssertEqual(draft.status, doing)
        let id = store.addTask(title: "New", draft: draft, projectId: pid, now: t0)!
        XCTAssertEqual(store.task(id)?.milestoneId, m)
        XCTAssertEqual(store.task(id)?.statusId, doing.id)
        XCTAssertEqual(store.tasks(in: .milestone(m, projectId: pid)).map(\.id), [id])

        // A draft moved to another project doesn't take the page's milestone
        var elsewhere = ComposerDraft()
        elsewhere.projectId = UUID()
        elsewhere.apply(preset: nil, in: .milestone(m, projectId: pid))
        XCTAssertNil(elsewhere.milestoneId)
        var plain = ComposerDraft()
        plain.apply(preset: nil, in: .project(pid))
        XCTAssertNil(plain.milestoneId)
    }

    // MARK: - Colors and migration

    func testNewMilestonesWalkThePaletteSkippingTheProjectColor() async {
        let (store, pid) = await makeStore()
        let projectColor = store.project(pid)!.colorHex
        let ids = (0..<3).map { store.addMilestone(projectId: pid, name: "M\($0)")! }
        let colors = ids.map { store.milestone($0)!.colorHex }
        XCTAssertEqual(Set(colors).count, 3, "neighbors differ")
        XCTAssertFalse(colors.contains(projectColor))
        XCTAssertTrue(colors.allSatisfy(Milestone.palette.contains))

        store.setMilestoneColor(ids[0], colorHex: 0x8B5CF6)
        XCTAssertEqual(store.milestone(ids[0])?.colorHex, 0x8B5CF6)
        store.undo()
        XCTAssertEqual(store.milestone(ids[0])?.colorHex, colors[0], "undoable")
        store.setMilestoneColor(ids[0], colorHex: Milestone.unsetColor)
        XCTAssertEqual(store.milestone(ids[0])?.colorHex, colors[0], "never back to no color")
    }

    func testSchema7MilestonesGetColorsOnLoad() throws {
        let pid = UUID(), m1 = UUID(), m2 = UUID(), tid = UUID()
        let json = """
        {"schemaVersion": 7,
         "projects": [{"id": "\(pid.uuidString)", "name": "Old", "colorHex": \(0xFF6B4A)}],
         "milestones": [{"id": "\(m1.uuidString)", "projectId": "\(pid.uuidString)", "name": "One", "notes": "keep"},
                        {"id": "\(m2.uuidString)", "projectId": "\(pid.uuidString)", "name": "Two"}],
         "tasks": [{"id": "\(tid.uuidString)", "projectId": "\(pid.uuidString)", "milestoneId": "\(m2.uuidString)", "title": "T"}],
         "runningTimers": {}, "timeEntries": [], "preferences": {}}
        """
        let decoder = LocalJSONWorkspaceRepository.makeDecoder()
        let ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(ws.schemaVersion, 8)
        XCTAssertEqual(ws.milestones.map(\.colorHex), [0x4EA1F5, 0x2DBE7A], "palette order, skipping the project's coral")
        XCTAssertEqual(ws.milestones[0].notes, "keep")
        XCTAssertEqual(ws.tasks[0].milestoneId, m2, "nothing else changes")

        // Stored colors survive a round trip and aren't reassigned
        var edited = ws
        edited.milestones[0].colorHex = 0xEC4899
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(edited)
        XCTAssertEqual(try decoder.decode(Workspace.self, from: data).migrated().milestones.map(\.colorHex), [0xEC4899, 0x2DBE7A])
    }

    // MARK: - Create and open

    func testNewProjectReturnAddsWithToastShiftReturnOpens() async {
        let (store, _) = await makeStore()
        let model = TasksViewModel()
        let quiet = model.addProject("Bravo", open: false, store: store)!
        XCTAssertEqual(model.scope, .all, "↵ stays put")
        XCTAssertEqual(model.toast?.message, "Added Bravo")
        XCTAssertEqual(model.toast?.open, .project(quiet))
        model.openFromToast(store)
        XCTAssertEqual(model.scope, .project(quiet))

        let opened = model.addProject("Charlie", open: true, store: store)!
        XCTAssertEqual(model.scope, .project(opened))
        XCTAssertEqual(model.openDetail, .project(opened), "⇧↵ opens its panel")
        XCTAssertNil(model.addProject("  ", open: true, store: store))
    }

    func testNewMilestoneReturnAddsWithToastShiftReturnShowsItsPage() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.select(.project(pid))
        let quiet = model.addMilestone("Beta", projectId: pid, open: false, store: store)!
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(model.toast?.message, "Added Beta")
        XCTAssertTrue(model.canOpen(model.toast!.open!, store: store))
        model.openFromToast(store)
        XCTAssertEqual(model.scope, .milestone(quiet, projectId: pid))

        let opened = model.addMilestone("Gamma", projectId: pid, open: true, store: store)!
        XCTAssertEqual(model.scope, .milestone(opened, projectId: pid))
        XCTAssertNil(model.addMilestone("", projectId: pid, open: true, store: store))
    }

    func testShiftReturnFromTheComposerOpensTheTaskReadyToDescribe() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "A", projectId: pid, now: t0)!
        let model = TasksViewModel()
        model.openNewTask(id)
        XCTAssertEqual(model.openTaskId, id)
        XCTAssertEqual(model.describeTaskId, id)
    }

    // MARK: - ⌘N at the top

    func testCommandNPinsTheComposerAtTheTopOfTheFirstGroup() async {
        let (store, pid) = await makeStore()
        for i in 0..<64 { store.addTask(title: "T\(i)", projectId: pid, now: t0) }
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        let firstGroup = model.listGroups(store).first!.id
        if !model.isCollapsed(firstGroup) { model.toggleGroup(firstGroup) }

        XCTAssertTrue(model.perform(.newTask, store: store))
        let key = TasksViewModel.listComposerKey(firstGroup)
        XCTAssertEqual(model.activeComposer, key)
        XCTAssertTrue(model.isComposerPinned(key))
        XCTAssertFalse(model.isCollapsed(firstGroup), "its group opens")
        XCTAssertEqual(model.focusRequest?.field, .newTask)

        // Closing it (or opening another group's) puts it back at the bottom
        model.activeComposer = nil
        XCTAssertFalse(model.isComposerPinned(key))

        model.tab = .board
        model.perform(.newTask, store: store)
        XCTAssertEqual(model.activeComposer, TasksViewModel.boardComposerKey(model.boardColumns(store)[0]))
        XCTAssertTrue(model.isComposerPinned(model.activeComposer!))
    }

    func testTasksAddedAtTheTopComeFirstInTheirGroup() async {
        let (store, pid) = await makeStore()
        let first = store.addTask(title: "Old 1", projectId: pid, now: t0)!
        store.addTask(title: "Old 2", projectId: pid, now: t0)
        var draft = ComposerDraft()
        draft.atTop = true
        let top = store.addTask(title: "New", draft: draft, projectId: pid, now: t0)!
        let bottom = store.addTask(title: "Last", draft: ComposerDraft(), projectId: pid, now: t0)!

        let model = TasksViewModel()
        model.select(.project(pid))
        let ids = model.listGroups(store).first!.tasks.map(\.id)
        XCTAssertEqual(ids.first, top)
        XCTAssertEqual(ids[1], first)
        XCTAssertEqual(ids.last, bottom)

        model.flash(top)
        XCTAssertEqual(model.flashTaskId, top)
    }
}
