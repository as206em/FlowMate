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

    // MARK: - Old sprints in one group

    func testOldSprintsMergeIntoOneGroup() async {
        let (store, pid) = await makeStore()
        let start = store.sprint.startDate
        let done1 = store.addTask(title: "done in 1", projectId: pid, now: t0)!
        store.setStatus(done1, .done, now: t0)
        let carried = store.addTask(title: "carried", projectId: pid, now: t0)!
        store.completeSprint(unfinished: .moveToNextSprint, now: start.addingTimeInterval(14 * 86_400))
        store.setStatus(carried, .done, now: t0)
        store.completeSprint(now: start.addingTimeInterval(28 * 86_400))

        let entries = store.pastSprintTasks(in: .project(pid))
        XCTAssertEqual(entries.map(\.task.id), [carried, done1], "newest sprint first, each task once")
        XCTAssertEqual(entries.map(\.sprint.number), [2, 1], "a carried-over task sits under its latest sprint")

        let model = TasksViewModel()
        XCTAssertTrue(model.isCollapsed(TasksViewModel.pastSprintsGroupKey), "starts collapsed")
        XCTAssertTrue(SprintPlanView.pastSprintsHint(store.pastSprints()).hasPrefix("2 sprints · 2 done · "))
    }

    // MARK: - Impact column

    func testImpactColumnInEveryTable() {
        let wide = TaskColumnLayout.make(showProject: true, width: 1200)
        XCTAssertTrue(wide.contains(.impact))
        let columns = wide.columns
        XCTAssertEqual(columns.firstIndex(of: .impact), columns.firstIndex(of: .priority)! + 1, "right after Priority")
        XCTAssertEqual(TaskColumn.impact.sortKey, .impact)
        XCTAssertFalse(TaskSortKey.impact.defaultAscending, "highest impact first")
    }

    func testImpactRowValueAndSort() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        let inherited = store.addTask(title: "inherited", projectId: pid, now: t0)!
        let own = store.addTask(title: "own", projectId: pid, now: t0)!
        store.setTaskImpact([own], 9)
        let display = RowDisplay.maker(store: store, model: model)
        XCTAssertEqual(display(store.task(inherited)!).impact, RowImpact(value: ImpactScale.neutral, source: "default"))
        XCTAssertEqual(display(store.task(own)!).impact, RowImpact(value: 9, source: "task"))
        store.setProjectImpact(pid, 7)
        let after = RowDisplay.maker(store: store, model: model)
        XCTAssertEqual(after(store.task(inherited)!).impact, RowImpact(value: 7, source: "project"))

        let sorted = store.sorted([store.task(inherited)!, store.task(own)!], by: TaskSort(key: .impact))
        XCTAssertEqual(sorted.map(\.id), [own, inherited])
    }

    // MARK: - Priority in the score

    func testPriorityPoints() {
        XCTAssertEqual(ImpactRules.priorityPoints(.high), 20)
        XCTAssertEqual(ImpactRules.priorityPoints(.medium), 0)
        XCTAssertEqual(ImpactRules.priorityPoints(.low), -20)
        XCTAssertEqual(ImpactRules.score(base: 95, priority: 20, boost: 0, nudge: 0), 100, "capped at 100")
        XCTAssertEqual(ImpactRules.score(base: 5, priority: -20, boost: 0, nudge: 0), 0, "floored at 0")
    }

    func testPriorityMovesTheScore() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "A", projectId: pid, now: t0)!
        store.setExpectedMinutes(id, 30)
        let medium = store.nextBestScore(store.task(id)!, now: t0)
        XCTAssertEqual(medium.score, 50, "impact 5 × 10, small task, medium priority adds nothing")
        XCTAssertFalse(medium.reason.contains("priority"))

        store.setPriority(id, .high)
        let high = store.nextBestScore(store.task(id)!, now: t0)
        XCTAssertEqual(high.score, 70)
        XCTAssertEqual(high.priorityPoints, 20)
        XCTAssertTrue(high.reason.contains("high priority +20"))

        store.setPriority(id, .low)
        XCTAssertEqual(store.nextBestScore(store.task(id)!, now: t0).score, 30)
    }

    // MARK: - Copy task ID for agents

    func testCopyTaskIdPutsTheIdOnThePasteboard() {
        let id = UUID()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FinetuneTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        TaskIdentifierCopy.copy(id, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), id.uuidString)
    }

    func testGetTaskByCopiedIdReturnsDetailsAndSubtasks() async throws {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Finetune", projectId: pid, now: t0)!
        store.setNotes(id, "Make it nicer")
        store.addSubtask(id, title: "Hide seconds")
        store.addSubtask(id, title: "Impact column")
        let tools = MCPTaskTools(store: store)
        let copied = TaskIdentifierCopy.text(for: id)

        for pasted in [copied, " \(copied)\n", "`\(copied)`", String(copied.prefix(8)).lowercased()] {
            let json = try tools.call("get_task", ["id": pasted])
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            XCTAssertEqual(object["id"] as? String, id.uuidString, pasted)
            XCTAssertEqual(object["title"] as? String, "Finetune")
            XCTAssertEqual(object["notes"] as? String, "Make it nicer")
            XCTAssertEqual((object["subtasks"] as? [[String: Any]])?.compactMap { $0["title"] as? String }, ["Hide seconds", "Impact column"])
            XCTAssertEqual(object["impact"] as? Int, ImpactScale.neutral)
            XCTAssertNotNil(object["score"])
        }
    }
}
