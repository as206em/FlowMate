import XCTest
@testable import FlowMate

@MainActor
final class TaskStoreTests: XCTestCase {
    private var tempDir: URL!
    /// Whole-second base time so dates survive JSON round trips exactly
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TaskStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// A loaded store with one empty project
    private func makeStore(_ repo: WorkspaceRepository = InMemoryWorkspaceRepository(.empty)) async -> (TaskStore, UUID) {
        let store = TaskStore(repository: repo, saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        return (store, pid)
    }

    // MARK: - Repository

    func testLocalJSONRoundTrip() async throws {
        let repo = LocalJSONWorkspaceRepository(fileURL: tempDir.appendingPathComponent("workspace.json"))
        let missing = try await repo.load()
        XCTAssertNil(missing)

        var ws = Workspace.sample(now: t0)
        let pid = ws.projects[0].id
        ws.tasks[0].dueDate = t0.addingTimeInterval(86_400)
        ws.tasks[0].subtasks = [Subtask(title: "One", isDone: true)]
        ws.tasks[0].spentSeconds = 123.5
        ws.runningTimers[ws.tasks[1].id] = t0.addingTimeInterval(0.25)
        ws.milestones.append(Milestone(projectId: pid, name: "Undated"))
        try await repo.save(ws)

        let loaded = try await repo.load()
        XCTAssertEqual(loaded, ws)

        let json = try String(contentsOf: tempDir.appendingPathComponent("workspace.json"))
        XCTAssertTrue(json.contains("\"schemaVersion\" : \(Workspace.currentSchemaVersion)"))
        XCTAssertTrue(json.contains(ws.tasks[1].id.uuidString), "running timers keyed by task id string")
    }

    func testCorruptFileFallsBackToBackup() async throws {
        let url = tempDir.appendingPathComponent("workspace.json")
        let repo = LocalJSONWorkspaceRepository(fileURL: url)
        let ws = Workspace.sample(now: t0)
        try await repo.save(ws)
        _ = try await repo.load() // creates the .bak of the last good file

        try Data("{ not json".utf8).write(to: url)
        let recovered = try await repo.load()
        XCTAssertEqual(recovered, ws)
    }

    func testTolerantDecodingSkipsBadRecords() throws {
        let pid = UUID()
        let json = """
        {"projects":[{"id":"\(pid.uuidString)","name":"P"}],
         "tasks":[{"id":"\(UUID().uuidString)","projectId":"\(pid.uuidString)","title":"Ok","status":"weird"},
                  {"title":"missing ids"}],
         "futureField": 1}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(ws.projects.count, 1)
        XCTAssertEqual(ws.tasks.count, 1)
        XCTAssertEqual(ws.tasks[0].status, .todo)
        XCTAssertEqual(ws.tasks[0].expectedMinutes, 60)
    }

    func testFirstLaunchSeedsSampleAndSaves() async throws {
        let repo = InMemoryWorkspaceRepository(nil)
        let store = TaskStore(repository: repo)
        await store.load()
        XCTAssertEqual(store.projects.map(\.name), ["FlowMate"])
        XCTAssertFalse(store.workspace.tasks.isEmpty)
        let saved = await repo.stored
        XCTAssertEqual(saved, store.workspace)
    }

    // MARK: - Timers

    func testMultipleTimersRunConcurrently() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!

        store.startTimer(a, now: t0)
        store.startTimer(b, now: t0.addingTimeInterval(10))
        XCTAssertTrue(store.isRunning(a))
        XCTAssertTrue(store.isRunning(b))
        XCTAssertEqual(store.runningTasks.map(\.id), [a, b])
        XCTAssertEqual(store.task(a)?.status, .inProgress, "starting a To do task moves it to In progress")
        XCTAssertEqual(store.elapsed(a, now: t0.addingTimeInterval(60)), 60, accuracy: 0.001)
        XCTAssertEqual(store.elapsed(b, now: t0.addingTimeInterval(60)), 50, accuracy: 0.001)
        XCTAssertTrue(store.isProjectRunning(pid))
        XCTAssertTrue(store.ticker.isActive)

        store.pauseAllTimers(now: t0.addingTimeInterval(100))
        XCTAssertTrue(store.runningTasks.isEmpty)
        XCTAssertFalse(store.ticker.isActive)
        XCTAssertEqual(store.task(a)!.spentSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(store.task(b)!.spentSeconds, 90, accuracy: 0.001)
    }

    func testPauseAccumulatesSpentTime() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.setExpectedMinutes(a, 1)

        store.toggleTimer(a, now: t0)
        store.toggleTimer(a, now: t0.addingTimeInterval(30))
        store.toggleTimer(a, now: t0.addingTimeInterval(100))
        store.toggleTimer(a, now: t0.addingTimeInterval(145))
        XCTAssertFalse(store.isRunning(a))
        XCTAssertEqual(store.task(a)!.spentSeconds, 75, accuracy: 0.001)
        XCTAssertEqual(store.elapsed(a, now: t0.addingTimeInterval(999)), 75, accuracy: 0.001)
        XCTAssertTrue(store.isOverExpected(store.task(a)!))
    }

    func testMarkingDonePausesTimer() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        store.setStatus(a, .done, now: t0.addingTimeInterval(20))
        XCTAssertFalse(store.isRunning(a))
        XCTAssertEqual(store.task(a)!.spentSeconds, 20, accuracy: 0.001)
    }

    func testRunningTimersPersistAcrossRestart() async throws {
        let repo = LocalJSONWorkspaceRepository(fileURL: tempDir.appendingPathComponent("workspace.json"))
        let (store, pid) = await makeStore(repo)
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        await store.flush()

        let reopened = TaskStore(repository: repo)
        await reopened.load()
        XCTAssertTrue(reopened.isRunning(a))
        XCTAssertEqual(reopened.startedAt(a), t0)
        XCTAssertEqual(reopened.elapsed(a, now: t0.addingTimeInterval(3600)), 3600, accuracy: 0.001)
    }

    func testDebouncedSaveWritesToRepository() async throws {
        let repo = InMemoryWorkspaceRepository(.empty)
        let (store, pid) = await makeStore(repo)
        store.addTask(title: "Saved later", projectId: pid)
        try await Task.sleep(nanoseconds: 300_000_000)
        let saved = await repo.stored
        XCTAssertEqual(saved?.tasks.map(\.title), ["Saved later"])
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    // MARK: - Sprints

    func testCompleteSprint() async {
        let (store, pid) = await makeStore()
        let start = store.project(pid)!.sprint.startDate
        store.setSprintGoal(projectId: pid, goal: "Ship it")
        let doneActive = store.addTask(title: "done", projectId: pid, sprintSlot: .active)!
        store.setStatus(doneActive, .done)
        let openActive = store.addTask(title: "open", projectId: pid, sprintSlot: .active)!
        store.setStatus(openActive, .inProgress)
        let next = store.addTask(title: "next", projectId: pid, sprintSlot: .next)!
        let backlog = store.addTask(title: "backlog", projectId: pid, sprintSlot: .backlog)!
        let doneBacklog = store.addTask(title: "done backlog", projectId: pid, sprintSlot: .backlog)!
        store.setStatus(doneBacklog, .done)

        let other = store.addProject(name: "Other")!
        let otherNext = store.addTask(title: "other next", projectId: other, sprintSlot: .next)!

        store.completeSprint(projectId: pid)

        XCTAssertEqual(store.task(doneActive)?.sprintSlot, .closed)
        XCTAssertEqual(store.task(openActive)?.sprintSlot, .active)
        XCTAssertEqual(store.task(openActive)?.status, .inProgress)
        XCTAssertEqual(store.task(next)?.sprintSlot, .active)
        XCTAssertEqual(store.task(backlog)?.sprintSlot, .backlog)
        XCTAssertEqual(store.task(doneBacklog)?.sprintSlot, .backlog)
        XCTAssertEqual(store.task(otherNext)?.sprintSlot, .next, "other projects are untouched")

        let sprint = store.project(pid)!.sprint
        XCTAssertEqual(sprint.number, 2)
        // The next sprint starts on the day the sprint is completed, so dates never drift
        XCTAssertEqual(sprint.startDate, Calendar.current.startOfDay(for: Date()))
        XCTAssertEqual(store.project(pid)!.pastSprints.first?.startDate, start)
        XCTAssertEqual(sprint.displayGoal, SprintState.goalPlaceholder)
        XCTAssertEqual(store.sprintName(pid), "Sprint 2")
        XCTAssertEqual(store.boardTasks(in: .project(pid), status: .done).count, 0)

        // Reopening a closed task, or starting its timer, brings it back to the backlog
        store.setStatus(doneActive, .todo)
        XCTAssertEqual(store.task(doneActive)?.sprintSlot, .backlog)
        store.moveTask(doneActive, toSlot: .active)
        store.setStatus(doneActive, .done)
        store.completeSprint(projectId: pid)
        XCTAssertEqual(store.task(doneActive)?.sprintSlot, .closed)
        store.startTimer(doneActive)
        XCTAssertEqual(store.task(doneActive)?.sprintSlot, .backlog)
        XCTAssertEqual(store.task(doneActive)?.status, .inProgress)
    }

    func testSprintDisplay() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 26
        let sprint = SprintState(number: 14, startDate: Calendar.current.date(from: comps)!)
        XCTAssertEqual(sprint.name, "Sprint 14")
        XCTAssertEqual(sprint.dateRange, "Oct 26 – Nov 8")
        XCTAssertEqual(sprint.nextDateRange, "Nov 9 – Nov 22")
    }

    // MARK: - Cascades

    func testDeleteProjectCascades() async {
        let (store, pid) = await makeStore()
        let keep = store.addProject(name: "Keep")!
        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m)!
        let k = store.addTask(title: "K", projectId: keep)!
        store.startTimer(a)
        store.startTimer(k)

        store.deleteProject(pid)
        XCTAssertNil(store.project(pid))
        XCTAssertNil(store.task(a))
        XCTAssertNil(store.milestone(m))
        XCTAssertFalse(store.isRunning(a))
        XCTAssertTrue(store.isRunning(k))
        XCTAssertEqual(store.workspace.tasks.map(\.id), [k])
    }

    func testDeleteMilestoneClearsTasks() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "M", dueDate: t0)!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m)!
        store.setStatus(a, .done)
        store.addTask(title: "B", projectId: pid, milestoneId: m)
        XCTAssertEqual(store.milestoneProgress(m), MilestoneProgress(done: 1, total: 2))

        store.deleteMilestone(m)
        XCTAssertNil(store.milestone(m))
        XCTAssertNotNil(store.task(a))
        XCTAssertTrue(store.workspace.tasks.allSatisfy { $0.milestoneId == nil })
    }

    // MARK: - Tasks

    func testQuickAddDefaultsAndValidation() async {
        let (store, pid) = await makeStore()
        XCTAssertNil(store.addTask(title: "   ", projectId: pid))
        XCTAssertNil(store.addTask(title: "x", projectId: UUID()))
        let a = store.addTask(title: " Write docs ", projectId: pid)!
        let task = store.task(a)!
        XCTAssertEqual(task.title, "Write docs")
        XCTAssertEqual(task.sprintSlot, .active)
        XCTAssertEqual(task.status, .todo)
        XCTAssertEqual(task.priority, .medium)
        XCTAssertEqual(task.expectedMinutes, 60)
        XCTAssertEqual(store.openCount(pid), 1)
    }

    func testMoveAndReorder() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid)!
        let b = store.addTask(title: "B", projectId: pid)!
        let c = store.addTask(title: "C", projectId: pid)!
        store.moveTask(c, toStatus: .inProgress, before: b)
        XCTAssertEqual(store.tasks(in: .project(pid)).map(\.id), [a, c, b])
        XCTAssertEqual(store.task(c)?.status, .inProgress)
        store.moveTask(a, toSlot: .backlog)
        XCTAssertEqual(store.sprintTasks(projectId: pid, slot: .backlog).map(\.id), [a])
        XCTAssertEqual(store.tasks(in: .project(pid)).last?.id, a)
    }

    func testSubtasksAndChecklist() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid)!
        let s = store.addSubtask(a, title: "Step")!
        store.toggleSubtask(a, s)
        XCTAssertEqual(store.task(a)?.subtaskSummary, "1/1")
        store.renameSubtask(a, s, to: "Step 1")
        XCTAssertEqual(store.task(a)?.subtasks.first?.title, "Step 1")
        store.removeSubtask(a, s)
        XCTAssertNil(store.task(a)?.subtaskSummary)

        store.setNotes(a, "# Title\n- [ ] one\n- [x] two")
        store.toggleNotesChecklist(a, line: 1)
        store.toggleNotesChecklist(a, line: 2)
        XCTAssertEqual(store.task(a)?.notes, "# Title\n- [x] one\n- [ ] two")
    }

    func testProjectColorsAndMilestoneTaskRules() async {
        let (store, pid) = await makeStore()
        XCTAssertEqual(store.project(pid)?.colorHex, Focus.projectPalette[0])
        let other = store.addProject(name: "Other")!
        XCTAssertEqual(store.project(other)?.colorHex, Focus.projectPalette[1])

        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "A", projectId: other)!
        store.setMilestone(a, m)
        XCTAssertNil(store.task(a)?.milestoneId, "milestone from another project is rejected")

        let b = store.addTask(title: "B", projectId: pid, milestoneId: m)!
        store.setProject(b, other)
        XCTAssertEqual(store.task(b)?.projectId, other)
        XCTAssertNil(store.task(b)?.milestoneId)
    }

    func testDueHelpers() async {
        let (store, pid) = await makeStore()
        let now = Date()
        let a = store.addTask(title: "A", projectId: pid)!
        store.setDueDate(a, Calendar.current.date(byAdding: .day, value: -2, to: now))
        XCTAssertTrue(store.isOverdue(store.task(a)!, now: now))
        store.setDueDate(a, now)
        XCTAssertTrue(store.isDueToday(store.task(a)!, now: now))
        XCTAssertFalse(store.isOverdue(store.task(a)!, now: now))
        XCTAssertEqual(TaskDates.dueLabel(now, now: now), "Today")
        store.setStatus(a, .done)
        XCTAssertFalse(store.isDueToday(store.task(a)!, now: now))
    }

    // MARK: - Menu bar project play button

    func testProjectPlayStartsRecentInProgressThenTopTodo() async {
        let (store, pid) = await makeStore()
        XCTAssertNil(store.nextTaskToStart(projectId: pid))

        let backlog = store.addTask(title: "Later", projectId: pid, sprintSlot: .backlog, now: t0)!
        let first = store.addTask(title: "First", projectId: pid, now: t0)!
        _ = store.addTask(title: "Second", projectId: pid, now: t0)!
        XCTAssertEqual(store.nextTaskToStart(projectId: pid)?.id, first, "top To do in the active sprint")
        XCTAssertNotEqual(store.nextTaskToStart(projectId: pid)?.id, backlog)

        let working = store.addTask(title: "Working", projectId: pid, now: t0)!
        store.setStatus(working, .inProgress, now: t0.addingTimeInterval(60))
        XCTAssertEqual(store.startProject(pid, now: t0.addingTimeInterval(120)), working)
        XCTAssertTrue(store.isRunning(working))
        XCTAssertTrue(store.activeSprintTasks(projectId: pid).contains { $0.id == working })
        XCTAssertFalse(store.activeSprintTasks(projectId: pid).contains { $0.id == backlog })
    }
}
