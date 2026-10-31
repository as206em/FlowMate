import AppKit
import XCTest
@testable import FlowMate

/// Seams between the features built in separate phases: custom workflows, the time log, milestone
/// pages, Today, keyboard pickers and ⌘K, the portfolio, sprint capacity, projects without sprints,
/// labels and saved views. Plus the fixes of the final QA pass (label drags, sleep prompt
/// persistence, milestone colors, the past sprint header, the bulk bar, the timeline).
@MainActor
final class IntegrationSeamsTests: XCTestCase {
    private let now = Date()

    private func makeStore() async -> TaskStore {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        return store
    }

    private func day(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: now))!
    }

    /// A Dev project with one task in each interesting status, and a Simple project.
    private func devFixture() async -> (TaskStore, dev: UUID, simple: UUID, review: UUID, canceled: UUID, done: UUID, backlog: UUID) {
        let store = await makeStore()
        let dev = store.addProject(name: "Atlas")!
        let simple = store.addProject(name: "Beacon")!
        store.applyWorkflowPreset(projectId: dev, .dev)
        let p = store.project(dev)!
        let review = store.addTask(title: "In review", projectId: dev, sprintSlot: .active)!
        let canceled = store.addTask(title: "Dropped", projectId: dev, sprintSlot: .active)!
        let done = store.addTask(title: "Shipped", projectId: dev, sprintSlot: .active)!
        let backlog = store.addTask(title: "Someday", projectId: dev, sprintSlot: .active)!
        store.setStatus(review, p.status("review")!)
        store.setStatus(canceled, p.status("canceled")!)
        store.setStatus(done, p.status("done")!)
        store.setStatus(backlog, p.status("backlog")!)
        store.clearUndoHistory()
        return (store, dev, simple, review, canceled, done, backlog)
    }

    // MARK: - Custom workflows across features

    func testDevWorkflowInTodayUpNextAndOverview() async {
        let (store, dev, _, review, canceled, done, backlog) = await devFixture()
        for id in [review, canceled, done, backlog] { store.setDueDate(id, day(-1)) }
        let plan = store.todayPlan(now: now)
        // Overdue lists open tasks only: Review (started) and Backlog (not started)
        XCTAssertEqual(Set(plan.overdue.map(\.id)), [review, backlog])
        XCTAssertEqual(plan.doneToday.map(\.id), [done], "Done today counts done, not canceled")
        XCTAssertEqual(store.todayCount(now: now), 2)
        XCTAssertFalse(store.upNext(now: now).contains { $0.id == canceled || $0.id == done })
        let card = store.projectOverview(dev, now: now)!
        XCTAssertEqual(card.inProgressCount, 1, "Review is a Started status")
        XCTAssertEqual(card.overdueCount, 2)
        XCTAssertEqual(card.sprintPlanned, 3, "canceled work isn't planned")
        XCTAssertEqual(card.sprintDone, 1)
    }

    func testDevWorkflowInMilestoneProgressAndCapacity() async {
        let (store, dev, _, review, canceled, done, backlog) = await devFixture()
        let m = store.addMilestone(projectId: dev, name: "Beta", dueDate: day(-2))!
        for id in [review, canceled, done, backlog] { store.setMilestone(id, m); store.setExpectedMinutes(id, 60) }
        XCTAssertEqual(store.milestoneProgress(m), MilestoneProgress(done: 1, total: 3))
        XCTAssertTrue(store.isOverdue(store.milestone(m)!, now: now))
        XCTAssertEqual(store.milestoneForecast(m, now: now)?.remainingHours ?? 0, 2, accuracy: 0.01)
        let load = store.slotLoad(scope: .project(dev), slot: .active, now: now)
        XCTAssertEqual(load.count, 3)
        XCTAssertEqual(load.plannedMinutes, 180)
        let stats = store.completionStats(now: now)
        XCTAssertEqual(stats.planned, 180)
        XCTAssertEqual(stats.done, 60)
        XCTAssertEqual(store.notificationInput(now: now).dueTasks.count, 0, "no due dates set on tasks")
        store.setDueDate(canceled, day(1)); store.setDueDate(done, day(1)); store.setDueDate(review, day(1))
        XCTAssertEqual(store.notificationInput(now: now).dueTasks.map(\.id), [review], "closed tasks get no reminders")
    }

    func testXKeyAndStatusPickerUseTheTasksOwnWorkflow() async {
        let (store, dev, simple, review, canceled, _, _) = await devFixture()
        let other = store.addTask(title: "Plain", projectId: simple)!
        XCTAssertTrue(store.toggleDone([review, other]))
        XCTAssertEqual(store.task(review)?.statusId, store.project(dev)!.firstStatus(.done).id)
        XCTAssertEqual(store.task(other)?.statusId, "done")
        XCTAssertFalse(store.toggleDone([review, other]))
        XCTAssertEqual(store.task(review)?.statusId, store.project(dev)!.defaultStatus.id)
        // Canceled counts as not done: X completes it
        XCTAssertTrue(store.toggleDone([canceled]))
        XCTAssertEqual(store.task(canceled)?.statusCategory, .done)

        let model = TasksViewModel(defaults: UserDefaults(suiteName: "seams-\(UUID())")!, stateKey: UUID().uuidString)
        let options = model.quickPickOptions(.status, ids: [review], query: "", store: store)
        XCTAssertTrue(options.contains { $0.title == "Review" })
        XCTAssertTrue(options.contains { $0.title == "Canceled" })
        // Across projects: shared statuses by name, then categories
        let mixed = model.quickPickOptions(.status, ids: [review, other], query: "", store: store)
        XCTAssertFalse(mixed.contains { $0.title == "Review" })
    }

    func testStatusGroupsAndSavedViewStatusFilterAcrossProjects() async {
        let (store, dev, simple, review, _, _, _) = await devFixture()
        let other = store.addProject(name: "Comet")!
        store.applyWorkflowPreset(projectId: other, .dev)
        let review2 = store.addTask(title: "Also review", projectId: other)!
        store.setStatus(review2, store.project(other)!.status("review")!)
        _ = store.addTask(title: "Plain", projectId: simple)
        var options = TaskViewOptions.standard
        options.filter.statuses = ["review"]
        let id = store.addSavedView(name: "In review", scope: .all, layout: .list, options: options)!
        let view = store.savedView(id)!
        XCTAssertEqual(store.filtered(store.tasks(in: .all), by: view.options.filter).map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [review, review2].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(store.savedViewCount(view), 2)
        // A status deleted from every workflow leaves the view (which then shows open tasks)
        XCTAssertTrue(store.deleteStatus(projectId: dev, statusId: "review"))
        XCTAssertTrue(store.deleteStatus(projectId: other, statusId: "review"))
        XCTAssertEqual(store.savedView(id)?.options.filter.statuses, [])
        XCTAssertEqual(store.savedViewCount(store.savedView(id)!), store.tasks(in: .all).filter { !$0.isClosed && $0.sprintSlot != .closed }.count)
    }

    // MARK: - Projects without sprints

    func testProjectWithoutSprintsInTodayUpNextPaletteAndQuickAdd() async {
        let store = await makeStore()
        let p = store.addProject(name: "Garden")!
        store.setUsesSprints(p, false)
        let t = store.addTask(title: "Water", projectId: p, sprintSlot: .backlog)!
        XCTAssertEqual(store.task(t)?.sprintSlot, .active, "no sprints: every task is current")
        XCTAssertTrue(store.upNext(now: now).contains { $0.id == t })
        let card = store.projectOverview(p, now: now)!
        XCTAssertEqual(card.sprintPlanned, 1)
        // #next stays in the title; the box's sprint is ignored
        let plan = store.planQuickAdd("Prune #next", projectId: p, sprintSlot: .next, now: now)
        XCTAssertEqual(plan.title, "Prune #next")
        let outcome = store.quickAddTask("Prune #next", projectId: p, sprintSlot: .next, now: now)!
        XCTAssertEqual(store.task(outcome.taskId)?.sprintSlot, .active)

        let model = TasksViewModel(defaults: UserDefaults(suiteName: "seams-\(UUID())")!, stateKey: UUID().uuidString)
        model.syncProjects(store)
        model.select(.project(p))
        XCTAssertFalse(model.tabs.contains(.sprints))
        XCTAssertFalse(model.availableGroupings.contains(.sprint))
        model.select(ids: [t])
        XCTAssertFalse(model.openQuickPicker(.sprint, store: store), "R does nothing without sprints")
        let commands = model.paletteCommands(store)
        XCTAssertFalse(commands.contains(.quickAction(.sprint)))
        XCTAssertFalse(commands.contains(.completeSprint), "no project takes part in the sprint")
        // A saved view with a sprint filter still counts the project's tasks
        var options = TaskViewOptions.standard
        options.filter.sprintSlots = [.next]
        let id = store.addSavedView(name: "Next", scope: .project(p), layout: .list, options: options)!
        XCTAssertEqual(store.savedViewCount(store.savedView(id)!), 2)
    }

    // MARK: - Moving a task between projects

    func testMoveBetweenProjectsRemapsStatusKeepsLabelsAndTimeClearsMilestone() async {
        let (store, dev, simple, review, _, _, _) = await devFixture()
        let label = store.addLabel("bug")!
        store.setLabels(review, [label])
        let m = store.addMilestone(projectId: dev, name: "Beta")!
        store.setMilestone(review, m)
        store.addTimeEntry(taskId: review, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-600))
        store.addToToday([review], now: now)
        store.setProject(review, simple)
        let moved = store.task(review)!
        XCTAssertEqual(moved.projectId, simple)
        XCTAssertEqual(moved.statusCategory, .started)
        XCTAssertEqual(moved.statusId, store.project(simple)!.firstStatus(.started).id)
        XCTAssertEqual(moved.labelIds, [label])
        XCTAssertNil(moved.milestoneId)
        XCTAssertEqual(moved.spentSeconds, 3000, accuracy: 0.5)
        XCTAssertEqual(store.workspace.timeEntries.filter { $0.taskId == review }.count, 1)
        XCTAssertTrue(moved.isPinned)
        // Undo puts it all back
        store.undo()
        XCTAssertEqual(store.task(review)?.projectId, dev)
        XCTAssertEqual(store.task(review)?.statusId, "review")
        XCTAssertEqual(store.task(review)?.milestoneId, m)
    }

    func testMoveIntoAndOutOfProjectsWithoutSprintsSetsTheSlot() async {
        let store = await makeStore()
        let sprints = store.addProject(name: "Sprinty")!
        let plain = store.addProject(name: "Plain")!
        store.setUsesSprints(plain, false)
        store.setDefaultSprintSlot(sprints, .next)
        let a = store.addTask(title: "From sprints", projectId: sprints, sprintSlot: .backlog)!
        store.setProject(a, plain)
        XCTAssertEqual(store.task(a)?.sprintSlot, .active)
        let b = store.addTask(title: "Idea", projectId: plain)!
        store.setProject(b, sprints)
        XCTAssertEqual(store.task(b)?.sprintSlot, .next, "lands where the project's new tasks go")
        let c = store.addTask(title: "Doing", projectId: plain)!
        store.setCategory(c, .started)
        store.setProject(c, sprints)
        XCTAssertEqual(store.task(c)?.sprintSlot, .active, "work in flight stays current")
        let d = store.addTask(title: "Between sprints", projectId: sprints, sprintSlot: .backlog)!
        store.setProject(d, store.addProject(name: "Other")!)
        XCTAssertEqual(store.task(d)?.sprintSlot, .backlog, "both with sprints: the slot stays")
    }

    // MARK: - Deleting things views, focus and timers point at

    func testDeletingProjectMilestoneAndLabelCleansViewsTimersAndPreferences() async {
        let (store, dev, simple, review, _, _, _) = await devFixture()
        let label = store.addLabel("bug")!
        store.setLabels(review, [label])
        let m = store.addMilestone(projectId: dev, name: "Beta")!
        var options = TaskViewOptions.standard
        options.filter.labels = [label]
        let msView = store.addSavedView(name: "Beta bugs", scope: .milestone(m, projectId: dev), layout: .list, options: options)!
        let allView = store.addSavedView(name: "Bugs", scope: .all, layout: .list, options: options)!
        let projectView = store.addSavedView(name: "Atlas", scope: .project(dev), layout: .board, options: .standard)!
        store.deleteLabel(label)
        XCTAssertEqual(store.savedView(allView)?.options.filter.labels, [])
        XCTAssertEqual(store.task(review)?.labelIds, [])
        store.deleteMilestone(m)
        XCTAssertNil(store.savedView(msView))
        XCTAssertNotNil(store.savedView(projectView))

        store.startTimer(review, now: now.addingTimeInterval(-600))
        store.addTimeEntry(taskId: review, start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        store.addToToday([review], now: now)
        store.systemWillSleep(at: now.addingTimeInterval(-500))
        store.systemDidWake(at: now.addingTimeInterval(-100))
        XCTAssertEqual(store.awayGaps.count, 1)
        store.deleteProject(dev)
        XCTAssertNil(store.savedView(projectView))
        XCTAssertTrue(store.workspace.runningTimers.isEmpty)
        XCTAssertTrue(store.workspace.timeEntries.isEmpty)
        XCTAssertTrue(store.awayGaps.isEmpty, "the sleep prompt forgets deleted tasks")
        XCTAssertFalse(store.todayPlan(now: now).focus.contains { $0.id == review })
        XCTAssertNotNil(store.project(simple))
        // Undo brings the project, its view and its time back
        store.undo()
        XCTAssertNotNil(store.savedView(projectView))
        XCTAssertEqual(store.task(review)?.spentSeconds ?? 0, 3600 + 500, accuracy: 120)
    }

    // MARK: - Undo across the new action types

    func testUndoRedoKeepsWorkspaceNormalized() async {
        let (store, dev, simple, review, canceled, _, _) = await devFixture()
        let label = store.addLabel("bug")!
        store.setLabels(review, [label])
        store.addTimeEntry(taskId: review, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800))
        store.addToToday([review], now: now)
        let view = store.addSavedView(name: "Mine", scope: .project(dev), layout: .list, options: .standard)!
        store.applyWorkflowPreset(projectId: dev, .simple)
        store.deleteLabel(label)
        store.setProject(canceled, simple)
        store.setUsesSprints(simple, false)
        store.setWeeklyCapacity(dev, hours: 12)
        store.deleteSavedView(view)
        func check(_ step: String) {
            var ws = store.workspace
            let before = ws
            ws.normalizeStatuses(); ws.normalizeCompletion(); ws.normalizeTime(); ws.normalizeLabels(); ws.normalizePreferences()
            XCTAssertEqual(ws, before, "not normalized after \(step)")
            for task in store.workspace.tasks {
                XCTAssertTrue(store.project(task.projectId)!.statuses.contains { $0.id == task.statusId }, step)
                XCTAssertTrue(task.labelIds.allSatisfy { store.label($0) != nil }, step)
            }
        }
        var undone = 0
        while let name = store.undo() { check("undo \(name)"); undone += 1 }
        XCTAssertGreaterThanOrEqual(undone, 8)
        XCTAssertEqual(store.task(review)?.statusId, "review")
        XCTAssertEqual(store.task(review)?.spentSeconds ?? 0, 0, accuracy: 0.5)
        while let name = store.redo() { check("redo \(name)") }
        XCTAssertNil(store.savedView(view))
        XCTAssertEqual(store.task(review)?.spentSeconds ?? 0, 1800, accuracy: 0.5)
        XCTAssertNil(store.label(label))
    }

    // MARK: - Fixes of the QA pass

    func testDraggingBetweenLabelGroupsMovesTheLabel() async {
        let store = await makeStore()
        let p = store.addProject(name: "Atlas")!
        let bug = store.addLabel("bug")!, design = store.addLabel("design")!, ux = store.addLabel("ux")!
        let t = store.addTask(title: "Task", projectId: p)!
        store.setLabels(t, [bug, ux])
        store.moveTask(t, to: .label(design), reorder: false, from: .label(bug))
        XCTAssertEqual(Set(store.task(t)!.labelIds), [ux, design], "bug comes off, ux stays")
        XCTAssertEqual(store.undo(), "Move task")
        XCTAssertEqual(store.task(t)?.labelIds, [bug, ux])
        // From No label, or without a known source: adds
        store.moveTask(t, to: .label(design), reorder: false, from: .label(nil))
        XCTAssertEqual(Set(store.task(t)!.labelIds), [bug, ux, design])
        // Onto a label it already has, from another: just the source comes off
        store.moveTask(t, to: .label(design), reorder: false, from: .label(ux))
        XCTAssertEqual(Set(store.task(t)!.labelIds), [bug, design])
        // The table passes the source group's drop along
        TaskGroupSection.perform(.group(.label(ux), reorder: false), id: t, before: nil,
                                 from: .group(.label(bug), reorder: false), store: store)
        XCTAssertEqual(Set(store.task(t)!.labelIds), [design, ux])
    }

    func testSleepPromptSurvivesRelaunch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seams-\(UUID())")
        let url = dir.appendingPathComponent("workspace.json")
        let store = TaskStore(repository: LocalJSONWorkspaceRepository(fileURL: url), saveDelay: 0)
        await store.load()
        let p = store.addProject(name: "Atlas")!
        let t = store.addTask(title: "Long run", projectId: p)!
        store.startTimer(t, now: now.addingTimeInterval(-3 * 3600))
        store.systemWillSleep(at: now.addingTimeInterval(-2 * 3600))
        store.systemDidWake(at: now.addingTimeInterval(-600))
        XCTAssertEqual(store.awayGaps.count, 1)
        XCTAssertTrue(store.undoStack.allSatisfy { !$0.name.contains("sleep") }, "recording isn't an undo step")
        await store.flush()

        let relaunched = TaskStore(repository: LocalJSONWorkspaceRepository(fileURL: url), saveDelay: 0)
        await relaunched.load()
        XCTAssertEqual(relaunched.awayGaps.map(\.id), store.awayGaps.map(\.id))
        XCTAssertEqual(relaunched.awayDuration, store.awayDuration, accuracy: 0.01)
        XCTAssertEqual(relaunched.awayTasks.map(\.id), [t])
        XCTAssertNotNil(relaunched.notificationInput(now: now).away)
        relaunched.discardAwayTime()
        XCTAssertTrue(relaunched.awayGaps.isEmpty)
        // Undo puts the time back but doesn't ask again
        relaunched.undo()
        XCTAssertTrue(relaunched.awayGaps.isEmpty)
        // Keep clears it for good too
        relaunched.systemWillSleep(at: now.addingTimeInterval(-1200))
        relaunched.systemDidWake(at: now.addingTimeInterval(-300))
        relaunched.keepAwayTime()
        await relaunched.flush()
        let third = TaskStore(repository: LocalJSONWorkspaceRepository(fileURL: url), saveDelay: 0)
        await third.load()
        XCTAssertTrue(third.awayGaps.isEmpty)
    }

    func testSchema11FileLoadsWithNoSleepPromptAndBadGapsAreDropped() throws {
        let pid = UUID(), tid = UUID()
        let json = """
        {"schemaVersion":11,"projects":[{"id":"\(pid)","name":"Atlas","colorHex":16739146}],"milestones":[],
         "tasks":[{"id":"\(tid)","projectId":"\(pid)","title":"T","statusId":"todo","statusCategory":"notStarted"}],
         "runningTimers":{},"timeEntries":[],
         "preferences":{"pendingAway":[{"start":"2026-10-30T10:00:00Z","end":"2026-10-30T12:00:00Z","kind":"sleep","taskIds":["\(tid)"]},
                                       {"start":"2026-10-30T10:00:00Z","end":"2026-10-30T12:00:00Z","kind":"locked","taskIds":["\(UUID())"]},
                                       {"start":"bad"}]}}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(ws.preferences.pendingAway.count, 1)
        XCTAssertEqual(ws.preferences.pendingAway.first?.taskIds, [tid])
        let none = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data("""
        {"schemaVersion":11,"projects":[],"milestones":[],"tasks":[],"runningTimers":{}}
        """.utf8)).migrated()
        XCTAssertTrue(none.preferences.pendingAway.isEmpty)
    }

    func testMilestoneColorAvoidsColorsCloseToTheProjects() {
        // A custom red close to the palette's coral (0xFF6B4A): coral is skipped
        XCTAssertLessThan(ColorDistance.deltaE(0xEF5350, 0xFF6B4A), Milestone.minimumDistanceFromProject)
        let first = Milestone.nextColor(projectColor: 0xEF5350, used: [])
        XCTAssertNotEqual(first, 0xFF6B4A)
        XCTAssertGreaterThanOrEqual(ColorDistance.deltaE(first, 0xEF5350), Milestone.minimumDistanceFromProject)
        // Walking the palette never lands near the project color
        var used: [UInt32] = []
        for _ in 0..<20 {
            let hex = Milestone.nextColor(projectColor: 0xFF7043, used: used)
            XCTAssertGreaterThanOrEqual(ColorDistance.deltaE(hex, 0xFF7043), Milestone.minimumDistanceFromProject)
            used.append(hex)
        }
        // Palette colors themselves are all far enough apart to stay choices for each other
        for a in Focus.projectPalette {
            XCTAssertEqual(Milestone.palette.filter { ColorDistance.deltaE(a, $0) < Milestone.minimumDistanceFromProject }, [a])
        }
        XCTAssertEqual(ColorDistance.deltaE(0x123456, 0x123456), 0, accuracy: 0.0001)
        // Migration uses the same rule
        let p = Project(name: "Red", colorHex: 0xEF5350)
        var ws = Workspace(projects: [p], milestones: [Milestone(projectId: p.id, name: "M")])
        ws.assignMilestoneColors()
        XCTAssertNotEqual(ws.milestones[0].colorHex, 0xFF6B4A)
    }

    func testPastSprintHeaderHintDoesNotRepeatTheCount() {
        let sprint = PastSprint(number: 3, startDate: day(-14), endDate: day(-1), goal: "", taskIds: [UUID(), UUID(), UUID()],
                                doneTaskIds: [UUID(), UUID()], completedAt: day(-1), plannedMinutes: 180, doneMinutes: 120,
                                trackedSeconds: 7200)
        XCTAssertTrue(sprint.headerHint.hasPrefix("2 done · 3h planned · 2h tracked"))
        XCTAssertFalse(sprint.headerHint.contains("of 3"))
    }

    func testTimelineStickyMonthLabelAndLabelRoom() {
        // Scrolled past the month start: pinned to the visible edge
        XCTAssertEqual(TimelineScale.stickyLabelX(8, visibleLeft: 40, nextX: 400, labelWidth: 100), 48)
        // Not scrolled: where it is
        XCTAssertEqual(TimelineScale.stickyLabelX(8, visibleLeft: 0, nextX: 400, labelWidth: 100), 8)
        // The next month's label pushes it back, never left of its own start
        XCTAssertEqual(TimelineScale.stickyLabelX(8, visibleLeft: 250, nextX: 300, labelWidth: 100), 192)
        XCTAssertEqual(TimelineScale.stickyLabelX(200, visibleLeft: 250, nextX: 260, labelWidth: 100), 200)
        let scale = TimelineScale.fitting([], now: now, zoom: .quarter, visibleWidth: 800)
        XCTAssertEqual(scale.labelRoom(from: 100, before: [100, 180, 400]), 58)
        XCTAssertEqual(scale.labelRoom(from: 100, before: [130]), 8, "a target flag right after the diamond")
        XCTAssertEqual(scale.labelRoom(from: 100, before: []), scale.width - 122)
    }

    func testDroppingAnUndatedMilestoneOnTheTimelineSetsItsDate() async {
        let store = await makeStore()
        let p = store.addProject(name: "Atlas")!
        let m = store.addMilestone(projectId: p, name: "Someday")!
        let target = day(9).addingTimeInterval(13 * 3600)
        XCTAssertEqual(store.placeMilestone(m, on: target), "Someday")
        XCTAssertEqual(store.milestone(m)?.dueDate, day(9))
        XCTAssertNil(store.placeMilestone(m, on: day(9)), "same day: nothing to do")
        XCTAssertEqual(store.undo(), "Change milestone date")
        XCTAssertNil(store.milestone(m)?.dueDate)
        XCTAssertEqual(TimelineDateDrop.milestoneId(from: TimelineDateDrop.payload(m)), m)
        XCTAssertNil(TimelineDateDrop.milestoneId(from: UUID().uuidString), "task drags aren't milestones")
    }

    func testQuickPickerAnchorsStackSoTheLatestVisibleWins() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = root
        let id = UUID()
        let card = QuickPickerAnchor.AnchorView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let panelRow = QuickPickerAnchor.AnchorView(frame: NSRect(x: 100, y: 0, width: 10, height: 10))
        card.key = QuickPickerAnchors.key(.task(id))
        panelRow.key = QuickPickerAnchors.key(.task(id))
        root.addSubview(card)
        XCTAssertTrue(QuickPickerAnchors.resolve(.task(id), in: window)?.view === card)
        root.addSubview(panelRow)
        XCTAssertTrue(QuickPickerAnchors.resolve(.task(id), in: window)?.view === panelRow, "the milestone panel's row wins")
        panelRow.removeFromSuperview()
        XCTAssertTrue(QuickPickerAnchors.resolve(.task(id), in: window)?.view === card, "the card takes over again")
        card.removeFromSuperview()
        XCTAssertNil(QuickPickerAnchors.resolve(.task(id), in: window))
    }

    func testMenuBarStatusItemButtonIsFoundByType() {
        _ = NSApplication.shared
        MenuBarStatusItem.reset()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item); MenuBarStatusItem.reset() }
        item.button?.title = "FM"
        guard let expected = item.button, let window = expected.window else {
            return XCTFail("no status bar window in this environment")
        }
        // A window with an ordinary button first: never picked
        let decoy = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        decoy.contentView?.addSubview(NSButton(title: "Not it", target: nil, action: nil))
        XCTAssertTrue(MenuBarStatusItem.button(in: [decoy, window]) === expected)
        // Kept: found again without looking
        XCTAssertTrue(MenuBarStatusItem.button(in: []) === expected)
        MenuBarStatusItem.reset()
        XCTAssertNil(MenuBarStatusItem.button(in: [decoy]))
    }
}

/// FLOWMATE_DATA_DIR moves every file FlowMate writes; without it nothing changes.
final class AppDataLocationTests: XCTestCase {
    func testOverrideMovesTheDataFolderAndDefaultIsUnchanged() {
        let normal = AppDataLocation.directory(environment: [:])
        XCTAssertEqual(normal.lastPathComponent, "FlowMate")
        XCTAssertTrue(normal.path.hasSuffix("Library/Application Support/FlowMate"))
        XCTAssertEqual(AppDataLocation.directory(environment: ["FLOWMATE_DATA_DIR": "  "]), normal)
        XCTAssertEqual(AppDataLocation.directory(environment: ["FLOWMATE_DATA_DIR": "/tmp/fm-qa"]).path, "/tmp/fm-qa")
        XCTAssertEqual(AppDataLocation.directory(environment: ["FLOWMATE_DATA_DIR": "~/fm"]).path,
                       (NSHomeDirectory() as NSString).appendingPathComponent("fm"))
    }
}
