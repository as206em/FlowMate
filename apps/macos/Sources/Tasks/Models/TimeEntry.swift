import Foundation

/// Where a time entry came from.
enum TimeEntrySource: String, CaseIterable, Sendable, TolerantStringEnum {
    /// A timer session, written when the timer stops
    case timer
    /// Added or adjusted by hand ("Add time…", "Adjust time")
    case manual
    /// Time tracked before sessions were kept (schema 6 and older): one entry per task
    case imported

    static var fallback: TimeEntrySource { .manual }

    var title: String {
        switch self {
        case .timer: return "Timer"
        case .manual: return "Added by hand"
        case .imported: return "Imported"
        }
    }
}

/// One stretch of time spent on a task. A task's time spent is the sum of its entries plus the
/// running session (Workspace.runningTimers), which becomes an entry when the timer stops.
struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var taskId: UUID
    var start: Date
    var end: Date
    var note: String?
    var source: TimeEntrySource

    init(id: UUID = UUID(), taskId: UUID, start: Date, end: Date, note: String? = nil, source: TimeEntrySource) {
        self.id = id
        self.taskId = taskId
        self.start = start
        self.end = end
        self.note = Self.cleaned(note)
        self.source = source
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }

    /// Seconds of this entry inside `range`.
    func seconds(in range: DateInterval) -> TimeInterval {
        Self.overlap(start, end, range)
    }

    static func overlap(_ start: Date, _ end: Date, _ range: DateInterval) -> TimeInterval {
        max(0, min(end, range.end).timeIntervalSince(max(start, range.start)))
    }

    /// A blank note is no note.
    static func cleaned(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey { case id, taskId, start, end, note, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decode(.id, or: UUID())
        taskId = try c.decode(UUID.self, forKey: .taskId)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        note = Self.cleaned(c.decodeOptional(.note))
        source = c.decode(.source, or: .manual)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(taskId, forKey: .taskId)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(source, forKey: .source)
    }
}

// MARK: - Keeping time and completion consistent

extension Workspace {
    /// Entries of one task, oldest first.
    func timeEntries(of taskId: UUID) -> [TimeEntry] {
        timeEntries.filter { $0.taskId == taskId }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    }

    /// Runs after every change (TaskStore.mutate, undo, load): drops entries of tasks that are gone
    /// or that have no length, and sets each task's `spentSeconds` to the sum of its entries, so
    /// everything that reads `spentSeconds` sees the time log's total.
    mutating func normalizeTime() {
        let taskIds = Set(tasks.map(\.id))
        if timeEntries.contains(where: { !taskIds.contains($0.taskId) || $0.end <= $0.start }) {
            timeEntries.removeAll { !taskIds.contains($0.taskId) || $0.end <= $0.start }
        }
        var totals: [UUID: TimeInterval] = [:]
        for entry in timeEntries { totals[entry.taskId, default: 0] += entry.duration }
        for i in tasks.indices {
            let total = totals[tasks[i].id] ?? 0
            if tasks[i].spentSeconds != total { tasks[i].spentSeconds = total }
        }
    }

    /// A task finished (done or canceled) has a completion date; an open one has none. A task that
    /// closes without one gets its last update time (the status change stamps it).
    mutating func normalizeCompletion() {
        for i in tasks.indices {
            if tasks[i].isClosed {
                if tasks[i].completedAt == nil { tasks[i].completedAt = tasks[i].updatedAt }
            } else if tasks[i].completedAt != nil {
                tasks[i].completedAt = nil
            }
        }
    }

    /// Time counted in `spentSeconds` that no entry explains (data from schema 6 and older, or
    /// built by hand) becomes one `imported` entry ending at the task's last update, so totals
    /// never change. Then the totals are re-derived from the entries.
    mutating func reconcileTrackedTime(now: Date = Date()) {
        var logged: [UUID: TimeInterval] = [:]
        for entry in timeEntries { logged[entry.taskId, default: 0] += entry.duration }
        for task in tasks {
            let missing = task.spentSeconds - (logged[task.id] ?? 0)
            guard missing > 0.01 else { continue }
            let end = min(task.updatedAt, now)
            timeEntries.append(TimeEntry(taskId: task.id, start: end.addingTimeInterval(-missing), end: end, source: .imported))
        }
        normalizeTime()
    }

    /// Stops a running timer at `time`, writing the session as a timer entry (none when it has no length).
    mutating func closeSession(_ taskId: UUID, at time: Date) {
        preferences.longRunKeptAt[taskId] = nil
        guard let started = runningTimers.removeValue(forKey: taskId) else { return }
        if time > started {
            timeEntries.append(TimeEntry(taskId: taskId, start: started, end: time, source: .timer))
        }
    }

    /// Takes `seconds` off a task's latest entries (latest end first): each is shortened from its
    /// end, and removed once nothing is left of it. Stops at zero.
    mutating func trimTrackedTime(_ taskId: UUID, by seconds: TimeInterval) {
        var remaining = seconds
        let latestFirst = timeEntries.indices
            .filter { timeEntries[$0].taskId == taskId }
            .sorted { timeEntries[$0].end > timeEntries[$1].end }
        var emptied = Set<UUID>()
        for i in latestFirst where remaining > 0 {
            let length = timeEntries[i].duration
            if length <= remaining {
                emptied.insert(timeEntries[i].id)
                remaining -= length
            } else {
                timeEntries[i].end = timeEntries[i].end.addingTimeInterval(-remaining)
                remaining = 0
            }
        }
        timeEntries.removeAll { emptied.contains($0.id) }
    }

    /// Takes `range` out of a task's tracked time: the running session (when it started before
    /// the range ends) is split, its part before the range becoming an entry and the timer going on
    /// from the end of the range; timer entries overlapping the range are cut or split around it.
    mutating func removeTrackedTime(_ taskId: UUID, in range: DateInterval) {
        guard range.duration > 0 else { return }
        if let started = runningTimers[taskId], started < range.end {
            if started < range.start {
                timeEntries.append(TimeEntry(taskId: taskId, start: started, end: range.start, source: .timer))
            }
            runningTimers[taskId] = range.end
        }
        var result: [TimeEntry] = []
        for entry in timeEntries {
            guard entry.taskId == taskId, entry.source == .timer,
                  entry.start < range.end, entry.end > range.start else {
                result.append(entry)
                continue
            }
            if entry.start < range.start {
                var before = entry
                before.end = range.start
                result.append(before)
            }
            if entry.end > range.end {
                var after = entry
                // The part after keeps the id only when nothing came before it
                if entry.start < range.start { after.id = UUID() }
                after.start = range.end
                result.append(after)
            }
        }
        timeEntries = result
    }
}
