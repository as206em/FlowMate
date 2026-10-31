import XCTest
@testable import FlowMate

/// List quick fixes: status cycle, one status order, moving tasks between projects,
/// column sorting and layout, and Enter in the menu bar search.
@MainActor
final class TaskListBatch1Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        return (store, pid)
    }

    // MARK: - Status order and cycle (#38, #39)

    func testOneStatusAndPriorityOrder() {
        XCTAssertEqual(WorkflowPreset.simple.statuses, [.todo, .inProgress, .done])
        XCTAssertEqual(WorkflowPreset.simple.statuses.map(\.name), ["To do", "In progress", "Done"])
        XCTAssertEqual(StatusCategory.ordered, [.notStarted, .started, .done, .canceled])
        XCTAssertEqual(TaskPriority.ordered, [.high, .medium, .low])
    }

    func testStatusCircleCyclesThroughAllStatuses() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.cycleStatus(a, now: t0)
        XCTAssertEqual(store.task(a)?.statusId, WorkflowStatus.inProgress.id)
        store.startTimer(a, now: t0)
        store.cycleStatus(a, now: t0.addingTimeInterval(60))
        XCTAssertEqual(store.task(a)?.statusId, WorkflowStatus.done.id)
        XCTAssertFalse(store.isRunning(a), "Done pauses the timer")
        store.cycleStatus(a, now: t0.addingTimeInterval(120))
        XCTAssertEqual(store.task(a)?.statusId, WorkflowStatus.todo.id)
        store.cycleStatus(UUID()) // unknown id is a no-op
    }

    // MARK: - Move to project (#7)

    func testMoveToProjectKeepsTimerAndClearsMilestone() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        store.setSprintSlot(a, .next)
        store.startTimer(a, now: t0)

        store.setProject(a, other)
        let moved = store.task(a)!
        XCTAssertEqual(moved.projectId, other)
        XCTAssertNil(moved.milestoneId)
        XCTAssertEqual(moved.sprintSlot, .next)
        XCTAssertTrue(store.isRunning(a), "moving never stops a timer")
        XCTAssertEqual(store.tasks(of: other).map(\.id), [a])
        XCTAssertTrue(store.tasks(of: pid).isEmpty)

        store.setProject(a, UUID())
        XCTAssertEqual(store.task(a)?.projectId, other, "unknown project is ignored")
    }

    // MARK: - Sorting (#3)

    func testSortToggleCycle() {
        var sort = TaskSort.manual
        sort = sort.toggled(.due)
        XCTAssertEqual(sort, TaskSort(key: .due, ascending: true))
        sort = sort.toggled(.due)
        XCTAssertEqual(sort, TaskSort(key: .due, ascending: false))
        sort = sort.toggled(.due)
        XCTAssertEqual(sort, .manual)
        XCTAssertEqual(TaskSort.manual.toggled(.priority), TaskSort(key: .priority, ascending: false), "high first")
        XCTAssertEqual(TaskSort(key: .title).toggled(.priority).key, .priority)
    }

    func testSortByColumns() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "banana", projectId: pid, now: t0)!
        let b = store.addTask(title: "Apple", projectId: pid, now: t0)!
        let c = store.addTask(title: "cherry", projectId: pid, now: t0)!
        store.setPriority(a, .low)
        store.setPriority(b, .high)
        store.setDueDate(a, t0.addingTimeInterval(86_400 * 2))
        store.setDueDate(c, t0.addingTimeInterval(86_400))
        let tasks = store.tasks(of: pid)

        XCTAssertEqual(store.sorted(tasks, by: .manual).map(\.id), [a, b, c])
        XCTAssertEqual(store.sorted(tasks, by: TaskSort(key: .title)).map(\.id), [b, a, c], "case-insensitive")
        XCTAssertEqual(store.sorted(tasks, by: TaskSort(key: .priority)).map(\.id), [b, c, a])
        XCTAssertEqual(store.sorted(tasks, by: TaskSort(key: .due)).map(\.id), [c, a, b], "no date last")
        XCTAssertEqual(store.sorted(tasks, by: TaskSort(key: .due, ascending: false)).map(\.id), [a, c, b],
                       "no date stays last when descending")
        // Ties keep the manual order
        XCTAssertEqual(store.sorted(tasks, by: TaskSort(key: .milestone)).map(\.id), [a, b, c])
    }

    func testSortDecodingIsTolerant() throws {
        let data = Data(#"{"key":"bogus"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(TaskSort.self, from: data), .manual)
        let round = try JSONDecoder().decode(TaskSort.self, from: JSONEncoder().encode(TaskSort(key: .due, ascending: false)))
        XCTAssertEqual(round, TaskSort(key: .due, ascending: false))
    }

    // MARK: - Column layout (#3)

    func testColumnLayoutKeepsTitleRoom() {
        let wide = TaskColumnLayout.make(showProject: true, width: 1200)
        XCTAssertEqual(wide.columns, TaskColumn.allCases)

        let project = TaskColumnLayout.make(showProject: false, width: 1000)
        XCTAssertFalse(project.contains(.project))
        XCTAssertTrue(project.contains(.sprint))

        let sprints = TaskColumnLayout.make(showProject: false, excluding: [.sprint], width: 1000)
        XCTAssertFalse(sprints.contains(.sprint))

        for width in stride(from: 400, through: 1000, by: 20) {
            let layout = TaskColumnLayout.make(showProject: true, width: CGFloat(width))
            XCTAssertTrue(layout.contains(.title) && layout.contains(.status) && layout.contains(.timer))
            if layout.columns.count > TaskColumn.allCases.count - TaskColumnLayout.dropOrder.count {
                XCTAssertGreaterThanOrEqual(CGFloat(width) - layout.fixedWidth, TaskColumnLayout.minTitleWidth)
            }
        }
        let narrow = TaskColumnLayout.make(showProject: true, width: 760)
        XCTAssertFalse(narrow.contains(.sprint), "sprint drops first")
        XCTAssertTrue(narrow.contains(.due))
    }

    // MARK: - Menu bar search Enter (#14)

    func testMenuSearchEnterOpensResultInsteadOfAdding() async {
        let (store, pid) = await makeStore()
        let task = store.addTask(title: "Fix login", projectId: pid, now: t0)!

        let match = store.menuSearchResults("login", canAdd: true)
        XCTAssertEqual(match.items, [.add, .task(task)])
        XCTAssertEqual(match.initialHighlight, .task(task), "↵ opens the match, not Add")
        XCTAssertEqual(match.moving(.task(task), by: -1), .add, "↑ reaches the Add row")
        XCTAssertEqual(match.moving(.add, by: -1), .add, "clamped at the top")
        XCTAssertEqual(match.moving(.task(task), by: 1), .task(task), "clamped at the bottom")

        let alpha = store.menuSearchResults("alp", canAdd: true)
        XCTAssertEqual(alpha.initialHighlight, .project(pid))

        let typo = store.menuSearchResults("lgoin", canAdd: true)
        XCTAssertEqual(typo.items, [.add])
        XCTAssertNil(typo.initialHighlight, "a typo with no matches never creates a task on ↵")
        XCTAssertEqual(typo.validated(.task(task)), nil)
        XCTAssertEqual(typo.moving(nil, by: 1), .add)

        XCTAssertTrue(store.menuSearchResults("  ", canAdd: true).items.isEmpty)
    }
}
