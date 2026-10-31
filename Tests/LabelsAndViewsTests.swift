import AppKit
import XCTest
@testable import FlowMate

/// Labels (workspace-wide tags) and saved views ("smart lists"): the model and its migration to
/// schema 11, label CRUD with cleanup and undo, the %label word in every New task box, the Label
/// filter and grouping, the L picker, saved view apply / modified / update / revert, persistence,
/// window-state restore, sidebar navigation and the ⌘K palette.
@MainActor
final class LabelsAndViewsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Atlas", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    private func task(_ store: TaskStore, _ title: String, _ pid: UUID, slot: SprintSlot = .active) -> UUID {
        store.addTask(title: title, projectId: pid, sprintSlot: slot, now: t0)!
    }

    // MARK: - Model and migration

    func testSchema10FileMigratesToElevenWithNoLabelsOrViews() throws {
        let pid = UUID(), tid = UUID()
        let json = """
        {"schemaVersion":10,
         "projects":[{"id":"\(pid)","name":"Atlas","colorHex":16739146,"sortIndex":0}],
         "milestones":[],
         "tasks":[{"id":"\(tid)","projectId":"\(pid)","title":"Old task","statusId":"todo","statusCategory":"notStarted"}],
         "runningTimers":{}, "timeEntries":[]}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated(now: t0)
        XCTAssertEqual(Workspace.currentSchemaVersion, 12)
        XCTAssertEqual(ws.schemaVersion, 12)
        XCTAssertEqual(ws.tasks.map(\.title), ["Old task"], "nothing is lost")
        XCTAssertEqual(ws.tasks[0].labelIds, [])
        XCTAssertEqual(ws.labels, [])
        XCTAssertEqual(ws.savedViews, [])
    }

    func testLabelsAndViewsRoundTripAndDecodeTolerantly() throws {
        let pid = UUID(), tid = UUID(), lid = UUID(), dup = UUID(), vid = UUID(), gone = UUID()
        // A duplicate label name, a dangling label id on the task, a broken label entry, a view of
        // a project that doesn't exist and a view with a bogus layout
        let json = """
        {"schemaVersion":11,
         "projects":[{"id":"\(pid)","name":"Atlas","colorHex":16739146,"sortIndex":0}],
         "milestones":[],
         "tasks":[{"id":"\(tid)","projectId":"\(pid)","title":"T","statusId":"todo","statusCategory":"notStarted",
                   "labelIds":["\(lid)","\(UUID())","\(dup)", 42]}],
         "labels":[{"id":"\(lid)","name":"  bug  ","colorHex":5152245},{"id":"\(dup)","name":"BUG"},{"name":"no id"}],
         "savedViews":[{"id":"\(vid)","name":"Bugs","scope":"all","layout":"bogus",
                        "options":{"filter":{"labels":["\(lid)","\(dup)"]},"grouping":"label"}},
                       {"id":"\(UUID())","name":"Gone","scope":"\(gone)","layout":"board"}]}
        """
        let decoder = LocalJSONWorkspaceRepository.makeDecoder()
        let ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated(now: t0)
        XCTAssertEqual(ws.labels.map(\.name), ["bug"], "names are cleaned; a duplicate name merges into the first")
        XCTAssertEqual(ws.tasks[0].labelIds, [lid], "dangling ids go, the duplicate's id maps to the first, once")
        XCTAssertEqual(ws.savedViews.map(\.id), [vid], "a view of a deleted project is dropped")
        XCTAssertEqual(ws.savedViews[0].layout, .list)
        XCTAssertEqual(ws.savedViews[0].options.filter.labels, [lid])
        XCTAssertEqual(ws.savedViews[0].options.grouping, .label)

        let again = try decoder.decode(Workspace.self, from: LocalJSONWorkspaceRepository.makeEncoder().encode(ws))
        XCTAssertEqual(again.labels, ws.labels)
        XCTAssertEqual(again.savedViews, ws.savedViews)
        XCTAssertEqual(again.tasks.map(\.labelIds), ws.tasks.map(\.labelIds))
    }

    // MARK: - Label CRUD, cleanup and undo

    func testLabelCrudDeleteCleanupAndUndo() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid), b = task(store, "B", pid)
        let bug = store.addLabel("  Bug ")!
        XCTAssertEqual(store.label(bug)?.name, "Bug")
        XCTAssertEqual(store.addLabel("bug"), bug, "the same name (any case) is the same label")
        let ui = store.addLabel("UI")!
        XCTAssertNotEqual(store.label(ui)?.colorHex, store.label(bug)?.colorHex, "new labels take an unused color")
        XCTAssertEqual(store.labels.map(\.name), ["Bug", "UI"])

        XCTAssertFalse(store.renameLabel(ui, to: "BUG"), "another label has the name")
        XCTAssertFalse(store.renameLabel(ui, to: "   "))
        XCTAssertTrue(store.renameLabel(ui, to: "Design"))
        store.setLabelColor(ui, colorHex: 0x2DBE7A)
        XCTAssertEqual(store.label(ui)?.colorHex, 0x2DBE7A)

        store.addLabel(bug, to: [a, b])
        store.addLabel(ui, to: [a])
        XCTAssertEqual(store.labelUsage()[bug], 2)
        XCTAssertEqual(store.task(a)?.labelIds, [bug, ui])
        XCTAssertTrue(store.allHave(bug, [a, b]))
        XCTAssertTrue(store.someHave(ui, [a, b]))

        // A view filtering by the label loses it with the label
        let view = store.addSavedView(name: "Bugs", scope: .all, layout: .list, options: {
            var o = TaskViewOptions(); o.filter.labels = [bug]; return o
        }())!

        store.deleteLabel(bug)
        XCTAssertNil(store.label(bug))
        XCTAssertEqual(store.task(a)?.labelIds, [ui], "it comes off every task")
        XCTAssertEqual(store.task(b)?.labelIds, [])
        XCTAssertEqual(store.savedView(view)?.options.filter.labels, [])
        XCTAssertEqual(store.undoActionName, "Delete label")

        store.undo()
        XCTAssertEqual(store.label(bug)?.name, "Bug")
        XCTAssertEqual(store.task(a)?.labelIds, [bug, ui], "undo puts it back on every task")
        XCTAssertEqual(store.task(b)?.labelIds, [bug])
        XCTAssertEqual(store.savedView(view)?.options.filter.labels, [bug])
    }

    func testToggleOnSeveralTasksIsOneStepAndCreateAdds() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid), b = task(store, "B", pid)
        let bug = store.addLabel("bug")!
        store.addLabel(bug, to: [a])
        store.clearUndoHistory()
        XCTAssertTrue(store.toggleLabel(bug, on: [a, b]), "some have it: it goes on all of them")
        XCTAssertEqual(store.undoStack.count, 1)
        XCTAssertTrue(store.allHave(bug, [a, b]))
        XCTAssertFalse(store.toggleLabel(bug, on: [a, b]), "all have it: it comes off all of them")
        XCTAssertEqual(store.task(a)?.labelIds, [])

        let made = store.createLabel("Waiting on client", adding: [a, b])!
        XCTAssertEqual(store.task(b)?.labelIds, [made])
        store.undo()
        XCTAssertNil(store.label(made), "creating and adding is one step")
    }

    // MARK: - %label in every New task box

    func testLabelWordParsesWithoutClashingWithSprints() {
        XCTAssertEqual(ComposerInput.token("%bug"), .label("bug"))
        XCTAssertEqual(ComposerInput.token("%\"needs review\""), .label("needs review"))
        XCTAssertEqual(ComposerInput.token("%needs_review"), .label("needs review"))
        XCTAssertNil(ComposerInput.token("%"))
        XCTAssertNil(ComposerInput.token("50%"))
        XCTAssertEqual(ComposerInput.token("#next"), .slot(.next), "# stays the sprint word")
        let input = QuickAddInput.parse("Fix login %bug %ui !high #next")
        XCTAssertEqual(input.title, "Fix login")
        XCTAssertEqual(input.labelQueries, ["bug", "ui"])
        XCTAssertEqual(input.slot, .next)
        XCTAssertEqual(ComposerInput.activeTrigger("Fix %bu")?.trigger, .label)
    }

    func testOneLineQuickAddLabelsExistingAndCreatesNew() async {
        let (store, pid) = await makeStore()
        let bug = store.addLabel("Bug")!
        XCTAssertEqual(store.quickAddPreview("Fix it %bug %urgent", projectId: pid), ["%Bug", "New label %urgent"])
        let outcome = store.quickAddTask("Fix it %bug %urgent", projectId: pid, now: t0)!
        let added = store.task(outcome.taskId)!
        XCTAssertEqual(added.title, "Fix it")
        let urgent = store.matchLabel("urgent")!.id
        XCTAssertEqual(added.labelIds, [bug, urgent])
        XCTAssertEqual(outcome.applied, ["%Bug", "%urgent"])
        store.undo()
        XCTAssertNil(store.matchLabel("urgent"), "the new label goes with the task on undo")
        XCTAssertNil(store.task(outcome.taskId))

        // The global box and the window's field read the same words
        let box = QuickAddBoxModel()
        box.projectId = pid
        box.text = "Ship %bug"
        let id = box.add(store: store)!
        XCTAssertEqual(store.task(id)?.labelIds, [bug])
        XCTAssertTrue(box.added?.contains("%Bug") ?? false)

        let model = TasksViewModel()
        XCTAssertTrue(model.quickAdd("Review %bug", projectId: pid, milestoneId: nil, open: false, store: store))
        XCTAssertEqual(model.selectedTaskId.flatMap { store.task($0) }?.labelIds, [bug])

        // Tab completes an existing label, written as a word
        _ = store.addLabel("Needs review")
        XCTAssertEqual(store.completeQuickAdd("Check %need", projectId: pid), "Check %Needs_review ")
        XCTAssertNil(store.completeQuickAdd("Check %brandnew", projectId: pid), "a new name is complete as typed")
    }

    func testComposerLabelsFromWordsChipAndGroup() async {
        let (store, pid) = await makeStore()
        let bug = store.addLabel("Bug")!
        // Words finish when a space follows; an unknown name waits to be made with the task
        let result = ComposerInput.extract("Polish %bug %polish ")
        XCTAssertEqual(result.tokens, [.label("bug"), .label("polish")])
        var draft = ComposerDraft()
        for case let .label(name) in result.tokens { draft.addLabel(named: name, existing: store.matchLabel(name)) }
        draft.addLabel(named: "Polish", existing: nil)
        XCTAssertEqual(draft.labelIds, [bug])
        XCTAssertEqual(draft.newLabelNames, ["polish"], "one new name, whatever its case")
        XCTAssertTrue(draft.hasValues)
        XCTAssertNil(store.matchLabel("polish"), "nothing is made before the task is added")
        let id = store.addTask(title: result.text, draft: draft, projectId: pid, now: t0)!
        XCTAssertEqual(store.task(id)?.title, "Polish")
        XCTAssertEqual(store.task(id)?.labelIds.count, 2)
        XCTAssertNotNil(store.matchLabel("polish"))

        // A label group's composer gives its label
        var grouped = ComposerDraft()
        grouped.apply(preset: .label(bug), in: .project(pid))
        XCTAssertEqual(grouped.labelIds, [bug])

        // The % menu: labels that match, then Create
        let rows = store.composerSuggestions(.label, query: "bu", projectId: pid)
        XCTAssertEqual(rows.first?.action, .label(bug))
        XCTAssertEqual(rows.last?.action, .newLabel("bu"))
        XCTAssertFalse(store.composerSuggestions(.label, query: "bug", projectId: pid).contains { $0.action == .newLabel("bug") })
        XCTAssertTrue(store.composerSuggestions(.all, query: "", projectId: pid).contains { $0.action == .trigger(.label) })
    }

    // MARK: - Filter, grouping, search

    func testLabelFilterIsAnyOfAndSearchFindsLabelNames() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid), b = task(store, "B", pid), c = task(store, "C", pid)
        let bug = store.addLabel("Bug")!, ui = store.addLabel("Interface")!
        store.addLabel(bug, to: [a])
        store.addLabel(ui, to: [b])
        var filter = TaskFilter()
        filter.labels = [bug, ui]
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: filter).map(\.id), [a, b])
        XCTAssertEqual(filter.chipCount, 1)
        filter.labels = [UUID()]
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: filter).count, 3, "a deleted label never hides everything")
        var search = TaskFilter()
        search.query = "interf"
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: search).map(\.id), [b])
        _ = c
    }

    func testGroupByLabelListsTasksUnderEachLabelAndDropsAddIt() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid), b = task(store, "B", pid), c = task(store, "C", pid)
        let bug = store.addLabel("Bug")!, ui = store.addLabel("UI")!
        _ = store.addLabel("Unused")
        store.addLabel(bug, to: [a, b])
        store.addLabel(ui, to: [a])
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        model.options.grouping = .label
        let groups = model.listGroups(store)
        XCTAssertEqual(groups.map(\.title), ["Bug", "UI", "No label"], "labels in use, by name, then No label")
        XCTAssertEqual(groups[0].tasks.map(\.id), [a, b])
        XCTAssertEqual(groups[1].tasks.map(\.id), [a], "a task with two labels is under both")
        XCTAssertEqual(groups[2].tasks.map(\.id), [c])
        XCTAssertNotNil(groups[0].labelColorHex)
        XCTAssertEqual(model.visibleTasks(store).map(\.id), [a, b, c], "↑/↓ visit each task once")

        store.moveTask(c, to: .label(ui))
        XCTAssertEqual(store.task(c)?.labelIds, [ui])
        store.moveTask(a, to: .label(nil))
        XCTAssertEqual(store.task(a)?.labelIds, [], "No label takes them all off")
    }

    func testChipLayoutFitsWhatItCanThenCountsTheRest() {
        let more: (Int) -> CGFloat = { _ in 20 }
        XCTAssertEqual(LabelChipLayout.fit([40, 40], width: 100, spacing: 4, moreWidth: more).more, 0)
        let three = LabelChipLayout.fit([40, 40, 40], width: 100, spacing: 4, moreWidth: more)
        XCTAssertEqual(three.widths, [40], "two chips and +1 don't fit: one chip and +2")
        XCTAssertEqual(three.more, 2)
        let wide = LabelChipLayout.fit([300, 40], width: 100, spacing: 4, moreWidth: more)
        XCTAssertEqual(wide.widths.count, 1)
        XCTAssertLessThanOrEqual(wide.widths[0] + 4 + 20, 100, "the first chip narrows to fit")
        XCTAssertEqual(wide.more, 1)
    }

    // MARK: - The L picker

    func testLPickerTogglesLabelsAndCreatesOnSeveralTasks() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid), b = task(store, "B", pid)
        let bug = store.addLabel("Bug")!
        store.addLabel(bug, to: [a])
        let model = TasksViewModel()
        model.select(.project(pid))
        model.select(ids: [a, b])
        XCTAssertEqual(TasksShortcut.match(keyCode: 37, characters: "l", modifiers: []), .pickLabels)
        XCTAssertTrue(model.perform(.pickLabels, store: store))
        XCTAssertEqual(model.quickPicker?.action, .labels)
        XCTAssertEqual(model.quickPicker?.anchor, .bulk)
        XCTAssertTrue(TaskQuickAction.labels.isMultiSelect)

        let options = model.quickPickOptions(.labels, ids: [a, b], query: "", store: store)
        XCTAssertEqual(options.map(\.title), ["Bug"])
        XCTAssertTrue(options[0].isMixed, "one of the two has it")
        XCTAssertFalse(options[0].isCurrent)
        model.applyQuickPick(.label(bug), ids: [a, b], store: store)
        XCTAssertTrue(store.allHave(bug, [a, b]))
        XCTAssertEqual(model.toast?.message, "Labeled 2 tasks Bug")

        let typed = model.quickPickOptions(.labels, ids: [a, b], query: "Later", store: store)
        XCTAssertEqual(typed.first?.value, .newLabel("Later"))
        model.applyQuickPick(.newLabel("Later"), ids: [a, b], store: store)
        XCTAssertEqual(store.task(b)?.labelIds.count, 2)
        XCTAssertTrue(model.quickPickOptions(.labels, ids: [a], query: "later", store: store).allSatisfy { !$0.isTyped })
    }

    // MARK: - Saved views

    private func viewModel(_ suite: String = UUID().uuidString) -> (TasksViewModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "labels-views-\(suite)")!
        return (TasksViewModel(defaults: defaults, stateKey: "state"), defaults)
    }

    func testSaveViewApplyModifiedUpdateRevert() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid), b = task(store, "B", pid)
        store.setPriority(a, .high)
        let (model, _) = viewModel()
        model.select(.project(pid))
        model.tab = .list
        XCTAssertFalse(model.canSaveView, "nothing to save while the filters are the defaults")
        model.filter.priorities = [.high]
        XCTAssertTrue(model.canSaveView)

        let id = model.saveCurrentView(name: "  Hot  ", icon: "flame", store: store)!
        let view = store.savedView(id)!
        XCTAssertEqual(view.name, "Hot")
        XCTAssertEqual(view.scope, .project(pid))
        XCTAssertEqual(view.layout, .list)
        XCTAssertEqual(view.options.filter.priorities, [.high])
        XCTAssertEqual(model.activeViewId, id)
        XCTAssertEqual(model.sidebarSelection, .view(id))
        XCTAssertFalse(model.isViewModified(store))
        XCTAssertEqual(store.savedViewCount(view), 1)

        // The project keeps its own filters apart from the view's
        model.select(.project(pid))
        XCTAssertNil(model.activeViewId)
        model.clearOptions()
        XCTAssertEqual(model.filter, TaskFilter())
        model.applySavedView(id, store: store)
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(model.filter.priorities, [.high])
        XCTAssertEqual(model.listGroups(store).flatMap(\.tasks).map(\.id), [a])

        // Changing the filters marks it modified; Revert and Update
        model.filter.priorities = []
        XCTAssertTrue(model.isViewModified(store))
        model.revertActiveView(store)
        XCTAssertFalse(model.isViewModified(store))
        XCTAssertEqual(model.filter.priorities, [.high])
        model.tab = .board
        XCTAssertTrue(model.isViewModified(store), "Board or List is part of the view")
        model.tab = .list
        model.filter.priorities = [.high, .medium]
        model.updateActiveView(store)
        XCTAssertFalse(model.isViewModified(store))
        XCTAssertEqual(store.savedView(id)?.options.filter.priorities, [.high, .medium])
        XCTAssertEqual(store.savedViewCount(store.savedView(id)!), 2)
        XCTAssertEqual(model.toast?.message, "Updated Hot")
        store.undo()
        XCTAssertEqual(store.savedView(id)?.options.filter.priorities, [.high], "update is an undo step")
        _ = b
    }

    func testSavedViewRenameDuplicateReorderDeleteAndUndo() async {
        let (store, _) = await makeStore()
        let one = store.addSavedView(name: "One", scope: .all, layout: .list, options: .standard)!
        let two = store.addSavedView(name: "Two", scope: .all, layout: .board, options: .standard)!
        XCTAssertNil(store.addSavedView(name: "   ", scope: .all, layout: .list, options: .standard))
        store.renameSavedView(one, to: "First")
        store.setSavedViewIcon(one, "star")
        let copy = store.duplicateSavedView(one)!
        XCTAssertEqual(store.savedViews.map(\.name), ["First", "First copy", "Two"])
        store.moveSavedView(two, before: one)
        XCTAssertEqual(store.savedViews.map(\.id), [two, one, copy])
        store.moveSavedView(two, before: nil)
        XCTAssertEqual(store.savedViews.map(\.id), [one, copy, two])

        let (model, _) = viewModel()
        model.applySavedView(two, store: store)
        XCTAssertEqual(model.effectiveTab, .board)
        model.deleteSavedView(two, store: store)
        XCTAssertNil(model.activeViewId, "the scope stays, without the view")
        XCTAssertEqual(model.scope, .all)
        store.undo()
        XCTAssertNotNil(store.savedView(two))
    }

    func testViewOfDeletedProjectGoesWithItAndComesBackOnUndo() async {
        let (store, pid) = await makeStore()
        let view = store.addSavedView(name: "Atlas", scope: .project(pid), layout: .list, options: .standard)!
        store.deleteProject(pid)
        XCTAssertNil(store.savedView(view))
        store.undo()
        XCTAssertNotNil(store.savedView(view))
    }

    func testSavedViewPersistsAndWindowRestoresIt() async throws {
        let repo = InMemoryWorkspaceRepository(.empty)
        let store = TaskStore(repository: repo, saveDelay: 0.01)
        await store.load()
        let pid = store.addProject(name: "Atlas", now: t0)!
        let suite = UUID().uuidString
        let (model, _) = viewModel(suite)
        model.select(.project(pid))
        model.tab = .board
        model.filter.priorities = [.high]
        let id = model.saveCurrentView(name: "Hot", icon: nil, store: store)!
        model.filter.query = "draft"
        await store.flush()

        // The data file keeps the view
        let saved = try await repo.load()
        XCTAssertEqual(saved?.savedViews.map(\.name), ["Hot"])
        XCTAssertEqual(saved?.savedViews.first?.layout, .board)

        // The window comes back on it, with its filters (search text is never kept)
        let (restored, _) = viewModel(suite)
        XCTAssertEqual(restored.activeViewId, id)
        XCTAssertEqual(restored.scope, .project(pid))
        XCTAssertEqual(restored.effectiveTab, .board)
        XCTAssertEqual(restored.filter.priorities, [.high])
        XCTAssertEqual(restored.filter.query, "")
        restored.dropStaleIds(store)
        XCTAssertEqual(restored.activeViewId, id, "a view that exists stays on screen")

        store.deleteSavedView(id)
        restored.dropStaleIds(store)
        XCTAssertNil(restored.activeViewId)
        XCTAssertEqual(restored.scope, .project(pid))
    }

    func testSidebarOrderStepsAndFocusIncludeViews() async {
        let (store, pid) = await makeStore()
        let v1 = store.addSavedView(name: "One", scope: .all, layout: .list, options: .standard)!
        let v2 = store.addSavedView(name: "Two", scope: .project(pid), layout: .board, options: .standard)!
        let (model, _) = viewModel()
        model.select(.all)
        XCTAssertEqual(model.sidebarScopes(store), [.today, .all, .view(v1), .view(v2), .project(pid)])
        XCTAssertTrue(model.stepSidebar(1, store: store))
        XCTAssertEqual(model.sidebarSelection, .view(v1))
        XCTAssertEqual(model.scope, .all)
        XCTAssertTrue(model.stepSidebar(1, store: store))
        XCTAssertEqual(model.sidebarSelection, .view(v2))
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(model.effectiveTab, .board)
        XCTAssertTrue(model.stepSidebar(1, store: store))
        XCTAssertEqual(model.sidebarSelection, .project(pid))
        XCTAssertNil(model.activeViewId)

        // ⌘0 starts on the item on screen; ↵ on a view applies it
        model.applySavedView(v1, store: store)
        model.focusSidebar(store: store)
        XCTAssertEqual(model.sidebarCursor, .view(v1))
        model.moveSidebarCursor(1, store: store)
        model.activateSidebarCursor(store: store)
        XCTAssertEqual(model.sidebarSelection, .view(v2))
    }

    func testSuggestionsAreOnlyMadeWhenPicked() async {
        let (store, _) = await makeStore()
        XCTAssertTrue(store.savedViews.isEmpty, "no views are made on their own")
        XCTAssertEqual(SavedViewSuggestion.starters.count, 2)
        let (model, _) = viewModel()
        let id = model.addSuggestedView(SavedViewSuggestion.starters[0], store: store)!
        XCTAssertEqual(store.savedView(id)?.name, "High priority")
        XCTAssertEqual(model.activeViewId, id)
        XCTAssertEqual(model.filter.priorities, [.high])
    }

    // MARK: - ⌘K

    func testPaletteFindsLabelsAndViews() async {
        let (store, pid) = await makeStore()
        let a = task(store, "Alpha", pid)
        _ = task(store, "Beta", pid)
        let bug = store.addLabel("Bugfix")!
        store.addLabel(bug, to: [a])
        let view = store.addSavedView(name: "Weekly review", scope: .all, layout: .list, options: .standard)!
        let model = TasksViewModel()
        model.paletteQuery = "bugfix"
        XCTAssertTrue(model.paletteResults(store).items.contains(.label(bug)))
        model.paletteQuery = "weekly"
        XCTAssertEqual(model.paletteResults(store).items.first, .savedView(view))
        XCTAssertTrue(model.paletteCommands(store).contains(.manageLabels))

        // A label shows a filtered All projects List
        model.select(.project(pid))
        model.runPaletteItem(.label(bug), store: store)
        XCTAssertEqual(model.scope, .all)
        XCTAssertEqual(model.effectiveTab, .list)
        XCTAssertEqual(model.filter.labels, [bug])
        XCTAssertEqual(model.listGroups(store).flatMap(\.tasks).map(\.id), [a])
        // A view is applied, and both are remembered as recent picks
        model.runPaletteItem(.savedView(view), store: store)
        XCTAssertEqual(model.activeViewId, view)
        XCTAssertEqual(model.paletteItem(forKey: "view:\(view.uuidString)", store: store), .savedView(view))
        XCTAssertEqual(model.paletteItem(forKey: "label:\(bug.uuidString)", store: store), .label(bug))

        // Save view… and Update / Revert follow what's on screen
        model.select(.all)
        model.tab = .list
        model.filter.due = [.overdue]
        XCTAssertTrue(model.paletteCommands(store).contains(.saveView))
        model.run(.saveView, store: store)
        XCTAssertEqual(model.savingView?.kind, .new)
        model.applySavedView(view, store: store)
        model.filter.due = [.noDate]
        XCTAssertTrue(model.paletteCommands(store).contains(.updateView))
        model.run(.revertView, store: store)
        XCTAssertEqual(model.filter.due, [])
    }

    func testDeletingLabelFromWindowClearsItFromScopeFiltersWithUndoToast() async {
        let (store, pid) = await makeStore()
        let a = task(store, "A", pid)
        let bug = store.addLabel("Bug")!
        store.addLabel(bug, to: [a])
        let model = TasksViewModel()
        model.showLabel(bug, store: store)
        XCTAssertEqual(model.filter.labels, [bug])
        model.deleteLabel(bug, store: store)
        XCTAssertEqual(model.filter.labels, [], "a scope's chip goes with the label")
        XCTAssertEqual(model.toast?.message, "Deleted Bug from 1 task")
        XCTAssertNotNil(model.toast?.undoId)
        model.undoFromToast(store)
        XCTAssertEqual(store.task(a)?.labelIds, [bug])
    }
}
