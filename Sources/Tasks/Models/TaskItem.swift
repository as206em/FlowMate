import Foundation

enum TaskStatus: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case todo, inProgress, done

    static var fallback: TaskStatus { .todo }
    var id: String { rawValue }

    /// The one display order used everywhere: board columns, list groups, menus and pickers.
    static let ordered: [TaskStatus] = [.todo, .inProgress, .done]

    /// What a click on the status circle moves to: To do → In progress → Done → To do.
    var next: TaskStatus {
        switch self {
        case .todo: return .inProgress
        case .inProgress: return .done
        case .done: return .todo
        }
    }

    var title: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }

    var focusKind: FocusStatusKind {
        switch self {
        case .todo: return .todo
        case .inProgress: return .inProgress
        case .done: return .done
        }
    }
}

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
    var status: TaskStatus
    var priority: TaskPriority
    var title: String
    /// Markdown description
    var notes: String
    var subtasks: [Subtask]
    var dueDate: Date?
    var expectedMinutes: Int
    /// Accumulated time from paused sessions; a running session is added on top (see TaskStore.elapsed)
    var spentSeconds: TimeInterval
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Double
    /// The sprint number a `closed` task was closed in ("Sprint 3"); nil for older data.
    var closedSprintNumber: Int?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        milestoneId: UUID? = nil,
        sprintSlot: SprintSlot = .active,
        status: TaskStatus = .todo,
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
        closedSprintNumber: Int? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.milestoneId = milestoneId
        self.sprintSlot = sprintSlot
        self.status = status
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
    }

    var isDone: Bool { status == .done }
    var subtasksDone: Int { subtasks.filter(\.isDone).count }
    /// "2/4", or nil when there are no subtasks
    var subtaskSummary: String? { subtasks.isEmpty ? nil : "\(subtasksDone)/\(subtasks.count)" }

    private enum CodingKeys: String, CodingKey {
        case id, projectId, milestoneId, sprintSlot, status, priority, title, notes, subtasks
        case dueDate, expectedMinutes, spentSeconds, createdAt, updatedAt, sortIndex, closedSprintNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        milestoneId = c.decodeOptional(.milestoneId)
        sprintSlot = c.decode(.sprintSlot, or: .backlog)
        status = c.decode(.status, or: .todo)
        priority = c.decode(.priority, or: .medium)
        title = c.decode(.title, or: "Untitled task")
        notes = c.decode(.notes, or: "")
        subtasks = c.decodeLossyArray(.subtasks)
        dueDate = c.decodeOptional(.dueDate)
        expectedMinutes = max(1, c.decode(.expectedMinutes, or: TaskItem.defaultExpectedMinutes))
        spentSeconds = max(0, c.decode(.spentSeconds, or: 0))
        createdAt = c.decode(.createdAt, or: Date())
        updatedAt = c.decode(.updatedAt, or: createdAt)
        sortIndex = c.decode(.sortIndex, or: 0)
        closedSprintNumber = c.decodeOptional(.closedSprintNumber)
    }
}
