import AppKit
import XCTest
@testable import FlowMate

/// Power use: bulk selection and edits, duplicate, quick-add tokens and the remembered project,
/// stepping through tasks, fixing tracked time, the long-run prompt, custom expected time,
/// typed dates, the overdue reschedule and subtask order and conversion.
@MainActor
final class TaskPowerBatch4Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    /// Thursday Oct 29 2026, noon UTC
    private var thursday: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))! }
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - #27 Durations

    func testDurationParser() {
        XCTAssertEqual(TaskDurationParser.minutes("1h 15m"), 75)
        XCTAssertEqual(TaskDurationParser.minutes("1h15m"), 75)
        XCTAssertEqual(TaskDurationParser.minutes("90"), 90)
        XCTAssertEqual(TaskDurationParser.minutes("90m"), 90)
        XCTAssertEqual(TaskDurationParser.minutes("1.5h"), 90)
        XCTAssertEqual(TaskDurationParser.minutes("1,5h"), 90)
        XCTAssertEqual(TaskDurationParser.minutes("1:15"), 75)
        XCTAssertEqual(TaskDurationParser.seconds("1:12:30"), 4350)
        XCTAssertEqual(TaskDurationParser.minutes("2 hours"), 120)
        XCTAssertEqual(TaskDurationParser.minutes("45 min"), 45)
        XCTAssertEqual(TaskDurationParser.minutes("0"), 0)
        XCTAssertNil(TaskDurationParser.minutes("soon"))
        XCTAssertNil(TaskDurationParser.minutes("1h banana"))
        XCTAssertNil(TaskDurationParser.minutes("1:75"))
        XCTAssertEqual(TaskDurationParser.format(seconds: 4350), "1h 12m")
        XCTAssertEqual(TaskDurationParser.format(seconds: 7200), "2h")
        XCTAssertEqual(TaskDurationParser.format(seconds: 59), "0m")
    }

    func testCustomExpectedTimeAboveEightHours() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Long", projectId: pid, now: t0)!
        store.setExpectedMinutes(id, TaskDurationParser.minutes("9h 30m")!)
        XCTAssertEqual(store.task(id)?.expectedMinutes, 570)
    }

    // MARK: - #28 Typed dates

    func testTypedDates() {
        let now = thursday
        func parse(_ text: String, locale: String = "en_US") -> Date? {
            TaskDateParser.parse(text, now: now, calendar: utc, locale: Locale(identifier: locale))
        }
        XCTAssertEqual(parse("today"), day(10, 29))
        XCTAssertEqual(parse("tomorrow"), day(10, 30))
        XCTAssertEqual(parse("tmr"), day(10, 30))
        XCTAssertEqual(parse("fri"), day(10, 30), "the next Friday")
        XCTAssertEqual(parse("Friday"), day(10, 30))
        XCTAssertEqual(parse("thu"), day(11, 5), "today's weekday means next week")
        XCTAssertEqual(parse("next fri"), day(11, 6))
        XCTAssertEqual(parse("3d"), day(11, 1))
        XCTAssertEqual(parse("+3"), day(11, 1))
        XCTAssertEqual(parse("in 2 weeks"), day(11, 12))
        XCTAssertEqual(parse("in 3"), day(11, 1))
        XCTAssertEqual(parse("nov 18"), day(11, 18))
        XCTAssertEqual(parse("Nov18"), day(11, 18))
        XCTAssertEqual(parse("18 nov"), day(11, 18))
        XCTAssertEqual(parse("18th nov"), day(11, 18))
        XCTAssertEqual(parse("november 18, 2027"), day(11, 18, 2027))
        XCTAssertEqual(parse("oct 1"), day(10, 1, 2027), "passed dates mean next year")
        XCTAssertEqual(parse("11/18"), day(11, 18))
        XCTAssertEqual(parse("18/11", locale: "en_GB"), day(11, 18))
        XCTAssertEqual(parse("2026-12-01"), day(12, 1))
        XCTAssertEqual(parse("29"), day(10, 29))
        XCTAssertEqual(parse("28"), day(11, 28))
        XCTAssertNil(parse("feb 30"))
        XCTAssertNil(parse("someday"))
        XCTAssertNil(parse(""))
    }

    // MARK: - #19 Quick add

    func testQuickAddTokens() {
        let input = QuickAddInput.parse("Fix login !high @beta due:fri ~1h30m", now: thursday, calendar: utc)
        XCTAssertEqual(input.title, "Fix login")
        XCTAssertEqual(input.priority, .high)
        XCTAssertEqual(input.milestoneQuery, "beta")
        XCTAssertEqual(input.dueDate, day(10, 30))
        XCTAssertEqual(input.expectedMinutes, 90)

        let quoted = QuickAddInput.parse("Ship @\"Beta launch\" due:\"nov 18\" !low", now: thursday, calendar: utc)
        XCTAssertEqual(quoted.title, "Ship")
        XCTAssertEqual(quoted.milestoneQuery, "Beta launch")
        XCTAssertEqual(quoted.dueDate, day(11, 18))
        XCTAssertEqual(quoted.priority, .low)

        let plain = QuickAddInput.parse("Email bob@example.com about !important stuff due:never", now: thursday, calendar: utc)
        XCTAssertEqual(plain.title, "Email bob@example.com about !important stuff due:never", "unknown tokens stay in the title")
        XCTAssertFalse(plain.hasTokens)
    }

    func testQuickAddTaskAppliesTokensAsOneStepAndRemembersProject() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let mid = store.addMilestone(projectId: other, name: "Beta launch")!
        store.clearUndoHistory()
        XCTAssertEqual(store.defaultProject?.id, pid, "first project until one is used")

        let outcome = store.quickAddTask("Write post !h @beta-launch ~45m due:tomorrow", projectId: other, now: t0)
        let task = store.task(outcome!.taskId)!
        XCTAssertEqual(task.title, "Write post")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.milestoneId, mid)
        XCTAssertEqual(task.expectedMinutes, 45)
        XCTAssertNotNil(task.dueDate)
        XCTAssertEqual(outcome?.applied.first, "High")
        XCTAssertTrue(outcome!.applied.contains("Beta launch"))
        XCTAssertEqual(store.undoStack.count, 1, "the add and its tokens are one step")
        XCTAssertEqual(store.defaultProject?.id, other, "the last project used is remembered")

        store.undo()
        XCTAssertNil(store.task(outcome!.taskId))
        XCTAssertEqual(store.preferences.lastProjectId, other, "undo doesn't touch preferences")

        let miss = store.quickAddTask("Thing @nope", projectId: other, now: t0)
        XCTAssertEqual(miss?.unmatchedMilestone, "@nope")
        XCTAssertNil(store.task(miss!.taskId)?.milestoneId)

        let onlyTokens = store.quickAddTask("!high", projectId: other, now: t0)
        XCTAssertEqual(store.task(onlyTokens!.taskId)?.title, "!high", "a title of only tokens is kept as typed")
    }

    func testQuickAddFromViewModelShowsOpenToastOrOpens() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        XCTAssertTrue(model.quickAdd("A", projectId: pid, milestoneId: nil, slot: .backlog, open: false, store: store))
        let id = model.selectedTaskId!
        XCTAssertEqual(store.task(id)?.sprintSlot, .backlog)
        XCTAssertEqual(model.toast?.openTaskId, id)
        XCTAssertEqual(model.toast?.message, "Added to Alpha")
        model.openFromToast()
        XCTAssertEqual(model.openTaskId, id)

        model.closePanel()
        XCTAssertTrue(model.quickAdd("B", projectId: pid, milestoneId: nil, slot: .active, open: true, store: store))
        XCTAssertEqual(model.openTaskId, model.selectedTaskId, "⇧↵ opens the new task")
        XCTAssertFalse(model.quickAdd("   ", projectId: pid, milestoneId: nil, slot: .active, open: false, store: store))
    }

    // MARK: - #16 Bulk selection and edits

    func testClickSelection() async {
        let (store, pid) = await makeStore()
        let ids = (0..<5).map { store.addTask(title: "T\($0)", projectId: pid, now: t0)! }
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list

        model.select(ids[1], modifiers: [], store: store)
        XCTAssertEqual(model.selectedTaskIds, [ids[1]])
        model.select(ids[3], modifiers: .shift, store: store)
        XCTAssertEqual(model.selectedTaskIds, Set(ids[1...3]), "⇧-click selects the range")
        XCTAssertTrue(model.isMultiSelecting)
        model.select(ids[2], modifiers: .command, store: store)
        XCTAssertEqual(model.selectedTaskIds, [ids[1], ids[3]], "⌘-click removes")
        model.select(ids[0], modifiers: .command, store: store)
        XCTAssertEqual(model.selectedIds(store), [ids[0], ids[1], ids[3]], "in on-screen order")
        model.select(ids[4], modifiers: [], store: store)
        XCTAssertEqual(model.selectedTaskIds, [ids[4]], "a plain click selects one")

        model.selectAll(store)
        XCTAssertEqual(model.selectedTaskIds.count, 5)
        model.clearSelection()
        XCTAssertTrue(model.selectedTaskIds.isEmpty)

        model.selectedTaskId = ids[2]
        XCTAssertTrue(model.extendSelection(1, store: store))
        XCTAssertTrue(model.extendSelection(1, store: store))
        XCTAssertEqual(model.selectedTaskIds, Set(ids[2...4]))
        XCTAssertTrue(model.extendSelection(-1, store: store))
        XCTAssertEqual(model.selectedTaskIds, Set(ids[2...3]), "⇧↑ shrinks back toward the anchor")

        // Shortcut mapping
        XCTAssertEqual(TasksShortcut.match(keyCode: 0, characters: "a", modifiers: .command), .selectAll)
        XCTAssertEqual(TasksShortcut.match(keyCode: 126, characters: "", modifiers: .shift), .extendUp)
        XCTAssertEqual(TasksShortcut.match(keyCode: 125, characters: "", modifiers: .shift), .extendDown)
        XCTAssertEqual(TasksShortcut.match(keyCode: 33, characters: "[", modifiers: .command), .previousTask)
        XCTAssertEqual(TasksShortcut.match(keyCode: 30, characters: "]", modifiers: .command), .nextTask)
        XCTAssertTrue(TasksShortcut.nextTask.worksWhileTyping)
        XCTAssertFalse(TasksShortcut.selectAll.worksWhileTyping)
    }

    func testBulkEditsAreOneUndoStepEach() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Other", now: t0)!
        let mid = store.addMilestone(projectId: pid, name: "M1")!
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let c = store.addTask(title: "C", projectId: other, now: t0)!
        store.startTimer(a, now: t0)
        store.clearUndoHistory()

        store.setStatus([a, b, c], .done, now: t0.addingTimeInterval(600))
        XCTAssertEqual(store.undoStack.count, 1)
        XCTAssertTrue([a, b, c].allSatisfy { store.task($0)?.status == .done })
        XCTAssertFalse(store.isRunning(a), "Done pauses timers")
        XCTAssertEqual(store.task(a)?.spentSeconds, 600)

        store.setPriority([a, b, c], .high)
        store.setDueDate([a, b], t0)
        XCTAssertEqual(store.undoStack.count, 3)

        XCTAssertEqual(store.setMilestone([a, b, c], mid), 2, "tasks of other projects are skipped")
        XCTAssertNil(store.task(c)?.milestoneId)
        XCTAssertEqual(store.commonProjectId([a, b]), pid)
        XCTAssertNil(store.commonProjectId([a, c]))

        store.setProject([a, c], other)
        XCTAssertEqual(store.task(a)?.projectId, other)
        XCTAssertNil(store.task(a)?.milestoneId)

        store.undo()
        XCTAssertEqual(store.task(a)?.projectId, pid)
        XCTAssertEqual(store.task(a)?.spentSeconds, 600, "undo keeps tracked time")

        store.setSprintSlot([a, b], .next)
        XCTAssertEqual(store.task(b)?.sprintSlot, .next)
        store.deleteTasks([a, b])
        XCTAssertNil(store.task(a))
        XCTAssertEqual(store.undoActionName, "Delete tasks")
        store.undo()
        XCTAssertNotNil(store.task(a))
        XCTAssertNotNil(store.task(b))

        let copies = store.duplicateTasks([a, b], now: t0)
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(store.undoActionName, "Duplicate task")
    }

    func testBulkFromViewModelShowsUndoToast() async {
        let (store, pid) = await makeStore()
        let ids = (0..<3).map { store.addTask(title: "T\($0)", projectId: pid, now: t0)! }
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        model.select(ids: ids)
        model.bulk({ "\(TaskStore.taskCount($0)) moved to Done" }, store: store) { store.setStatus($0, .done) }
        XCTAssertEqual(model.toast?.message, "3 tasks moved to Done")
        XCTAssertEqual(model.toast?.undoId, store.lastUndoId)

        model.deleteSelected(store)
        XCTAssertTrue(ids.allSatisfy { store.task($0) == nil })
        XCTAssertTrue(model.selectedTaskIds.isEmpty)
        XCTAssertEqual(model.toast?.message, "3 tasks deleted")
        model.undoFromToast(store)
        XCTAssertTrue(ids.allSatisfy { store.task($0) != nil })

        // ⌘⌫ with several selected deletes them all
        model.select(ids: [ids[0], ids[1]])
        XCTAssertTrue(model.perform(.delete, store: store))
        XCTAssertNil(store.task(ids[0]))
        XCTAssertNil(store.task(ids[1]))
        store.undo()
        model.select(ids: [ids[0], ids[1]])
        store.deleteTask(ids[0])
        model.pruneSelection(store)
        XCTAssertEqual(model.selectedTaskIds, [ids[1]], "deleted tasks leave the selection")
    }

    // MARK: - #29 Overdue

    func testRescheduleOverdue() async {
        let (store, pid) = await makeStore()
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))!
        let a = store.addTask(title: "Late A", projectId: pid)!
        let b = store.addTask(title: "Late B", projectId: pid)!
        let c = store.addTask(title: "On time", projectId: pid)!
        store.setDueDate([a, b], yesterday)
        store.clearUndoHistory()
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        model.filter.due = [.overdue]
        XCTAssertEqual(model.visibleTasks(store).map(\.id), [a, b])

        let tomorrow = DuePreset.tomorrow.date(now: now)
        model.rescheduleOverdue(to: tomorrow, store: store, now: now)
        XCTAssertEqual(store.task(a)?.dueDate, tomorrow)
        XCTAssertEqual(store.task(b)?.dueDate, tomorrow)
        XCTAssertNil(store.task(c)?.dueDate)
        XCTAssertEqual(store.undoStack.count, 1)
        XCTAssertEqual(model.toast?.message, "2 tasks moved to Tomorrow")
    }

    // MARK: - #21 Stepping through tasks

    func testStepOpenTask() async {
        let (store, pid) = await makeStore()
        let ids = (0..<3).map { store.addTask(title: "T\($0)", projectId: pid, now: t0)! }
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        model.openTask(ids[0])
        XCTAssertEqual(model.openTaskPosition(store)?.index, 0)
        XCTAssertFalse(model.stepOpenTask(-1, store: store), "already first")
        XCTAssertTrue(model.perform(.nextTask, store: store))
        XCTAssertEqual(model.openTaskId, ids[1])
        XCTAssertEqual(model.selectedTaskId, ids[1])
        _ = model.perform(.nextTask, store: store)
        XCTAssertFalse(model.stepOpenTask(1, store: store), "already last")
        XCTAssertTrue(model.perform(.previousTask, store: store))
        XCTAssertEqual(model.openTaskId, ids[1])
        model.closePanel()
        XCTAssertFalse(model.perform(.nextTask, store: store), "needs an open task")
    }

    // MARK: - #25 Fixing tracked time

    func testSetTimeSpentAndUndo() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Forgot", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        store.pauseTimer(id, now: t0.addingTimeInterval(5 * 3600))
        store.clearUndoHistory()

        store.setTimeSpent(id, seconds: 3600, now: t0.addingTimeInterval(6 * 3600))
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600)
        XCTAssertEqual(store.undoActionName, "Adjust time")
        store.undo()
        XCTAssertEqual(store.task(id)?.spentSeconds, 5 * 3600, "undo takes the adjustment back out")
        store.redo()
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600)

        // Quick taps coalesce into one step, and their changes add up
        var clock = t0.addingTimeInterval(7 * 3600)
        store.clock = { clock }
        store.adjustTimeSpent(id, by: 15 * 60)
        clock = clock.addingTimeInterval(0.5)
        store.adjustTimeSpent(id, by: 5 * 60)
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600 + 20 * 60)
        XCTAssertEqual(store.undoStack.count, 2)
        store.undo()
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600)

        store.adjustTimeSpent(id, by: -2 * 3600)
        XCTAssertEqual(store.task(id)?.spentSeconds, 0, "never below zero")
    }

    func testSetTimeSpentWhileRunningKeepsTheTimerGoing() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Running", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        let adjustAt = t0.addingTimeInterval(4 * 3600)
        store.setTimeSpent(id, seconds: 1800, now: adjustAt)
        XCTAssertTrue(store.isRunning(id))
        XCTAssertEqual(store.elapsed(id, now: adjustAt), 1800)
        XCTAssertEqual(store.elapsed(id, now: adjustAt.addingTimeInterval(60)), 1860)

        store.undo(now: adjustAt.addingTimeInterval(60))
        XCTAssertTrue(store.isRunning(id), "undo never stops a timer")
        XCTAssertEqual(store.elapsed(id, now: adjustAt.addingTimeInterval(60)), 4 * 3600 + 60, accuracy: 0.5)
    }

    // MARK: - #26 Forgotten timers

    func testStopAtAndLongRunPrompt() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Forgot", projectId: pid, now: t0)!
        let other = store.addTask(title: "Other", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        store.startTimer(other, now: t0.addingTimeInterval(3600))
        XCTAssertEqual(store.preferences.longRunPromptMinutes, 180)

        XCTAssertTrue(store.longRunningTasks(now: t0.addingTimeInterval(2 * 3600)).isEmpty)
        let later = t0.addingTimeInterval(3 * 3600 + 1)
        XCTAssertEqual(store.longRunningTasks(now: later).map(\.id), [id], "only the long session asks")
        XCTAssertTrue(store.isRunning(id), "asking never stops a timer")

        store.keepRunning(id, now: later)
        XCTAssertTrue(store.longRunningTasks(now: later.addingTimeInterval(3600)).map(\.id) == [other])
        XCTAssertEqual(store.longRunningTasks(now: later.addingTimeInterval(3 * 3600 + 1)).count, 2, "asks again later")

        store.setLongRunPromptMinutes(0)
        XCTAssertTrue(store.longRunningTasks(now: later.addingTimeInterval(10 * 3600)).isEmpty, "off")
        store.setLongRunPromptMinutes(180)

        // Stop at: time after the chosen moment isn't counted; clamped to the start and now
        store.stopTimer(id, at: t0.addingTimeInterval(90 * 60), now: later)
        XCTAssertFalse(store.isRunning(id))
        XCTAssertEqual(store.task(id)?.spentSeconds, 90 * 60)
        XCTAssertTrue(store.isRunning(other), "timers never stop each other")
        store.stopTimer(other, at: t0, now: later)
        XCTAssertEqual(store.task(other)?.spentSeconds, 0, "can't stop before it started")

        // Settings aren't undo steps
        store.clearUndoHistory()
        store.setShowsMenuBarClock(true)
        XCTAssertTrue(store.preferences.showsMenuBarClock)
        XCTAssertFalse(store.canUndo)
    }

    func testMenuBarClockTitle() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        XCTAssertEqual(MenuBarClockText.title(store: store, now: t0.addingTimeInterval(65)), Focus.clockString(65))
        store.startTimer(b, now: t0.addingTimeInterval(60))
        XCTAssertEqual(MenuBarClockText.title(store: store, now: t0.addingTimeInterval(120)), Focus.clockString(60) + " +1",
                       "the most recent timer, plus how many others")
    }

    // MARK: - #30 Subtasks

    func testSubtaskReorderAndConvert() async {
        let (store, pid) = await makeStore()
        let mid = store.addMilestone(projectId: pid, name: "M")!
        let id = store.addTask(title: "Parent", projectId: pid, milestoneId: mid, sprintSlot: .next, now: t0)!
        let next = store.addTask(title: "Next", projectId: pid, now: t0)!
        store.setPriority(id, .high)
        let s1 = store.addSubtask(id, title: "One")!
        let s2 = store.addSubtask(id, title: "Two")!
        let s3 = store.addSubtask(id, title: "Three")!
        store.toggleSubtask(id, s3)
        store.clearUndoHistory()

        store.moveSubtask(id, s3, before: s1)
        XCTAssertEqual(store.task(id)?.subtasks.map(\.id), [s3, s1, s2])
        store.moveSubtask(id, s3, before: nil)
        XCTAssertEqual(store.task(id)?.subtasks.map(\.id), [s1, s2, s3])

        let newId = store.convertSubtaskToTask(id, s3, now: t0)!
        let converted = store.task(newId)!
        XCTAssertEqual(converted.title, "Three")
        XCTAssertEqual(converted.status, .done, "a checked subtask becomes a done task")
        XCTAssertEqual(converted.milestoneId, mid)
        XCTAssertEqual(converted.sprintSlot, .next)
        XCTAssertEqual(converted.priority, .high)
        XCTAssertEqual(store.task(id)?.subtasks.map(\.id), [s1, s2])
        let order = store.tasks(of: pid).map(\.id)
        XCTAssertEqual(order, [id, newId, next], "placed just below the parent")
        XCTAssertEqual(store.undoActionName, "Convert to task")
        store.undo()
        XCTAssertNil(store.task(newId))
        XCTAssertEqual(store.task(id)?.subtasks.count, 3)

        let model = TasksViewModel()
        model.convertSubtask(s1, of: id, store: store)
        XCTAssertNotNil(model.toast?.openTaskId)
        XCTAssertNotNil(model.toast?.undoId)
    }

    // MARK: - #17 Duplicate

    func testDuplicateResetsSubtasksAndTime() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Orig", projectId: pid, now: t0)!
        let s = store.addSubtask(id, title: "Sub")!
        store.toggleSubtask(id, s)
        store.setTimeSpent(id, seconds: 600, now: t0)
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        model.selectedTaskId = id
        XCTAssertTrue(model.perform(.duplicate, store: store))
        let copy = store.task(model.selectedTaskId!)!
        XCTAssertNotEqual(copy.id, id)
        XCTAssertEqual(copy.spentSeconds, 0)
        XCTAssertEqual(copy.subtasks.map(\.isDone), [false])
    }

    // MARK: - Schema 3

    func testVersion2FileLoadsWithDefaultPreferences() throws {
        let pid = UUID()
        let json = """
        {"schemaVersion": 2,
         "projects": [{"id": "\(pid)", "name": "P", "colorHex": 1,
                       "sprint": {"number": 1, "startDate": "2026-10-12T00:00:00Z", "lengthWeeks": 2}}],
         "milestones": [], "tasks": [], "runningTimers": {}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertGreaterThanOrEqual(Workspace.currentSchemaVersion, 3)
        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(ws.preferences, WorkspacePreferences())
        XCTAssertFalse(ws.preferences.showsMenuBarClock)
        XCTAssertEqual(ws.preferences.longRunPromptMinutes, 180)

        // Bad or dangling values fall back
        let bad = """
        {"schemaVersion": 3, "projects": [], "preferences": {"lastProjectId": "\(UUID())", "showsMenuBarClock": "yes",
         "longRunPromptMinutes": -5}}
        """
        let badWs = try decoder.decode(Workspace.self, from: Data(bad.utf8)).migrated()
        XCTAssertNil(badWs.preferences.lastProjectId, "a project that's gone is forgotten")
        XCTAssertFalse(badWs.preferences.showsMenuBarClock)
        XCTAssertEqual(badWs.preferences.longRunPromptMinutes, 0)

        // Round trip
        var round = Workspace()
        round.preferences = WorkspacePreferences(lastProjectId: pid, showsMenuBarClock: true, longRunPromptMinutes: 60)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: encoder.encode(round))
        XCTAssertEqual(decoded.preferences, round.preferences)
    }
}
