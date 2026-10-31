import Foundation

enum TaskPriority: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case low, medium, high

    static var fallback: TaskPriority { .medium }
    var id: String { rawValue }

    /// The one display order used everywhere: High, Medium, Low.
    static let ordered: [TaskPriority] = [.high, .medium, .low]

    /// For sorting: higher is more important
    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var focusLevel: FocusPriorityLevel {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

/// Where a task sits in its project's sprint plan. `closed` is set by "Complete sprint"
/// (the task then belongs to a past sprint and is hidden from List unless a filter shows it).
enum SprintSlot: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case active, next, backlog, closed

    static var fallback: SprintSlot { .backlog }
    var id: String { rawValue }

    /// Slots a user can pick in the task panel or drag between in the Sprints view
    static let plannable: [SprintSlot] = [.active, .next, .backlog]
}

struct Subtask: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }

    private enum CodingKeys: String, CodingKey { case id, title, isDone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decode(.id, or: UUID())
        title = c.decode(.title, or: "")
        isDone = c.decode(.isDone, or: false)
    }
}

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    /// Expected-time choices offered in the UI (15m – 8h)
    static let expectedChoices = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]
    static let defaultExpectedMinutes = 60

    var id: UUID
    var projectId: UUID
    var milestoneId: UUID?
    var sprintSlot: SprintSlot
    /// A status of the task's project (Project.statuses). The store keeps it valid.
    var statusId: String
    /// The category of that status, kept in step by the store (Workspace.normalizeStatuses), so
    /// anything can ask whether a task is done without looking up its project.
    var statusCategory: StatusCategory
    var priority: TaskPriority
    var title: String
    /// Markdown description
    var notes: String
    var subtasks: [Subtask]
    var dueDate: Date?
    var expectedMinutes: Int
    /// Time tracked so far: the sum of the task's time entries (Workspace.timeEntries), kept in step
    /// by the store (Workspace.normalizeTime). A running session is added on top (TaskStore.elapsed).
    var spentSeconds: TimeInterval
    var createdAt: Date
    var updatedAt: Date
    /// When the task last moved into a done or canceled status (which one: `statusCategory`); nil
    /// while it's open. Kept by the store (Workspace.normalizeCompletion).
    var completedAt: Date?
    var sortIndex: Double
    /// The sprint number a `closed` task was closed in ("Sprint 3"); nil for older data.
    var closedSprintNumber: Int?
    /// The number of the upcoming sprint a `next` task is planned in when that is not the one right
    /// after the active sprint (nil: the next one). Meaningful only while the slot is `next`.
    var laterSprint: Int?
    /// The day you pinned the task to Today ("Add to Today", ⌘T), as midnight of that day; nil when
    /// it isn't pinned. An open task pinned on an earlier day stays in Today's My focus, labeled
    /// "From yesterday", until it's done or unpinned.
    var focusDate: Date?
    /// Order inside Today's My focus (drag to reorder); lower comes first.
    var focusIndex: Double
    /// Workspace labels (Workspace.labels), in the order they were added. The store keeps them
    /// existing and unique (Workspace.normalizeLabels).
    var labelIds: [UUID]

    init(
        id: UUID = UUID(),
        projectId: UUID,
        milestoneId: UUID? = nil,
        sprintSlot: SprintSlot = .active,
        status: WorkflowStatus = .todo,
        priority: TaskPriority = .medium,
        title: String,
        notes: String = "",
        subtasks: [Subtask] = [],
        dueDate: Date? = nil,
        expectedMinutes: Int = TaskItem.defaultExpectedMinutes,
        spentSeconds: TimeInterval = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        sortIndex: Double = 0,
        closedSprintNumber: Int? = nil,
        laterSprint: Int? = nil,
        completedAt: Date? = nil,
        focusDate: Date? = nil,
        focusIndex: Double = 0,
        labelIds: [UUID] = []
    ) {
        self.id = id
        self.projectId = projectId
        self.milestoneId = milestoneId
        self.sprintSlot = sprintSlot
        self.statusId = status.id
        self.statusCategory = status.category
        self.priority = priority
        self.title = title
        self.notes = notes
        self.subtasks = subtasks
        self.dueDate = dueDate
        self.expectedMinutes = expectedMinutes
        self.spentSeconds = spentSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.sortIndex = sortIndex
        self.closedSprintNumber = closedSprintNumber
        self.laterSprint = laterSprint
        self.completedAt = status.category.isClosed ? (completedAt ?? self.updatedAt) : nil
        self.focusDate = focusDate
        self.focusIndex = focusIndex
        self.labelIds = labelIds
    }

    /// Finished: done or canceled. Closed tasks have no timer, aren't overdue and collapse in List.
    var isClosed: Bool { statusCategory.isClosed }
    /// Done (not canceled); what progress counts.
    var isDone: Bool { statusCategory == .done }
    var isCanceled: Bool { statusCategory == .canceled }
    var subtasksDone: Int { subtasks.filter(\.isDone).count }
    /// "2/4", or nil when there are no subtasks
    var subtaskSummary: String? { subtasks.isEmpty ? nil : "\(subtasksDone)/\(subtasks.count)" }
    /// Pinned to Today (on any day; see `focusDate`).
    var isPinned: Bool { focusDate != nil }

    private enum CodingKeys: String, CodingKey {
        case id, projectId, milestoneId, sprintSlot, statusId, statusCategory, priority, title, notes, subtasks
        case dueDate, expectedMinutes, spentSeconds, createdAt, updatedAt, completedAt, sortIndex, closedSprintNumber
        case focusDate, focusIndex, labelIds, laterSprint
    }

    private enum LegacyKeys: String, CodingKey { case status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        milestoneId = c.decodeOptional(.milestoneId)
        sprintSlot = c.decode(.sprintSlot, or: .backlog)
        if let id: String = c.decodeOptional(.statusId), !id.isEmpty {
            statusId = id
            statusCategory = c.decode(.statusCategory, or: .notStarted)
        } else {
            // Schema 5 and older: a fixed status ("todo", "inProgress", "done"). The Simple
            // workflow every project migrates to uses the same ids.
            let legacy = (try? decoder.container(keyedBy: LegacyKeys.self))
                .flatMap { $0.decodeOptional(.status) as String? }
            let status = [WorkflowStatus.todo, .inProgress, .done].first { $0.id == legacy } ?? .todo
            statusId = status.id
            statusCategory = status.category
        }
        priority = c.decode(.priority, or: .medium)
        title = c.decode(.title, or: "Untitled task")
        notes = c.decode(.notes, or: "")
        subtasks = c.decodeLossyArray(.subtasks)
        dueDate = c.decodeOptional(.dueDate)
        expectedMinutes = max(1, c.decode(.expectedMinutes, or: TaskItem.defaultExpectedMinutes))
        spentSeconds = max(0, c.decode(.spentSeconds, or: 0))
        createdAt = c.decode(.createdAt, or: Date())
        updatedAt = c.decode(.updatedAt, or: createdAt)
        // Schema 6 and older have none; Workspace.normalizeCompletion fills it for closed tasks
        completedAt = c.decodeOptional(.completedAt)
        sortIndex = c.decode(.sortIndex, or: 0)
        closedSprintNumber = c.decodeOptional(.closedSprintNumber)
        // Schema 8 and older: nothing is pinned to Today
        focusDate = c.decodeOptional(.focusDate)
        focusIndex = c.decode(.focusIndex, or: 0)
        // Schema 10 and older: no labels
        labelIds = c.decodeLossyArray(.labelIds)
        // Older files plan nothing beyond the next sprint
        laterSprint = c.decodeOptional(.laterSprint)
    }
}
