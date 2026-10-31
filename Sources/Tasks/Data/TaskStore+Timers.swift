import Foundation

// Task timers. Any number can run at once; starting one never stops another.
extension TaskStore {
    func isRunning(_ taskId: UUID) -> Bool {
        workspace.runningTimers[taskId] != nil
    }

    var hasRunningTimers: Bool { !workspace.runningTimers.isEmpty }

    /// Starts the task's timer. A task that isn't started (not started, done or canceled) moves to
    /// the project's first Started status; without one, a closed task reopens to the first Not
    /// started status.
    func startTimer(_ taskId: UUID, now: Date = Date()) {
        guard let task = task(taskId), !isRunning(taskId) else { return }
        let target = Self.startedStatus(for: task, in: project(task.projectId))
        // Timers aren't undo steps: undo never stops a timer or removes tracked time
        mutate(recordsUndo: false) { ws in
            ws.runningTimers[taskId] = now
            if let target, let i = ws.tasks.firstIndex(where: { $0.id == taskId }), ws.tasks[i].statusId != target.id {
                ws.tasks[i].statusId = target.id
                ws.tasks[i].statusCategory = target.category
                ws.tasks[i].updatedAt = now
                // A task reopened from a closed sprint goes back to planning
                if ws.tasks[i].sprintSlot == .closed { ws.tasks[i].sprintSlot = .backlog }
            }
        }
    }

    /// The status a task moves to when its timer starts, or nil to keep its status.
    static func startedStatus(for task: TaskItem, in project: Project?) -> WorkflowStatus? {
        guard let project, task.statusCategory != .started else { return nil }
        if project.hasCategory(.started) { return project.firstStatus(.started) }
        return task.isClosed ? project.defaultStatus : nil
    }

    /// Stops the task's timer and adds the session to `spentSeconds`.
    func pauseTimer(_ taskId: UUID, now: Date = Date()) {
        guard isRunning(taskId) else { return }
        mutate(recordsUndo: false) { ws in
            // A Keep answer only applies to the session it answered
            ws.preferences.longRunKeptAt[taskId] = nil
            guard let started = ws.runningTimers.removeValue(forKey: taskId),
                  let i = ws.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            ws.tasks[i].spentSeconds += max(0, now.timeIntervalSince(started))
            ws.tasks[i].updatedAt = now
        }
    }

    func toggleTimer(_ taskId: UUID, now: Date = Date()) {
        if isRunning(taskId) {
            pauseTimer(taskId, now: now)
        } else {
            startTimer(taskId, now: now)
        }
    }

    func pauseAllTimers(now: Date = Date()) {
        for id in workspace.runningTimers.keys {
            pauseTimer(id, now: now)
        }
    }

    /// Pauses every running timer of a project (menu bar project ring button).
    func pauseTimers(projectId: UUID, now: Date = Date()) {
        for task in runningTasks where task.projectId == projectId {
            pauseTimer(task.id, now: now)
        }
    }

    /// Total time on the task: stored time plus the running session, if any.
    func elapsed(_ taskId: UUID, now: Date = Date()) -> TimeInterval {
        guard let task = task(taskId) else { return 0 }
        return elapsed(task, now: now)
    }

    func elapsed(_ task: TaskItem, now: Date = Date()) -> TimeInterval {
        let running = workspace.runningTimers[task.id].map { max(0, now.timeIntervalSince($0)) } ?? 0
        return task.spentSeconds + running
    }

    /// Ring fill toward the expected time; above 1 means over time (draw red).
    func progress(_ task: TaskItem, now: Date = Date()) -> Double {
        elapsed(task, now: now) / Double(max(1, task.expectedMinutes) * 60)
    }

    func isOverExpected(_ task: TaskItem, now: Date = Date()) -> Bool {
        progress(task, now: now) > 1
    }

    /// Running tasks, earliest started first.
    var runningTasks: [TaskItem] {
        workspace.runningTimers
            .sorted { $0.value == $1.value ? $0.key.uuidString < $1.key.uuidString : $0.value < $1.value }
            .compactMap { task($0.key) }
    }

    func startedAt(_ taskId: UUID) -> Date? {
        workspace.runningTimers[taskId]
    }

    /// True when any task of the project has a running timer.
    func isProjectRunning(_ projectId: UUID) -> Bool {
        runningTasks.contains { $0.projectId == projectId }
    }
}

// Project-level timer helpers for the menu bar.
extension TaskStore {
    /// The task a project's play button starts: the most recently touched started task (any
    /// Started status), otherwise the top Not started task in the active sprint.
    func nextTaskToStart(projectId: UUID) -> TaskItem? {
        let tasks = tasks(of: projectId).filter { $0.sprintSlot != .closed }
        if let recent = tasks.filter({ $0.statusCategory == .started }).max(by: { $0.updatedAt < $1.updatedAt }) {
            return recent
        }
        return tasks.first { $0.sprintSlot == .active && $0.statusCategory == .notStarted }
    }

    /// Starts the project's next task (see `nextTaskToStart`). Returns the started task's id.
    @discardableResult
    func startProject(_ projectId: UUID, now: Date = Date()) -> UUID? {
        guard let task = nextTaskToStart(projectId: projectId) else { return nil }
        startTimer(task.id, now: now)
        return task.id
    }

    /// Open tasks of the project's active sprint, plus anything of it that is running (menu bar expansion).
    func activeSprintTasks(projectId: UUID) -> [TaskItem] {
        tasks(of: projectId).filter { ($0.sprintSlot == .active && !$0.isClosed) || isRunning($0.id) }
    }
}
