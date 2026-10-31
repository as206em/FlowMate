import Foundation

// Power use: bulk edits, quick-add tokens, fixing tracked time, the long-run prompt,
// subtask order and conversion, and the preferences stored with the workspace.

// MARK: - Bulk edits

extension TaskStore {
    /// Ids that still exist, in the given order, without duplicates.
    func existing(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { task($0) != nil && seen.insert($0).inserted }
    }

    /// "3 tasks" / "1 task"
    static func taskCount(_ n: Int) -> String { "\(n) \(n == 1 ? "task" : "tasks")" }

    func setPriority(_ ids: [UUID], _ priority: TaskPriority) {
        undoGroup("Change priority") {
            for id in existing(ids) { setPriority(id, priority) }
        }
    }

    /// Sets the due date of several tasks (nil clears it). Rescheduling overdue tasks uses this.
    func setDueDate(_ ids: [UUID], _ dueDate: Date?) {
        undoGroup("Change due date") {
            for id in existing(ids) { setDueDate(id, dueDate) }
        }
    }

    /// Moves several tasks to a sprint slot. Tasks of past sprints stay where they are.
    func setSprintSlot(_ ids: [UUID], _ slot: SprintSlot) {
        guard slot != .closed else { return }
        undoGroup("Change sprint") {
            for id in existing(ids) where task(id)?.sprintSlot != .closed { setSprintSlot(id, slot) }
        }
    }

    /// Sets the milestone of several tasks. With a milestone, only tasks of its project change;
    /// nil clears the milestone of all of them. Returns how many changed.
    @discardableResult
    func setMilestone(_ ids: [UUID], _ milestoneId: UUID?) -> Int {
        let projectId = milestoneId.flatMap { milestone($0)?.projectId }
        if milestoneId != nil, projectId == nil { return 0 }
        var changed = 0
        undoGroup("Change milestone") {
            for id in existing(ids) {
                guard let task = task(id), task.milestoneId != milestoneId else { continue }
                if let projectId, task.projectId != projectId { continue }
                setMilestone(id, milestoneId)
                changed += 1
            }
        }
        return changed
    }

    func setProject(_ ids: [UUID], _ projectId: UUID) {
        undoGroup("Move to project") {
            for id in existing(ids) { setProject(id, projectId) }
        }
    }

    func deleteTasks(_ ids: [UUID]) {
        let ids = Set(existing(ids))
        guard !ids.isEmpty else { return }
        mutate(ids.count == 1 ? "Delete task" : "Delete tasks") { ws in
            ws.tasks.removeAll { ids.contains($0.id) }
            for id in ids { ws.runningTimers[id] = nil }
        }
    }

    /// Duplicates each task below its original. Returns the copies' ids.
    @discardableResult
    func duplicateTasks(_ ids: [UUID], now: Date = Date()) -> [UUID] {
        undoGroup("Duplicate task") {
            existing(ids).compactMap { duplicateTask($0, now: now) }
        }
    }

    /// The project all the tasks share, if they share one (for the bulk Milestone menu).
    func commonProjectId(_ ids: [UUID]) -> UUID? {
        let projects = Set(existing(ids).compactMap { task($0)?.projectId })
        return projects.count == 1 ? projects.first : nil
    }
}

// MARK: - Quick add

/// What a quick add did, for the "Added to X" toast.
struct QuickAddOutcome: Equatable {
    let taskId: UUID
    let projectId: UUID
    /// Tokens applied, in words: ["High", "Beta launch", "Due Fri", "1h 30m"]
    let applied: [String]
    /// A milestone token that matched nothing: "@betaa"
    let unmatchedMilestone: String?
}

extension TaskStore {
    /// The milestone a `@query` means: an exact name (ignoring case, spaces and punctuation),
    /// then a name starting with it, then one containing it. Open milestones win over completed ones.
    func matchMilestone(_ query: String, projectId: UUID) -> Milestone? {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let q = key(query)
        guard !q.isEmpty else { return nil }
        let all = milestones(of: projectId)
        let ordered = all.filter { !$0.isCompleted } + all.filter(\.isCompleted)
        return ordered.first { key($0.name) == q }
            ?? ordered.first { key($0.name).hasPrefix(q) }
            ?? ordered.first { key($0.name).contains(q) }
    }
}

// MARK: - Preferences

extension TaskStore {
    var preferences: WorkspacePreferences { workspace.preferences }

    /// Where New task fields in All projects add to: the last project used, else the first one.
    var defaultProject: Project? {
        if let id = preferences.lastProjectId, let project = project(id), !project.isArchived { return project }
        return projects.first
    }

    /// Remembers the project for the next quick add. Not an undo step.
    func rememberProject(_ projectId: UUID) {
        guard project(projectId) != nil, preferences.lastProjectId != projectId else { return }
        mutate(recordsUndo: false) { $0.preferences.lastProjectId = projectId }
    }

    func setShowsMenuBarClock(_ on: Bool) {
        mutate(recordsUndo: false) { $0.preferences.showsMenuBarClock = on }
    }

    /// 0 turns the "Still working?" prompt off.
    func setLongRunPromptMinutes(_ minutes: Int) {
        mutate(recordsUndo: false) { $0.preferences.longRunPromptMinutes = max(0, minutes) }
    }

    /// 0 turns idle stopping off.
    func setIdleStopMinutes(_ minutes: Int) {
        mutate(recordsUndo: false) { $0.preferences.idleStopMinutes = max(0, minutes) }
    }
}

// MARK: - Fixing tracked time

extension TaskStore {
    /// Sets the total time spent on a task ("Adjust time…") by editing its time log: more time is
    /// one `manual` entry ending now; less time is taken off its latest entries (a running session
    /// is recorded first when the entries alone don't cover the cut). A running timer keeps running.
    /// Undo puts the entries back. Ignores changes under a second.
    func setTimeSpent(_ id: UUID, seconds: TimeInterval, now: Date = Date()) {
        guard let task = task(id) else { return }
        let newTotal = max(0, seconds.rounded())
        let delta = newTotal - elapsed(task, now: now)
        guard abs(delta) >= 1 else { return }
        if delta < 0, -delta > task.spentSeconds + 0.5, let started = startedAt(id), now > started {
            // The cut reaches into the running session: record it, the timer goes on from now
            mutate(recordsUndo: false) { ws in
                ws.closeSession(id, at: now)
                ws.runningTimers[id] = now
            }
        }
        mutate("Adjust time", coalesce: "time-\(id)") { ws in
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { return }
            if delta > 0 {
                ws.timeEntries.append(TimeEntry(taskId: id, start: now.addingTimeInterval(-delta), end: now, source: .manual))
            } else {
                ws.trimTrackedTime(id, by: -delta)
            }
            ws.tasks[i].updatedAt = now
        }
    }

    /// Adds (or with a negative value removes) time spent. Never goes below zero.
    func adjustTimeSpent(_ id: UUID, by seconds: TimeInterval, now: Date = Date()) {
        setTimeSpent(id, seconds: elapsed(id, now: now) + seconds, now: now)
    }

    /// Pauses a timer as if you'd stopped it at `time` (clamped between its start and now).
    /// The time after that isn't counted. Like any pause, not an undo step.
    func stopTimer(_ id: UUID, at time: Date, now: Date = Date()) {
        guard let started = startedAt(id) else { return }
        pauseTimer(id, now: min(max(time, started), now))
    }
}

// MARK: - "Still working on X?"

extension TaskStore {
    /// How long the prompt waits, or nil when it's off.
    var longRunThreshold: TimeInterval? {
        let minutes = preferences.longRunPromptMinutes
        return minutes > 0 ? TimeInterval(minutes * 60) : nil
    }

    /// Running tasks whose current session passed the threshold since it started (or since you
    /// last answered Keep), longest running first. The prompt never stops a timer by itself.
    func longRunningTasks(now: Date = Date()) -> [TaskItem] {
        guard let threshold = longRunThreshold else { return [] }
        return runningTasks.filter { task in
            guard let started = startedAt(task.id) else { return false }
            let since = max(started, longRunAcknowledged[task.id] ?? started)
            return now.timeIntervalSince(since) >= threshold
        }
    }

    /// "Keep": the timer runs on and the prompt waits another full interval.
    func keepRunning(_ id: UUID, now: Date = Date()) {
        guard isRunning(id) else { return }
        // A setting, not an undo step
        mutate(recordsUndo: false) { $0.preferences.longRunKeptAt[id] = now }
    }

    /// Length of the current session (not the task's total), for "running for 3h 10m".
    func sessionLength(_ id: UUID, now: Date = Date()) -> TimeInterval {
        startedAt(id).map { max(0, now.timeIntervalSince($0)) } ?? 0
    }
}

// MARK: - Subtasks

extension TaskStore {
    /// Drag to reorder: puts the subtask before another one (or last when nil).
    func moveSubtask(_ taskId: UUID, _ subtaskId: UUID, before beforeId: UUID?) {
        guard subtaskId != beforeId else { return }
        updateTask(taskId, action: "Reorder subtasks") { task in
            guard let from = task.subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
            let subtask = task.subtasks.remove(at: from)
            let to = beforeId.flatMap { id in task.subtasks.firstIndex { $0.id == id } } ?? task.subtasks.count
            task.subtasks.insert(subtask, at: to)
        }
    }

    /// Turns a subtask into its own task just below the parent: same project, milestone and sprint,
    /// in the project's first Done status if it was checked (else its first Not started one).
    /// One undo step. Returns the new task's id.
    @discardableResult
    func convertSubtaskToTask(_ taskId: UUID, _ subtaskId: UUID, now: Date = Date()) -> UUID? {
        guard let parent = task(taskId), let subtask = parent.subtasks.first(where: { $0.id == subtaskId }) else { return nil }
        let workflow = project(parent.projectId)
        let task = TaskItem(
            projectId: parent.projectId,
            milestoneId: parent.milestoneId,
            sprintSlot: parent.sprintSlot == .closed ? .backlog : parent.sprintSlot,
            status: workflow?.firstStatus(subtask.isDone ? .done : .notStarted) ?? (subtask.isDone ? .done : .todo),
            priority: parent.priority,
            title: subtask.title,
            createdAt: now,
            sortIndex: sortIndex(after: taskId)
        )
        mutate("Convert to task") { ws in
            guard let i = ws.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            ws.tasks[i].subtasks.removeAll { $0.id == subtaskId }
            ws.tasks[i].updatedAt = now
            ws.tasks.append(task)
        }
        return task.id
    }
}
