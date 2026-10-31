import Foundation

// The Today page's sections and the actions it adds (Add to Today, → Tomorrow, Move all overdue),
// each with its toast. The data comes from TaskStore.todayPlan.

/// One section of the Today page.
struct TodaySection: Equatable {
    enum Kind: Equatable { case running, overdue, dueToday, focus, done }

    let kind: Kind
    let key: String
    let title: String
    let tasks: [TaskItem]
}

extension TasksViewModel {
    static let todayRunningKey = "today-running"
    static let todayOverdueKey = "today-overdue"
    static let todayDueKey = "today-due"
    static let todayFocusKey = "today-focus"
    static let todayDoneKey = "today-done"

    /// The sections in page order. Running, Overdue, Due today and Done today only show with
    /// tasks in them; My focus always shows (its empty state says how to pin tasks).
    static func todaySections(_ plan: TodayPlan) -> [TodaySection] {
        var sections: [TodaySection] = []
        if !plan.running.isEmpty { sections.append(TodaySection(kind: .running, key: todayRunningKey, title: "Running", tasks: plan.running)) }
        if !plan.overdue.isEmpty { sections.append(TodaySection(kind: .overdue, key: todayOverdueKey, title: "Overdue", tasks: plan.overdue)) }
        if !plan.dueToday.isEmpty { sections.append(TodaySection(kind: .dueToday, key: todayDueKey, title: "Due today", tasks: plan.dueToday)) }
        sections.append(TodaySection(kind: .focus, key: todayFocusKey, title: "My focus", tasks: plan.focus))
        if !plan.doneToday.isEmpty { sections.append(TodaySection(kind: .done, key: todayDoneKey, title: "Done today", tasks: plan.doneToday)) }
        return sections
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
