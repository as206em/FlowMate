import Foundation

// Today: what to work on today across every project. Tasks you pinned ("Add to Today", ⌘T), tasks
// due today or overdue, the timers running, what you finished today and the time tracked today.
// The menu bar's Up next and the morning notification read the same queries.
//
// Pinning stores the day (TaskItem.focusDate). An open task pinned on an earlier day rolls into
// today's My focus on its own and says so ("From yesterday"); "→ Tomorrow" pins it to tomorrow
// instead, which hides it until then.

/// Everything the Today page shows, each task in one section only: a running task shows under
/// Running; a pinned one under My focus (even when it's due or overdue); the rest by due date.
struct TodayPlan: Equatable {
    var running: [TaskItem] = []
    var overdue: [TaskItem] = []
    var dueToday: [TaskItem] = []
    /// Pinned for today or carried over from an earlier day, not running, in your order
    var focus: [TaskItem] = []
    /// Done (not canceled) today, latest first
    var doneToday: [TaskItem] = []
    /// What's left of the pinned tasks (running ones included): expected time minus time tracked
    var plannedSeconds: TimeInterval = 0
    /// Pinned tasks carried over from an earlier day
    var carriedOver: Int = 0
    /// Time tracked today, all projects, running timers included
    var trackedSeconds: TimeInterval = 0
    /// Time tracked today per project, most first
    var trackedByProject: [ProjectTime] = []

    struct ProjectTime: Equatable {
        let projectId: UUID
        let name: String
        let colorHex: UInt32
        let seconds: TimeInterval
    }

    /// Every task on the page, top to bottom (↑/↓ walk this order)
    var allTasks: [TaskItem] { running + overdue + dueToday + focus + doneToday }

    var isEmpty: Bool { running.isEmpty && overdue.isEmpty && dueToday.isEmpty && focus.isEmpty && doneToday.isEmpty }
}

/// What the "→ Tomorrow" button on a Today row (and the bulk actions) can move.
enum TodayMove: Equatable, Sendable {
    case today, tomorrow
}

extension TaskStore {
    // MARK: - Queries

    /// The task is pinned for `now`'s day or an earlier one, and still open.
    func isInFocus(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !task.isClosed, let day = task.focusDate else { return false }
        return day < Self.dayInterval(now, calendar: calendar).end
    }

    /// "From yesterday" / "From Tue, Oct 28" for a task pinned on an earlier day; nil when it was
    /// pinned today (or isn't pinned).
    func focusCarryLabel(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let day = task.focusDate, isInFocus(task, now: now, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard day < today else { return nil }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day >= yesterday { return "From yesterday" }
        return "From " + Self.focusDayFormatter.string(from: day)
    }

    private static let focusDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    /// Open tasks of the projects in the sidebar (archived projects stay out of Today).
    private func openActiveTasks() -> [TaskItem] {
        let archived = Set(archivedProjects.map(\.id))
        return workspace.tasks.filter { !$0.isClosed && !archived.contains($0.projectId) }
    }

    func todayPlan(now: Date = Date(), calendar: Calendar = .current) -> TodayPlan {
        let archived = Set(archivedProjects.map(\.id))
        let day = Self.dayInterval(now, calendar: calendar)
        let open = openActiveTasks()
        var plan = TodayPlan()
        plan.running = runningTasks.filter { !archived.contains($0.projectId) }
        let running = Set(plan.running.map(\.id))
        let pinned = open.filter { isInFocus($0, now: now, calendar: calendar) }
        let pinnedIds = Set(pinned.map(\.id))
        let rest = open.filter { !running.contains($0.id) && !pinnedIds.contains($0.id) }

        plan.overdue = rest.filter { isOverdue($0, now: now) }.sorted { a, b in
            if a.dueDate != b.dueDate { return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }
            return Self.byPriority(a, b)
        }
        plan.dueToday = rest.filter { isDueToday($0, now: now) }.sorted(by: Self.byPriority)
        plan.focus = pinned.filter { !running.contains($0.id) }.sorted(by: Self.byFocusOrder)
        plan.doneToday = workspace.tasks
            .filter { $0.isDone && !archived.contains($0.projectId) && ($0.completedAt.map(day.contains) ?? false) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        plan.plannedSeconds = pinned.reduce(0) { total, task in
            total + max(0, TimeInterval(task.expectedMinutes * 60) - elapsed(task, now: now))
        }
        plan.carriedOver = pinned.filter { ($0.focusDate ?? day.start) < day.start }.count
        plan.trackedSeconds = trackedSeconds(.all, in: day, now: now)
        plan.trackedByProject = trackedSecondsByProject(in: day, now: now)
            .compactMap { id, seconds -> TodayPlan.ProjectTime? in
                guard let project = project(id), seconds >= 1 else { return nil }
                return TodayPlan.ProjectTime(projectId: id, name: project.name, colorHex: project.colorHex, seconds: seconds)
            }
            .sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
        return plan
    }

    /// The sidebar's Today badge: open tasks that are overdue, due today or pinned for today.
    func todayCount(now: Date = Date(), calendar: Calendar = .current) -> Int {
        openActiveTasks().filter { isOverdue($0, now: now) || isDueToday($0, now: now) || isInFocus($0, now: now, calendar: calendar) }.count
    }

    /// Open tasks due today and overdue (the menu header and the morning summary).
    func dueCounts(now: Date = Date()) -> (dueToday: Int, overdue: Int) {
        let open = openActiveTasks()
        return (open.filter { isDueToday($0, now: now) }.count, open.filter { isOverdue($0, now: now) }.count)
    }

    /// The menu bar's Up next: overdue, due today and pinned tasks, then the top not started tasks
    /// of each project's active sprint (high priority first), leaving out what the menu already
    /// lists as in progress. At most `limit`.
    func upNext(limit: Int = 6, now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let listed = menuInProgressTasks
        var seen = Set((listed.running + listed.paused).map(\.id))
        var result: [TaskItem] = []
        func add(_ tasks: [TaskItem]) {
            for task in tasks where result.count < limit && seen.insert(task.id).inserted { result.append(task) }
        }
        let open = openActiveTasks()
        add(open.filter { isOverdue($0, now: now) }.sorted { ($0.dueDate ?? .distantFuture, -$0.priority.rank) < ($1.dueDate ?? .distantFuture, -$1.priority.rank) })
        add(open.filter { isDueToday($0, now: now) }.sorted(by: Self.byPriority))
        add(open.filter { isInFocus($0, now: now, calendar: calendar) }.sorted(by: Self.byFocusOrder))
        let projectOrder = Dictionary(projects.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        add(open.filter { $0.sprintSlot == .active && $0.statusCategory == .notStarted }.sorted { a, b in
            if a.priority != b.priority { return a.priority.rank > b.priority.rank }
            let pa = projectOrder[a.projectId] ?? .max, pb = projectOrder[b.projectId] ?? .max
            return pa == pb ? a.sortIndex < b.sortIndex : pa < pb
        })
        return result
    }

    /// High priority first, then the user's order.
    static func byPriority(_ a: TaskItem, _ b: TaskItem) -> Bool {
        a.priority == b.priority ? a.sortIndex < b.sortIndex : a.priority.rank > b.priority.rank
    }

    static func byFocusOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        a.focusIndex == b.focusIndex ? byPriority(a, b) : a.focusIndex < b.focusIndex
    }

    // MARK: - Pinning

    /// "Add to Today": pins the tasks for today, after the ones already pinned. Closed tasks are
    /// skipped. One undo step.
    func addToToday(_ ids: [UUID], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let ids = existing(ids)
        mutate(ids.count == 1 ? "Add to Today" : "Add tasks to Today") { ws in
            var next = (ws.tasks.filter { $0.focusDate != nil && !$0.isClosed }.map(\.focusIndex).max() ?? -1) + 1
            for id in ids {
                guard let i = ws.tasks.firstIndex(where: { $0.id == id }), !ws.tasks[i].isClosed else { continue }
                let alreadyToday = ws.tasks[i].focusDate == today
                ws.tasks[i].focusDate = today
                if !alreadyToday {
                    ws.tasks[i].focusIndex = next
                    next += 1
                }
            }
        }
    }

    /// "Remove from Today". One undo step.
    func removeFromToday(_ ids: [UUID]) {
        let ids = Set(existing(ids))
        mutate(ids.count == 1 ? "Remove from Today" : "Remove tasks from Today") { ws in
            for i in ws.tasks.indices where ids.contains(ws.tasks[i].id) { ws.tasks[i].focusDate = nil }
        }
    }

    /// ⌘T and the menus: pins the tasks, or unpins them when every one is already in Today.
    /// Returns true when they were added.
    @discardableResult
    func toggleToday(_ ids: [UUID], now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let tasks = existing(ids).compactMap { task($0) }
        guard !tasks.isEmpty else { return false }
        if tasks.allSatisfy({ isInFocus($0, now: now, calendar: calendar) || ($0.isClosed && $0.isPinned) }) {
            removeFromToday(tasks.map(\.id))
            return false
        }
        addToToday(tasks.map(\.id), now: now, calendar: calendar)
        return true
    }

    /// Drag in My focus: pins the task (if it wasn't) and puts it before another pinned task, or
    /// last. One undo step.
    func moveInFocus(_ id: UUID, before beforeId: UUID?, now: Date = Date(), calendar: Calendar = .current) {
        guard let moving = task(id), !moving.isClosed, id != beforeId else { return }
        var order = todayPlan(now: now, calendar: calendar).focus.map(\.id).filter { $0 != id }
        let at = beforeId.flatMap { order.firstIndex(of: $0) } ?? order.count
        order.insert(id, at: at)
        let today = calendar.startOfDay(for: now)
        let wasPinned = isInFocus(moving, now: now, calendar: calendar)
        mutate(wasPinned ? "Reorder Today" : "Add to Today") { ws in
            for (index, taskId) in order.enumerated() {
                guard let i = ws.tasks.firstIndex(where: { $0.id == taskId }) else { continue }
                ws.tasks[i].focusIndex = Double(index)
                if taskId == id, !wasPinned { ws.tasks[i].focusDate = today }
            }
        }
    }

    /// "→ Tomorrow" on a Today row, or a bulk move: a pinned task is pinned to that day instead, and
    /// a due date on or before today moves to that day. Moving to today pins nothing; it only
    /// brings overdue dates to today. One undo step.
    func moveToDay(_ ids: [UUID], _ move: TodayMove, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let target = move == .today ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        let ids = Set(existing(ids))
        let end = Self.dayInterval(now, calendar: calendar).end
        mutate(move == .today ? "Move to today" : "Move to tomorrow") { ws in
            for i in ws.tasks.indices where ids.contains(ws.tasks[i].id) && !ws.tasks[i].isClosed {
                var task = ws.tasks[i]
                if let due = task.dueDate, due < end, due != target { task.dueDate = target }
                if move == .tomorrow, let pinned = task.focusDate, pinned < end { task.focusDate = target }
                guard task != ws.tasks[i] else { continue }
                task.updatedAt = now
                ws.tasks[i] = task
            }
        }
    }
}
