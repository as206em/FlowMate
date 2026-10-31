import XCTest
@testable import FlowMate

/// Statuses per project: migration, presets, editing a workflow, and everything that follows the
/// status category (timers, Complete sprint, moving between projects, board columns, filters).
@MainActor
final class WorkflowTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore(_ preset: WorkflowPreset = .simple) async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        if preset != .simple { store.applyWorkflowPreset(projectId: pid, preset, now: t0) }
        return (store, pid)
    }

    private func status(_ store: TaskStore, _ pid: UUID, _ name: String) -> WorkflowStatus {
        store.project(pid)!.statuses.first { $0.name == name }!
    }

    // MARK: - Migration

    func testSchema5WorkspaceMigratesToTheSimpleWorkflowWithoutLosingAnything() throws {
        let pid = UUID(), other = UUID()
        let ids = (0..<5).map { _ in UUID() }
        func task(_ id: UUID, _ status: String?, project: UUID = pid) -> String {
            let s = status.map { #", "status": "\#($0)""# } ?? ""
            return #"{"id": "\#(id.uuidString)", "projectId": "\#(project.uuidString)", "title": "T", "spentSeconds": 90, "sprintSlot": "active"\#(s)}"#
        }
        let json = """
        {"schemaVersion": 5,
         "projects": [{"id": "\(pid.uuidString)", "name": "Old", "colorHex": 4235766},
                      {"id": "\(other.uuidString)", "name": "Other"}],
         "milestones": [],
         "tasks": [\(task(ids[0], "todo")), \(task(ids[1], "inProgress")), \(task(ids[2], "done")),
                   \(task(ids[3], "weird")), \(task(ids[4], nil, project: other))],
         "runningTimers": {"\(ids[1].uuidString)": "2026-10-01T10:00:00Z"},
         "preferences": {}}
        """
        let decoder = LocalJSONWorkspaceRepository.makeDecoder()
        let ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated()

        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(Workspace.currentSchemaVersion, 7)
        for project in ws.projects {
            XCTAssertEqual(project.statuses, WorkflowPreset.simple.statuses, "every project gets the Simple workflow")
        }
        XCTAssertEqual(ws.projects[0].colorHex, 4235766)
        XCTAssertEqual(ws.tasks.map(\.statusId), ["todo", "inProgress", "done", "todo", "todo"])
        XCTAssertEqual(ws.tasks.map(\.statusCategory), [.notStarted, .started, .done, .notStarted, .notStarted])
        XCTAssertEqual(ws.tasks.map(\.spentSeconds), Array(repeating: 90, count: 5), "time is kept")
        XCTAssertNotNil(ws.runningTimers[ids[1]], "a running timer survives")

        // The new shape round-trips
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(ws)
        let again = try decoder.decode(Workspace.self, from: data).migrated()
        XCTAssertEqual(again.projects.map(\.statuses), ws.projects.map(\.statuses))
        XCTAssertEqual(again.tasks.map(\.statusId), ws.tasks.map(\.statusId))
        XCTAssertEqual(again.tasks.map(\.statusCategory), ws.tasks.map(\.statusCategory))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"statusId\""))
        XCTAssertTrue(text.contains("\"statuses\""))
    }

    func testBrokenWorkflowsAreRepairedOnLoad() throws {
        let pid = UUID(), tid = UUID()
        // A workflow with no Done status, a duplicate id and a task pointing at a missing status
        let json = """
        {"schemaVersion": 6,
         "projects": [{"id": "\(pid.uuidString)", "name": "P", "statuses": [
            {"id": "a", "name": "Inbox", "colorHex": 1, "category": "notStarted"},
            {"id": "a", "name": "Dup", "category": "started"},
            {"id": "b", "name": "", "category": "started"}]}],
         "tasks": [{"id": "\(tid.uuidString)", "projectId": "\(pid.uuidString)", "title": "T",
                    "statusId": "gone", "statusCategory": "started"}]}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated()
        let statuses = ws.projects[0].statuses
        XCTAssertEqual(statuses.map(\.id).prefix(2), ["a", "b"], "the duplicate is dropped")
        XCTAssertEqual(statuses[1].name, "Started", "a blank name gets the category's")
        XCTAssertTrue(statuses.contains { $0.category == .done }, "a Done status is added")
        XCTAssertEqual(ws.tasks[0].statusId, "b", "a missing status lands on the first of its category")
    }

    // MARK: - Presets

    func testApplyingAPresetRemapsTasksByCategory() async {
        let (store, pid) = await makeStore()
        let todo = store.addTask(title: "Todo", projectId: pid, now: t0)!
        let doing = store.addTask(title: "Doing", projectId: pid, now: t0)!
        let done = store.addTask(title: "Done", projectId: pid, now: t0)!
        store.setStatus(doing, .inProgress, now: t0)
        store.setStatus(done, .done, now: t0)

        store.applyWorkflowPreset(projectId: pid, .dev, now: t0)
        XCTAssertEqual(store.project(pid)?.statuses.map(\.name), ["Backlog", "To do", "In progress", "Review", "Done", "Canceled"])
        XCTAssertEqual(store.task(todo)?.statusId, "todo", "the same name and category is kept")
        XCTAssertEqual(store.task(doing)?.statusId, "inProgress")
        XCTAssertEqual(store.task(done)?.statusId, "done")

        let review = status(store, pid, "Review")
        store.setStatus(doing, review, now: t0)
        store.applyWorkflowPreset(projectId: pid, .kanban, now: t0)
        XCTAssertEqual(store.project(pid)?.statuses.map(\.name), ["To do", "Doing", "Done"])
        XCTAssertEqual(store.task(doing)?.statusId, "doing", "Review is started: the first started status")
        XCTAssertEqual(store.task(doing)?.statusCategory, .started)
        XCTAssertEqual(store.undoActionName, "Apply Kanban workflow")

        store.undo()
        XCTAssertEqual(store.project(pid)?.statuses.count, 6)
        XCTAssertEqual(store.task(doing)?.statusId, "review", "undo restores the workflow and the task's status")
        store.redo()
        XCTAssertEqual(store.task(doing)?.statusId, "doing")
    }

    func testApplyingAPresetToCanceledTasksWithoutCanceledMovesThemToDone() async {
        let (store, pid) = await makeStore(.dev)
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.setStatus(a, .canceled, now: t0)
        store.applyWorkflowPreset(projectId: pid, .simple, now: t0)
        XCTAssertEqual(store.task(a)?.statusId, "done")
        XCTAssertTrue(store.task(a)!.isClosed)
    }

    // MARK: - Editing a workflow

    func testAddRenameRecolorReorderAndUndo() async {
        let (store, pid) = await makeStore()
        let id = store.addStatus(projectId: pid, name: "  QA ", category: .started)!
        XCTAssertNil(store.addStatus(projectId: pid, name: "  ", category: .started))
        XCTAssertEqual(store.project(pid)?.statuses.map(\.name), ["To do", "In progress", "QA", "Done"],
                       "added after the last status of its category")
        store.renameStatus(projectId: pid, statusId: id, to: "Q")
        store.renameStatus(projectId: pid, statusId: id, to: "QA review")
        store.setStatusColor(projectId: pid, statusId: id, colorHex: 0x14B8A6)
        store.moveStatus(projectId: pid, statusId: id, by: -1)
        XCTAssertEqual(store.project(pid)?.statuses.map(\.name), ["To do", "QA review", "In progress", "Done"])
        store.moveStatus(projectId: pid, statusId: id, before: nil)
        XCTAssertEqual(store.project(pid)?.statuses.last?.name, "QA review")
        XCTAssertEqual(store.project(pid)?.status(id)?.colorHex, 0x14B8A6)

        store.undo() // move to end
        store.undo() // move up
        store.undo() // color
        XCTAssertEqual(store.project(pid)?.status(id)?.colorHex, WorkflowStatus.amberHex)
        store.undo() // both renames are one step
        XCTAssertEqual(store.project(pid)?.status(id)?.name, "QA")
        store.undo() // add
        XCTAssertNil(store.project(pid)?.status(id))
    }

    func testCategoryChangesKeepTheRulesAndPauseTimers() async {
        let (store, pid) = await makeStore()
        XCTAssertFalse(store.setStatusCategory(projectId: pid, statusId: "todo", .started),
                       "the only Not started status can't change kind")
        XCTAssertFalse(store.setStatusCategory(projectId: pid, statusId: "done", .canceled))
        XCTAssertFalse(store.canDeleteStatus(projectId: pid, statusId: "done"))
        XCTAssertFalse(store.deleteStatus(projectId: pid, statusId: "todo"))
        XCTAssertTrue(store.canDeleteStatus(projectId: pid, statusId: "inProgress"))

        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        XCTAssertEqual(store.task(a)?.statusId, "inProgress")
        XCTAssertTrue(store.setStatusCategory(projectId: pid, statusId: "inProgress", .done, now: t0.addingTimeInterval(60)))
        XCTAssertEqual(store.task(a)?.statusCategory, .done, "tasks follow their status's kind")
        XCTAssertFalse(store.isRunning(a), "becoming done pauses the timer")
        XCTAssertEqual(store.task(a)?.spentSeconds, 60)
        store.undo()
        XCTAssertEqual(store.task(a)?.statusCategory, .started)
    }

    func testDeletingAStatusInUseMovesItsTasks() async {
        let (store, pid) = await makeStore(.dev)
        let review = status(store, pid, "Review")
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.setStatus(a, review, now: t0)
        store.setStatus(b, review, now: t0)
        store.startTimer(b, now: t0)
        XCTAssertEqual(store.statusUsage(projectId: pid, statusId: review.id), 2)

        XCTAssertTrue(store.deleteStatus(projectId: pid, statusId: review.id, reassignTo: "done", now: t0.addingTimeInterval(30)))
        XCTAssertNil(store.project(pid)?.status(review.id))
        XCTAssertEqual(store.task(a)?.statusId, "done")
        XCTAssertEqual(store.task(b)?.statusId, "done")
        XCTAssertFalse(store.isRunning(b), "moving to done pauses the timer")
        XCTAssertEqual(store.undoActionName, "Delete status")

        store.undo()
        XCTAssertNotNil(store.project(pid)?.status(review.id))
        XCTAssertEqual(store.task(a)?.statusId, review.id)

        // Without a target: the first remaining status of the same kind
        XCTAssertTrue(store.deleteStatus(projectId: pid, statusId: review.id))
        XCTAssertEqual(store.task(a)?.statusId, "inProgress")
    }

    // MARK: - Behaviour follows the category

    func testTimersFollowTheCategory() async {
        let (store, pid) = await makeStore(.dev)
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        XCTAssertEqual(store.task(a)?.statusId, "backlog", "new tasks start in the first Not started status")
        store.startTimer(a, now: t0)
        XCTAssertEqual(store.task(a)?.statusId, "inProgress", "starting moves to the first Started status")

        store.setStatus(a, status(store, pid, "Review"), now: t0.addingTimeInterval(10))
        XCTAssertTrue(store.isRunning(a), "another started status keeps the timer")
        store.pauseTimer(a, now: t0.addingTimeInterval(20))
        store.startTimer(a, now: t0.addingTimeInterval(30))
        XCTAssertEqual(store.task(a)?.statusId, "review", "a started task keeps its status")

        store.setStatus(a, .canceled, now: t0.addingTimeInterval(40))
        XCTAssertFalse(store.isRunning(a), "canceled pauses the timer")
        XCTAssertEqual(store.task(a)?.spentSeconds, 30)
        XCTAssertFalse(store.activeSprintTasks(projectId: pid).contains { $0.id == a })

        // A workflow without a started status: a closed task reopens, an open one stays put
        let (simple, sp) = await makeStore()
        XCTAssertTrue(simple.deleteStatus(projectId: sp, statusId: "inProgress"))
        let b = simple.addTask(title: "B", projectId: sp, now: t0)!
        simple.setStatus(b, .done, now: t0)
        simple.startTimer(b, now: t0)
        XCTAssertEqual(simple.task(b)?.statusId, "todo")
        let c = simple.addTask(title: "C", projectId: sp, now: t0)!
        simple.startTimer(c, now: t0)
        XCTAssertEqual(simple.task(c)?.statusId, "todo")
    }

    func testMenuPlayPicksTheRecentStartedTaskElseTopNotStarted() async {
        let (store, pid) = await makeStore(.dev)
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        XCTAssertEqual(store.nextTaskToStart(projectId: pid)?.id, a, "top not started task")
        store.setStatus(b, status(store, pid, "Review"), now: t0.addingTimeInterval(5))
        XCTAssertEqual(store.nextTaskToStart(projectId: pid)?.id, b, "any started status counts")
        XCTAssertEqual(store.menuInProgressTasks.paused.map(\.id), [b])
    }

    func testStatusCircleCyclesThroughTheWorkflow() async {
        let (store, pid) = await makeStore(.dev)
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        var seen: [String] = []
        for i in 0..<6 {
            store.cycleStatus(a, now: t0.addingTimeInterval(Double(i)))
            seen.append(store.task(a)!.statusId)
        }
        XCTAssertEqual(seen, ["todo", "inProgress", "review", "done", "canceled", "backlog"])
    }

    func testCompleteSprintClosesDoneAndCanceled() async {
        let (store, pid) = await makeStore(.dev)
        let done = store.addTask(title: "Done", projectId: pid, now: t0)!
        let canceled = store.addTask(title: "Canceled", projectId: pid, now: t0)!
        let open = store.addTask(title: "Open", projectId: pid, now: t0)!
        store.setStatus(done, .done, now: t0)
        store.setStatus(canceled, .canceled, now: t0)
        store.setStatus(open, status(store, pid, "Review"), now: t0)

        store.completeSprint(projectId: pid, unfinished: .moveToNextSprint, now: t0)
        XCTAssertEqual(store.task(done)?.sprintSlot, .closed)
        XCTAssertEqual(store.task(canceled)?.sprintSlot, .closed)
        XCTAssertEqual(store.task(open)?.sprintSlot, .active)
        let past = store.project(pid)!.pastSprints.last!
        XCTAssertEqual(Set(past.taskIds), [done, canceled, open])
        XCTAssertEqual(past.doneTaskIds, [done], "only done tasks count as done")

        // Reopening a closed task by status puts it back into planning
        store.setStatus(canceled, .todo, now: t0)
        XCTAssertEqual(store.task(canceled)?.sprintSlot, .backlog)
    }

    func testOverdueAndProgressIgnoreCanceled() async {
        let (store, pid) = await makeStore(.dev)
        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, milestoneId: m, now: t0)!
        store.setDueDate(a, t0.addingTimeInterval(-3 * 86_400))
        XCTAssertTrue(store.isOverdue(store.task(a)!, now: t0))
        store.setStatus(a, .canceled, now: t0)
        XCTAssertFalse(store.isOverdue(store.task(a)!, now: t0), "canceled tasks aren't overdue")
        store.setStatus(b, .done, now: t0)
        let progress = store.milestoneProgress(m)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(progress.total, 1, "canceled work leaves the total")
        XCTAssertEqual(store.openCount(pid), 0)
    }

    func testMovingToAnotherProjectRemapsTheStatus() async {
        let (store, dev) = await makeStore(.dev)
        let simple = store.addProject(name: "Simple", now: t0)!
        let dev2 = store.addProject(name: "Dev 2", now: t0)!
        store.applyWorkflowPreset(projectId: dev2, .dev, now: t0)
        let a = store.addTask(title: "A", projectId: dev, now: t0)!
        let b = store.addTask(title: "B", projectId: dev, now: t0)!
        let c = store.addTask(title: "C", projectId: dev, now: t0)!
        store.setStatus(a, status(store, dev, "Review"), now: t0)
        store.setStatus(b, status(store, dev, "Review"), now: t0)
        store.setStatus(c, .canceled, now: t0)

        store.setProject(a, simple)
        XCTAssertEqual(store.task(a)?.statusId, "inProgress", "the first status of the same category")
        store.setProject(b, dev2)
        XCTAssertEqual(store.task(b)?.statusId, "review", "a status with the same name and category is kept")
        store.setProject(c, simple)
        XCTAssertEqual(store.task(c)?.statusId, "done", "no canceled status: the closest closed one")

        store.undo()
        XCTAssertEqual(store.task(c)?.projectId, dev)
        XCTAssertEqual(store.task(c)?.statusId, "canceled")

        // Dropping on a list group of another project's status goes through the same mapping
        store.moveTask(a, to: .status(status(store, dev, "Review")), reorder: false)
        XCTAssertEqual(store.task(a)?.statusId, "inProgress", "a status of another project is matched in the task's own")
    }

    // MARK: - Views

    func testBoardColumnsFollowTheWorkflowOrCategories() async throws {
        let (store, dev) = await makeStore(.dev)
        let simple = store.addProject(name: "Simple", now: t0)!
        let a = store.addTask(title: "A", projectId: dev, now: t0)!
        let b = store.addTask(title: "B", projectId: simple, now: t0)!
        store.setStatus(a, status(store, dev, "Review"), now: t0)
        store.setStatus(b, .inProgress, now: t0)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WorkflowTests-\(UUID().uuidString)"))
        let model = TasksViewModel(defaults: defaults)

        model.select(.project(dev))
        XCTAssertEqual(model.boardColumns(store).map(\.statusTitle), ["Backlog", "To do", "In progress", "Review", "Done", "Canceled"])

        model.select(.all)
        XCTAssertEqual(model.boardColumns(store).map(\.statusTitle), ["Not started", "Started", "Done"],
                       "All projects groups by category; Canceled hides while empty")
        XCTAssertEqual(Set(model.boardTasks(store, column: .category(.started)).map(\.id)), [a, b])
        store.moveTask(a, toCategory: .canceled)
        XCTAssertEqual(store.task(a)?.statusId, "canceled")
        XCTAssertEqual(model.boardColumns(store).last?.statusTitle, "Canceled")
        store.moveTask(b, toCategory: .done)
        XCTAssertEqual(store.task(b)?.statusId, "done")

        // List groups: a project's statuses; All projects by category; closed ones start collapsed
        let groups = store.groups(store.tasks(in: .all), by: .status, in: .all)
        XCTAssertEqual(groups.map(\.title), ["Not started", "Started", "Done", "Canceled"])
        XCTAssertTrue(model.isCollapsed(TaskGroupValue.category(.canceled).key))
        XCTAssertTrue(model.isCollapsed(TaskGroupValue.status(status(store, dev, "Canceled")).key))
        XCTAssertFalse(model.isCollapsed(TaskGroupValue.status(status(store, dev, "Review")).key))
        let devGroups = store.groups(store.tasks(of: dev), by: .status, in: .project(dev))
        XCTAssertEqual(devGroups.count, 6)
        XCTAssertEqual(devGroups.last?.tasks.map(\.id), [a])
    }

    func testFiltersSortAndBulkEditsAcrossWorkflows() async {
        let (store, dev) = await makeStore(.dev)
        let simple = store.addProject(name: "Simple", now: t0)!
        let a = store.addTask(title: "A", projectId: dev, now: t0)!
        let b = store.addTask(title: "B", projectId: simple, now: t0)!
        let c = store.addTask(title: "C", projectId: dev, now: t0)!
        store.setStatus(a, status(store, dev, "Review"), now: t0)
        store.setStatus(c, .done, now: t0)

        var f = TaskFilter()
        f.categories = [.started]
        XCTAssertEqual(store.filtered(store.tasks(in: .all), by: f).map(\.id), [a])
        f = TaskFilter()
        f.statuses = ["review", "deleted-status"]
        XCTAssertEqual(store.filtered(store.tasks(in: .all), by: f).map(\.id), [a])
        f.statuses = ["deleted-status"]
        XCTAssertEqual(store.filtered(store.tasks(in: .all), by: f).count, 3, "a stale status chip never hides everything")

        // Sort by status: one project in workflow order; several by category first
        XCTAssertEqual(store.sorted(store.tasks(of: dev), by: TaskSort(key: .status)).map(\.id), [a, c])
        XCTAssertEqual(store.sorted([c, a, b].compactMap { store.task($0) }, by: TaskSort(key: .status)).map(\.id), [b, a, c])

        // Bulk: tasks of both projects share To do, In progress and Done
        XCTAssertEqual(store.commonStatuses(for: [a, b]).map(\.name), ["To do", "In progress", "Done"])
        XCTAssertEqual(store.commonStatuses(for: [a, c]).count, 6)
        store.setCategory([a, b], .done)
        XCTAssertEqual([store.task(a)?.statusId, store.task(b)?.statusId], ["done", "done"])
        XCTAssertEqual(store.undoActionName, "Change status")
        store.undo()
        XCTAssertEqual(store.task(a)?.statusId, "review", "one undo step")
    }

    func testComposerPresetsPickTheStatusOrCategory() async {
        let (store, dev) = await makeStore(.dev)
        var draft = ComposerDraft()
        draft.status = status(store, dev, "Review")
        let a = store.addTask(title: "A", draft: draft, projectId: dev, now: t0)!
        XCTAssertEqual(store.task(a)?.statusId, "review")
        draft = ComposerDraft()
        draft.category = .started
        let b = store.addTask(title: "B", draft: draft, projectId: dev, now: t0)!
        XCTAssertEqual(store.task(b)?.statusId, "inProgress")
        let c = store.addTask(title: "C", draft: ComposerDraft(), projectId: dev, now: t0)!
        XCTAssertEqual(store.task(c)?.statusId, "backlog")
        let copy = store.duplicateTask(a, now: t0)!
        XCTAssertEqual(store.task(copy)?.statusId, "backlog", "a duplicate starts over")
    }
}
