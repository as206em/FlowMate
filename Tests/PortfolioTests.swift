import XCTest
@testable import FlowMate

/// All projects › Overview (PortfolioRules, TaskStore.portfolio).
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

    // MARK: - Remaining hours

    func testRemainingHoursCountsOpenTasksOnly() {
        let hours = PortfolioRules.remainingHours([
            (expectedMinutes: 120, trackedSeconds: 1800, isClosed: false), // 1.5h left
            (expectedMinutes: 60, trackedSeconds: 7200, isClosed: false),  // over: 0
            (expectedMinutes: 600, trackedSeconds: 0, isClosed: true),     // done: 0
        ])
        XCTAssertEqual(hours, 1.5, accuracy: 0.0001)
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

    /// Three projects: fine, stale (untouched 12 days), overdue tasks; plus an archived one that
    /// never shows.
    private func portfolioStore() async -> (TaskStore, [String: UUID]) {
        func project(_ name: String, created: Date) -> Project {
            Project(name: name, colorHex: 0x4EA1F5, createdAt: created)
        }
        let fine = project("Fine", created: day(-60))
        let stale = project("Stale", created: day(-60))
        let late = project("Late tasks", created: day(-60))
        var archived = project("Archived", created: day(-60))
        archived.archivedAt = day(-1)
        func task(_ p: Project, _ title: String, updated: Date, due: Date? = nil,
                  expected: Int = 60, status: WorkflowStatus = .todo, slot: SprintSlot = .active) -> TaskItem {
            TaskItem(projectId: p.id, sprintSlot: slot, status: status, title: title, dueDate: due,
                     expectedMinutes: expected, createdAt: day(-60), updatedAt: updated)
        }
        let fineTask = task(fine, "Fine task", updated: day(0), status: .inProgress)
        let ws = Workspace(
            projects: [fine, stale, late, archived],
            tasks: [
                fineTask,
                task(fine, "Done", updated: day(-1), status: .done),
                task(stale, "Old", updated: day(-12)),
                task(late, "Late 1", updated: day(-1), due: day(-3)),
                task(late, "Late 2", updated: day(-1), due: day(-1)),
                task(archived, "Hidden", updated: day(-90), due: day(-9)),
            ],
            timeEntries: [TimeEntry(taskId: fineTask.id, start: now.addingTimeInterval(-5400), end: now.addingTimeInterval(-1800), source: .timer)],
            sprint: SprintState(number: 4, startDate: day(-6))
        )
        let store = TaskStore(repository: InMemoryWorkspaceRepository(ws), saveDelay: 0.05)
        await store.load()
        return (store, ["fine": fine.id, "stale": stale.id, "late": late.id,
                        "archived": archived.id, "fineTask": fineTask.id])
    }

    func testAttentionOrdering() async {
        let (store, ids) = await portfolioStore()
        let cards = store.portfolio(sortedBy: .attention, now: now, calendar: calendar)
        XCTAssertEqual(cards.map(\.project.name), ["Late tasks", "Stale", "Fine"])
        XCTAssertFalse(cards.contains { $0.id == ids["archived"] }, "archived projects stay out")
        XCTAssertEqual(cards.map(\.attentionLevel), [2, 1, 0])

        XCTAssertEqual(store.portfolio(sortedBy: .name, now: now, calendar: calendar).map(\.project.name),
                       ["Fine", "Late tasks", "Stale"])
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
                        trackedThisWeek: 0, overdueCount: overdue, inProgressCount: 0,
                        lastActivity: day(-untouched), untouchedDays: untouched,
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
        XCTAssertEqual(fine.untouchedDays, 0)

        let stale = store.projectOverview(ids["stale"]!, now: now, calendar: calendar)!
        XCTAssertEqual(stale.untouchedDays, 12)
        XCTAssertTrue(stale.isStale)

        let late = store.projectOverview(ids["late"]!, now: now, calendar: calendar)!
        XCTAssertEqual(late.overdueCount, 2)
    }

    // MARK: - Window

    func testOverviewTabPaletteAndRememberedChoices() async {
        let (store, ids) = await portfolioStore()
        let defaults = UserDefaults(suiteName: "portfolio-\(UUID())")!
        let model = TasksViewModel(defaults: defaults, stateKey: "state")
        model.select(.all)
        XCTAssertEqual(model.tabs, [.overview, .list, .sprints])
        XCTAssertEqual(TasksViewModel.tabs(in: .project(ids["fine"]!)), [.list, .sprints])
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

        // The sort comes back after relaunch, and All projects its tab
        model.showOverview()
        model.overviewSort = .activity
        let restored = TasksViewModel(defaults: defaults, stateKey: "state")
        XCTAssertEqual(restored.overviewSort, .activity)
        XCTAssertEqual(restored.tab, .overview)

        // Older state without these keys decodes to the defaults
        let old = try! JSONDecoder().decode(TasksViewModel.WindowState.self, from: Data(#"{"scope":"all","tabs":{"all":"list"}}"#.utf8))
        XCTAssertEqual(old.overviewSort, .attention)
    }
}
