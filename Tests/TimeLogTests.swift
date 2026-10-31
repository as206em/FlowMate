import XCTest
@testable import FlowMate

/// The time log (schema 7): migration of old totals, sessions written by timers, editing entries
/// by hand, range queries, completion dates, sleep/lock handling and undo.
@MainActor
final class TimeLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeStore() async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        return (store, pid)
    }

    private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    // MARK: - Migration

    func testSchema6TotalsBecomeImportedEntriesWithoutChanging() throws {
        let pid = UUID(), a = UUID(), b = UUID(), c = UUID()
        let json = """
        {"schemaVersion": 6,
         "projects": [{"id": "\(pid.uuidString)", "name": "Old"}],
         "milestones": [],
         "tasks": [
           {"id": "\(a.uuidString)", "projectId": "\(pid.uuidString)", "title": "A", "spentSeconds": 5400,
            "statusId": "done", "statusCategory": "done", "updatedAt": "2026-10-20T12:00:00Z", "createdAt": "2026-10-01T09:00:00Z"},
           {"id": "\(b.uuidString)", "projectId": "\(pid.uuidString)", "title": "B", "spentSeconds": 0,
            "statusId": "todo", "statusCategory": "notStarted"},
           {"id": "\(c.uuidString)", "projectId": "\(pid.uuidString)", "title": "C", "spentSeconds": 90.5,
            "statusId": "inProgress", "statusCategory": "started", "updatedAt": "2026-10-21T08:00:00Z"}],
         "runningTimers": {"\(c.uuidString)": "2026-10-21T09:00:00Z"},
         "preferences": {}}
        """
        let ws = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(ws.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(ws.tasks.first { $0.id == a }?.spentSeconds ?? 0, 5400, accuracy: 0.001, "totals unchanged")
        XCTAssertEqual(ws.tasks.first { $0.id == b }?.spentSeconds, 0)
        XCTAssertEqual(ws.tasks.first { $0.id == c }?.spentSeconds ?? 0, 90.5, accuracy: 0.001)
        XCTAssertEqual(ws.timeEntries.count, 2, "one imported entry per task with time")
        let imported = ws.timeEntries(of: a)
        XCTAssertEqual(imported.map(\.source), [.imported])
        let updated = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        XCTAssertEqual(imported.first?.end, updated, "ends at the task's last update")
        XCTAssertEqual(ws.runningTimers[c], ISO8601DateFormatter().date(from: "2026-10-21T09:00:00Z"), "running timers kept")

        XCTAssertEqual(ws.tasks.first { $0.id == a }?.completedAt, updated, "done tasks are dated by their last update")
        XCTAssertNil(ws.tasks.first { $0.id == b }?.completedAt)

        // Loading again changes nothing
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(ws)
        let again = try LocalJSONWorkspaceRepository.makeDecoder().decode(Workspace.self, from: data).migrated()
        XCTAssertEqual(again.timeEntries.count, 2)
        XCTAssertEqual(again.tasks.first { $0.id == a }?.spentSeconds ?? 0, 5400, accuracy: 0.01)
    }

    // MARK: - Timers write entries

    func testPauseWritesATimerEntry() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Work", projectId: pid, now: t0)!
        store.startTimer(id, now: at(1))
        store.pauseTimer(id, now: at(2.5))
        let entries = store.timeEntries(of: id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.source, .timer)
        XCTAssertEqual(entries.first?.start, at(1))
        XCTAssertEqual(entries.first?.end, at(2.5))
        XCTAssertEqual(store.task(id)?.spentSeconds, 1.5 * 3600)

        store.startTimer(id, now: at(3))
        XCTAssertEqual(store.elapsed(id, now: at(3.5)), 2 * 3600, "entries plus the running session")
        store.stopTimer(id, at: at(3.25), now: at(4))
        XCTAssertEqual(store.timeEntries(of: id).last?.end, at(3.25), "Stop at… ends the entry there")
        XCTAssertEqual(store.task(id)?.spentSeconds, 1.75 * 3600)
    }

    func testTimerSessionSurvivesARelaunch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("workspace.json")

        let first = TaskStore(repository: LocalJSONWorkspaceRepository(fileURL: url), saveDelay: 0.01)
        await first.load()
        let pid = first.addProject(name: "P", now: t0)!
        let id = first.addTask(title: "T", projectId: pid, now: t0)!
        first.startTimer(id, now: at(1))
        await first.flush()

        // Quit and relaunch: the session goes on from its start and is recorded whole
        let second = TaskStore(repository: LocalJSONWorkspaceRepository(fileURL: url), saveDelay: 0.01)
        await second.load()
        XCTAssertEqual(second.startedAt(id), at(1))
        second.pauseTimer(id, now: at(3))
        XCTAssertEqual(second.timeEntries(of: id).map(\.start), [at(1)])
        XCTAssertEqual(second.task(id)?.spentSeconds, 2 * 3600)
    }

    // MARK: - Editing by hand

    func testEditAndDeleteEntriesUpdateTotalsAndUndo() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Work", projectId: pid, now: t0)!
        store.startTimer(id, now: at(1))
        store.pauseTimer(id, now: at(2))
        let entry = store.timeEntries(of: id)[0]
        store.clearUndoHistory()

        XCTAssertEqual(store.updateTimeEntry(entry.id, start: at(1), end: at(0.5), now: at(5)), .endNotAfterStart)
        XCTAssertEqual(store.updateTimeEntry(entry.id, start: at(1), end: at(6), now: at(5)), .endInFuture)
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600, "refused edits change nothing")

        XCTAssertNil(store.updateTimeEntry(entry.id, start: at(0.5), end: at(2), now: at(5)))
        XCTAssertEqual(store.task(id)?.spentSeconds, 1.5 * 3600)
        XCTAssertEqual(store.undoActionName, "Edit time")
        store.undo(now: at(5))
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600, "undo restores the session")
        store.redo(now: at(5))
        XCTAssertEqual(store.task(id)?.spentSeconds, 1.5 * 3600)

        store.deleteTimeEntry(entry.id, now: at(5))
        XCTAssertEqual(store.task(id)?.spentSeconds, 0)
        XCTAssertTrue(store.timeEntries(of: id).isEmpty)
        store.undo(now: at(5))
        XCTAssertEqual(store.timeEntries(of: id).map(\.id), [entry.id])
        XCTAssertEqual(store.task(id)?.spentSeconds, 1.5 * 3600)
    }

    func testAddTimeByHand() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Meeting", projectId: pid, now: t0)!
        guard case let .success(entryId) = store.addTimeEntry(taskId: id, start: at(1), end: at(1.75), note: "  Planning  ", now: at(4)) else {
            return XCTFail("adds")
        }
        XCTAssertEqual(store.timeEntry(entryId)?.source, .manual)
        XCTAssertEqual(store.timeEntry(entryId)?.note, "Planning", "notes are trimmed")
        XCTAssertEqual(store.task(id)?.spentSeconds, 45 * 60)
        XCTAssertEqual(store.undoActionName, "Add time")

        if case .success = store.addTimeEntry(taskId: id, start: at(5), end: at(6), now: at(4)) { XCTFail("no future time") }
        if case .success = store.addTimeEntry(taskId: id, start: at(2), end: at(2), now: at(4)) { XCTFail("needs a length") }

        store.undo(now: at(4))
        XCTAssertEqual(store.task(id)?.spentSeconds, 0)
    }

    func testAdjustTimeEditsTheLogAndUndoKeepsLaterSessions() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Forgot", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        store.pauseTimer(id, now: at(5))
        store.clearUndoHistory()
        var clock = at(6)
        store.clock = { clock }

        // Less time: cut from the latest session
        store.setTimeSpent(id, seconds: 3600, now: at(6))
        clock = at(7)
        XCTAssertEqual(store.timeEntries(of: id).map(\.end), [at(1)])
        // More time: a manual entry ending now
        store.adjustTimeSpent(id, by: 15 * 60, now: at(7))
        XCTAssertEqual(store.timeEntries(of: id).last?.source, .manual)
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600 + 15 * 60)

        // A timer session after the edit survives undoing it
        store.startTimer(id, now: at(8))
        store.pauseTimer(id, now: at(9))
        store.undo(now: at(9))
        XCTAssertEqual(store.task(id)?.spentSeconds, 2 * 3600, "the +15m goes, the new session stays")
        store.undo(now: at(9))
        XCTAssertEqual(store.task(id)?.spentSeconds, 6 * 3600, "the cut comes back")
    }

    func testCuttingIntoARunningSessionRecordsIt() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "Long", projectId: pid, now: t0)!
        store.startTimer(id, now: t0)
        store.setTimeSpent(id, seconds: 1800, now: at(2))
        XCTAssertTrue(store.isRunning(id), "the timer keeps running")
        XCTAssertEqual(store.elapsed(id, now: at(2)), 1800)
        XCTAssertEqual(store.elapsed(id, now: at(3)), 1800 + 3600)
    }

    func testDeleteDuplicateAndMoveTasks() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let id = store.addTask(title: "Work", projectId: pid, now: t0)!
        store.addTimeEntry(taskId: id, start: at(1), end: at(2), now: at(3))

        let copy = store.duplicateTask(id, now: at(3))!
        XCTAssertTrue(store.timeEntries(of: copy).isEmpty, "a duplicate has no time")
        XCTAssertEqual(store.task(copy)?.spentSeconds, 0)

        store.setProject(id, other)
        XCTAssertEqual(store.timeEntries(of: id).count, 1, "moving keeps entries")
        XCTAssertEqual(store.trackedSeconds(.project(other), in: DateInterval(start: t0, end: at(5)), now: at(5)), 3600)
        XCTAssertEqual(store.trackedSeconds(.project(pid), in: DateInterval(start: t0, end: at(5)), now: at(5)), 0)

        store.deleteTask(id)
        XCTAssertTrue(store.workspace.timeEntries.allSatisfy { $0.taskId != id }, "deleting removes entries")
        store.undo(now: at(5))
        XCTAssertEqual(store.timeEntries(of: id).count, 1, "undo brings them back")
        XCTAssertEqual(store.task(id)?.spentSeconds, 3600)
    }

    // MARK: - Queries

    func testRangeQueriesAcrossMidnight() async {
        let (store, pid) = await makeStore()
        let milestone = store.addMilestone(projectId: pid, name: "M1")!
        let a = store.addTask(title: "A", projectId: pid, milestoneId: milestone, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let day = utc.startOfDay(for: t0)
        let midnight = utc.date(byAdding: .day, value: 1, to: day)!
        // 23:00 → 01:30 the next day
        store.addTimeEntry(taskId: a, start: midnight.addingTimeInterval(-3600), end: midnight.addingTimeInterval(5400), now: midnight.addingTimeInterval(86_400))
        // Running on B since 01:00
        store.startTimer(b, now: midnight.addingTimeInterval(3600))
        let now = midnight.addingTimeInterval(3 * 3600)

        let first = DateInterval(start: day, end: midnight)
        let second = DateInterval(start: midnight, end: midnight.addingTimeInterval(86_400))
        XCTAssertEqual(store.trackedSeconds(in: first, now: now), 3600)
        XCTAssertEqual(store.trackedSeconds(in: second, now: now), 5400 + 2 * 3600, "running session counts up to now")
        XCTAssertEqual(store.trackedSeconds(.task(a), in: second, now: now), 5400)
        XCTAssertEqual(store.trackedSecondsByMilestone(in: second, now: now)[milestone], 5400)
        XCTAssertEqual(store.trackedSecondsByProject(in: first, now: now)[pid], 3600)
        XCTAssertEqual(store.trackedSecondsByTask(in: second, now: now), [a: 5400, b: 7200])

        let days = store.trackedSecondsByDay(in: DateInterval(start: day, end: second.end), calendar: utc, now: now)
        XCTAssertEqual(days.map(\.day), [day, midnight])
        XCTAssertEqual(days.map(\.seconds), [3600, 5400 + 7200])
        XCTAssertEqual(store.trackedToday(now: now, calendar: utc), 5400 + 7200)
    }

    func testTrackedInSprint() async {
        let (store, pid) = await makeStore()
        let id = store.addTask(title: "A", projectId: pid, now: t0)!
        let sprint = store.sprint
        store.addTimeEntry(taskId: id, start: sprint.startDate.addingTimeInterval(3600), end: sprint.startDate.addingTimeInterval(7200), now: at(500))
        store.addTimeEntry(taskId: id, start: sprint.startDate.addingTimeInterval(-7200), end: sprint.startDate.addingTimeInterval(-3600), now: at(500))
        XCTAssertEqual(store.trackedInSprint(projectId: pid, now: at(500)), 3600, "only the sprint's days")
    }

    // MARK: - Completion date

    func testCompletedAtSetOnCloseAndClearedOnReopen() async {
        let (store, pid) = await makeStore()
        store.applyWorkflowPreset(projectId: pid, .dev, now: t0)
        let id = store.addTask(title: "A", projectId: pid, now: t0)!
        XCTAssertNil(store.task(id)?.completedAt)
        store.setCategory(id, .done, now: at(2))
        XCTAssertEqual(store.task(id)?.completedAt, at(2))
        store.setCategory(id, .canceled, now: at(3))
        XCTAssertEqual(store.task(id)?.completedAt, at(2), "stays closed: keeps the date")
        XCTAssertEqual(store.task(id)?.statusCategory, .canceled)
        store.setCategory(id, .notStarted, now: at(4))
        XCTAssertNil(store.task(id)?.completedAt, "reopened")
        store.undo(now: at(5))
        XCTAssertEqual(store.task(id)?.completedAt, at(2))
    }

    // MARK: - Sleep and lock

    func testDiscardSleepTimeSplitsTheSession() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.startTimer(a, now: at(1))
        store.startTimer(b, now: at(1))
        store.systemWillSleep(at: at(2))
        store.systemDidWake(at: at(4))
        XCTAssertEqual(store.awayGaps.count, 1)
        XCTAssertEqual(store.awayDuration, 2 * 3600)
        XCTAssertEqual(Set(store.awayTasks.map(\.id)), [a, b])

        // B was stopped after waking, before the answer: its entry is cut the same way
        store.pauseTimer(b, now: at(5))
        store.clearUndoHistory()
        store.discardAwayTime()
        XCTAssertTrue(store.awayGaps.isEmpty)
        XCTAssertEqual(store.timeEntries(of: a).map(\.end), [at(2)], "the entry ends when the Mac slept")
        XCTAssertEqual(store.startedAt(a), at(4), "the timer goes on from wake")
        XCTAssertEqual(store.elapsed(a, now: at(5)), 2 * 3600)
        XCTAssertEqual(store.timeEntries(of: b).map(\.start), [at(1), at(4)])
        XCTAssertEqual(store.task(b)?.spentSeconds, 2 * 3600)

        store.undo(now: at(5))
        XCTAssertEqual(store.startedAt(a), at(1), "undo puts the sleep time back")
        XCTAssertEqual(store.elapsed(a, now: at(5)), 4 * 3600)
        XCTAssertEqual(store.task(b)?.spentSeconds, 4 * 3600)
        XCTAssertEqual(store.timeEntries(of: a).count, 0)
    }

    func testShortSleepOrNoTimersDoesNotAsk() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.systemWillSleep(at: at(1))
        store.systemDidWake(at: at(3))
        XCTAssertTrue(store.awayGaps.isEmpty, "no timers ran")

        store.startTimer(a, now: at(3))
        store.systemWillSleep(at: at(4))
        store.systemDidWake(at: at(4).addingTimeInterval(120))
        XCTAssertTrue(store.awayGaps.isEmpty, "two minutes is too short to ask")

        store.systemWillSleep(at: at(5))
        store.systemDidWake(at: at(6))
        store.keepAwayTime()
        XCTAssertTrue(store.awayGaps.isEmpty)
        XCTAssertEqual(store.elapsed(a, now: at(6)), 3 * 3600, "Keep counts the time")
    }

    func testLockThenSleepEndsAtUnlock() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        store.startTimer(a, now: at(1))
        store.screenDidLock(at: at(2))
        store.systemWillSleep(at: at(2.1))
        store.systemDidWake(at: at(8))
        XCTAssertTrue(store.awayGaps.isEmpty, "waking to the lock screen isn't being back")
        store.screenDidUnlock(at: at(8.5))
        XCTAssertEqual(store.awayGaps.first?.start, at(2))
        XCTAssertEqual(store.awayGaps.first?.end, at(8.5))
        XCTAssertEqual(store.awayGaps.first?.kind, .sleep)
    }
}
