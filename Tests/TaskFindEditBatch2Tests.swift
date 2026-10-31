import AppKit
import XCTest
@testable import FlowMate

/// Find and edit: undo/redo, filters, grouping and moving between groups, duplicate,
/// due presets, per-project view options and the window's keyboard shortcuts.
@MainActor
final class TaskFindEditBatch2Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    // MARK: - Undo (#13)

    func testUndoRedoDelete() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.deleteTask(a)
        XCTAssertNil(store.task(a))
        XCTAssertEqual(store.undoActionName, "Delete task")

        XCTAssertEqual(store.undo(), "Delete task")
        XCTAssertEqual(store.task(a)?.title, "A")
        XCTAssertTrue(store.canRedo)

        XCTAssertEqual(store.redo(), "Delete task")
        XCTAssertNil(store.task(a))
        store.undo()
        store.undo() // the add
        XCTAssertTrue(store.workspace.tasks.isEmpty)
        XCTAssertNil(store.undo(), "only the project add is left, and it was cleared")
    }

    func testTypingCoalescesIntoOneStep() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        var clock = t0
        store.clock = { clock }
        let before = store.undoStack.count
        for title in ["Ab", "Abc", "Abcd"] {
            clock = clock.addingTimeInterval(0.4)
            store.setTitle(a, title)
        }
        XCTAssertEqual(store.undoStack.count, before + 1, "rapid typing is one step")
        // A pause starts a new step
        clock = clock.addingTimeInterval(5)
        store.setTitle(a, "Abcde")
        XCTAssertEqual(store.undoStack.count, before + 2)

        store.undo()
        XCTAssertEqual(store.task(a)?.title, "Abcd")
        store.undo()
        XCTAssertEqual(store.task(a)?.title, "A")
        // After undo, the next edit never merges into an older step
        store.setTitle(a, "B")
        store.setTitle(a, "Bc")
        store.undo()
        XCTAssertEqual(store.task(a)?.title, "A")
    }

    func testNewEditClearsRedoAndHistoryIsCapped() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.setPriority(a, .high)
        store.undo()
        XCTAssertTrue(store.canRedo)
        store.setPriority(a, .low)
        XCTAssertFalse(store.canRedo)

        for i in 0..<(TaskStore.undoLimit + 20) {
            store.setExpectedMinutes(a, 10 + i)
        }
        XCTAssertEqual(store.undoStack.count, TaskStore.undoLimit)
    }

    func testDragIsOneUndoStep() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let steps = store.undoStack.count
        store.moveTask(b, toStatus: .inProgress, before: a)
        XCTAssertEqual(store.undoStack.count, steps + 1)
        XCTAssertEqual(store.undoActionName, "Move task")
        store.undo()
        XCTAssertEqual(store.task(b)?.statusId, WorkflowStatus.todo.id)
        XCTAssertEqual(store.tasks(of: pid).map(\.id), [a, b])
    }

    func testTimersAreNotUndoStepsAndUndoKeepsTrackedTime() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let other = store.addTask(title: "Other", projectId: pid, now: t0)!
        store.setPriority(other, .high)
        let steps = store.undoStack.count
        store.startTimer(a, now: t0)
        store.pauseTimer(a, now: t0.addingTimeInterval(600))
        store.startTimer(a, now: t0.addingTimeInterval(700))
        XCTAssertEqual(store.undoStack.count, steps, "timer starts and pauses aren't undo steps")

        // Undoing an unrelated edit leaves the running timer and the tracked time alone
        store.undo(now: t0.addingTimeInterval(800))
        XCTAssertEqual(store.task(other)?.priority, .medium)
        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.task(a)?.spentSeconds, 600)
        XCTAssertEqual(store.task(a)?.statusId, WorkflowStatus.inProgress.id, "a running task never shows To do")
    }

    func testUndoingReopenOfRunningTaskPausesIt() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.setStatus(a, .done, now: t0)
        store.setStatus(a, .todo, now: t0)
        store.startTimer(a, now: t0)
        // Undo "Change status" brings back Done: a Done task can't run, so the timer pauses and keeps the time
        store.undo(now: t0.addingTimeInterval(120))
        XCTAssertEqual(store.task(a)?.statusId, WorkflowStatus.done.id)
        XCTAssertFalse(store.isRunning(a))
        XCTAssertEqual(store.task(a)?.spentSeconds, 120)
    }

    func testUndoDeleteBringsBackRunningTimerAndCompleteSprintUndoes() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        store.deleteTask(a)
        XCTAssertFalse(store.isRunning(a))
        store.undo()
        XCTAssertTrue(store.isRunning(a), "an undone delete restores the task as it was")

        store.setStatus(a, .done, now: t0)
        let number = store.project(pid)!.sprint.number
        store.completeSprint(projectId: pid, now: t0)
        XCTAssertEqual(store.task(a)?.sprintSlot, .closed)
        XCTAssertEqual(store.undoActionName, "Complete sprint")
        store.undo()
        XCTAssertEqual(store.task(a)?.sprintSlot, .active)
        XCTAssertEqual(store.project(pid)?.sprint.number, number)
    }

    func testLoadClearsUndoHistory() async {
        let (store, pid) = await makeStore()
        store.addTask(title: "A", projectId: pid, now: t0)
        XCTAssertTrue(store.canUndo)
        await store.load()
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - Filters (#2)

    func testSearchMatchesTitleDescriptionAndSubtasks() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "Fix login bug", projectId: pid, now: t0)!
        let b = store.addTask(title: "Write docs", projectId: pid, now: t0)!
        store.setNotes(b, "Mention the Login flow")
        let c = store.addTask(title: "Release", projectId: pid, now: t0)!
        store.addSubtask(c, title: "Tag the build")

        var f = TaskFilter()
        f.query = "login"
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: f).map(\.id), [a, b])
        f.query = "  tag build "
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: f).map(\.id), [c], "every word must match somewhere")
        f.query = "nothing"
        XCTAssertTrue(store.filtered(store.tasks(of: pid), by: f).isEmpty)
    }

    func testChipsCombine() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let m = store.addMilestone(projectId: pid, name: "M1")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let c = store.addTask(title: "C", projectId: other, now: t0)!
        store.setPriority(a, .high)
        store.setStatus(b, .inProgress)
        store.setSprintSlot(c, .backlog)
        let all = store.tasks(in: .all)

        var f = TaskFilter()
        f.priorities = [.high]
        XCTAssertEqual(store.filtered(all, by: f).map(\.id), [a])
        f = TaskFilter()
        f.statuses = [WorkflowStatus.todo.id]
        f.projectIds = [pid]
        XCTAssertEqual(store.filtered(all, by: f).map(\.id), [a])
        f = TaskFilter()
        f.milestones = [nil]
        XCTAssertEqual(store.filtered(all, by: f).map(\.id), [b, c])
        f.milestones = [m, nil]
        XCTAssertEqual(store.filtered(all, by: f).count, 3)
        f = TaskFilter()
        f.sprintSlots = [.backlog]
        XCTAssertEqual(store.filtered(all, by: f).map(\.id), [c])

        // A deleted milestone in the filter is ignored rather than hiding everything
        f = TaskFilter()
        f.milestones = [UUID()]
        XCTAssertEqual(store.filtered(all, by: f).count, 3)
        XCTAssertEqual(f.chipCount, 1)
        XCTAssertFalse(f.isEmpty)
    }

    func testDueFilters() async {
        let (store, pid) = await makeStore()
        let now = t0
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let overdue = store.addTask(title: "Late", projectId: pid, now: t0)!
        store.setDueDate(overdue, cal.date(byAdding: .day, value: -2, to: today))
        let dueToday = store.addTask(title: "Today", projectId: pid, now: t0)!
        store.setDueDate(dueToday, today)
        let farAway = store.addTask(title: "Later", projectId: pid, now: t0)!
        store.setDueDate(farAway, cal.date(byAdding: .day, value: 30, to: today))
        let noDate = store.addTask(title: "None", projectId: pid, now: t0)!
        let doneLate = store.addTask(title: "Done late", projectId: pid, now: t0)!
        store.setDueDate(doneLate, cal.date(byAdding: .day, value: -2, to: today))
        store.setStatus(doneLate, .done)

        var f = TaskFilter()
        f.due = [.overdue]
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: f, now: now).map(\.id), [overdue], "done tasks aren't overdue")
        f.due = [.thisWeek]
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: f, now: now).map(\.id), [dueToday])
        f.due = [.noDate, .overdue]
        XCTAssertEqual(store.filtered(store.tasks(of: pid), by: f, now: now).map(\.id), [overdue, noDate])
    }

    func testViewOptionsDecodeTolerantly() throws {
        let json = #"{"filter":{"query":"x","statuses":["todo","bogus"],"due":["overdue"]},"sort":{"key":"due"},"grouping":"weird"}"#
        let options = try JSONDecoder().decode(TaskViewOptions.self, from: Data(json.utf8))
        XCTAssertEqual(options.filter.query, "x")
        // Status ids are free strings now (custom workflows); unknown ones are ignored when filtering
        XCTAssertEqual(options.filter.statuses, [WorkflowStatus.todo.id, "bogus"])
        XCTAssertEqual(options.filter.due, [.overdue])
        XCTAssertEqual(options.sort, TaskSort(key: .due))
        XCTAssertEqual(options.grouping, .status)
        let empty = try JSONDecoder().decode(TaskViewOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .standard)
        // Round trip, including "No milestone"
        var custom = TaskViewOptions()
        custom.filter.milestones = [nil, UUID()]
        let back = try JSONDecoder().decode(TaskViewOptions.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(back, custom)
    }

    func testOptionsAreKeptPerProjectAndCleared() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.filter.query = "all"
        model.select(.project(pid))
        XCTAssertEqual(model.filter.query, "", "each project starts clean")
        model.filter.priorities = [.high]
        model.options.grouping = .project
        XCTAssertEqual(model.grouping, .status, "Project grouping only applies in All projects")
        model.select(.all)
        XCTAssertEqual(model.filter.query, "all")
        model.select(.project(pid))
        XCTAssertEqual(model.filter.priorities, [.high])
        model.clearOptions()
        XCTAssertEqual(model.options, .standard)
        XCTAssertFalse(model.options.isCustomized)
        _ = store
    }

    // MARK: - Grouping and moving between groups (#4, #5)

    func testGroupsByMilestoneAndSprint() async {
        let (store, pid) = await makeStore()
        let m1 = store.addMilestone(projectId: pid, name: "Beta", dueDate: t0)!
        let m2 = store.addMilestone(projectId: pid, name: "Launch")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m1, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!

        let byMilestone = store.groups(store.tasks(of: pid), by: .milestone, in: .project(pid))
        XCTAssertEqual(byMilestone.map(\.value), [.milestone(m1), .milestone(m2), .milestone(nil)])
        XCTAssertEqual(byMilestone.map { $0.tasks.map(\.id) }, [[a], [], [b]])
        XCTAssertEqual(byMilestone.last?.title, "No milestone")

        let bySprint = store.groups(store.tasks(of: pid), by: .sprint, in: .project(pid))
        XCTAssertEqual(bySprint.map(\.value), [.sprint(.active), .sprint(.next), .sprint(.backlog)], "closed shows only when used")
        store.setStatus(a, .done)
        store.completeSprint(projectId: pid, now: t0)
        let afterClose = store.groups(store.tasks(of: pid), by: .sprint, in: .project(pid))
        XCTAssertEqual(afterClose.last?.value, .sprint(.closed))
        XCTAssertEqual(afterClose.last?.acceptsDrop, false)

        let byStatus = store.groups(store.tasks(of: pid), by: .status, in: .project(pid))
        XCTAssertEqual(byStatus.map(\.title), ["To do", "In progress", "Done"])
    }

    func testDropOnGroupSetsValueAndReorders() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let m = store.addMilestone(projectId: pid, name: "M")!
        let foreign = store.addMilestone(projectId: other, name: "Theirs")!
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!

        store.moveTask(b, to: .milestone(m), before: a)
        XCTAssertEqual(store.task(b)?.milestoneId, m)
        XCTAssertEqual(store.tasks(of: pid).map(\.id), [b, a])
        store.undo()
        XCTAssertNil(store.task(b)?.milestoneId)
        XCTAssertEqual(store.tasks(of: pid).map(\.id), [a, b], "one undo step reverts value and order")

        // A milestone of another project brings the task along
        store.moveTask(a, to: .milestone(foreign))
        XCTAssertEqual(store.task(a)?.projectId, other)
        XCTAssertEqual(store.task(a)?.milestoneId, foreign)

        store.startTimer(b, now: t0)
        store.moveTask(b, to: .status(.done), reorder: false, now: t0.addingTimeInterval(60))
        XCTAssertEqual(store.task(b)?.statusId, WorkflowStatus.done.id)
        XCTAssertFalse(store.isRunning(b), "Done still pauses the timer")
        store.moveTask(b, to: .priority(.high))
        XCTAssertEqual(store.task(b)?.priority, .high)
        store.moveTask(b, to: .sprint(.closed))
        XCTAssertNotEqual(store.task(b)?.sprintSlot, .closed, "can't drop into a closed sprint")
        store.moveTask(b, to: .project(other))
        XCTAssertEqual(store.task(b)?.projectId, other)
    }

    // MARK: - Inline edits (#6) and duplicate (#15)

    func testDuePresets() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        // 15:00 UTC on some day
        let base = 1_793_200_000
        let now = Date(timeIntervalSince1970: TimeInterval(base - base % 86_400 + 15 * 3600))
        let day = { (d: Date) in cal.dateComponents([.year, .month, .day, .weekday], from: d) }
        XCTAssertEqual(DuePreset.today.date(now: now, calendar: cal), cal.startOfDay(for: now))
        XCTAssertEqual(DuePreset.tomorrow.date(now: now, calendar: cal),
                       cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)))
        let nextWeek = DuePreset.nextWeek.date(now: now, calendar: cal)
        XCTAssertEqual(day(nextWeek).weekday, 2, "next week starts on the first weekday")
        XCTAssertGreaterThan(nextWeek, now)
        XCTAssertLessThanOrEqual(nextWeek.timeIntervalSince(now), 7 * 86_400)
    }

    func testInlineRenameIsOneStep() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.renameTaskOnce(a, "  Renamed ")
        XCTAssertEqual(store.task(a)?.title, "Renamed")
        store.renameTaskOnce(a, "   ")
        XCTAssertEqual(store.task(a)?.title, "Renamed", "blank titles are ignored")
        store.undo()
        XCTAssertEqual(store.task(a)?.title, "A")
    }

    func testDuplicateResetsProgressAndSitsBelow() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.addSubtask(a, title: "Step")
        store.toggleSubtask(a, store.task(a)!.subtasks[0].id)
        store.setPriority(a, .high)
        store.startTimer(a, now: t0)
        store.pauseTimer(a, now: t0.addingTimeInterval(300))

        let copy = store.duplicateTask(a, now: t0)!
        let dup = store.task(copy)!
        XCTAssertEqual(dup.title, "A")
        XCTAssertEqual(dup.priority, .high)
        XCTAssertEqual(dup.statusId, WorkflowStatus.todo.id)
        XCTAssertEqual(dup.spentSeconds, 0)
        XCTAssertEqual(dup.subtasks.map(\.isDone), [false])
        XCTAssertNotEqual(dup.subtasks[0].id, store.task(a)!.subtasks[0].id)
        XCTAssertEqual(store.tasks(of: pid).map(\.id), [a, copy, b])
        XCTAssertNil(store.duplicateTask(UUID()))
    }

    // MARK: - Keyboard (#15)

    func testShortcutMatching() {
        func match(_ key: String, _ code: UInt16 = 0, _ mods: NSEvent.ModifierFlags = []) -> TasksShortcut? {
            TasksShortcut.match(keyCode: code, characters: key, modifiers: mods)
        }
        XCTAssertEqual(match("z", 6, .command), .undo)
        XCTAssertEqual(match("Z", 6, [.command, .shift]), .redo)
        XCTAssertEqual(match("n", 45, .command), .newTask)
        XCTAssertEqual(match("N", 45, [.command, .shift]), .newProject)
        XCTAssertEqual(match("f", 3, .command), .find)
        XCTAssertEqual(match("2", 19, .command), .tab2)
        XCTAssertEqual(match("", 126, [.numericPad, .function]), .selectPrevious, "arrow keys carry these flags")
        XCTAssertEqual(match("\r", 36), .open)
        XCTAssertEqual(match(" ", 49), .toggleTimer)
        XCTAssertEqual(match("", 51, .command), .delete)
        XCTAssertEqual(match("d", 2, .command), .duplicate)
        XCTAssertEqual(match("/", 44, .command), .help)
        XCTAssertNil(match("", 51), "plain Delete does nothing")
        XCTAssertNil(match("z", 6, [.command, .option]))
        XCTAssertNil(match("a", 0))

        XCTAssertTrue(TasksShortcut.find.worksWhileTyping)
        XCTAssertFalse(TasksShortcut.undo.worksWhileTyping, "⌘Z in a field undoes the typing")
        XCTAssertFalse(TasksShortcut.toggleTimer.worksWhileTyping)
        XCTAssertFalse(TasksShortcut.delete.worksWhileTyping)
    }

    func testKeyboardSelectionOpenDeleteAndToastUndo() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let c = store.addTask(title: "C", projectId: pid, now: t0)!
        store.setStatus(c, .inProgress)

        XCTAssertEqual(model.visibleTasks(store).map(\.id), [a, b, c], "To do, then In progress")
        XCTAssertTrue(model.perform(.selectNext, store: store))
        XCTAssertEqual(model.selectedTaskId, a)
        model.perform(.selectNext, store: store)
        model.perform(.selectNext, store: store)
        model.perform(.selectNext, store: store)
        XCTAssertEqual(model.selectedTaskId, c, "stops at the last row")

        // Filters change what ↑/↓ walk
        model.filter.query = "B"
        XCTAssertEqual(model.visibleTasks(store).map(\.id), [b])
        model.filter.query = ""

        XCTAssertTrue(model.perform(.toggleTimer, store: store))
        XCTAssertTrue(store.isRunning(c))

        XCTAssertTrue(model.perform(.open, store: store))
        XCTAssertEqual(model.openTaskId, c)
        XCTAssertFalse(model.perform(.selectPrevious, store: store), "arrows scroll the open panel")

        XCTAssertTrue(model.perform(.delete, store: store))
        XCTAssertNil(store.task(c))
        XCTAssertNil(model.openTaskId)
        XCTAssertEqual(model.selectedTaskId, b, "selection moves to a neighbour")
        XCTAssertEqual(model.toast?.message, "Task deleted")
        XCTAssertNotNil(model.toast?.undoId)

        model.undoFromToast(store)
        XCTAssertNotNil(store.task(c))
        XCTAssertNil(model.toast)

        // A toast whose step is no longer the newest never undoes something else
        model.perform(.selectNext, store: store)
        model.deleteTask(a, store: store)
        store.setPriority(b, .high)
        model.undoFromToast(store)
        XCTAssertNil(store.task(a), "the toast's undo was stale")
        XCTAssertEqual(store.task(b)?.priority, .high)

        XCTAssertTrue(model.perform(.undo, store: store))
        XCTAssertEqual(store.task(b)?.priority, .medium)
        XCTAssertEqual(model.toast?.message, "Undid change priority")
        XCTAssertTrue(model.perform(.redo, store: store))
        XCTAssertEqual(store.task(b)?.priority, .high)

        XCTAssertTrue(model.perform(.duplicate, store: store))
        XCTAssertEqual(store.tasks(of: pid).count, 3)

        XCTAssertTrue(model.perform(.tab1, store: store))
        XCTAssertEqual(model.tab, .board)
        XCTAssertTrue(model.perform(.find, store: store))
        XCTAssertEqual(model.tab, .board, "Board has the filter bar")
        XCTAssertEqual(model.focusRequest?.field, .search)
        model.tab = .milestones
        model.perform(.find, store: store)
        XCTAssertEqual(model.tab, .list)

        model.select(.all)
        XCTAssertFalse(model.perform(.tab4, store: store), "All projects has three tabs")
    }
}
