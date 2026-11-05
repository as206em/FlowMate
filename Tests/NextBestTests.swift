import XCTest
@testable import FlowMate

/// Task types, the sprint's Make / Reach mix and Next best: the 0–100 score, Send up / down / to
/// top / Back to normal, Keep warm, the ^type word and the schema 14 migration.
@MainActor
final class NextBestTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)
    private var build: UUID { TaskType.defaults[0].id }
    private var customers: UUID { TaskType.defaults[1].id }
    private var sales: UUID { TaskType.defaults[2].id }

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Atlas", now: t0)!
        store.clearUndoHistory()
        return (store, pid)
    }

    private func task(_ store: TaskStore, _ title: String, _ pid: UUID, minutes: Int = 30, now: Date? = nil) -> UUID {
        let id = store.addTask(title: title, projectId: pid, sprintSlot: .active, now: now ?? t0)!
        store.setExpectedMinutes(id, minutes)
        return id
    }

    // MARK: - Rules

    func testEffortFactorSteps() {
        XCTAssertEqual(ImpactRules.effortFactor(minutesLeft: 30), 1.0)
        XCTAssertEqual(ImpactRules.effortFactor(minutesLeft: 31), 0.9)
        XCTAssertEqual(ImpactRules.effortFactor(minutesLeft: 120), 0.8)
        XCTAssertEqual(ImpactRules.effortFactor(minutesLeft: 240), 0.7)
        XCTAssertEqual(ImpactRules.effortFactor(minutesLeft: 241), 0.6)
        XCTAssertEqual(ImpactRules.base(impact: 9, minutesLeft: 30), 90)
        XCTAssertEqual(ImpactRules.base(impact: 9, minutesLeft: 240), 63)
    }

    func testScoreIsClampedTo0Through100() {
        XCTAssertEqual(ImpactRules.score(base: 95, boost: 5, nudge: 30), 100)
        XCTAssertEqual(ImpactRules.score(base: 10, boost: 0, nudge: -45), 0)
    }

    func testImpactAveragesWithTheType() {
        XCTAssertEqual(ImpactRules.impact(inherited: 5, typeImpact: 9), 7)
        XCTAssertEqual(ImpactRules.impact(inherited: 6, typeImpact: 9), 8, "7.5 rounds up")
        XCTAssertEqual(ImpactRules.impact(inherited: 4, typeImpact: nil), 4)
    }

    func testNudgeStepsGrowAndTheOtherDirectionTakesBackTheLastStep() {
        var state = (nudge: 0, run: 0)
        state = ImpactRules.press(up: true, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, 5)
        state = ImpactRules.press(up: true, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, 15)
        state = ImpactRules.press(up: true, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, 30)
        state = ImpactRules.press(up: true, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, 45, "15 from the third press on")
        state = ImpactRules.press(up: false, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, 30, "down takes back the last 15")
        state = ImpactRules.press(up: false, nudge: state.nudge, run: state.run)
        state = ImpactRules.press(up: false, nudge: state.nudge, run: state.run)
        state = ImpactRules.press(up: false, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, 0)
        XCTAssertEqual(state.run, 0)
        state = ImpactRules.press(up: false, nudge: state.nudge, run: state.run)
        XCTAssertEqual(state.nudge, -5, "a fresh run downward")
    }

    func testCadenceFollowsProjectImpact() {
        XCTAssertEqual(ImpactRules.cadenceDays(impact: 10), 1)
        XCTAssertEqual(ImpactRules.cadenceDays(impact: 7), 3)
        XCTAssertEqual(ImpactRules.cadenceDays(impact: 5), 7)
        XCTAssertEqual(ImpactRules.cadenceDays(impact: 1), 14)
    }

    // MARK: - Mix

    func testMixSplitsPlannedTimeByBucketAndFlagsTheLightOne() async {
        let (store, pid) = await makeStore()
        let a = task(store, "Refactor", pid, minutes: 240)
        let b = task(store, "Call 3 users", pid, minutes: 60)
        _ = task(store, "Untyped", pid, minutes: 30)
        store.setType([a], build)
        store.setType([b], customers)
        var mix = store.sprintMix()
        XCTAssertEqual(mix.makeMinutes, 240)
        XCTAssertEqual(mix.reachMinutes, 60)
        XCTAssertEqual(mix.untypedMinutes, 30)
        XCTAssertEqual(mix.reachPercent, 20)
        XCTAssertNil(mix.behind, "no target, no warning")
        store.setReachTarget(50)
        mix = store.sprintMix()
        XCTAssertEqual(mix.behind, .reach)
        XCTAssertEqual(mix.warning, "Reach is light")
        store.setReachTarget(30)
        XCTAssertNil(store.sprintMix().behind, "within 10 points")
    }

    // MARK: - Ranking

    func testRankingUsesImpactEffortAndTheMixBoost() async {
        let (store, pid) = await makeStore()
        store.setProjectImpact(pid, 6)
        let big = task(store, "Big build", pid, minutes: 480)
        let small = task(store, "Email a lead", pid, minutes: 30)
        store.setType([big], build)
        store.setType([small], sales)
        store.setReachTarget(50)
        let list = store.nextBest(now: t0)
        XCTAssertEqual(list.ranked.map(\.task.id), [small, big])
        let top = list.ranked[0].score
        // (6 + 9) / 2 = 7.5 → 8; 8 × 10 × 1.0 = 80; Reach is light: +5
        XCTAssertEqual(top.impact, 8)
        XCTAssertEqual(top.base, 80)
        XCTAssertEqual(top.boost, 5)
        XCTAssertEqual(top.score, 85)
        XCTAssertEqual(list.ranked[1].score.score, 36, "(6 + 5) / 2 = 5.5 → 6; 60 × 0.6 for 8h; Make gets no boost")
    }

    func testTaskImpactOverridesMilestoneWhichOverridesProject() async {
        let (store, pid) = await makeStore()
        store.setProjectImpact(pid, 3)
        let mid = store.addMilestone(projectId: pid, name: "Launch")!
        store.setMilestoneImpact(mid, 8)
        let id = task(store, "Landing page", pid)
        XCTAssertEqual(store.ownOrInheritedImpact(store.task(id)!).value, 3)
        store.setMilestone(id, mid)
        XCTAssertEqual(store.ownOrInheritedImpact(store.task(id)!).source, "milestone")
        XCTAssertEqual(store.ownOrInheritedImpact(store.task(id)!).value, 8)
        store.setTaskImpact([id], 10)
        XCTAssertEqual(store.ownOrInheritedImpact(store.task(id)!).value, 10)
        store.setTaskImpact([id], nil)
        XCTAssertEqual(store.ownOrInheritedImpact(store.task(id)!).value, 8)
    }

    func testCandidatesLeaveOutWhatTodayAlreadyShowsAndOtherSprints() async {
        let (store, pid) = await makeStore()
        let plain = task(store, "Plain", pid)
        let pinned = task(store, "Pinned", pid)
        let due = task(store, "Due", pid)
        let backlog = store.addTask(title: "Backlog", projectId: pid, sprintSlot: .backlog, now: t0)!
        store.addToToday([pinned], now: t0)
        store.setDueDate(due, t0)
        _ = backlog
        XCTAssertEqual(store.nextBestCandidates(now: t0).map(\.id), [plain])
    }

    func testSendToTopPinsForTheDayAndBackToNormalClearsIt() async {
        let (store, pid) = await makeStore()
        store.setProjectImpact(pid, 9)
        let high = task(store, "High", pid)
        let low = task(store, "Low", pid)
        store.setTaskImpact([low], 1)
        XCTAssertEqual(store.nextBest(now: t0).ranked.first?.task.id, high)
        store.sendToTop(low, now: t0)
        XCTAssertEqual(store.nextBest(now: t0).ranked.first?.task.id, low)
        let tomorrow = t0.addingTimeInterval(86_400)
        XCTAssertEqual(store.nextBest(now: tomorrow).ranked.first?.task.id, high, "a pin expires with the day")
        store.resetNextBest(low)
        XCTAssertFalse(store.task(low)!.isNudged)
    }

    func testSendUpMovesTheScoreAndUndoes() async {
        let (store, pid) = await makeStore()
        let id = task(store, "Task", pid)
        let before = store.nextBestScore(store.task(id)!, now: t0).score
        store.sendNextBest(id, up: true)
        store.sendNextBest(id, up: true)
        XCTAssertEqual(store.nextBestScore(store.task(id)!, now: t0).score, min(100, before + 15))
        store.undo()
        XCTAssertEqual(store.task(id)!.nudge, 5)
    }

    func testClosingATaskClearsItsNudge() async {
        let (store, pid) = await makeStore()
        let id = task(store, "Task", pid)
        store.sendNextBest(id, up: true)
        store.sendToTop(id, now: t0)
        store.setCategory(id, .done, now: t0)
        XCTAssertEqual(store.task(id)!.nudge, 0)
        XCTAssertNil(store.task(id)!.topPinnedAt)
    }

    func testCompletingTheSprintClearsNudges() async {
        let (store, pid) = await makeStore()
        let id = task(store, "Carry over", pid)
        store.sendNextBest(id, up: false)
        store.completeSprint(unfinished: .moveToNextSprint, now: t0)
        XCTAssertEqual(store.task(id)!.nudge, 0)
        XCTAssertEqual(store.task(id)!.nudgeRun, 0)
    }

    // MARK: - Sprint planning

    private func backlog(_ store: TaskStore, _ title: String, _ pid: UUID, minutes: Int) -> UUID {
        let id = store.addTask(title: title, projectId: pid, sprintSlot: .backlog, now: t0)!
        store.setExpectedMinutes(id, minutes)
        return id
    }

    func testFillToCapacityTakesTheBestThatFit() async {
        let (store, pid) = await makeStore()
        store.setWeeklyCapacity(pid, hours: 1)  // 2h in a 2-week sprint
        let best = backlog(store, "Best", pid, minutes: 60)
        let low = backlog(store, "Low", pid, minutes: 60)
        let big = backlog(store, "Big", pid, minutes: 90)
        store.setTaskImpact([best], 9)
        store.setTaskImpact([low], 2)
        store.setTaskImpact([big], 8)
        let moved = store.fillSprintToCapacity(now: t0)
        XCTAssertEqual(moved, [best, low], "Big no longer fits after Best")
        XCTAssertEqual(store.task(big)!.sprintSlot, .backlog)
        store.undo()
        XCTAssertEqual(store.task(best)!.sprintSlot, .backlog, "one undo step")
    }

    func testFillToCapacityRebalancesTheMix() async {
        let (store, pid) = await makeStore()
        store.setWeeklyCapacity(pid, hours: 1)
        store.setReachTarget(50)
        let a = backlog(store, "Build A", pid, minutes: 30)
        let b = backlog(store, "Build B", pid, minutes: 30)
        let sell = backlog(store, "Sell", pid, minutes: 30)
        store.setType([a, b], build)
        store.setType([sell], sales)
        store.setTaskImpact([a, b], 10)
        store.setTaskImpact([sell], 4)
        // Build A: (10+5)/2 → 8 → 80. Sell: (4+9)/2 → 7 → 70, +5 once Reach is behind
        let moved = store.fillSprintToCapacity(now: t0)
        XCTAssertEqual(moved.first, a)
        XCTAssertEqual(moved.count, 3)
    }

    func testFillToCapacityNeedsACapacity() async {
        let (store, pid) = await makeStore()
        _ = backlog(store, "Idea", pid, minutes: 30)
        XCTAssertTrue(store.fillSprintToCapacity(now: t0).isEmpty)
    }

    func testSortByScoreOrdersTheBacklog() async {
        let (store, pid) = await makeStore()
        let low = backlog(store, "Low", pid, minutes: 30)
        let high = backlog(store, "High", pid, minutes: 30)
        store.setTaskImpact([low], 2)
        store.setTaskImpact([high], 9)
        store.sortByScore(slot: .backlog, now: t0)
        XCTAssertEqual(store.sprintTasks(slot: .backlog).map(\.id), [high, low])
    }

    // MARK: - Keep warm

    func testKeepWarmListsAProjectPastItsCadence() async {
        let (store, main) = await makeStore()
        store.setProjectImpact(main, 10)
        _ = task(store, "Main work", main)
        let side = store.addProject(name: "Orbit", now: t0.addingTimeInterval(-30 * 86_400))!
        store.setProjectImpact(side, 2)
        let old = t0.addingTimeInterval(-20 * 86_400)
        let sideTask = store.addTask(title: "Reply to user", projectId: side, sprintSlot: .active, now: old)!
        let list = store.nextBest(shown: 1, now: t0)
        XCTAssertEqual(list.keepWarm.map(\.task.id), [sideTask])
        XCTAssertEqual(list.keepWarm.first?.keepWarm?.hasPrefix("Orbit untouched 20 days"), true)
        XCTAssertTrue(store.nextBest(shown: 5, now: t0).keepWarm.isEmpty, "already visible in the ranking")
    }

    // MARK: - Types and words

    func testCaretWordSetsTheTypeAndUnknownStaysInTitle() async {
        let (store, pid) = await makeStore()
        let outcome = store.quickAddTask("Call Sam ^customers", projectId: pid, now: t0)!
        let added = store.task(outcome.taskId)!
        XCTAssertEqual(added.title, "Call Sam")
        XCTAssertEqual(added.typeId, customers)
        let other = store.quickAddTask("Fix ^nope", projectId: pid, now: t0)!
        XCTAssertEqual(store.task(other.taskId)!.title, "Fix ^nope")
        XCTAssertNil(store.task(other.taskId)!.typeId)
    }

    func testProjectDefaultTypeAppliesToNewTasks() async {
        let (store, pid) = await makeStore()
        store.setProjectDefaultType(pid, sales)
        XCTAssertEqual(store.task(task(store, "Pitch", pid))!.typeId, sales)
    }

    func testDeletingATypeUntypesItsTasksAndUndoBringsItBack() async {
        let (store, pid) = await makeStore()
        let id = task(store, "Post", pid)
        store.setType([id], sales)
        store.setProjectDefaultType(pid, sales)
        store.deleteTaskType(sales)
        XCTAssertNil(store.task(id)!.typeId)
        XCTAssertNil(store.project(pid)!.defaultTypeId)
        store.undo()
        XCTAssertEqual(store.task(id)!.typeId, sales)
    }

    func testTypeNamesAreUnique() async {
        let (store, _) = await makeStore()
        XCTAssertNil(store.addTaskType("sales"))
        XCTAssertNotNil(store.addTaskType("Support", bucket: .reach))
        XCTAssertFalse(store.renameTaskType(build, to: "Support"))
    }

    // MARK: - Migration

    func testSchema13FileGetsDefaultTypesAndRoundTrips() throws {
        let pid = UUID(), tid = UUID()
        let json = """
        {"schemaVersion":13,
         "projects":[{"id":"\(pid)","name":"Atlas","colorHex":16739146}],
         "milestones":[],
         "tasks":[{"id":"\(tid)","projectId":"\(pid)","title":"Old","statusId":"todo","statusCategory":"notStarted"}],
         "runningTimers":{}, "timeEntries":[]}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated(now: t0)
        XCTAssertEqual(ws.schemaVersion, 14)
        XCTAssertEqual(ws.taskTypes, TaskType.defaults)
        XCTAssertNil(ws.tasks[0].typeId)
        XCTAssertEqual(ws.tasks[0].nudge, 0)
        XCTAssertNil(ws.projects[0].impact)
        XCTAssertNil(ws.sprint.reachTargetPercent)

        var changed = ws
        changed.tasks[0].typeId = TaskType.defaults[1].id
        changed.tasks[0].impact = 8
        changed.tasks[0].nudge = 15
        changed.tasks[0].nudgeRun = 2
        changed.projects[0].impact = 9
        changed.sprint.reachTargetPercent = 40
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(changed)
        let back = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: data).migrated(now: t0)
        XCTAssertEqual(back.tasks[0].typeId, TaskType.defaults[1].id)
        XCTAssertEqual(back.tasks[0].impact, 8)
        XCTAssertEqual(back.tasks[0].nudge, 15)
        XCTAssertEqual(back.projects[0].impact, 9)
        XCTAssertEqual(back.sprint.reachTargetPercent, 40)
    }

    func testSchema14FileWithEveryTypeDeletedStaysEmpty() throws {
        let json = """
        {"schemaVersion":14, "projects":[], "milestones":[], "tasks":[], "runningTimers":{}, "timeEntries":[], "taskTypes":[]}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated(now: t0)
        XCTAssertTrue(ws.taskTypes.isEmpty)
    }
}
