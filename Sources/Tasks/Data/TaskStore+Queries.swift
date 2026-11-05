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

    /// The project a task belongs to
    func project(of task: TaskItem) -> Project? { project(task.projectId) }

    // MARK: - Task lists

    /// Every task in the scope, closed ones included. All projects leaves out archived projects.
    func tasks(in scope: TaskScope) -> [TaskItem] {
        let all: [TaskItem]
        if let projectId = scope.projectId {
            all = workspace.tasks.filter { $0.projectId == projectId }
        } else {
            let archived = Set(archivedProjects.map(\.id))
            all = archived.isEmpty ? workspace.tasks : workspace.tasks.filter { !archived.contains($0.projectId) }
        }
        return all.sorted { $0.sortIndex < $1.sortIndex }
    }

    func tasks(of projectId: UUID) -> [TaskItem] { tasks(in: .project(projectId)) }

    /// List group: all tasks in scope with the given status (closed sprints included).
    func listTasks(in scope: TaskScope, status: WorkflowStatus) -> [TaskItem] {
        tasks(in: scope).filter { $0.statusId == status.id }
    }

    /// Sprints view group: the tasks in `scope` (All projects by default) sitting in the active
    /// sprint, the next one (not the later ones, see `sprintTasks(ahead:in:)`) or the backlog.
    /// Projects that don't take part in sprints have none.
    func sprintTasks(slot: SprintSlot, in scope: TaskScope = .all) -> [TaskItem] {
        if slot == .next { return sprintTasks(ahead: 1, in: scope) }
        return Self.openFirst(tasks(in: scope).filter { $0.sprintSlot == slot && usesSprints($0.projectId) })
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

    // MARK: - Sprints

    /// "Sprint 14"
    func sprintName() -> String { workspace.sprint.name }

    /// "Oct 26 – Nov 8"
    func sprintDateRange() -> String { workspace.sprint.dateRange }

    /// The active sprint, shared by every project.
    var sprint: SprintState { workspace.sprint }

    /// Label for a task's slot: "Sprint 14", "Sprint 15", "Backlog", or for a closed task the
    /// past sprint it closed in ("Sprint 12"; "Closed sprint" for older data). Empty for an open
    /// task of a project without sprints.
    func sprintLabel(for task: TaskItem) -> String {
        if task.sprintSlot != .closed, !usesSprints(task.projectId) { return "" }
        if task.sprintSlot == .closed, let number = task.closedSprintNumber { return "Sprint \(number)" }
        if let ahead = upcomingAhead(of: task) { return workspace.sprint.name(ahead: ahead) }
        return sprintLabel(task.sprintSlot)
    }

    /// Completed sprints, newest first.
    func pastSprints() -> [PastSprint] { workspace.pastSprints.reversed() }

    /// The tasks of a past sprint that still exist, in manual order.
    /// Only those in `scope` when given (one project's slice of a sprint of all projects).
    func tasks(of pastSprint: PastSprint, in scope: TaskScope = .all) -> [TaskItem] {
        let ids = Set(pastSprint.taskIds)
        return workspace.tasks
            .filter { ids.contains($0.id) && (scope.projectId == nil || $0.projectId == scope.projectId) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func sprintLabel(_ slot: SprintSlot) -> String {
        let sprint = workspace.sprint
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
