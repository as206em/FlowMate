import XCTest
@testable import FlowMate

/// Audit round 1: the Board caption (#20) and one naming for past sprints (#38).
@MainActor
final class TaskAuditRound1Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    func testBoardCaptionCountsNextAndBacklog() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.select(.project(pid))
        let sprint = store.sprintName(pid)

        _ = store.addTask(title: "Now", projectId: pid, sprintSlot: .active, now: t0)
        XCTAssertEqual(model.boardCaption(store), "Showing \(sprint)")

        _ = store.addTask(title: "Soon", projectId: pid, sprintSlot: .next, now: t0)
        let later = store.addTask(title: "Later", projectId: pid, sprintSlot: .backlog, now: t0)!
        XCTAssertEqual(model.boardCaption(store), "Showing \(sprint) · 2 more in Next and Backlog")
        XCTAssertEqual(model.boardWaitingCount(store), 2)

        // Done tasks don't wait; chips narrow the count like the board
        store.setStatus(later, .done)
        XCTAssertEqual(model.boardWaitingCount(store), 1)
        model.filter.query = "nothing like it"
        XCTAssertEqual(model.boardWaitingCount(store), 0)
        model.filter = TaskFilter()

        model.select(.all)
        XCTAssertEqual(model.boardCaption(store), "Showing each project's active sprint · 1 more in Next and Backlog")
    }

    func testBoardCaptionHidesWhileEmptyStateExplains() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.select(.project(pid))
        _ = store.addTask(title: "Later", projectId: pid, sprintSlot: .backlog, now: t0)
        XCTAssertEqual(model.boardEmptyReason(store), .sprintEmpty(waiting: 1))
        XCTAssertNil(model.boardCaption(store), "the empty state already says it")
    }

    func testPastSprintsGroupUsesOneName() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Closed", projectId: pid, sprintSlot: .active, now: t0)!
        store.setStatus(id, .done)
        store.completeSprint(projectId: pid, now: t0)
        var filter = TaskFilter()
        filter.sprintSlots = [.closed]
        let groups = store.groups(store.filtered(store.tasks(in: .project(pid)), by: filter, now: t0),
                                  by: .sprint, in: .project(pid))
        XCTAssertTrue(groups.contains { $0.title == "Past sprints" })
        XCTAssertFalse(groups.contains { $0.title.contains("Closed") })
    }
}
