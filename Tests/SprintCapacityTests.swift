import XCTest
@testable import FlowMate

/// Schema 10: sprint capacity and planning numbers, past sprint stats and velocity, projects
/// without sprints, and per-project defaults (view, expected time, sprint slot, icon).
@MainActor
final class SprintCapacityTests: XCTestCase {
    private let calendar = Calendar.current
    /// Wed Oct 28 2026, 12:00 local time
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
    private func hoursLater(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Atlas", now: now)!
        return (store, pid)
    }

    @discardableResult
    private func task(_ store: TaskStore, _ pid: UUID, _ title: String, slot: SprintSlot, minutes: Int) -> UUID {
        let id = store.addTask(title: title, projectId: pid, sprintSlot: slot, now: now)!
        store.setExpectedMinutes(id, minutes)
        return id
    }

    // MARK: - Migration

    func testSchema9MigratesToTenWithApproximatePastSprintStats() throws {
        let pid = UUID(), a = UUID(), b = UUID(), c = UUID()
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let iso = ISO8601DateFormatter()
        func d(_ day: Int, _ hour: Int) -> String {
            iso.string(from: calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!)
        }
        let json = """
        {"schemaVersion": 9,
         "projects": [{"id": "\(pid.uuidString)", "name": "Atlas", "colorHex": 4280391411,
            "pastSprints": [{"id": "\(UUID().uuidString)", "number": 3, "startDate": "\(iso.string(from: start))",
              "endDate": "\(iso.string(from: end))", "goal": "Ship", "taskIds": ["\(a.uuidString)", "\(b.uuidString)"],
              "doneTaskIds": ["\(a.uuidString)"], "completedAt": "\(iso.string(from: end))"}]}],
         "tasks": [
           {"id": "\(a.uuidString)", "projectId": "\(pid.uuidString)", "title": "A", "statusId": "done",
            "statusCategory": "done", "sprintSlot": "closed", "expectedMinutes": 120},
           {"id": "\(b.uuidString)", "projectId": "\(pid.uuidString)", "title": "B", "statusId": "todo",
            "statusCategory": "notStarted", "sprintSlot": "backlog", "expectedMinutes": 90},
           {"id": "\(c.uuidString)", "projectId": "\(pid.uuidString)", "title": "C", "statusId": "todo",
            "statusCategory": "notStarted", "sprintSlot": "active", "expectedMinutes": 30}],
         "timeEntries": [
           {"id": "\(UUID().uuidString)", "taskId": "\(a.uuidString)", "start": "\(d(13, 9))", "end": "\(d(13, 12))", "source": "timer"},
           {"id": "\(UUID().uuidString)", "taskId": "\(c.uuidString)", "start": "\(d(20, 9))", "end": "\(d(20, 10))", "source": "timer"},
           {"id": "\(UUID().uuidString)", "taskId": "\(a.uuidString)", "start": "\(d(27, 9))", "end": "\(d(27, 11))", "source": "timer"}]}
        """
        let decoder = LocalJSONWorkspaceRepository.makeDecoder()
        let ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated(now: now)
        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        let project = ws.projects[0]
        XCTAssertTrue(project.usesSprints, "older projects keep their sprints")
        XCTAssertNil(project.weeklyCapacityHours)
        XCTAssertNil(project.icon)
        XCTAssertNil(project.defaultView)
        XCTAssertEqual(project.defaultSprintSlot, .active)
        let past = ws.pastSprints[0]
        XCTAssertEqual(past.plannedMinutes, 210, "A 2h + B 1h30m")
        XCTAssertEqual(past.doneMinutes, 120)
        XCTAssertEqual(past.trackedSeconds, 4 * 3600, "3h + 1h inside Oct 12–25; Oct 27 is outside")
        XCTAssertNil(past.capacityHours)
        XCTAssertTrue(past.isApproximate)
        XCTAssertEqual(past.hoursLabel, "≈3h 30m planned · 4h tracked")
        XCTAssertEqual(past.statsSummary, "1 of 2 done · ≈3h 30m planned · 4h tracked · Oct 12 – Oct 25")
        XCTAssertEqual(ws.tasks.count, 3, "nothing lost")

        // New fields round-trip
        var changed = ws
        changed.projects[0].weeklyCapacityHours = 12.5
        changed.projects[0].usesSprints = false
        changed.projects[0].defaultView = .milestones
        changed.projects[0].defaultExpectedMinutes = 30
        changed.projects[0].defaultSprintSlot = .backlog
        changed.projects[0].icon = .symbol("hammer")
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(changed)
        let back = try decoder.decode(Workspace.self, from: data).migrated(now: now)
        let p = back.projects[0]
        XCTAssertEqual(p.weeklyCapacityHours, 12.5)
        XCTAssertFalse(p.usesSprints)
        XCTAssertEqual(p.defaultView, .milestones)
        XCTAssertEqual(p.defaultExpectedMinutes, 30)
        XCTAssertEqual(p.defaultSprintSlot, .backlog)
        XCTAssertEqual(p.icon, .symbol("hammer"))
        XCTAssertEqual(back.pastSprints, changed.pastSprints)
        XCTAssertEqual(back.pastSprints[0].plannedMinutes, 210, "a migrated file isn't migrated again")
    }

    func testSchema12ProjectSprintsMergeIntoOneWorkspaceSprint() throws {
        let a = UUID(), b = UUID()
        let iso = ISO8601DateFormatter()
        let d1 = iso.string(from: calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!)
        let d2 = iso.string(from: calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!)
        func past(_ n: Int, _ done: String) -> String {
            """
            {"id": "\(UUID().uuidString)", "number": \(n), "startDate": "\(d1)", "endDate": "\(d1)", "completedAt": "\(done)"}
            """
        }
        let json = """
        {"schemaVersion": 12,
         "projects": [
           {"id": "\(a.uuidString)", "name": "A", "colorHex": 1,
            "sprint": {"number": 3, "startDate": "\(d1)", "lengthWeeks": 2, "goal": "Old"}, "pastSprints": [\(past(2, d1))]},
           {"id": "\(b.uuidString)", "name": "B", "colorHex": 2,
            "sprint": {"number": 7, "startDate": "\(d2)", "lengthWeeks": 3, "goal": "Newest"}, "pastSprints": [\(past(6, d2))]}]}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated(now: now)
        XCTAssertEqual(ws.sprint.number, 7, "the sprint furthest along becomes the workspace's")
        XCTAssertEqual(ws.sprint.goal, "Newest")
        XCTAssertEqual(ws.sprint.lengthWeeks, 3)
        XCTAssertEqual(ws.pastSprints.map(\.number), [2, 6], "every project's history is kept, oldest first")
        XCTAssertNil(ws.projects[0].legacySprint)
        XCTAssertTrue(ws.projects.allSatisfy { $0.legacyPastSprints.isEmpty })
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(ws)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"legacy"), "the old fields aren't written back")
    }

    func testSprintIsSharedByProjectsAndCapacitiesAddUp() async {
        let (store, a) = await makeStore()
        let b = store.addProject(name: "Beta", now: now)!
        store.setWeeklyCapacity(a, hours: 10)
        store.setWeeklyCapacity(b, hours: 5)
        let ta = task(store, a, "A1", slot: .active, minutes: 60)
        let tb = task(store, b, "B1", slot: .active, minutes: 120)
        XCTAssertEqual(Set(store.sprintTasks(slot: .active).map(\.id)), [ta, tb], "one sprint holds both projects' tasks")
        XCTAssertEqual(store.sprintTasks(slot: .active, in: .project(b)).map(\.id), [tb])
        XCTAssertEqual(store.slotLoad(slot: .active).plannedMinutes, 180)
        XCTAssertEqual(store.slotLoad(slot: .active).capacityMinutes, 15 * 2 * 60, "10h + 5h a week × 2 weeks")
        XCTAssertEqual(store.slotLoad(scope: .project(b), slot: .active).capacityMinutes, 5 * 2 * 60)
        store.setUsesSprints(b, false)
        XCTAssertEqual(store.sprintTasks(slot: .active).map(\.id), [ta], "a project outside sprints adds nothing")
        XCTAssertEqual(store.slotLoad(slot: .active).capacityMinutes, 10 * 2 * 60)
        store.setUsesSprints(b, true)
        store.setSprintSlot(tb, .active)
        store.completeSprint(now: now)
        XCTAssertEqual(store.workspace.pastSprints.count, 1)
        XCTAssertEqual(Set(store.workspace.pastSprints[0].taskIds), [ta, tb])
        XCTAssertEqual(store.workspace.pastSprints[0].capacityHours, 30)
    }

    func testSprintsPlannedAheadHoldTasksAndShiftOnComplete() async {
        let (store, a) = await makeStore()
        XCTAssertEqual(store.upcomingSprints().map(\.name), ["Sprint 2"], "the next sprint always exists")
        store.setSprintLength(weeks: 1)
        store.setSprintStart(date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!)
        store.addUpcomingSprints(4)
        XCTAssertEqual(store.upcomingSprints().map(\.name), ["Sprint 2", "Sprint 3", "Sprint 4", "Sprint 5", "Sprint 6"])
        XCTAssertEqual(store.upcomingSprints().map(\.dateRange),
                       ["Nov 9 – Nov 15", "Nov 16 – Nov 22", "Nov 23 – Nov 29", "Nov 30 – Dec 6", "Dec 7 – Dec 13"],
                       "back to back, one week each")
        store.setUpcomingGoal(ahead: 1, goal: "Beta")

        let now1 = task(store, a, "Next", slot: .next, minutes: 60)
        let later = task(store, a, "Later", slot: .backlog, minutes: 120)
        let far = task(store, a, "Far", slot: .backlog, minutes: 30)
        store.setSprint([later], .upcoming(2))
        store.setSprint([far], .upcoming(4))
        XCTAssertEqual(store.sprintTasks(ahead: 2).map(\.id), [later])
        XCTAssertEqual(store.sprintTasks(slot: .next).map(\.id), [now1], "next holds only the first upcoming sprint")
        XCTAssertEqual(store.sprintLabel(for: store.task(far)!), "Sprint 5")
        XCTAssertEqual(store.sprintChoice(of: store.task(later)!), .upcoming(2))
        XCTAssertEqual(store.slotLoad(slot: .next, ahead: 2).plannedMinutes, 120)

        store.completeSprint(now: now)
        XCTAssertEqual(store.sprint.number, 2)
        XCTAssertEqual(store.task(now1)?.sprintSlot, .active, "next becomes active")
        XCTAssertEqual(store.sprintChoice(of: store.task(later)!), .upcoming(1), "Sprint 3 is the next one now")
        XCTAssertEqual(store.sprintChoice(of: store.task(far)!), .upcoming(3))
        XCTAssertEqual(store.upcomingSprints().map(\.name), ["Sprint 3", "Sprint 4", "Sprint 5", "Sprint 6"])
        XCTAssertEqual(store.sprint.goal, "Beta", "the goal planned for Sprint 2 carries over")

        // Taking the last sprint away sends its tasks to the backlog
        store.removeLastUpcomingSprint()
        store.removeLastUpcomingSprint()
        XCTAssertEqual(store.task(far)?.sprintSlot, .backlog)
        XCTAssertEqual(store.upcomingSprints().count, 2)
        store.setSprint([later], .active)
        XCTAssertEqual(store.task(later)?.sprintSlot, .active)
        XCTAssertNil(store.task(later)?.laterSprint)
    }

    func testCompletionRatesWeighByExpectedTime() async {
        let (store, pid) = await makeStore()
        let big = task(store, pid, "Big", slot: .active, minutes: 180)
        task(store, pid, "Small", slot: .active, minutes: 60)
        store.setStatus(big, .done, now: now)
        let c = store.projectCompletion(pid)
        XCTAssertEqual(c.doneCount, 1)
        XCTAssertEqual(c.totalCount, 2)
        XCTAssertEqual(c.percentText, "75%", "3h of 4h, not 1 of 2 tasks")
        XCTAssertEqual(c.detail, "3h of 4h · 1 of 2 tasks")
        var canceled = store.task(big)!
        canceled.statusCategory = .canceled
        canceled.expectedMinutes = 600
        XCTAssertEqual(Completion(store.tasks(of: pid) + [canceled]), c, "canceled tasks aren't part of the work")
        XCTAssertEqual(store.sprintCompletion().percentText, "75%")
        XCTAssertEqual(Completion().percentText, "0%")
        XCTAssertEqual(Completion().detail, "No tasks yet")
    }

    func testSprintBurnupFollowsDoneAndAddedScope() async {
        let (store, pid) = await makeStore()
        let start = calendar.startOfDay(for: now)
        store.setSprintStart(date: start)
        store.setSprintLength(weeks: 1)
        let a = task(store, pid, "A", slot: .active, minutes: 120)
        let day2 = calendar.date(byAdding: .day, value: 2, to: start)!.addingTimeInterval(3600)
        store.setStatus(a, .done, now: day2)
        let burnup = store.sprintBurnup(now: day2, calendar: calendar)
        XCTAssertEqual(burnup.days.count, 3, "start to today")
        XCTAssertEqual(burnup.days.map(\.doneHours), [0, 0, 2])
        XCTAssertEqual(burnup.plannedHours, 2)
        XCTAssertEqual(burnup.days.first?.plannedHours, 2, "planned time is never below what's done")
        // The ideal pace ends at the plan on the last day
        XCTAssertEqual(burnup.idealHours(on: burnup.end, calendar: calendar), 2, accuracy: 0.001)
        XCTAssertGreaterThan(burnup.aheadHours, 0)
        // The scope log keeps the sprint's earlier plan
        XCTAssertFalse(store.workspace.sprintScope.isEmpty)
        XCTAssertTrue(store.workspace.sprintScope.allSatisfy { $0.sprint == store.sprint.number })
    }

    func testBrokenIconAndBadSettingsDecodeTolerantly() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "name": "X", "colorHex": 1, "icon": {}, "weeklyCapacityHours": -4,
         "defaultSprintSlot": "closed", "defaultExpectedMinutes": 0, "defaultView": "gantt", "usesSprints": "maybe"}
        """
        let project = try LocalJSONWorkspaceRepository.makeDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertNil(project.icon)
        XCTAssertNil(project.weeklyCapacityHours)
        XCTAssertEqual(project.defaultSprintSlot, .active)
        XCTAssertNil(project.defaultExpectedMinutes)
        XCTAssertEqual(project.defaultView, .board, "an unknown view falls back to Board")
        XCTAssertTrue(project.usesSprints)
        XCTAssertEqual(ProjectIcon.emoji(from: "🚀 go"), .emoji("🚀"))
        XCTAssertNil(ProjectIcon.emoji(from: "abc"))
    }

    // MARK: - Capacity

    func testSlotTotalsAndCapacity() async {
        let (store, pid) = await makeStore()
        let a = task(store, pid, "A", slot: .active, minutes: 240)
        task(store, pid, "B", slot: .active, minutes: 180)
        task(store, pid, "C", slot: .next, minutes: 60)
        task(store, pid, "D", slot: .backlog, minutes: 90)
        task(store, pid, "E", slot: .backlog, minutes: 30)
        store.startTimer(a, now: now)
        store.pauseTimer(a, now: hoursLater(1))

        var active = store.slotLoad(scope: .project(pid), slot: .active, now: hoursLater(2))
        XCTAssertEqual(active.count, 2)
        XCTAssertEqual(active.plannedMinutes, 420)
        XCTAssertNil(active.capacityMinutes, "no capacity yet")
        XCTAssertEqual(active.remainingMinutes, 360, "7h expected − 1h tracked")
        XCTAssertEqual(active.label, "2 tasks · 7h · 6h left")
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .backlog).label, "2 tasks · 2h")

        store.setWeeklyCapacity(pid, hours: 10)
        XCTAssertEqual(store.weeklyCapacityHours(pid), 10)
        active = store.slotLoad(scope: .project(pid), slot: .active, now: hoursLater(2))
        XCTAssertEqual(active.capacityMinutes, 1200, "10h a week × 2 weeks")
        XCTAssertEqual(active.label, "2 tasks · 7h of 20h · 6h left")
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .next).label, "1 task · 1h of 20h")
        XCTAssertNil(store.slotLoad(scope: .project(pid), slot: .backlog).capacityMinutes, "the backlog has no capacity")
        XCTAssertEqual(store.sprintPlanLine(scope: .project(pid), now: hoursLater(2)).text, "Planned 7h of 20h · tracked 1h")

        // Dragging a task between slots moves its time
        store.moveTask(a, toSlot: .next, before: nil)
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .active).plannedMinutes, 180)
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .next).plannedMinutes, 300)

        store.setWeeklyCapacity(pid, hours: nil)
        XCTAssertNil(store.project(pid)?.weeklyCapacityHours)
        store.undo()
        XCTAssertEqual(store.project(pid)?.weeklyCapacityHours, 10, "capacity changes undo")
    }

    func testOverCapacityThresholds() async {
        XCTAssertEqual(SprintPlanRules.level(plannedMinutes: 17 * 60, capacityMinutes: 20 * 60), .under, "85%")
        XCTAssertEqual(SprintPlanRules.level(plannedMinutes: 18 * 60, capacityMinutes: 20 * 60), .near, "90% turns amber")
        XCTAssertEqual(SprintPlanRules.level(plannedMinutes: 20 * 60, capacityMinutes: 20 * 60), .near, "exactly full")
        XCTAssertEqual(SprintPlanRules.level(plannedMinutes: 20 * 60 + 1, capacityMinutes: 20 * 60), .over)
        XCTAssertEqual(SprintPlanRules.level(plannedMinutes: 900, capacityMinutes: nil), .under, "no capacity, no warning")

        let (store, pid) = await makeStore()
        store.setWeeklyCapacity(pid, hours: 4)
        store.setSprintLength(weeks: 1)
        task(store, pid, "A", slot: .active, minutes: 180)
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .active).level, .under)
        task(store, pid, "B", slot: .active, minutes: 45)
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .active).level, .near, "3h 45m of 4h")
        task(store, pid, "C", slot: .active, minutes: 30)
        XCTAssertEqual(store.slotLoad(scope: .project(pid), slot: .active).level, .over)
        XCTAssertEqual(store.sprintPlanLine(scope: .project(pid)).level, .over)
    }

    func testAtRiskUsesTheProjectsCapacity() async {
        let (store, pid) = await makeStore()
        // Due Mon Nov 2: Wed, Thu, Fri, Mon = 4 working days
        let due = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: now))!
        let mid = store.addMilestone(projectId: pid, name: "Beta", dueDate: due)!
        let id = task(store, pid, "Big", slot: .active, minutes: 12 * 60)
        store.setMilestone(id, mid)
        XCTAssertEqual(store.milestoneForecast(mid, now: now)?.health, .onTrack, "12h fits 4 days × 4h")
        store.setWeeklyCapacity(pid, hours: 5)
        XCTAssertEqual(store.milestoneForecast(mid, now: now)?.health, .atRisk, "5h a week is 1h a day: 4h left")
        XCTAssertEqual(store.milestoneForecast(mid, now: now)?.hoursAvailable, 4)
        store.setWeeklyCapacity(pid, hours: 20)
        XCTAssertEqual(store.milestoneForecast(mid, now: now)?.health, .onTrack, "4h a day: 16h")
    }

    // MARK: - Past sprints and velocity

    func testCompleteSprintStoresStatsFromTheTimeLog() async {
        let (store, pid) = await makeStore()
        store.setWeeklyCapacity(pid, hours: 10)
        let a = task(store, pid, "A", slot: .active, minutes: 120)
        let b = task(store, pid, "B", slot: .active, minutes: 60)
        task(store, pid, "C", slot: .next, minutes: 30)
        store.startTimer(a, now: now)
        store.pauseTimer(a, now: hoursLater(2))
        store.startTimer(b, now: hoursLater(3))
        store.setStatus(a, .done, now: hoursLater(4))

        store.completeSprint(unfinished: .moveToNextSprint, now: hoursLater(4))
        let past = store.workspace.pastSprints[0]
        XCTAssertEqual(past.plannedMinutes, 180)
        XCTAssertEqual(past.doneMinutes, 120)
        XCTAssertEqual(past.trackedSeconds, 3 * 3600, accuracy: 1, "2h of A plus B's running hour")
        XCTAssertEqual(past.capacityHours, 20)
        XCTAssertFalse(past.isApproximate)
        XCTAssertEqual(past.statsSummary.prefix(37), "1 of 2 done · 3h planned · 3h tracked")
        XCTAssertEqual(store.velocityHistory().map(\.doneHours), [2])
        store.undo()
        XCTAssertTrue(store.workspace.pastSprints.isEmpty, "one undo step")
    }

    func testVelocitySuggestion() async {
        XCTAssertNil(SprintPlanRules.velocity(doneMinutes: []))
        XCTAssertEqual(SprintPlanRules.velocity(doneMinutes: [600]), 600)
        XCTAssertEqual(SprintPlanRules.velocity(doneMinutes: [60, 120, 180, 240]), 180, "the last three")

        let project = Project(name: "Atlas", colorHex: 0xFF6B4A)
        var past: [PastSprint] = []
        for (n, done) in [(1, 600), (2, 900), (3, 1200)] {
            past.append(PastSprint(
                number: n, startDate: now, endDate: now, completedAt: now, plannedMinutes: done + 60, doneMinutes: done))
        }
        let pid = project.id
        let store = TaskStore(repository: InMemoryWorkspaceRepository(Workspace(projects: [project], sprint: SprintState(number: 4, startDate: calendar.startOfDay(for: now)), pastSprints: past)), saveDelay: 0.05)
        await store.load()
        XCTAssertEqual(store.recentVelocityMinutes(), 900)
        let a = task(store, pid, "A", slot: .active, minutes: 300)
        store.setStatus(a, .done, now: now)
        task(store, pid, "Open", slot: .active, minutes: 240)
        XCTAssertEqual(store.recentVelocityMinutes(includingActive: true), 800, "(900 + 1200 + 300) / 3")
        task(store, pid, "N", slot: .next, minutes: 600)
        XCTAssertEqual(store.nextSprintPlanMinutes(unfinished: .moveToNextSprint), 840, "Next plus the carried-over task")
        XCTAssertEqual(store.nextSprintPlanMinutes(unfinished: .moveToBacklog), 600)
        XCTAssertEqual(store.velocityHistory().map(\.number), [1, 2, 3])
        for _ in 4...8 { store.completeSprint(now: now) }
        XCTAssertEqual(store.velocityHistory().map(\.number), [3, 4, 5, 6, 7, 8], "the chart shows the last six")
    }

    // MARK: - Projects without sprints

    func testWithoutSprintsBoardAndNextTaskUseAllOpenTasks() async {
        let (store, pid) = await makeStore()
        let backlog = task(store, pid, "Later", slot: .backlog, minutes: 60)
        let next = task(store, pid, "Soon", slot: .next, minutes: 60)
        let model = TasksViewModel()
        model.select(.project(pid))
        model.syncProjects(store)
        XCTAssertNil(store.nextTaskToStart(projectId: pid), "with sprints, the backlog isn't current work")
        XCTAssertEqual(model.tabs, [.board, .list, .sprints, .milestones])

        store.setUsesSprints(pid, false, now: now)
        model.syncProjects(store)
        XCTAssertEqual(model.tabs, [.board, .list, .milestones], "no Sprints tab")
        model.tab = .sprints
        XCTAssertEqual(model.effectiveTab, .list)
        XCTAssertEqual(Set(model.allBoardTasks(store).map(\.id)), [backlog, next], "Board shows every open task")
        XCTAssertNil(model.boardCaption(store), "no Showing Sprint 1 caption")
        XCTAssertEqual(store.nextTaskToStart(projectId: pid)?.id, backlog)
        XCTAssertEqual(Set(store.activeSprintTasks(projectId: pid).map(\.id)), [backlog, next], "menu bar")
        XCTAssertEqual(store.sprintLabel(for: store.task(next)!), "")
        XCTAssertFalse(model.availableGroupings.contains(.sprint))
        model.options.grouping = .sprint
        XCTAssertEqual(model.grouping, .status, "no grouping by sprint")
        XCTAssertFalse(model.paletteCommands(store).contains(.completeSprint))
        let card = store.projectOverview(pid, now: now)!
        XCTAssertEqual(card.sprintLine, "No sprints · 2 open")
        XCTAssertEqual(store.upNext(now: now).first?.projectId, pid)

        // New tasks are current work; sprint words stay in the title
        let added = store.quickAddTask("Plan #next", projectId: pid, now: now)!
        XCTAssertEqual(store.task(added.taskId)?.title, "Plan #next")
        XCTAssertEqual(store.task(added.taskId)?.sprintSlot, .active)
        XCTAssertEqual(store.composerSuggestions(.sprint, query: "", projectId: pid), [])

        // A done task stays on the board for two weeks
        let done = task(store, pid, "Shipped", slot: .active, minutes: 30)
        store.setStatus(done, .done, now: now)
        XCTAssertTrue(store.isOnBoard(store.task(done)!, in: .project(pid), now: now))
        XCTAssertFalse(store.isOnBoard(store.task(done)!, in: .project(pid), now: hoursLater(24 * 15)))
    }

    func testTurningSprintsBackOn() async {
        let (store, pid) = await makeStore()
        store.setUsesSprints(pid, false, now: now)
        let started = task(store, pid, "Started", slot: .active, minutes: 60)
        store.setStatus(started, .inProgress, now: now)
        let idle = task(store, pid, "Idle", slot: .active, minutes: 60)
        let running = task(store, pid, "Running", slot: .active, minutes: 60)
        store.startTimer(running, now: now)
        let pinned = task(store, pid, "Pinned", slot: .active, minutes: 60)
        store.addToToday([pinned], now: now)
        let done = task(store, pid, "Done", slot: .active, minutes: 60)
        store.setStatus(done, .done, now: now)

        let later = hoursLater(24 * 3)
        store.setUsesSprints(pid, true, now: later)
        XCTAssertTrue(store.usesSprints(pid))
        XCTAssertEqual(store.task(started)?.sprintSlot, .active)
        XCTAssertEqual(store.task(running)?.sprintSlot, .active)
        XCTAssertEqual(store.task(pinned)?.sprintSlot, .active)
        XCTAssertEqual(store.task(idle)?.sprintSlot, .backlog, "waits to be planned")
        XCTAssertEqual(store.task(done)?.sprintSlot, .active, "done tasks close with the next sprint")
        store.undo()
        XCTAssertFalse(store.usesSprints(pid))
        XCTAssertEqual(store.task(idle)?.sprintSlot, .active, "one undo step")
    }

    // MARK: - Defaults

    func testDefaultsApplyToNewTasksFromComposerAndQuickAdd() async {
        let (store, pid) = await makeStore()
        store.setDefaultSprintSlot(pid, .backlog)
        store.setDefaultExpectedMinutes(pid, 30)

        // The composer, outside a sprint group (List grouped by status)
        var draft = ComposerDraft()
        draft.apply(preset: .status(.todo), in: .project(pid))
        let fromComposer = store.addTask(title: "Composer", draft: draft, projectId: pid, now: now)!
        XCTAssertEqual(store.task(fromComposer)?.sprintSlot, .backlog)
        XCTAssertEqual(store.task(fromComposer)?.expectedMinutes, 30)

        // A sprint group still picks its own sprint; a time word its own time
        var group = ComposerDraft()
        group.apply(preset: .sprint(.next), in: .project(pid))
        group.expectedMinutes = 90
        let fromGroup = store.addTask(title: "Group", draft: group, projectId: pid, now: now)!
        XCTAssertEqual(store.task(fromGroup)?.sprintSlot, .next)
        XCTAssertEqual(store.task(fromGroup)?.expectedMinutes, 90)

        // Quick add (menu bar, global box)
        let quick = store.quickAddTask("Quick", projectId: pid, now: now)!
        XCTAssertEqual(store.task(quick.taskId)?.sprintSlot, .backlog)
        XCTAssertEqual(store.task(quick.taskId)?.expectedMinutes, 30)
        let token = store.quickAddTask("Now one #now 2h", projectId: pid, now: now)!
        XCTAssertEqual(store.task(token.taskId)?.sprintSlot, .active, "a sprint word beats the default")
        XCTAssertEqual(store.task(token.taskId)?.expectedMinutes, 120)

        store.setDefaultSprintSlot(pid, .closed)
        XCTAssertEqual(store.project(pid)?.defaultSprintSlot, .active, "a past sprint can't be a default")
        store.setDefaultExpectedMinutes(pid, nil)
        XCTAssertEqual(store.project(pid)?.newTaskExpectedMinutes, 60)
    }

    func testDefaultViewOpensTheProjectOnIt() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Bolt", now: now)!
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        model.select(.project(other))
        model.select(.project(pid))
        XCTAssertEqual(model.effectiveTab, .list, "without a default: the last tab")

        store.setDefaultView(pid, .milestones)
        model.syncProjects(store)
        model.select(.project(other))
        model.select(.project(pid))
        XCTAssertEqual(model.effectiveTab, .milestones, "a default view always wins")

        store.setDefaultView(pid, .sprints)
        store.setUsesSprints(pid, false, now: now)
        model.syncProjects(store)
        model.select(.project(pid))
        XCTAssertEqual(model.effectiveTab, .list, "no Sprints without sprints")
    }

    func testIconSetAndUndo() async {
        let (store, pid) = await makeStore()
        store.setProjectIcon(pid, .emoji("🚀"))
        XCTAssertEqual(store.project(pid)?.icon, .emoji("🚀"))
        store.setProjectIcon(pid, nil)
        XCTAssertNil(store.project(pid)?.icon)
        store.undo()
        XCTAssertEqual(store.project(pid)?.icon, .emoji("🚀"))
    }
}
