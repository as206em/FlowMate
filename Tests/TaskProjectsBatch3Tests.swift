import XCTest
@testable import FlowMate

/// Projects, milestones and sprints: project and milestone panels' store logic, sprint history,
/// sprint dates and length, the Complete sprint choices, archive, project order and milestone completion.
@MainActor
final class TaskProjectsBatch3Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    private func day(_ offset: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: date))!
    }

    // MARK: - Schema (v1 files still load)

    func testVersion1FileLoadsAndMigrates() throws {
        let pid = UUID(), mid = UUID(), tid = UUID()
        let json = """
        {"schemaVersion": 1,
         "projects": [{"id": "\(pid)", "name": "Old", "colorHex": 4366581,
                       "sprint": {"number": 3, "startDate": "2026-10-12T00:00:00Z", "goal": "Ship"},
                       "createdAt": "2026-01-01T00:00:00Z"}],
         "milestones": [{"id": "\(mid)", "projectId": "\(pid)", "name": "Beta"}],
         "tasks": [{"id": "\(tid)", "projectId": "\(pid)", "milestoneId": "\(mid)", "sprintSlot": "closed",
                    "status": "done", "title": "T"}],
         "runningTimers": {}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated()

        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(Workspace.currentSchemaVersion, 3)
        let project = try XCTUnwrap(ws.projects.first)
        XCTAssertEqual(ws.sprint.lengthWeeks, 2, "the project's sprint became the workspace's")
        XCTAssertEqual(ws.sprint.number, 3)
        XCTAssertNil(project.legacySprint)
        XCTAssertEqual(project.notes, "")
        XCTAssertNil(project.targetDate)
        XCTAssertFalse(project.isArchived)
        XCTAssertTrue(ws.pastSprints.isEmpty)
        let milestone = try XCTUnwrap(ws.milestones.first)
        XCTAssertEqual(milestone.notes, "")
        XCTAssertFalse(milestone.isCompleted)
        XCTAssertNil(ws.tasks.first?.closedSprintNumber)

        // Bad values fall back instead of failing the file
        let bad = """
        {"id": "\(pid)", "name": "P", "sprint": {"number": 1, "startDate": "2026-10-12T00:00:00Z", "lengthWeeks": 9},
         "archivedAt": "nonsense", "pastSprints": [{"number": 2}, 5]}
        """
        let p = try decoder.decode(Project.self, from: Data(bad.utf8))
        XCTAssertEqual(p.legacySprint?.lengthWeeks, 4, "clamped to 1–4 weeks")
        XCTAssertNil(p.archivedAt)
        XCTAssertEqual(p.legacyPastSprints.map(\.number), [2], "broken history entries are dropped")
    }

    func testNewFieldsRoundTrip() async throws {
        var ws = Workspace.sample(now: t0)
        ws.projects[0].notes = "## Goal"
        ws.projects[0].targetDate = t0
        ws.projects[0].archivedAt = t0
        ws.sprint.lengthWeeks = 3
        ws.pastSprints = [PastSprint(number: 1, startDate: t0, endDate: t0, goal: "G",
                                                 taskIds: [ws.tasks[0].id], doneTaskIds: [], completedAt: t0)]
        ws.milestones[0].notes = "notes"
        ws.milestones[0].completedAt = t0
        ws.tasks[0].closedSprintNumber = 1

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Batch3-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = LocalJSONWorkspaceRepository(fileURL: dir.appendingPathComponent("workspace.json"))
        try await repo.save(ws)
        let loaded = try await repo.load()
        XCTAssertEqual(loaded, ws)
    }

    // MARK: - Sprints (#8, #9, #10)

    func testCompleteSprintKeepsHistoryAndStartsToday() async {
        let (store, pid) = await makeStore()
        let start = store.sprint.startDate
        store.setSprintGoal("Ship v1")
        let done = store.addTask(title: "done", projectId: pid, now: t0)!
        store.setStatus(done, .done, now: t0)
        let open = store.addTask(title: "open", projectId: pid, now: t0)!
        let next = store.addTask(title: "next", projectId: pid, sprintSlot: .next, now: t0)!
        let now = day(20, from: start)

        store.completeSprint(unfinished: .moveToNextSprint, nextGoal: "  Polish  ", now: now)

        XCTAssertEqual(store.sprint.number, 2)
        XCTAssertEqual(store.sprint.startDate, Calendar.current.startOfDay(for: now), "starts the day it's completed")
        XCTAssertEqual(store.sprint.goal, "Polish")
        XCTAssertEqual(store.workspace.pastSprints.count, 1)
        let past = store.workspace.pastSprints[0]
        XCTAssertEqual(past.number, 1)
        XCTAssertEqual(past.goal, "Ship v1")
        XCTAssertEqual(past.startDate, start)
        XCTAssertEqual(past.endDate, Calendar.current.startOfDay(for: now))
        XCTAssertEqual(Set(past.taskIds), [done, open])
        XCTAssertEqual(past.doneTaskIds, [done])
        XCTAssertEqual(past.doneLabel, "1 of 2 done")
        XCTAssertTrue(past.summary.hasSuffix("· 1 of 2 done"))

        XCTAssertEqual(store.task(done)?.sprintSlot, .closed)
        XCTAssertEqual(store.task(done)?.closedSprintNumber, 1)
        XCTAssertEqual(store.sprintLabel(for: store.task(done)!), "Sprint 1", "no more \"Closed sprint\"")
        XCTAssertEqual(store.task(open)?.sprintSlot, .active)
        XCTAssertEqual(store.task(next)?.sprintSlot, .active)
        XCTAssertEqual(store.pastSprints().map(\.number), [1])
        XCTAssertEqual(Set(store.tasks(of: past).map(\.id)), [done, open])

        // A second sprint goes on top of the history (newest first)
        store.completeSprint(now: day(1, from: now))
        XCTAssertEqual(store.pastSprints().map(\.number), [2, 1])

        // One undo step takes it all back
        store.undo()
        XCTAssertEqual(store.pastSprints().map(\.number), [1])
    }

    func testCompleteSprintUnfinishedChoices() async {
        for choice in UnfinishedSprintTasks.allCases {
            let (store, pid) = await makeStore()
            let open = store.addTask(title: "open", projectId: pid, now: t0)!
            store.setStatus(open, .inProgress, now: t0)
            store.completeSprint(unfinished: choice, now: t0)
            let task = store.task(open)!
            XCTAssertEqual(task.statusId, WorkflowStatus.inProgress.id, "\(choice): status is untouched")
            switch choice {
            case .moveToNextSprint: XCTAssertEqual(task.sprintSlot, .active)
            case .moveToBacklog: XCTAssertEqual(task.sprintSlot, .backlog)
            case .keepInSprint:
                XCTAssertEqual(task.sprintSlot, .closed)
                XCTAssertEqual(task.closedSprintNumber, 1)
            }
            XCTAssertEqual(store.workspace.pastSprints.first?.taskIds, [open])
            XCTAssertEqual(store.workspace.pastSprints.first?.doneTaskIds, [])
        }
    }

    func testSprintLengthStartAndNumber() async {
        let (store, pid) = await makeStore()
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 12; comps.hour = 15
        let start = Calendar.current.date(from: comps)!

        store.setSprintStart(date: start)
        XCTAssertEqual(store.sprint.startDate, Calendar.current.startOfDay(for: start))
        XCTAssertEqual(store.sprintDateRange(), "Oct 12 – Oct 25")

        store.setSprintLength(weeks: 1)
        XCTAssertEqual(store.sprintDateRange(), "Oct 12 – Oct 18")
        XCTAssertEqual(store.sprint.nextDateRange, "Oct 19 – Oct 25")
        store.setSprintLength(weeks: 7)
        XCTAssertEqual(store.sprint.lengthWeeks, 4)
        XCTAssertEqual(store.sprintDateRange(), "Oct 12 – Nov 8")
        store.setSprintLength(weeks: 0)
        XCTAssertEqual(store.sprint.lengthWeeks, 1)

        store.setSprintNumber(0)
        XCTAssertEqual(store.sprint.number, 1)
        store.setSprintNumber(14)
        XCTAssertEqual(store.sprintName(), "Sprint 14")

        // The length carries to the next sprint
        store.setSprintLength(weeks: 3)
        store.completeSprint(now: t0)
        XCTAssertEqual(store.sprint.lengthWeeks, 3)
        XCTAssertEqual(store.sprint.lengthInDays, 21)
    }

    // MARK: - Archive (#18)

    func testArchiveHidesProjectButKeepsData() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "Alpha task", projectId: pid, milestoneId: m, now: t0)!
        let b = store.addTask(title: "Beta task", projectId: other, now: t0)!
        store.startTimer(a, now: t0)

        store.archiveProject(pid, now: t0.addingTimeInterval(60))

        XCTAssertEqual(store.projects.map(\.id), [other], "gone from the sidebar list and pickers")
        XCTAssertEqual(store.archivedProjects.map(\.id), [pid])
        XCTAssertEqual(store.allProjects.count, 2)
        XCTAssertEqual(store.tasks(in: .all).map(\.id), [b], "All projects leaves it out")
        XCTAssertTrue(store.milestones(in: .all).isEmpty)
        XCTAssertEqual(store.tasks(in: .project(pid)).map(\.id), [a], "its own view still has everything")
        XCTAssertNotNil(store.milestone(m))
        XCTAssertFalse(store.isRunning(a), "timers pause")
        XCTAssertEqual(store.task(a)?.spentSeconds ?? 0, 60, accuracy: 0.001, "time is kept")
        XCTAssertTrue(store.searchTasks("task").allSatisfy { $0.projectId == other }, "menu bar search skips it")
        XCTAssertTrue(store.menuSearchResults("Alpha", canAdd: true).projects.isEmpty)
        XCTAssertEqual(store.undoActionName, "Archive project")

        store.undo()
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertFalse(store.isRunning(a), "undo never restarts a timer")

        store.redo()
        store.unarchiveProject(pid)
        XCTAssertEqual(Set(store.projects.map(\.id)), [pid, other])
    }

    func testArchiveFromViewModelLeavesTheProject() async {
        let (store, pid) = await makeStore()
        let model = TasksViewModel()
        model.select(.project(pid))
        model.openProject(pid)
        model.archiveProject(pid, store: store)
        XCTAssertEqual(model.scope, .all)
        XCTAssertNil(model.openDetail)
        XCTAssertEqual(model.toast?.message, "Project archived")
        model.undoFromToast(store)
        XCTAssertFalse(store.project(pid)!.isArchived)
    }

    // MARK: - Project order (#24)

    func testMoveProjectReorders() async {
        let (store, a) = await makeStore()
        let b = store.addProject(name: "B")!
        let c = store.addProject(name: "C")!
        store.moveProject(c, before: a)
        XCTAssertEqual(store.projects.map(\.id), [c, a, b])
        store.moveProject(c, before: nil)
        XCTAssertEqual(store.projects.map(\.id), [a, b, c])
        store.moveProject(a, before: c)
        XCTAssertEqual(store.projects.map(\.id), [b, a, c])
        store.moveProject(a, before: a)
        XCTAssertEqual(store.projects.map(\.id), [b, a, c], "dropping on itself does nothing")
        store.undo()
        XCTAssertEqual(store.projects.map(\.id), [a, b, c])
    }

    // MARK: - Projects and milestones (#1, #23)

    func testProjectPanelEdits() async {
        let (store, pid) = await makeStore()
        var now = t0
        store.clock = { now }
        store.setProjectName(pid, "Al")
        now += 0.5
        store.setProjectName(pid, "Alpha 2")
        store.setProjectName(pid, "   ")
        XCTAssertEqual(store.project(pid)?.name, "Alpha 2")
        store.setProjectNotes(pid, "# Notes")
        store.setProjectTargetDate(pid, t0)
        XCTAssertEqual(store.project(pid)?.targetDate, Calendar.current.startOfDay(for: t0))
        store.setProjectColor(pid, colorHex: Focus.projectPalette[3])

        store.undo()
        store.undo()
        store.undo()
        XCTAssertEqual(store.project(pid)?.notes, "")
        XCTAssertNil(store.project(pid)?.targetDate)
        store.undo()
        XCTAssertEqual(store.project(pid)?.name, "Alpha", "typing the name is one undo step")
    }

    func testMilestoneCompleteNotesAndTasks() async {
        let (store, pid) = await makeStore()
        let m1 = store.addMilestone(projectId: pid, name: "Beta", dueDate: day(-3, from: Date()))!
        let m2 = store.addMilestone(projectId: pid, name: "Launch", dueDate: day(10, from: Date()))!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m1, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, milestoneId: m1, now: t0)!
        store.setStatus(b, .done)

        XCTAssertEqual(store.milestoneTasks(m1).map(\.id), [a, b])
        XCTAssertEqual(store.milestoneProgress(m1).short, "1/2")
        XCTAssertTrue(store.isOverdue(store.milestone(m1)!))

        store.completeMilestone(m1, now: t0)
        XCTAssertTrue(store.milestone(m1)!.isCompleted)
        XCTAssertFalse(store.isOverdue(store.milestone(m1)!), "a completed milestone is never overdue")
        XCTAssertEqual(store.task(a)?.statusId, WorkflowStatus.todo.id, "its tasks are left alone")
        XCTAssertEqual(store.milestones(of: pid).map(\.id), [m2, m1], "completed ones sort last")
        XCTAssertEqual(store.undoActionName, "Complete milestone")

        store.reopenMilestone(m1)
        XCTAssertFalse(store.milestone(m1)!.isCompleted)
        XCTAssertEqual(store.milestones(of: pid).map(\.id), [m1, m2])

        store.setMilestoneNotes(m1, "Scope")
        store.setMilestoneName(m1, "Beta 1")
        XCTAssertEqual(store.milestone(m1)?.notes, "Scope")
        XCTAssertEqual(store.milestone(m1)?.name, "Beta 1")
    }

    // MARK: - Panels and the List (#1, #18, #22, #23)

    func testPanelsAreExclusiveAndCloseWhenGone() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        let model = TasksViewModel()

        model.openTask(a)
        model.openProject(pid)
        XCTAssertNil(model.openTaskId)
        XCTAssertEqual(model.openDetail, .project(pid))
        XCTAssertTrue(model.isPanelOpen)
        model.selectedTaskId = a
        XCTAssertNil(model.targetTaskId(store), "⌘⌫ and Space don't reach a task behind a project panel")

        model.openMilestone(m)
        XCTAssertEqual(model.openDetail, .milestone(m))
        model.openTask(a)
        XCTAssertNil(model.openDetail)
        XCTAssertEqual(model.openTaskId, a)

        model.openMilestone(m)
        model.deleteMilestone(m, store: store)
        XCTAssertNil(model.openDetail)
        XCTAssertNil(store.milestone(m))
        model.undoFromToast(store)
        XCTAssertNotNil(store.milestone(m))

        model.openMilestone(m)
        model.closePanel()
        XCTAssertFalse(model.isPanelOpen)
    }

    func testShowMilestoneTasks() async {
        let (store, pid) = await makeStore()
        let m = store.addMilestone(projectId: pid, name: "M")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: m, now: t0)!
        store.addTask(title: "B", projectId: pid, now: t0)
        let model = TasksViewModel()
        model.openMilestone(m)

        model.showTasks(ofMilestone: store.milestone(m)!)
        XCTAssertEqual(model.scope, .milestone(m, projectId: pid), "Show tasks opens the milestone's page")
        XCTAssertEqual(model.tab, .list)
        XCTAssertTrue(model.filter.isEmpty, "the page needs no filter chip")
        XCTAssertFalse(model.isPanelOpen)
        XCTAssertEqual(model.listGroups(store).flatMap(\.tasks).map(\.id), [a])
    }

    func testListHidesPastSprintTasksUnlessFiltered() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.setStatus(a, .done)
        store.completeSprint(now: t0)
        let model = TasksViewModel()
        model.select(.project(pid))

        XCTAssertEqual(model.listGroups(store).flatMap(\.tasks).map(\.id), [b])
        XCTAssertEqual(model.hiddenClosedCount(store), 1)

        model.filter.sprintSlots = [.closed]
        XCTAssertEqual(model.listGroups(store).flatMap(\.tasks).map(\.id), [a])
        XCTAssertEqual(model.hiddenClosedCount(store), 0)
    }

    func testPastSprintGroupsStartCollapsed() {
        let model = TasksViewModel()
        let sprint = PastSprint(number: 1, startDate: t0, endDate: t0, completedAt: t0)
        let key = TasksViewModel.pastSprintGroupKey(sprint)
        XCTAssertTrue(model.isCollapsed(key))
        model.toggleGroup(key)
        XCTAssertFalse(model.isCollapsed(key))
        XCTAssertTrue(model.isCollapsed(TaskGroupValue.status(.done).key), "Done still starts collapsed")
        XCTAssertFalse(model.isCollapsed(TasksViewModel.sprintGroupKey(.active)))
    }

    func testSidebarDisclosure() {
        let model = TasksViewModel()
        let id = UUID()
        XCTAssertFalse(model.isProjectExpanded(id))
        model.toggleProjectExpanded(id)
        XCTAssertTrue(model.isProjectExpanded(id))
        model.toggleProjectExpanded(id)
        XCTAssertFalse(model.isProjectExpanded(id))
    }
}
