import XCTest
@testable import FlowMate

/// Code review fixes: undoing a delete doesn't count the deleted time, closing unfinished tasks
/// with the sprint stops their timers, moving a task drops its old project's past sprint, and
/// crowded sort order is renumbered.
@MainActor
final class TaskReviewFixesTests: XCTestCase {
    private func makeStore() async -> (TaskStore, UUID, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let a = store.addProject(name: "Alpha")!
        let b = store.addProject(name: "Beta")!
        store.clearUndoHistory()
        return (store, a, b)
    }

    func testUndoDeleteDoesNotCountTimeWhileDeleted() async {
        let (store, a, _) = await makeStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let id = store.addTask(title: "Run", projectId: a)!
        store.startTimer(id, now: t0)
        store.clock = { t0.addingTimeInterval(600) }
        store.deleteTask(id)
        let later = t0.addingTimeInterval(7200)
        store.undo(now: later)
        XCTAssertEqual(store.task(id)?.spentSeconds ?? -1, 600, accuracy: 0.5)
        XCTAssertEqual(store.startedAt(id), later, "the timer runs again from the undo")
        XCTAssertEqual(store.elapsed(id, now: later), 600, accuracy: 0.5)
    }

    func testKeepInSprintStopsTimersOfClosedTasks() async {
        let (store, a, _) = await makeStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let id = store.addTask(title: "Unfinished", projectId: a)!
        store.startTimer(id, now: t0)
        store.completeSprint(unfinished: .keepInSprint, now: t0.addingTimeInterval(300))
        XCTAssertFalse(store.isRunning(id))
        XCTAssertEqual(store.task(id)?.sprintSlot, .closed)
        XCTAssertEqual(store.task(id)?.spentSeconds ?? -1, 300, accuracy: 0.5)
    }

    func testMoveToProjectLeavesOldPastSprint() async {
        let (store, a, b) = await makeStore()
        let id = store.addTask(title: "Shipped", projectId: a)!
        store.setStatus(id, .done)
        store.completeSprint()
        XCTAssertEqual(store.task(id)?.sprintSlot, .closed)
        store.setProject(id, b)
        XCTAssertEqual(store.task(id)?.sprintSlot, .backlog)
        XCTAssertNil(store.task(id)?.closedSprintNumber)
    }

    func testRepeatedDropsInOneGapKeepOrderExact() async {
        let (store, a, _) = await makeStore()
        let first = store.addTask(title: "First", projectId: a)!
        let last = store.addTask(title: "Last", projectId: a)!
        var moving: [UUID] = []
        for n in 0..<80 {
            let id = store.addTask(title: "T\(n)", projectId: a)!
            store.reorder(id, before: last)
            moving.append(id)
        }
        let order = store.workspace.tasks.sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        XCTAssertEqual(order, [first] + moving + [last])
        XCTAssertEqual(Set(store.workspace.tasks.map(\.sortIndex)).count, store.workspace.tasks.count)
    }

    func testPlainKeyShortcutsAreMarked() {
        XCTAssertTrue(TasksShortcut.toggleTimer.usesPlainKey)
        XCTAssertTrue(TasksShortcut.open.usesPlainKey)
        XCTAssertFalse(TasksShortcut.delete.usesPlainKey)
        XCTAssertFalse(TasksShortcut.undo.usesPlainKey)
    }
}

/// Feedback round: a milestone opened from its project panel goes Back to it; a calendar month
/// has whole weeks starting on the user's first weekday.
@MainActor
final class TaskFeedbackRoundTests: XCTestCase {
    func testMilestoneFromProjectPanelGoesBack() {
        let model = TasksViewModel()
        let project = UUID(), milestone = UUID()
        model.openProject(project)
        model.openMilestone(milestone, from: .project(project))
        XCTAssertEqual(model.openDetail, .milestone(milestone))
        XCTAssertEqual(model.panelBack, .project(project))
        model.goBack()
        XCTAssertEqual(model.openDetail, .project(project))
        XCTAssertNil(model.panelBack)

        model.openMilestone(milestone)
        XCTAssertNil(model.panelBack, "opened from elsewhere: no Back")
        model.openMilestone(milestone, from: .project(project))
        model.closePanel()
        XCTAssertNil(model.panelBack)
    }

    func testCalendarWeeksAreWholeAndCoverTheMonth() {
        let cal = Calendar.current
        let month = cal.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let weeks = FocusCalendar.weeks(of: month)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cal.component(.weekday, from: weeks[0][0]), cal.firstWeekday)
        let days = weeks.flatMap { $0 }.filter { cal.component(.month, from: $0) == 2 }
        XCTAssertEqual(days.count, 28)
    }
}
