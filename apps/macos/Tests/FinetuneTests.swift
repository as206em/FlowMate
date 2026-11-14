import AppKit
import XCTest
@testable import FlowMate

/// Fine-tuning: hours-and-minutes clocks, the collapsed old sprints, the Impact column, priority in
/// the score and copying a task's id for agents.
@MainActor
final class FinetuneTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    // MARK: - Clocks show hours and minutes only

    func testClockDropsSeconds() {
        XCTAssertEqual(Focus.clockString(0), "0:00")
        XCTAssertEqual(Focus.clockString(59), "0:00", "seconds are dropped, not rounded up")
        XCTAssertEqual(Focus.clockString(65), "0:01")
        XCTAssertEqual(Focus.clockString(5888), "1:38")
        XCTAssertEqual(Focus.clockString(36_000), "10:00")
        XCTAssertEqual(Focus.clockString(-5), "0:00")
    }

    func testMenuBarClockHasNoSeconds() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        XCTAssertEqual(MenuBarClockText.title(store: store, now: t0.addingTimeInterval(3725)), "1:02")
    }
}
