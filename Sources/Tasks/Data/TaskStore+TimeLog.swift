import Foundation

// The time log: each task's sessions (TimeEntry), editing them by hand, and the queries other
// views read (time tracked in a date range, per project, milestone, task or day, today, in a sprint).
// A task's total is always the sum of its entries plus its running session.

/// Why a session's times were refused.
enum TimeEntryProblem: Error, Equatable, Sendable {
    case endNotAfterStart
    case endInFuture
    case taskMissing

    var message: String {
        switch self {
        case .endNotAfterStart: return "The end must be after the start."
        case .endInFuture: return "The end can't be in the future."
        case .taskMissing: return "The task no longer exists."
        }
    }
}

/// What a time query counts.
enum TimeScope: Hashable, Sendable {
    case all
    case project(UUID)
    case milestone(UUID)
    case task(UUID)
    case tasks(Set<UUID>)
}

/// A stretch of tracked time: a stored entry, or the running session (`entryId` nil, ends now).
struct TrackedSpan: Equatable, Sendable {
    let taskId: UUID
    let entryId: UUID?
    let start: Date
    let end: Date

    var isRunning: Bool { entryId == nil }
    func seconds(in range: DateInterval) -> TimeInterval { TimeEntry.overlap(start, end, range) }
}

// MARK: - Editing

extension TaskStore {
    /// A small allowance for clocks: an end a few seconds ahead of now still counts as now.
    static let futureTolerance: TimeInterval = 5

    /// The task's sessions, oldest first (the running one isn't an entry yet).
    func timeEntries(of taskId: UUID) -> [TimeEntry] {
        workspace.timeEntries(of: taskId)
    }

    func timeEntry(_ id: UUID) -> TimeEntry? {
        workspace.timeEntries.first { $0.id == id }
    }

    /// Checks a session's times: the end after the start, and not in the future.
    static func validate(start: Date, end: Date, now: Date) -> TimeEntryProblem? {
        if end <= start { return .endNotAfterStart }
        if end > now.addingTimeInterval(futureTolerance) { return .endInFuture }
        return nil
    }

    /// "Add time…": a session added by hand. One undo step. Returns the entry's id, or the problem.
    @discardableResult
    func addTimeEntry(taskId: UUID, start: Date, end: Date, note: String? = nil,
                      source: TimeEntrySource = .manual, now: Date = Date()) -> Result<UUID, TimeEntryProblem> {
        guard task(taskId) != nil else { return .failure(.taskMissing) }
        if let problem = Self.validate(start: start, end: end, now: now) { return .failure(problem) }
        let entry = TimeEntry(taskId: taskId, start: start, end: min(end, now), note: note, source: source)
        mutate("Add time") { ws in
            ws.timeEntries.append(entry)
            if let i = ws.tasks.firstIndex(where: { $0.id == taskId }) { ws.tasks[i].updatedAt = now }
        }
        return .success(entry.id)
    }

    /// Changes a session's start and end. One undo step. Returns the problem when refused.
    @discardableResult
    func updateTimeEntry(_ id: UUID, start: Date, end: Date, now: Date = Date()) -> TimeEntryProblem? {
        guard let entry = timeEntry(id) else { return .taskMissing }
        if let problem = Self.validate(start: start, end: end, now: now) { return problem }
        guard entry.start != start || entry.end != min(end, now) else { return nil }
        editEntry(id, action: "Edit time", now: now) { entry in
            entry.start = start
            entry.end = min(end, now)
        }
        return nil
    }

    /// A session's note; quick typing shares one undo step.
    func setTimeEntryNote(_ id: UUID, _ note: String?, now: Date = Date()) {
        editEntry(id, action: "Edit time note", coalesce: "entry-note-\(id)", now: now) { $0.note = TimeEntry.cleaned(note) }
    }

    /// Deletes a session; the task's total drops by its length. One undo step.
    func deleteTimeEntry(_ id: UUID, now: Date = Date()) {
        guard let entry = timeEntry(id) else { return }
        mutate("Delete time") { ws in
            ws.timeEntries.removeAll { $0.id == id }
            if let i = ws.tasks.firstIndex(where: { $0.id == entry.taskId }) { ws.tasks[i].updatedAt = now }
        }
    }

    private func editEntry(_ id: UUID, action: String, coalesce: String? = nil, now: Date, _ change: (inout TimeEntry) -> Void) {
        mutate(action, coalesce: coalesce) { ws in
            guard let e = ws.timeEntries.firstIndex(where: { $0.id == id }) else { return }
            var entry = ws.timeEntries[e]
            change(&entry)
            guard entry != ws.timeEntries[e] else { return }
            ws.timeEntries[e] = entry
            if let i = ws.tasks.firstIndex(where: { $0.id == entry.taskId }) { ws.tasks[i].updatedAt = now }
        }
    }
}

// MARK: - Queries

extension TaskStore {
    /// Every tracked stretch of the tasks in `scope`: their entries, plus running sessions up to
    /// `now`. Project and milestone follow where each task is now (entries move with their task).
    func trackedSpans(_ scope: TimeScope = .all, now: Date = Date()) -> [TrackedSpan] {
        let include = taskFilter(scope)
        var spans = workspace.timeEntries.filter { include($0.taskId) }.map {
            TrackedSpan(taskId: $0.taskId, entryId: $0.id, start: $0.start, end: $0.end)
        }
        for (id, started) in workspace.runningTimers where include(id) && now > started {
            spans.append(TrackedSpan(taskId: id, entryId: nil, start: started, end: now))
        }
        return spans
    }

    /// Seconds tracked inside `range` (spans are clipped to it, so a session across midnight
    /// counts on both days).
    func trackedSeconds(_ scope: TimeScope = .all, in range: DateInterval, now: Date = Date()) -> TimeInterval {
        trackedSpans(scope, now: now).reduce(0) { $0 + $1.seconds(in: range) }
    }

    /// Seconds tracked inside `range` per task (tasks with none are left out).
    func trackedSecondsByTask(_ scope: TimeScope = .all, in range: DateInterval, now: Date = Date()) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for span in trackedSpans(scope, now: now) {
            let seconds = span.seconds(in: range)
            if seconds > 0 { result[span.taskId, default: 0] += seconds }
        }
        return result
    }

    /// Seconds tracked inside `range` per project.
    func trackedSecondsByProject(in range: DateInterval, now: Date = Date()) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for (taskId, seconds) in trackedSecondsByTask(in: range, now: now) {
            guard let projectId = task(taskId)?.projectId else { continue }
            result[projectId, default: 0] += seconds
        }
        return result
    }

    /// Seconds tracked inside `range` per milestone (tasks without one are left out).
    func trackedSecondsByMilestone(_ scope: TimeScope = .all, in range: DateInterval, now: Date = Date()) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for (taskId, seconds) in trackedSecondsByTask(scope, in: range, now: now) {
            guard let milestoneId = task(taskId)?.milestoneId else { continue }
            result[milestoneId, default: 0] += seconds
        }
        return result
    }

    /// One value per calendar day of `range` (midnight of the day → seconds), days without time
    /// included as 0, in order.
    func trackedSecondsByDay(_ scope: TimeScope = .all, in range: DateInterval, calendar: Calendar = .current,
                             now: Date = Date()) -> [(day: Date, seconds: TimeInterval)] {
        let spans = trackedSpans(scope, now: now)
        var result: [(day: Date, seconds: TimeInterval)] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let window = DateInterval(start: max(day, range.start), end: max(max(day, range.start), min(next, range.end)))
            result.append((day, spans.reduce(0) { $0 + $1.seconds(in: window) }))
            day = next
        }
        return result
    }

    /// The calendar day containing `date`.
    nonisolated static func dayInterval(_ date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// Whole days from `first` to `last`, both included (sprint dates are days).
    nonisolated static func days(_ first: Date, through last: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: first)
        let end = dayInterval(max(first, last), calendar: calendar).end
        return DateInterval(start: start, end: max(start, end))
    }

    /// Seconds tracked today (running timers included).
    func trackedToday(_ scope: TimeScope = .all, now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        trackedSeconds(scope, in: Self.dayInterval(now, calendar: calendar), now: now)
    }

    /// The active sprint's days, start to end.
    func sprintInterval(calendar: Calendar = .current) -> DateInterval {
        Self.days(workspace.sprint.startDate, through: workspace.sprint.endDate, calendar: calendar)
    }

    /// Seconds tracked during the active sprint's dates: on one project's tasks, or on all tasks
    /// of the projects in the sprint when `projectId` is nil.
    func trackedInSprint(projectId: UUID? = nil, now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        trackedSeconds(sprintTimeScope(projectId), in: sprintInterval(calendar: calendar), now: now)
    }

    /// Seconds tracked during a past sprint's dates (see `trackedInSprint(projectId:)`).
    func trackedInSprint(_ sprint: PastSprint, projectId: UUID? = nil, now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        trackedSeconds(sprintTimeScope(projectId), in: Self.days(sprint.startDate, through: sprint.endDate, calendar: calendar), now: now)
    }

    /// The time-log scope of a sprint number: one project, or every project that takes part.
    private func sprintTimeScope(_ projectId: UUID?) -> TimeScope {
        if let projectId { return .project(projectId) }
        let ids = Set(workspace.projects.filter(\.usesSprints).map(\.id))
        return .tasks(Set(workspace.tasks.filter { ids.contains($0.projectId) }.map(\.id)))
    }

    private func taskFilter(_ scope: TimeScope) -> (UUID) -> Bool {
        switch scope {
        case .all:
            return { _ in true }
        case let .task(id):
            return { $0 == id }
        case let .tasks(ids):
            return { ids.contains($0) }
        case let .project(projectId):
            let ids = Set(workspace.tasks.filter { $0.projectId == projectId }.map(\.id))
            return { ids.contains($0) }
        case let .milestone(milestoneId):
            let ids = Set(workspace.tasks.filter { $0.milestoneId == milestoneId }.map(\.id))
            return { ids.contains($0) }
        }
    }
}
