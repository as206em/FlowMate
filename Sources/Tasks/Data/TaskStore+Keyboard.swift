import Foundation

// Store operations behind the keyboard: X (done or back), ⌥↑/⌥↓ (manual order), several tasks'
// time at once, and the timer keys (⌥-click, ⇧Space, the global "pause or resume" hotkey).
extension TaskStore {
    // MARK: - Done or back (X)

    /// X: moves the tasks to their workflow's first Done status; when every one is already done,
    /// back to the first Not started status. Canceled tasks count as not done. One undo step.
    /// Returns true when they were marked done.
    @discardableResult
    func toggleDone(_ ids: [UUID], now: Date = Date()) -> Bool {
        let tasks = existing(ids).compactMap { task($0) }
        guard !tasks.isEmpty else { return false }
        let allDone = tasks.allSatisfy { $0.statusCategory == .done }
        undoGroup(allDone ? "Reopen task" : "Complete task") {
            for task in tasks {
                guard let project = project(task.projectId) else { continue }
                if allDone {
                    setStatus(task.id, project.defaultStatus, now: now)
                } else if task.statusCategory != .done, project.hasCategory(.done) {
                    setStatus(task.id, project.firstStatus(.done), now: now)
                }
            }
        }
        return !allDone
    }

    // MARK: - Manual order (⌥↑ / ⌥↓)

    /// Places the task just after another one in the global order.
    func place(_ id: UUID, after anchorId: UUID) {
        guard id != anchorId, task(anchorId) != nil else { return }
        // sortIndex(after:) looks at every task, the moving one included; take it out of the way first
        let others = workspace.tasks.filter { $0.id != id }
        guard let anchor = others.first(where: { $0.id == anchorId }) else { return }
        let following = others.map(\.sortIndex).filter { $0 > anchor.sortIndex }.min()
        let newIndex = following.map { (anchor.sortIndex + $0) / 2 } ?? anchor.sortIndex + 1
        mutate("Reorder task") { ws in
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { return }
            ws.tasks[i].sortIndex = newIndex
        }
        rebalanceSortIndexesIfCrowded()
    }

    /// Moves the selected tasks of one group up (−1) or down (+1) by a row inside `order` (the
    /// group as shown, top to bottom). Selected neighbours move together; nothing moves when the
    /// block is already at that end. `focus` reorders the Today page's My focus instead of the
    /// global order. One undo step. Returns false when nothing moved.
    @discardableResult
    func moveWithinGroup(_ selected: Set<UUID>, offset: Int, order: [UUID], focus: Bool = false, now: Date = Date()) -> Bool {
        guard offset == 1 || offset == -1 else { return false }
        let moving = order.filter(selected.contains)
        guard !moving.isEmpty else { return false }
        var newOrder = order
        if offset < 0 {
            guard newOrder.first.map({ !selected.contains($0) }) ?? false else { return false }
            for i in 1..<newOrder.count where selected.contains(newOrder[i]) && !selected.contains(newOrder[i - 1]) {
                newOrder.swapAt(i, i - 1)
            }
        } else {
            guard newOrder.last.map({ !selected.contains($0) }) ?? false else { return false }
            for i in stride(from: newOrder.count - 2, through: 0, by: -1)
            where selected.contains(newOrder[i]) && !selected.contains(newOrder[i + 1]) {
                newOrder.swapAt(i, i + 1)
            }
        }
        guard newOrder != order else { return false }
        undoGroup(focus ? "Reorder Today" : "Reorder task") {
            // From the bottom up, so each task lands before one already in its final place
            for index in newOrder.indices.reversed() where selected.contains(newOrder[index]) {
                let id = newOrder[index]
                let next = index + 1 < newOrder.count ? newOrder[index + 1] : nil
                if focus {
                    moveInFocus(id, before: next, now: now)
                } else if let next {
                    reorder(id, before: next)
                } else if index > 0 {
                    place(id, after: newOrder[index - 1])
                }
            }
        }
        return true
    }

    // MARK: - Time on several tasks

    /// T in the picker for several tasks: sets each one's time spent. One undo step.
    func setTimeSpent(_ ids: [UUID], seconds: TimeInterval, now: Date = Date()) {
        undoGroup("Adjust time") {
            for id in existing(ids) { setTimeSpent(id, seconds: seconds, now: now) }
        }
    }

    /// Adds (or with a negative value takes off) time on each task. One undo step.
    func adjustTimeSpent(_ ids: [UUID], by seconds: TimeInterval, now: Date = Date()) {
        undoGroup("Adjust time") {
            for id in existing(ids) { adjustTimeSpent(id, by: seconds, now: now) }
        }
    }

    func setExpectedMinutes(_ ids: [UUID], _ minutes: Int) {
        undoGroup("Change expected time") {
            for id in existing(ids) { setExpectedMinutes(id, minutes) }
        }
    }

    // MARK: - Timer keys

    /// ⌥-click or ⌥Space on a play button: this timer runs and every other one pauses.
    func startTimerExclusively(_ id: UUID, now: Date = Date()) {
        guard task(id) != nil else { return }
        for other in workspace.runningTimers.keys where other != id {
            pauseTimer(other, now: now)
        }
        startTimer(id, now: now)
    }

    /// The timer the "Pause or resume the last timer" hotkey acts on: the latest started of the
    /// running ones, else the task whose time was logged last.
    func lastTimerTaskId() -> UUID? {
        if let running = workspace.runningTimers.max(by: { $0.value < $1.value })?.key { return running }
        return workspace.timeEntries
            .filter { task($0.taskId) != nil }
            .max(by: { $0.end < $1.end })?.taskId
    }

    /// The global hotkey: pauses the timer started last, or when none runs, resumes the task
    /// worked on last. Returns the task and whether it now runs.
    @discardableResult
    func toggleLastTimer(now: Date = Date()) -> (taskId: UUID, running: Bool)? {
        guard let id = lastTimerTaskId() else { return nil }
        toggleTimer(id, now: now)
        return (id, isRunning(id))
    }
}
