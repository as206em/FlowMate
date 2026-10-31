import Foundation

/// One step of undo history: the whole workspace from before a user action.
/// Snapshots are cheap (value types) and make every change undoable the same way.
struct UndoEntry: Identifiable, Sendable {
    let id: UUID
    /// What the step did, e.g. "Delete task"
    let name: String
    let before: Workspace
    /// Rapid edits with the same key (typing a title) extend this step instead of adding one.
    let coalesceKey: String?
    var lastEdit: Date
    /// Time log edits the step made (add, edit or delete an entry, "Adjust time", "Discard sleep
    /// time"). Undo keeps tracked time as it is now, so these are taken back out one by one.
    var timeChanges: TimeLogChanges

    init(id: UUID = UUID(), name: String, before: Workspace, coalesceKey: String? = nil, lastEdit: Date,
         timeChanges: TimeLogChanges = TimeLogChanges()) {
        self.id = id
        self.name = name
        self.before = before
        self.coalesceKey = coalesceKey
        self.lastEdit = lastEdit
        self.timeChanges = timeChanges
    }
}

/// What an undoable step did to the time log, entry by entry. Timer pauses are never undo steps,
/// so undo can't restore the whole snapshot's entries (it would drop sessions recorded since);
/// it reverts just these.
struct TimeLogChanges: Equatable, Sendable {
    struct Change<Value: Equatable & Sendable>: Equatable, Sendable {
        /// nil: didn't exist
        var before: Value?
        var after: Value?
    }

    /// Entry id -> the entry before and after the step
    var entries: [UUID: Change<TimeEntry>] = [:]
    /// Task id -> when its running session started, before and after (a timer that went on with
    /// a later start, as "Discard sleep time" does). Starting and stopping timers isn't included.
    var timerStarts: [UUID: Change<Date>] = [:]

    init() {}

    init(from old: Workspace, to new: Workspace) {
        if old.timeEntries != new.timeEntries {
            let before = Dictionary(old.timeEntries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let after = Dictionary(new.timeEntries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for id in Set(before.keys).union(after.keys) where before[id] != after[id] {
                entries[id] = Change(before: before[id], after: after[id])
            }
        }
        for (id, started) in new.runningTimers {
            if let previous = old.runningTimers[id], previous != started {
                timerStarts[id] = Change(before: previous, after: started)
            }
        }
    }

    var isEmpty: Bool { entries.isEmpty && timerStarts.isEmpty }

    /// Adds a later step's changes: each item keeps its first `before` and takes the latest `after`.
    mutating func merge(_ later: TimeLogChanges) {
        for (id, change) in later.entries {
            let first = entries[id]?.before ?? (entries[id] == nil ? change.before : nil)
            entries[id] = Change(before: first, after: change.after)
            if entries[id]?.before == entries[id]?.after { entries[id] = nil }
        }
        for (id, change) in later.timerStarts {
            let first = timerStarts[id]?.before ?? change.before
            timerStarts[id] = Change(before: first, after: change.after)
            if timerStarts[id]?.before == timerStarts[id]?.after { timerStarts[id] = nil }
        }
    }

    /// Puts the `before` side back (undo) or the `after` side (redo). A timer start changes only
    /// while that timer still runs from the other side's start.
    func apply(to ws: inout Workspace, undo: Bool) {
        for (id, change) in entries {
            let target = undo ? change.before : change.after
            if let index = ws.timeEntries.firstIndex(where: { $0.id == id }) {
                if let target { ws.timeEntries[index] = target } else { ws.timeEntries.remove(at: index) }
            } else if let target {
                ws.timeEntries.append(target)
            }
        }
        for (id, change) in timerStarts {
            guard let from = undo ? change.after : change.before, let to = undo ? change.before : change.after,
                  ws.runningTimers[id] == from else { continue }
            ws.runningTimers[id] = to
        }
    }
}

// Undo and redo (⌘Z, ⇧⌘Z and the "Undo" toast).
//
// Every mutation records the workspace it replaced, except timer starts and pauses.
// Undo restores that snapshot but keeps tracked time as it is now: undo never removes
// time you spent, never starts a timer, and only pauses one when the task it restores is done or canceled.
// Hand edits of the time log are the exception: the step's own entry changes are reverted.
extension TaskStore {
    /// Steps kept; older ones drop off.
    static let undoLimit = 100
    /// Edits with the same coalesce key within this many seconds of each other are one step.
    static let undoCoalesceWindow: TimeInterval = 1.5

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    /// "Delete task", for menus and toasts
    var undoActionName: String? { undoStack.last?.name }
    var redoActionName: String? { redoStack.last?.name }
    /// The newest step's id, so a toast can check its action is still the one ⌘Z would undo.
    var lastUndoId: UUID? { undoStack.last?.id }

    /// Runs several mutations as one undo step named `name`.
    /// Nested groups fold into the outermost one.
    @discardableResult
    func undoGroup<T>(_ name: String, _ body: () -> T) -> T {
        if undoGroupDepth == 0 {
            undoGroupStart = (name, workspace)
            undoGroupHasChanges = false
            undoGroupTimeChanges = TimeLogChanges()
        }
        undoGroupDepth += 1
        let result = body()
        undoGroupDepth -= 1
        if undoGroupDepth == 0, let start = undoGroupStart {
            undoGroupStart = nil
            if undoGroupHasChanges, workspace != start.before {
                pushUndo(UndoEntry(name: start.name, before: start.before, lastEdit: clock(), timeChanges: undoGroupTimeChanges))
            }
            undoGroupHasChanges = false
            undoGroupTimeChanges = TimeLogChanges()
        }
        return result
    }

    /// Called by `mutate` after an undoable change.
    func recordUndo(_ name: String, before: Workspace, coalesce key: String?, timeChanges: TimeLogChanges = TimeLogChanges()) {
        if undoGroupDepth > 0 {
            undoGroupHasChanges = true
            undoGroupTimeChanges.merge(timeChanges)
            return
        }
        let now = clock()
        if let key, !undoCoalescingBlocked, var top = undoStack.last, top.coalesceKey == key,
           now.timeIntervalSince(top.lastEdit) <= Self.undoCoalesceWindow {
            top.lastEdit = now
            top.timeChanges.merge(timeChanges)
            undoStack[undoStack.count - 1] = top
            redoStack.removeAll()
            return
        }
        pushUndo(UndoEntry(name: name, before: before, coalesceKey: key, lastEdit: now, timeChanges: timeChanges))
    }

    private func pushUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
        redoStack.removeAll()
        undoCoalescingBlocked = false
    }

    /// Reverts the last step. Returns its name, or nil when there was nothing to undo.
    @discardableResult
    func undo(now: Date = Date()) -> String? {
        guard undoGroupDepth == 0, let entry = undoStack.popLast() else { return nil }
        let current = workspace
        var restored = Self.restoring(entry.before, over: current, removedAt: entry.lastEdit, now: now)
        entry.timeChanges.apply(to: &restored, undo: true)
        restored.normalizeTime()
        replaceWorkspace(restored)
        redoStack.append(UndoEntry(name: entry.name, before: current, lastEdit: clock(), timeChanges: entry.timeChanges))
        undoCoalescingBlocked = true
        return entry.name
    }

    /// Re-applies the last undone step. Returns its name, or nil when there was nothing to redo.
    @discardableResult
    func redo(now: Date = Date()) -> String? {
        guard undoGroupDepth == 0, let entry = redoStack.popLast() else { return nil }
        let current = workspace
        var restored = Self.restoring(entry.before, over: current, removedAt: entry.lastEdit, now: now)
        entry.timeChanges.apply(to: &restored, undo: false)
        restored.normalizeTime()
        replaceWorkspace(restored)
        undoStack.append(UndoEntry(name: entry.name, before: current, lastEdit: clock(), timeChanges: entry.timeChanges))
        undoCoalescingBlocked = true
        return entry.name
    }

    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        undoCoalescingBlocked = false
    }

    /// `target` with time tracking taken from `current`:
    /// - tasks in both keep their current time entries and running state;
    /// - tasks that come back (an undone delete) bring their entries back, and a timer that was
    ///   running counts until `removedAt` (when the step removed them) and starts again from `now`,
    ///   so the time the task spent deleted isn't counted;
    /// - a running task restored as done or canceled is paused, and one restored as not started
    ///   shows its project's first Started status.
    /// The caller reverts the step's own time log edits (TimeLogChanges) and re-derives totals.
    static func restoring(_ target: Workspace, over current: Workspace, removedAt: Date, now: Date) -> Workspace {
        var ws = target
        // Settings aren't undo steps
        ws.preferences = current.preferences
        // Sample projects that come back (an undone "Clear sample data") are still sample data
        let currentProjects = Set(current.projects.map(\.id))
        ws.preferences.sampleProjectIds += target.preferences.sampleProjectIds.filter {
            !currentProjects.contains($0) && !ws.preferences.sampleProjectIds.contains($0)
        }
        let currentTaskIds = Set(current.tasks.map(\.id))
        let targetTaskIds = Set(target.tasks.map(\.id))
        ws.timeEntries = current.timeEntries.filter { targetTaskIds.contains($0.taskId) }
            + target.timeEntries.filter { !currentTaskIds.contains($0.taskId) }
        var timers: [UUID: Date] = [:]
        for task in ws.tasks {
            let id = task.id
            if currentTaskIds.contains(id) {
                if let started = current.runningTimers[id] { timers[id] = started }
            } else if let started = target.runningTimers[id] {
                if removedAt > started {
                    ws.timeEntries.append(TimeEntry(taskId: id, start: started, end: removedAt, source: .timer))
                }
                timers[id] = now
            }
        }
        ws.runningTimers = timers
        for (id, _) in timers {
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { continue }
            switch ws.tasks[i].statusCategory {
            case .done, .canceled:
                ws.closeSession(id, at: now)
            case .notStarted:
                let project = ws.projects.first { $0.id == ws.tasks[i].projectId }
                if let project, project.hasCategory(.started) {
                    let status = project.firstStatus(.started)
                    ws.tasks[i].statusId = status.id
                    ws.tasks[i].statusCategory = status.category
                }
            case .started:
                break
            }
        }
        ws.normalizeCompletion()
        ws.normalizeTime()
        return ws
    }
}
