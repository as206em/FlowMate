import Foundation

// The Today page's sections and the actions it adds (Add to Today, → Tomorrow, Move all overdue),
// each with its toast. The data comes from TaskStore.todayPlan.

/// The Today page's one section: running, due, pinned and finished-today tasks together.
struct TodaySection: Equatable {
    let key: String
    let title: String
    let tasks: [TaskItem]
}

extension TasksViewModel {
    static let todayKey = "today"
    static let todaySprintKey = "today-sprint"

    /// Today focus (running, overdue, due today, pinned, then done today), always shown with an empty
    /// state that says how to pin tasks; then the current sprint's open tasks that aren't in it.
    static func todaySections(_ plan: TodayPlan, store: TaskStore) -> [TodaySection] {
        let focus = TodaySection(key: todayKey, title: "Today focus", tasks: plan.allTasks)
        let shown = Set(plan.allTasks.map(\.id))
        let sprint = store.sprintTasks(slot: .active).filter { !$0.isClosed && !shown.contains($0.id) }
        guard !sprint.isEmpty else { return [focus] }
        return [focus, TodaySection(key: todaySprintKey, title: "Current sprint", tasks: sprint)]
    }

    /// The tasks ⌘T and the bulk bar's Today button act on: the selection (or the open task).
    func todayTargets(_ store: TaskStore) -> [UUID] {
        if isMultiSelecting, !isPanelOpen { return selectedIds(store) }
        return targetTaskId(store).map { [$0] } ?? []
    }

    /// ⌘T, the row menu, the inspector and the bulk bar: pins the tasks to Today, or unpins them
    /// when all of them already are. Toast with Undo.
    func toggleToday(_ ids: [UUID], store: TaskStore, now: Date = Date()) {
        let ids = store.existing(ids)
        guard !ids.isEmpty else { return }
        let before = store.lastUndoId
        let added = store.toggleToday(ids, now: now)
        guard store.lastUndoId != before else { return }
        let subject = ids.count == 1 ? "Task" : TaskStore.taskCount(ids.count)
        showUndoToast(added ? "\(subject) added to Today" : "\(subject) removed from Today", store: store)
    }

    /// "→ Tomorrow" on a row, and the Overdue section's "Move all to today / tomorrow".
    func moveToDay(_ ids: [UUID], _ move: TodayMove, store: TaskStore, now: Date = Date()) {
        let before = store.lastUndoId
        store.moveToDay(ids, move, now: now)
        guard store.lastUndoId != before else { return }
        let subject = ids.count == 1 ? "Task" : TaskStore.taskCount(ids.count)
        showUndoToast("\(subject) moved to \(move == .today ? "today" : "tomorrow")", store: store)
    }

    /// The Overdue section's header buttons: every overdue task shown on Today.
    func moveAllOverdue(_ move: TodayMove, store: TaskStore, now: Date = Date()) {
        let ids = store.todayPlan(now: now).overdue.map(\.id)
        guard !ids.isEmpty else { return }
        moveToDay(ids, move, store: store, now: now)
    }
}
