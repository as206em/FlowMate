import XCTest
@testable import FlowMate

/// Audit round 3: ⌘N closes a side panel so the New task field isn't under the scrim, read-only
/// selectable text keeps ⌘A and the arrows, and the milestone row defaults to the last project used.
@MainActor
final class TaskAuditRound3Tests: XCTestCase {
    private func makeStore() async -> (TaskStore, UUID, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let a = store.addProject(name: "Alpha")!
        let b = store.addProject(name: "Beta")!
        store.clearUndoHistory()
        return (store, a, b)
    }

    func testNewTaskShortcutClosesAnOpenPanel() async {
        let (store, a, _) = await makeStore()
        let task = store.addTask(title: "One", projectId: a)!
        let model = TasksViewModel()
        model.openTask(task)
        XCTAssertTrue(model.isPanelOpen)
        XCTAssertTrue(model.perform(.newTask, store: store))
        XCTAssertFalse(model.isPanelOpen)
        XCTAssertEqual(model.focusRequest?.field, .newTask)

        model.openProject(a)
        XCTAssertTrue(model.perform(.newTask, store: store))
        XCTAssertNil(model.openDetail)
    }

    func testSelectableTextKeepsSelectionKeys() {
        XCTAssertTrue(TasksShortcut.selectAll.belongsToSelectableText)
        XCTAssertTrue(TasksShortcut.selectNext.belongsToSelectableText)
        XCTAssertTrue(TasksShortcut.extendUp.belongsToSelectableText)
        // Other shortcuts still act on tasks from read-only text
        XCTAssertFalse(TasksShortcut.delete.belongsToSelectableText)
        XCTAssertFalse(TasksShortcut.newTask.belongsToSelectableText)
        XCTAssertFalse(TasksShortcut.undo.belongsToSelectableText)
    }

    func testDefaultProjectFollowsTheLastProjectUsed() async {
        let (store, a, b) = await makeStore()
        XCTAssertEqual(store.defaultProject?.id, a)
        store.rememberProject(b)
        XCTAssertEqual(store.defaultProject?.id, b)
        store.archiveProject(b)
        XCTAssertEqual(store.defaultProject?.id, a, "an archived project is never the default target")
    }
}
