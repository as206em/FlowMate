import Foundation

// Read-only helpers for views. All task lists are sorted by `sortIndex`.
extension TaskStore {
    // MARK: - Lookup

    /// Projects in the sidebar, pickers and menu bar: not archived, in the user's order.
    var projects: [Project] { workspace.projects.filter { !$0.isArchived } }

    /// Archived projects, in the user's order (the sidebar's Archived section).
    var archivedProjects: [Project] { workspace.projects.filter(\.isArchived) }

    /// Every project, archived included.
    var allProjects: [Project] { workspace.projects }

    func isArchived(_ projectId: UUID) -> Bool { project(projectId)?.isArchived ?? false }

    func project(_ id: UUID) -> Project? {
        workspace.projects.first { $0.id == id }
    }

    func task(_ id: UUID) -> TaskItem? {
        workspace.tasks.first { $0.id == id }
    }

    func milestone(_ id: UUID) -> Milestone? {
        workspace.milestones.first { $0.id == id }
    }

    /// The project a task belongs to
    func project(of task: TaskItem) -> Project? { project(task.projectId) }

    func milestone(of task: TaskItem) -> Milestone? { task.milestoneId.flatMap { milestone($0) } }

    // MARK: - Task lists

    /// Every task in the scope, closed ones included. All projects leaves out archived projects.
    func tasks(in scope: TaskScope) -> [TaskItem] {
        let all: [TaskItem]
        if let milestoneId = scope.milestoneId {
            all = workspace.tasks.filter { $0.milestoneId == milestoneId }
        } else if let projectId = scope.projectId {
            all = workspace.tasks.filter { $0.projectId == projectId }
        } else {
            let archived = Set(archivedProjects.map(\.id))
            all = archived.isEmpty ? workspace.tasks : workspace.tasks.filter { !archived.contains($0.projectId) }
        }
        return all.sorted { $0.sortIndex < $1.sortIndex }
    }

    func tasks(of projectId: UUID) -> [TaskItem] { tasks(in: .project(projectId)) }

    /// Board column: active-sprint tasks with the given status. A milestone's board shows all of
    /// its tasks (any sprint or the backlog), leaving out only those closed with a past sprint.
    func boardTasks(in scope: TaskScope, status: WorkflowStatus) -> [TaskItem] {
        let now = Date()
        return tasks(in: scope).filter { isOnBoard($0, in: scope, now: now) && $0.statusId == status.id }
    }

    /// All projects board column: active-sprint tasks of a category, whatever their workflow.
    func boardTasks(in scope: TaskScope, category: StatusCategory) -> [TaskItem] {
        let now = Date()
        return tasks(in: scope).filter { isOnBoard($0, in: scope, now: now) && $0.statusCategory == category }
    }

    /// Done and canceled cards of a project without sprints stay on its board this long.
    nonisolated static let sprintlessClosedDays = 14

    /// Board shows the active sprint; a milestone's board shows every sprint and the backlog. A
    /// project without sprints shows every open task, and its done or canceled ones of the last
    /// two weeks (it has no Complete sprint to clear them).
    func isOnBoard(_ task: TaskItem, in scope: TaskScope, now: Date = Date()) -> Bool {
        Self.isOnBoard(task, in: scope, usesSprints: usesSprints(task.projectId), now: now)
    }

    nonisolated static func isOnBoard(_ task: TaskItem, in scope: TaskScope, usesSprints: Bool = true, now: Date = Date()) -> Bool {
        if scope.isMilestone { return task.sprintSlot != .closed }
        if usesSprints { return task.sprintSlot == .active }
        guard task.sprintSlot != .closed else { return false }
        guard task.isClosed else { return true }
        let cutoff = Calendar.current.date(byAdding: .day, value: -sprintlessClosedDays, to: Calendar.current.startOfDay(for: now)) ?? now
        return (task.completedAt ?? task.updatedAt) >= cutoff
    }

    /// List group: all tasks in scope with the given status (closed sprints included).
    func listTasks(in scope: TaskScope, status: WorkflowStatus) -> [TaskItem] {
        tasks(in: scope).filter { $0.statusId == status.id }
    }

    /// Sprints view group for one project: active, next or backlog.
    func sprintTasks(projectId: UUID, slot: SprintSlot) -> [TaskItem] {
        tasks(in: .project(projectId)).filter { $0.sprintSlot == slot }
    }

    /// Case-insensitive title search across all projects, open tasks first (menu bar search).
    func searchTasks(_ query: String, limit: Int = 20) -> [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let matches = tasks(in: .all).filter { $0.title.localizedCaseInsensitiveContains(q) }
        let ordered = matches.filter { !$0.isClosed } + matches.filter(\.isClosed)
        return Array(ordered.prefix(limit))
    }

    /// Unfinished tasks in a project (sidebar count).
    func openCount(_ projectId: UUID) -> Int {
        workspace.tasks.filter { $0.projectId == projectId && !$0.isClosed }.count
    }

    // MARK: - Milestones

    /// Milestones in scope: open ones first, then by due date (undated last), then name.
    /// All projects leaves out archived projects.
    func milestones(in scope: TaskScope) -> [Milestone] {
        if let id = scope.milestoneId { return milestone(id).map { [$0] } ?? [] }
        let archived = scope.projectId == nil ? Set(archivedProjects.map(\.id)) : []
        return workspace.milestones
            .filter { m in scope.projectId.map { m.projectId == $0 } ?? !archived.contains(m.projectId) }
            .sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
    }

    func milestones(of projectId: UUID) -> [Milestone] { milestones(in: .project(projectId)) }

    /// The milestone's tasks in manual order.
    func milestoneTasks(_ milestoneId: UUID) -> [TaskItem] {
        workspace.tasks.filter { $0.milestoneId == milestoneId }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The milestone page for a milestone (nil when it doesn't exist).
    func scope(ofMilestone id: UUID) -> TaskScope? {
        milestone(id).map { .milestone($0.id, projectId: $0.projectId) }
    }

    /// Time tracked on the milestone's tasks (running timers included) and the time they're
    /// expected to take (canceled tasks left out).
    func milestoneTime(_ milestoneId: UUID, now: Date = Date()) -> (tracked: TimeInterval, expectedMinutes: Int) {
        let tasks = workspace.tasks.filter { $0.milestoneId == milestoneId }
        let tracked = tasks.reduce(0) { $0 + elapsed($1, now: now) }
        let expected = tasks.filter { !$0.isCanceled }.reduce(0) { $0 + $1.expectedMinutes }
        return (tracked, expected)
    }

    /// Milestones in scope split by project, in sidebar order (the All projects Milestones tab).
    func milestonesByProject(in scope: TaskScope) -> [(project: Project, milestones: [Milestone])] {
        let all = milestones(in: scope)
        let order = scope.projectId.flatMap { project($0) }.map { [$0] } ?? projects
        return order.compactMap { p in
            let mine = all.filter { $0.projectId == p.id }
            return mine.isEmpty ? nil : (p, mine)
        }
    }

    func milestoneProgress(_ milestoneId: UUID) -> MilestoneProgress {
        // Canceled tasks are no longer part of the work
        let tasks = workspace.tasks.filter { $0.milestoneId == milestoneId && !$0.isCanceled }
        return MilestoneProgress(done: tasks.filter(\.isDone).count, total: tasks.count)
    }

    /// An open milestone past its due date with unfinished tasks.
    func isOverdue(_ milestone: Milestone, now: Date = Date()) -> Bool {
        guard !milestone.isCompleted, let due = milestone.dueDate else { return false }
        let progress = milestoneProgress(milestone.id)
        return progress.done < progress.total && TaskDates.isBeforeToday(due, now: now)
    }

    // MARK: - Sprints

    /// "Sprint 14"
    func sprintName(_ projectId: UUID) -> String {
        project(projectId)?.sprint.name ?? ""
    }

    /// "Oct 26 – Nov 8"
    func sprintDateRange(_ projectId: UUID) -> String {
        project(projectId)?.sprint.dateRange ?? ""
    }

    /// Label for a task's slot: "Sprint 14", "Sprint 15", "Backlog", or for a closed task the
    /// past sprint it closed in ("Sprint 12"; "Closed sprint" for older data). Empty for an open
    /// task of a project without sprints.
    func sprintLabel(for task: TaskItem) -> String {
        if task.sprintSlot != .closed, !usesSprints(task.projectId) { return "" }
        if task.sprintSlot == .closed, let number = task.closedSprintNumber { return "Sprint \(number)" }
        return sprintLabel(task.sprintSlot, projectId: task.projectId)
    }

    /// Completed sprints, newest first.
    func pastSprints(_ projectId: UUID) -> [PastSprint] {
        (project(projectId)?.pastSprints ?? []).reversed()
    }

    /// The tasks of a past sprint that still exist, in manual order.
    func tasks(of pastSprint: PastSprint) -> [TaskItem] {
        let ids = Set(pastSprint.taskIds)
        return workspace.tasks.filter { ids.contains($0.id) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    func sprintLabel(_ slot: SprintSlot, projectId: UUID) -> String {
        guard let sprint = project(projectId)?.sprint else { return "" }
        switch slot {
        case .active: return sprint.name
        case .next: return sprint.nextName
        case .backlog: return "Backlog"
        case .closed: return "Past sprint"
        }
    }

    // MARK: - Due dates

    /// Open (not done or canceled) task whose due date is before today.
    func isOverdue(_ task: TaskItem, now: Date = Date()) -> Bool {
        guard !task.isClosed, let due = task.dueDate else { return false }
        return TaskDates.isBeforeToday(due, now: now)
    }

    /// Open task due today.
    func isDueToday(_ task: TaskItem, now: Date = Date()) -> Bool {
        guard !task.isClosed, let due = task.dueDate else { return false }
        return Calendar.current.isDate(due, inSameDayAs: now)
    }
}

enum TaskDates {
    // DateFormatters are expensive to create, and a list label is formatted for every task
    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
    private static let sameYearFormatter = makeFormatter("MMM d")
    private static let otherYearFormatter = makeFormatter("MMM d, yyyy")

    static func isBeforeToday(_ date: Date, now: Date = Date()) -> Bool {
        date < Calendar.current.startOfDay(for: now)
    }

    /// "Today", "Tomorrow", "Yesterday", or "Nov 18" ("Nov 18, 2027" outside the current year).
    static func dueLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return (calendar.isDate(date, equalTo: now, toGranularity: .year) ? sameYearFormatter : otherYearFormatter).string(from: date)
    }
}
