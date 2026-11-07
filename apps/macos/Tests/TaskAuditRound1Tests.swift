import XCTest
@testable import FlowMate

/// Audit round 1: one naming for past sprints (#38).
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

    func testPastSprintsGroupUsesOneName() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Closed", projectId: pid, sprintSlot: .active, now: t0)!
        store.setStatus(id, .done)
        store.completeSprint(now: t0)
        var filter = TaskFilter()
        filter.sprintSlots = [.closed]
        let groups = store.groups(store.filtered(store.tasks(in: .project(pid)), by: filter, now: t0),
                                  by: .sprint, in: .project(pid))
        XCTAssertTrue(groups.contains { $0.title == "Past sprints" })
        XCTAssertFalse(groups.contains { $0.title.contains("Closed") })
    }
}
