import Foundation

/// Due-date filter chip values. Several can be on at once (they combine with OR).
enum TaskDueFilter: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case overdue, thisWeek, noDate

    static var fallback: TaskDueFilter { .noDate }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .thisWeek: return "This week"
        case .noDate: return "No date"
        }
    }
}

/// What the filter bar narrows List and Board to. Every dimension is a set; an empty set means
/// "any". Values inside one dimension combine with OR, dimensions combine with AND.
struct TaskFilter: Equatable, Codable, Sendable {
    /// Words to find in the title, description or subtasks. Every word must match somewhere.
    var query = ""
    /// Status ids of the project's workflow (a project's filter bar).
    var statuses: Set<String> = []
    /// Status categories (the All projects filter bar, where workflows differ). Statuses and
    /// categories are one dimension: a task matching either is shown.
    var categories: Set<StatusCategory> = []
    var priorities: Set<TaskPriority> = []
    /// Milestone ids; `nil` stands for "No milestone".
    var milestones: Set<UUID?> = []
    var sprintSlots: Set<SprintSlot> = []
    var due: Set<TaskDueFilter> = []
    /// Only used in All projects.
    var projectIds: Set<UUID> = []

    init() {}

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when nothing narrows the tasks.
    var isEmpty: Bool { trimmedQuery.isEmpty && chipCount == 0 }

    /// How many dimensions (chips) are set, search excluded.
    var chipCount: Int {
        [statuses.isEmpty && categories.isEmpty, priorities.isEmpty, milestones.isEmpty, sprintSlots.isEmpty, due.isEmpty, projectIds.isEmpty]
            .filter { !$0 }.count
    }

    private enum CodingKeys: String, CodingKey { case query, statuses, categories, priorities, milestones, sprintSlots, due, projectIds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = c.decode(.query, or: "")
        // Older state stored "todo" / "inProgress" / "done", the ids of the Simple workflow
        statuses = c.decode(.statuses, or: [])
        categories = c.decode(.categories, or: [])
        priorities = c.decode(.priorities, or: [])
        milestones = c.decode(.milestones, or: [])
        sprintSlots = c.decode(.sprintSlots, or: [])
        due = c.decode(.due, or: [])
        projectIds = c.decode(.projectIds, or: [])
    }
}

/// What the List groups its rows by. Dragging a row to another group changes that value.
enum TaskGrouping: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case status, milestone, project, priority, sprint

    static var fallback: TaskGrouping { .status }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .milestone: return "Milestone"
        case .project: return "Project"
        case .priority: return "Priority"
        case .sprint: return "Sprint"
        }
    }

    /// Groupings that make sense in a scope: Project only in All projects, Milestone not on a
    /// milestone's page (every task there has the same one).
    static func available(in scope: TaskScope) -> [TaskGrouping] {
        if scope.isMilestone { return allCases.filter { $0 != .project && $0 != .milestone } }
        return scope.projectId == nil ? allCases : allCases.filter { $0 != .project }
    }
}

/// Sort choices offered by the filter bar's Sort menu. Column headers can set the others.
extension TaskSortKey {
    static let menuChoices: [TaskSortKey] = [.manual, .priority, .due, .created, .updated]
}

/// How one scope's List and Board are narrowed, sorted and grouped. Kept per project.
struct TaskViewOptions: Equatable, Codable, Sendable {
    var filter = TaskFilter()
    var sort: TaskSort = .manual
    var grouping: TaskGrouping = .status

    init(filter: TaskFilter = TaskFilter(), sort: TaskSort = .manual, grouping: TaskGrouping = .status) {
        self.filter = filter
        self.sort = sort
        self.grouping = grouping
    }

    static let standard = TaskViewOptions()

    /// True when anything differs from the defaults (shows "Clear").
    var isCustomized: Bool { self != .standard }

    /// The grouping actually used in a scope (Project grouping falls back to Status inside a project).
    func effectiveGrouping(in scope: TaskScope) -> TaskGrouping {
        TaskGrouping.available(in: scope).contains(grouping) ? grouping : .status
    }

    private enum CodingKeys: String, CodingKey { case filter, sort, grouping }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filter = c.decode(.filter, or: TaskFilter())
        sort = c.decode(.sort, or: .manual)
        grouping = c.decode(.grouping, or: .status)
    }
}

/// The value a List group stands for. Dropping a task on the group sets it.
enum TaskGroupValue: Hashable, Sendable {
    /// A status of the project's workflow
    case status(WorkflowStatus)
    /// A status category (All projects, where workflows differ)
    case category(StatusCategory)
    case milestone(UUID?)
    case project(UUID)
    case priority(TaskPriority)
    case sprint(SprintSlot)

    /// Stable key for collapsing and the drop outline. Groups of done and canceled statuses start
    /// with "closed-", so they start collapsed (TasksViewModel.startsCollapsed).
    var key: String {
        switch self {
        case let .status(s): return (s.isClosed ? "closed-" : "") + "status-\(s.id)"
        case let .category(c): return (c.isClosed ? "closed-" : "") + "category-\(c.rawValue)"
        case let .milestone(id): return "milestone-\(id?.uuidString ?? "none")"
        case let .project(id): return "project-\(id.uuidString)"
        case let .priority(p): return "priority-\(p.rawValue)"
        case let .sprint(slot): return "sprint-\(slot.rawValue)"
        }
    }
}

/// One List group: header text, the value it stands for and its tasks.
struct TaskGroup: Identifiable, Equatable, Sendable {
    let value: TaskGroupValue
    let title: String
    var hint: String = ""
    /// Project tile color for project and All-projects milestone groups
    var colorHex: UInt32?
    /// Status and category groups: the status icon to draw
    var statusKind: FocusStatusKind?
    var statusColorHex: UInt32?
    /// False for groups you can't drop into (closed sprints)
    var acceptsDrop = true
    var tasks: [TaskItem]

    var id: String { value.key }
}
