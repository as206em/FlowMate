import XCTest
@testable import FlowMate

/// The New task composer: recognised words leave the title, trigger words open menus, and the
/// task is added with every property in one undo step.
@MainActor
final class TaskComposerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    func testFinishedWordsAreRecognised() {
        XCTAssertEqual(ComposerInput.token("2h"), .minutes(120))
        XCTAssertEqual(ComposerInput.token("90m"), .minutes(90))
        XCTAssertEqual(ComposerInput.token("1h30m"), .minutes(90))
        XCTAssertEqual(ComposerInput.token("1.5h"), .minutes(90))
        XCTAssertEqual(ComposerInput.token("~45m"), .minutes(45))
        XCTAssertEqual(ComposerInput.token("#next"), .slot(.next))
        XCTAssertEqual(ComposerInput.token("#backlog"), .slot(.backlog))
        XCTAssertEqual(ComposerInput.token("!high"), .priority(.high))
        XCTAssertEqual(ComposerInput.token("!1"), .priority(.high))
        XCTAssertEqual(ComposerInput.token("@beta"), .milestone("beta"))
        XCTAssertEqual(ComposerInput.token("+atlas"), .project("atlas"))
        XCTAssertNotNil(ComposerInput.token("due:fri", now: now))
        XCTAssertNotNil(ComposerInput.token("tomorrow", now: now))
        XCTAssertNil(ComposerInput.token("2"), "a bare number stays in the title")
        XCTAssertNil(ComposerInput.token("h2"))
        XCTAssertNil(ComposerInput.token("#idea"))
        XCTAssertNil(ComposerInput.token("Friday"), "weekday names stay text without due:")
    }

    func testExtractTakesOnlyFinishedWords() {
        var result = ComposerInput.extract("Write notes 2h")
        XCTAssertEqual(result.text, "Write notes 2h", "the last word is still being typed")
        XCTAssertTrue(result.tokens.isEmpty)

        result = ComposerInput.extract("Write notes 2h ")
        XCTAssertEqual(result.text, "Write notes ")
        XCTAssertEqual(result.tokens, [.minutes(120)])

        result = ComposerInput.extract("Write #next notes !high", final: true)
        XCTAssertEqual(result.text, "Write notes")
        XCTAssertEqual(result.tokens, [.slot(.next), .priority(.high)])

        result = ComposerInput.extract("Ship @nope ", accepts: { if case .milestone = $0 { return false }; return true })
        XCTAssertEqual(result.text, "Ship @nope ", "unknown milestones stay in the title")
    }

    func testTriggerWordOpensItsMenu() async {
        XCTAssertEqual(ComposerInput.activeTrigger("Write #ne")?.trigger, .sprint)
        XCTAssertEqual(ComposerInput.activeTrigger("Write #ne")?.query, "ne")
        XCTAssertEqual(ComposerInput.activeTrigger("Write @")?.trigger, .milestone)
        XCTAssertNil(ComposerInput.activeTrigger("Write #next "), "a finished word closes it")
        XCTAssertEqual(ComposerInput.removingActiveWord("Write #ne"), "Write ")

        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Atlas", now: now)!
        _ = store.addMilestone(projectId: pid, name: "Beta launch")
        let sprint = store.composerSuggestions(.sprint, query: "ne", projectId: pid)
        XCTAssertEqual(sprint.map(\.action), [.slot(.next)])
        let milestones = store.composerSuggestions(.milestone, query: "be", projectId: pid)
        XCTAssertEqual(milestones.first?.title, "◆ Beta launch")
        XCTAssertEqual(milestones.last?.action, .newMilestone("be"), "a new name can be created")
        XCTAssertEqual(store.composerSuggestions(.priority, query: "1", projectId: pid).map(\.action), [.priority(.high)])
        XCTAssertEqual(store.composerSuggestions(.all, query: "", projectId: pid).count, 8, "status (*) and label (%) are among them")
    }

    func testAddTaskAppliesTheDraftInOneUndoStep() async {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Atlas", now: now)!
        let mid = store.addMilestone(projectId: pid, name: "Beta")!
        store.clearUndoHistory()
        var draft = ComposerDraft()
        draft.slot = .next
        draft.milestoneId = mid
        draft.priority = .high
        draft.dueDate = now
        draft.expectedMinutes = 120
        let id = store.addTask(title: "Ship docs", draft: draft, projectId: pid, now: now)!
        let task = store.task(id)!
        XCTAssertEqual(task.sprintSlot, .next)
        XCTAssertEqual(task.milestoneId, mid)
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.dueDate, now)
        XCTAssertEqual(task.expectedMinutes, 120)
        store.undo()
        XCTAssertNil(store.task(id), "one undo removes it")
    }
}

@MainActor
final class TaskComposerGroupTests: XCTestCase {
    func testTaskAddedInAColumnTakesItsStatus() async {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Atlas")!
        var draft = ComposerDraft()
        draft.status = .inProgress
        let id = store.addTask(title: "Started", draft: draft, projectId: pid)!
        XCTAssertEqual(store.task(id)?.statusId, WorkflowStatus.inProgress.id)
        XCTAssertEqual(TaskGroupSection.preset(.slot(.next)), .sprint(.next))
        XCTAssertEqual(TaskGroupSection.preset(.group(.priority(.high), reorder: true)), .priority(.high))
    }
}
