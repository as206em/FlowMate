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
    /// Time spent the step added (or removed, when negative) by hand, per task ("Adjust time").
    /// Undo keeps tracked time as it is, so these are taken back out explicitly.
    var timeDelta: [UUID: TimeInterval]

    init(id: UUID = UUID(), name: String, before: Workspace, coalesceKey: String? = nil, lastEdit: Date,
         timeDelta: [UUID: TimeInterval] = [:]) {
        self.id = id
        self.name = name
        self.before = before
        self.coalesceKey = coalesceKey
        self.lastEdit = lastEdit
        self.timeDelta = timeDelta
    }
}

// Undo and redo (⌘Z, ⇧⌘Z and the "Undo" toast).
//
// Every mutation records the workspace it replaced, except timer starts and pauses.
// Undo restores that snapshot but keeps tracked time as it is now: undo never removes
// time you spent, never starts a timer, and only pauses one when the task it restores is Done.
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
            undoGroupTimeDelta = [:]
        }
        undoGroupDepth += 1
        let result = body()
        undoGroupDepth -= 1
        if undoGroupDepth == 0, let start = undoGroupStart {
            undoGroupStart = nil
            if undoGroupHasChanges, workspace != start.before {
                pushUndo(UndoEntry(name: start.name, before: start.before, lastEdit: clock(), timeDelta: undoGroupTimeDelta))
            }
            undoGroupHasChanges = false
            undoGroupTimeDelta = [:]
        }
        return result
    }

    /// Called by `mutate` after an undoable change.
    func recordUndo(_ name: String, before: Workspace, coalesce key: String?) {
        let delta = pendingTimeDelta
        pendingTimeDelta = [:]
        if undoGroupDepth > 0 {
            undoGroupHasChanges = true
            undoGroupTimeDelta.merge(delta, uniquingKeysWith: +)
            return
        }
        let now = clock()
        if let key, !undoCoalescingBlocked, var top = undoStack.last, top.coalesceKey == key,
           now.timeIntervalSince(top.lastEdit) <= Self.undoCoalesceWindow {
            top.lastEdit = now
            top.timeDelta.merge(delta, uniquingKeysWith: +)
            undoStack[undoStack.count - 1] = top
            redoStack.removeAll()
            return
        }
        pushUndo(UndoEntry(name: name, before: before, coalesceKey: key, lastEdit: now, timeDelta: delta))
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
        Self.applyTimeDelta(entry.timeDelta, sign: -1, to: &restored)
        replaceWorkspace(restored)
        redoStack.append(UndoEntry(name: entry.name, before: current, lastEdit: clock(), timeDelta: entry.timeDelta))
        undoCoalescingBlocked = true
        return entry.name
    }

    /// Re-applies the last undone step. Returns its name, or nil when there was nothing to redo.
    @discardableResult
    func redo(now: Date = Date()) -> String? {
        guard undoGroupDepth == 0, let entry = redoStack.popLast() else { return nil }
        let current = workspace
        var restored = Self.restoring(entry.before, over: current, removedAt: entry.lastEdit, now: now)
        Self.applyTimeDelta(entry.timeDelta, sign: 1, to: &restored)
        replaceWorkspace(restored)
        undoStack.append(UndoEntry(name: entry.name, before: current, lastEdit: clock(), timeDelta: entry.timeDelta))
        undoCoalescingBlocked = true
        return entry.name
    }

    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        undoCoalescingBlocked = false
    }

    /// `target` with time tracking taken from `current`:
    /// - tasks in both keep their current spent time and running state;
    /// - tasks that come back (an undone delete) keep the time they tracked until `removedAt` (when
    ///   the step removed them); a timer that was running starts again from `now`, so the time the
    ///   task spent deleted isn't counted;
    /// - a running task restored as Done is paused, and one restored as To do shows In progress.
    static func restoring(_ target: Workspace, over current: Workspace, removedAt: Date, now: Date) -> Workspace {
        var ws = target
        // Settings aren't undo steps
        ws.preferences = current.preferences
        // Sample projects that come back (an undone "Clear sample data") are still sample data
        let currentProjects = Set(current.projects.map(\.id))
        ws.preferences.sampleProjectIds += target.preferences.sampleProjectIds.filter {
            !currentProjects.contains($0) && !ws.preferences.sampleProjectIds.contains($0)
        }
        let currentTasks = Dictionary(current.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var timers: [UUID: Date] = [:]
        for i in ws.tasks.indices {
            let id = ws.tasks[i].id
            if let now = currentTasks[id] {
                ws.tasks[i].spentSeconds = now.spentSeconds
                if let started = current.runningTimers[id] { timers[id] = started }
            } else if let started = target.runningTimers[id] {
                ws.tasks[i].spentSeconds += max(0, removedAt.timeIntervalSince(started))
                timers[id] = now
            }
        }
        for (id, started) in timers {
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { continue }
            switch ws.tasks[i].status {
            case .done:
                ws.tasks[i].spentSeconds += max(0, now.timeIntervalSince(started))
                timers[id] = nil
            case .todo:
                ws.tasks[i].status = .inProgress
            case .inProgress:
                break
            }
        }
        ws.runningTimers = timers
        return ws
    }

    /// Takes a hand adjustment of time spent back out (sign −1, undo) or puts it back (+1, redo).
    static func applyTimeDelta(_ delta: [UUID: TimeInterval], sign: Double, to ws: inout Workspace) {
        for (id, seconds) in delta {
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { continue }
            ws.tasks[i].spentSeconds = max(0, ws.tasks[i].spentSeconds + sign * seconds)
        }
    }
}
