import XCTest
@testable import FlowMate

/// All projects › Overview (PortfolioRules, TaskStore.portfolio) and the roadmap timeline
/// (TimelineScale, dragging a milestone's due date).
@MainActor
final class PortfolioTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }()
    /// Fri Oct 30 2026, 12:00 local time
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
    private var today: Date { calendar.startOfDay(for: now) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    // MARK: - Milestone health

    func testWorkingDaysLeftSkipsWeekends() {
        XCTAssertEqual(PortfolioRules.workingDaysLeft(until: day(0), now: now, calendar: calendar), 1, "due today still has today")
        XCTAssertEqual(PortfolioRules.workingDaysLeft(until: day(1), now: now, calendar: calendar), 1, "Saturday adds nothing")
        XCTAssertEqual(PortfolioRules.workingDaysLeft(until: day(5), now: now, calendar: calendar), 4, "Fri, Mon, Tue, Wed")
        XCTAssertEqual(PortfolioRules.workingDaysLeft(until: day(-1), now: now, calendar: calendar), 0)
    }

    func testMilestoneHealthWithoutCapacityUsesFourHoursADay() {
        let open = MilestoneProgress(done: 1, total: 4)
        // Due Wed Nov 4: 4 working days × 4h = 16h
        func health(_ remaining: Double, due: Date? = nil, completed: Bool = false, progress: MilestoneProgress? = nil) -> MilestoneHealth {
            PortfolioRules.milestoneHealth(dueDate: due ?? day(5), isCompleted: completed, progress: progress ?? open,
                                           remainingHours: remaining, now: now, calendar: calendar)
        }
        XCTAssertEqual(health(16), .onTrack, "exactly fits")
        XCTAssertEqual(health(16.5), .atRisk)
        XCTAssertEqual(health(2, due: day(-2)), .overdue)
        XCTAssertEqual(health(0, due: day(-2), progress: MilestoneProgress(done: 3, total: 3)), .complete, "all tasks done")
        XCTAssertEqual(health(40, completed: true), .complete)
        XCTAssertEqual(PortfolioRules.milestoneHealth(dueDate: nil, isCompleted: false, progress: open, remainingHours: 500,
                                                      now: now, calendar: calendar), .onTrack, "no date, no risk")
        XCTAssertEqual(health(1, due: day(1)), .onTrack, "due Saturday: Friday's 4h")
        XCTAssertEqual(health(5, due: day(1)), .atRisk)
        XCTAssertTrue(MilestoneHealth.atRisk.needsAttention)
        XCTAssertEqual(MilestoneHealth.overdue.label, "Overdue")
        XCTAssertNil(MilestoneHealth.onTrack.label)
    }

    func testMilestoneHealthWithCapacity() {
        let open = MilestoneProgress(done: 0, total: 2)
        func health(_ remaining: Double, weekly: Double?) -> MilestoneHealth {
            PortfolioRules.milestoneHealth(dueDate: day(5), isCompleted: false, progress: open, remainingHours: remaining,
                                           weeklyCapacityHours: weekly, now: now, calendar: calendar)
        }
        // 40h a week = 8h a day × 4 days = 32h
        XCTAssertEqual(health(20, weekly: 40), .onTrack)
        XCTAssertEqual(health(33, weekly: 40), .atRisk)
        // 10h a week = 2h a day × 4 = 8h
        XCTAssertEqual(health(10, weekly: 10), .atRisk)
        XCTAssertEqual(health(8, weekly: 10), .onTrack)
        XCTAssertEqual(PortfolioRules.dailyHours(weeklyCapacityHours: 0), 4, "no capacity falls back to 4h")
    }

    func testRemainingHoursCountsOpenTasksOnly() {
        let hours = PortfolioRules.remainingHours([
            (expectedMinutes: 120, trackedSeconds: 1800, isClosed: false), // 1.5h left
            (expectedMinutes: 60, trackedSeconds: 7200, isClosed: false),  // over: 0
            (expectedMinutes: 600, trackedSeconds: 0, isClosed: true),     // done: 0
        ])
        XCTAssertEqual(hours, 1.5, accuracy: 0.0001)
    }

    func testStoreForecastFlagsAtRiskMilestone() async {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let p = store.addProject(name: "Atlas", now: now)!
        let m = store.addMilestone(projectId: p, name: "Beta", dueDate: day(5))!
        for i in 0..<3 {
            let t = store.addTask(title: "T\(i)", projectId: p, milestoneId: m, now: now)!
            store.setExpectedMinutes(t, 360)
        }
        let forecast = store.milestoneForecast(m, now: now, calendar: calendar)!
        XCTAssertEqual(forecast.remainingHours, 18, accuracy: 0.001)
        XCTAssertEqual(forecast.workingDaysLeft, 4)
        XCTAssertEqual(forecast.hoursAvailable, 16)
        XCTAssertEqual(forecast.health, .atRisk)
        XCTAssertEqual(forecast.remainingLabel, "18h left")
    }

    // MARK: - Sprint day

    func testSprintDay() {
        let sprint = SprintState(number: 14, startDate: day(-6), lengthWeeks: 2)
        let d = PortfolioRules.sprintDay(sprint, now: now, calendar: calendar)
        XCTAssertEqual(d, SprintDay(day: 7, length: 14))
        XCTAssertEqual(PortfolioRules.sprintLine(sprint, day: d), "Sprint 14 · day 7 of 14")
        XCTAssertEqual(PortfolioRules.sprintDay(sprint, now: day(7).addingTimeInterval(3600 * 23), calendar: calendar).day, 14, "last day")

        let future = SprintState(number: 2, startDate: day(3))
        let before = PortfolioRules.sprintDay(future, now: now, calendar: calendar)
        XCTAssertFalse(before.hasStarted)
        XCTAssertTrue(PortfolioRules.sprintLine(future, day: before).hasPrefix("Sprint 2 · starts "))

        let old = SprintState(number: 3, startDate: day(-20), lengthWeeks: 1)
        let after = PortfolioRules.sprintDay(old, now: now, calendar: calendar)
        XCTAssertTrue(after.isOver)
        XCTAssertTrue(PortfolioRules.sprintLine(old, day: after).hasPrefix("Sprint 3 · ended "))
    }

    // MARK: - Activity

    func testLastActivityAndUntouchedDays() {
        let created = day(-30)
        XCTAssertEqual(PortfolioRules.lastActivity([], fallback: created), created)
        XCTAssertEqual(PortfolioRules.lastActivity([day(-12), day(-3)], fallback: created), day(-3))
        XCTAssertEqual(PortfolioRules.lastActivity([day(-40)], fallback: created), created, "never older than the project")
        XCTAssertEqual(PortfolioRules.untouchedDays(since: day(-12).addingTimeInterval(80_000), now: now, calendar: calendar), 12)
        XCTAssertEqual(PortfolioRules.untouchedDays(since: today, now: now, calendar: calendar), 0)
        XCTAssertEqual(PortfolioRules.activityLabel(untouchedDays: 0), "Active today")
        XCTAssertEqual(PortfolioRules.activityLabel(untouchedDays: 1), "Active yesterday")
        XCTAssertEqual(PortfolioRules.activityLabel(untouchedDays: 12), "Untouched 12 days")
    }

    // MARK: - Attention order and the cards

    /// Five projects: fine, stale (untouched 12 days), overdue tasks, a milestone at risk, an
    /// overdue milestone; plus an archived one that never shows.
    private func portfolioStore() async -> (TaskStore, [String: UUID]) {
        func project(_ name: String, created: Date) -> Project {
            Project(name: name, colorHex: 0x4EA1F5, createdAt: created)
        }
        let fine = project("Fine", created: day(-60))
        let stale = project("Stale", created: day(-60))
        let late = project("Late tasks", created: day(-60))
        let risky = project("Risky", created: day(-60))
        let overdue = project("Overdue milestone", created: day(-60))
        var archived = project("Archived", created: day(-60))
        archived.archivedAt = day(-1)
        let mRisk = Milestone(projectId: risky.id, name: "Launch", dueDate: day(5), colorHex: 0xFF6B4A)
        let mLate = Milestone(projectId: overdue.id, name: "Release", dueDate: day(-2), colorHex: 0xFF6B4A)
        func task(_ p: Project, _ title: String, updated: Date, due: Date? = nil, milestone: UUID? = nil,
                  expected: Int = 60, status: WorkflowStatus = .todo, slot: SprintSlot = .active) -> TaskItem {
            TaskItem(projectId: p.id, milestoneId: milestone, sprintSlot: slot, status: status, title: title, dueDate: due,
                     expectedMinutes: expected, createdAt: day(-60), updatedAt: updated)
        }
        let fineTask = task(fine, "Fine task", updated: day(0), status: .inProgress)
        let ws = Workspace(
            projects: [fine, stale, late, risky, overdue, archived],
            milestones: [mRisk, mLate],
            tasks: [
                fineTask,
                task(fine, "Done", updated: day(-1), status: .done),
                task(stale, "Old", updated: day(-12)),
                task(late, "Late 1", updated: day(-1), due: day(-3)),
                task(late, "Late 2", updated: day(-1), due: day(-1)),
                task(risky, "Big", updated: day(-1), milestone: mRisk.id, expected: 20 * 60),
                task(overdue, "Unfinished", updated: day(-1), milestone: mLate.id),
                task(archived, "Hidden", updated: day(-90), due: day(-9)),
            ],
            timeEntries: [TimeEntry(taskId: fineTask.id, start: now.addingTimeInterval(-5400), end: now.addingTimeInterval(-1800), source: .timer)],
            sprint: SprintState(number: 4, startDate: day(-6))
        )
        let store = TaskStore(repository: InMemoryWorkspaceRepository(ws), saveDelay: 0.05)
        await store.load()
        return (store, ["fine": fine.id, "stale": stale.id, "late": late.id, "risky": risky.id, "overdue": overdue.id,
                        "archived": archived.id, "fineTask": fineTask.id, "mRisk": mRisk.id])
    }

    func testAttentionOrdering() async {
        let (store, ids) = await portfolioStore()
        let cards = store.portfolio(sortedBy: .attention, now: now, calendar: calendar)
        XCTAssertEqual(cards.map(\.project.name), ["Overdue milestone", "Risky", "Late tasks", "Stale", "Fine"])
        XCTAssertFalse(cards.contains { $0.id == ids["archived"] }, "archived projects stay out")
        XCTAssertEqual(cards.map(\.attentionLevel), [4, 3, 2, 1, 0])

        XCTAssertEqual(store.portfolio(sortedBy: .name, now: now, calendar: calendar).map(\.project.name),
                       ["Fine", "Late tasks", "Overdue milestone", "Risky", "Stale"])
        XCTAssertEqual(store.portfolio(sortedBy: .activity, now: now, calendar: calendar).first?.project.name, "Fine")
        XCTAssertEqual(store.portfolio(sortedBy: .activity, now: now, calendar: calendar).last?.project.name, "Stale")

        // Ties at one level: more overdue tasks first, then longer untouched
        let a = card(level: .none, overdue: 1, untouched: 2, name: "A")
        let b = card(level: .none, overdue: 3, untouched: 0, name: "B")
        let c = card(level: .none, overdue: 1, untouched: 5, name: "C")
        XCTAssertEqual(PortfolioRules.sorted([a, b, c], by: .attention).map(\.project.name), ["B", "C", "A"])
    }

    private enum Level { case none }
    private func card(level: Level, overdue: Int, untouched: Int, name: String) -> ProjectOverview {
        ProjectOverview(project: Project(name: name, colorHex: 0),
                        sprint: SprintState(startDate: today), sprintDay: SprintDay(day: 1, length: 14), sprintDone: 0, sprintPlanned: 0, trackedInSprint: 0,
                        trackedThisWeek: 0, overdueCount: overdue, inProgressCount: 0, nextMilestone: nil,
                        nextMilestoneForecast: nil, lastActivity: day(-untouched), untouchedDays: untouched,
                        nextTaskId: nil, isRunning: false)
    }

    func testProjectOverviewCard() async {
        let (store, ids) = await portfolioStore()
        let fine = store.projectOverview(ids["fine"]!, now: now, calendar: calendar)!
        XCTAssertEqual(fine.sprintLine, "Sprint 4 · day 7 of 14")
        XCTAssertEqual(fine.sprintDone, 1)
        XCTAssertEqual(fine.sprintPlanned, 2)
        XCTAssertEqual(fine.inProgressCount, 1)
        XCTAssertEqual(fine.trackedThisWeek, 3600, accuracy: 1)
        XCTAssertEqual(fine.trackedInSprint, 3600, accuracy: 1)
        XCTAssertEqual(fine.nextTaskId, ids["fineTask"], "the play button starts the started task")
        XCTAssertNil(fine.nextMilestone)
        XCTAssertEqual(fine.untouchedDays, 0)

        let stale = store.projectOverview(ids["stale"]!, now: now, calendar: calendar)!
        XCTAssertEqual(stale.untouchedDays, 12)
        XCTAssertTrue(stale.isStale)

        let late = store.projectOverview(ids["late"]!, now: now, calendar: calendar)!
        XCTAssertEqual(late.overdueCount, 2)

        let risky = store.projectOverview(ids["risky"]!, now: now, calendar: calendar)!
        XCTAssertEqual(risky.nextMilestone?.id, ids["mRisk"])
        XCTAssertEqual(risky.nextMilestoneForecast?.health, .atRisk, "20h left, 16h of working time")
    }

    // MARK: - Timeline mapping

    func testTimelineScaleFitsDefaultWindowAndDates() {
        let scale = TimelineScale.fitting([], now: now, zoom: .quarter, visibleWidth: 980, calendar: calendar)
        XCTAssertLessThanOrEqual(scale.start, day(-14))
        XCTAssertEqual(calendar.component(.weekday, from: scale.start), 2, "starts on a Monday")
        XCTAssertTrue(scale.contains(day(84)))
        XCTAssertEqual(scale.pointsPerDay, 10, "98 days in 980pt")

        let far = TimelineScale.fitting([day(200), day(-60)], now: now, zoom: .quarter, visibleWidth: 980, calendar: calendar)
        XCTAssertTrue(far.contains(day(207)))
        XCTAssertTrue(far.contains(day(-67)))

        XCTAssertEqual(TimelineScale.pointsPerDay(zoom: .month, visibleWidth: 1050), 30)
        XCTAssertEqual(TimelineScale.pointsPerDay(zoom: .quarter, visibleWidth: 300), 8, "never below the minimum")
    }

    func testTimelineDateToXAndBack() {
        let scale = TimelineScale(start: day(0), dayCount: 60, pointsPerDay: 20, calendar: calendar)
        XCTAssertEqual(scale.x(for: day(0)), 10, "middle of the first day")
        XCTAssertEqual(scale.x(for: day(3).addingTimeInterval(3600 * 20)), 70, "time of day doesn't matter")
        XCTAssertEqual(scale.lineX(for: day(3)), 60)
        XCTAssertEqual(scale.date(atX: 65), day(3))
        XCTAssertEqual(scale.date(atX: 79.9), day(3))
        XCTAssertEqual(scale.date(atX: 80), day(4))
        XCTAssertEqual(scale.date(atX: scale.x(for: day(17))), day(17), "round trip")
        XCTAssertEqual(scale.width, 1200)
        XCTAssertEqual(scale.weekStarts.first.map { calendar.component(.weekday, from: $0) }, 2)
    }

    func testDragSnapsToWholeDays() {
        let scale = TimelineScale(start: day(-14), dayCount: 98, pointsPerDay: 10, calendar: calendar)
        XCTAssertEqual(scale.dayOffset(forTranslation: 4), 0)
        XCTAssertEqual(scale.dayOffset(forTranslation: 6), 1)
        XCTAssertEqual(scale.dayOffset(forTranslation: 14), 1)
        XCTAssertEqual(scale.dayOffset(forTranslation: 26), 3)
        XCTAssertEqual(scale.dayOffset(forTranslation: -16), -2)
        let due = day(5).addingTimeInterval(9 * 3600)
        XCTAssertEqual(scale.draggedDate(from: due, translation: 31), day(8).addingTimeInterval(9 * 3600), "keeps its time")
        XCTAssertEqual(scale.draggedDate(from: due, translation: -3), due)
    }

    func testDraggingDueDateIsOneUndoStep() async {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let p = store.addProject(name: "Atlas", now: now)!
        let m = store.addMilestone(projectId: p, name: "Beta", dueDate: day(5))!
        store.clearUndoHistory()
        XCTAssertNil(store.shiftMilestoneDue(m, byDays: 0, calendar: calendar), "no move, no step")
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.shiftMilestoneDue(m, byDays: 3, calendar: calendar), day(8))
        XCTAssertEqual(store.milestone(m)?.dueDate, day(8))
        XCTAssertNotNil(store.undo())
        XCTAssertEqual(store.milestone(m)?.dueDate, day(5))
        XCTAssertFalse(store.canUndo, "one step")
        _ = store.redo()
        XCTAssertEqual(store.milestone(m)?.dueDate, day(8))

        let undated = store.addMilestone(projectId: p, name: "Later")!
        XCTAssertNil(store.shiftMilestoneDue(undated, byDays: 2, calendar: calendar), "undated milestones sit in the tray")
    }

    // MARK: - Window

    func testOverviewTabPaletteAndRememberedChoices() async {
        let (store, ids) = await portfolioStore()
        let defaults = UserDefaults(suiteName: "portfolio-\(UUID())")!
        let model = TasksViewModel(defaults: defaults, stateKey: "state")
        model.select(.all)
        XCTAssertEqual(model.tabs, [.overview, .board, .list, .sprints, .milestones])
        XCTAssertEqual(TasksViewModel.tabs(in: .project(ids["fine"]!)), [.board, .list, .sprints, .milestones])
        XCTAssertEqual(TasksViewModel.tab(.overview, in: .project(ids["fine"]!)), .list)

        // ⌘K "Go to Overview" from a project
        model.select(.project(ids["fine"]!))
        model.openPalette(store: store)
        model.paletteQuery = "overview"
        XCTAssertEqual(model.paletteResults(store).items.first, .command(.goToOverview))
        model.runPaletteItem(.command(.goToOverview), store: store)
        XCTAssertEqual(model.scope, .all)
        XCTAssertEqual(model.effectiveTab, .overview)
        XCTAssertFalse(model.showsFilterBar)
        XCTAssertFalse(model.paletteCommands(store).contains(.goToOverview), "already there")
        XCTAssertFalse(model.paletteCommands(store).contains(.switchTab(.overview)))

        // The overdue count opens the project's List filtered to overdue
        model.showOverdueTasks(of: ids["late"]!)
        XCTAssertEqual(model.scope, .project(ids["late"]!))
        XCTAssertEqual(model.effectiveTab, .list)
        XCTAssertEqual(model.filter.due, [.overdue])
        XCTAssertEqual(model.visibleTasks(store, now: now).count, 2)

        // ⌘N on Overview goes to List
        model.showOverview()
        model.startNewTask(store)
        XCTAssertEqual(model.effectiveTab, .list)

        // The sort, the layout and the zoom come back after relaunch, and All projects its tab
        model.showOverview()
        model.overviewSort = .activity
        model.milestonesLayout = .timeline
        model.timelineZoom = .month
        let restored = TasksViewModel(defaults: defaults, stateKey: "state")
        XCTAssertEqual(restored.overviewSort, .activity)
        XCTAssertEqual(restored.milestonesLayout, .timeline)
        XCTAssertEqual(restored.timelineZoom, .month)
        XCTAssertEqual(restored.tab, .overview)

        // Older state without these keys decodes to the defaults
        let old = try! JSONDecoder().decode(TasksViewModel.WindowState.self, from: Data(#"{"scope":"all","tabs":{"all":"list"}}"#.utf8))
        XCTAssertEqual(old.overviewSort, .attention)
        XCTAssertEqual(old.milestonesLayout, .list)
        XCTAssertEqual(old.timelineZoom, .quarter)
    }
}
