import Foundation

/// What a task list is sorted by. `manual` is the drag order (`sortIndex`).
/// The list column headers set it; the filter bar's Sort menu can reuse it.
enum TaskSortKey: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case manual, status, title, project, milestone, sprint, due, priority, expected, created, updated

    static var fallback: TaskSortKey { .manual }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .status: return "Status"
        case .title: return "Title"
        case .project: return "Project"
        case .milestone: return "Milestone"
        case .sprint: return "Sprint"
        case .due: return "Due"
        case .priority: return "Priority"
        case .expected: return "Expected"
        case .created: return "Created"
        case .updated: return "Updated"
        }
    }

    /// Direction of the first click: the most useful end first
    /// (high priority, soonest due, newest change, A to Z).
    var defaultAscending: Bool {
        switch self {
        case .priority, .created, .updated: return false
        default: return true
        }
    }
}

/// A sort key plus its direction. Ties fall back to the manual order.
struct TaskSort: Equatable, Codable, Sendable {
    var key: TaskSortKey
    var ascending: Bool

    static let manual = TaskSort(key: .manual, ascending: true)

    init(key: TaskSortKey, ascending: Bool? = nil) {
        self.key = key
        self.ascending = ascending ?? key.defaultAscending
    }

    var isManual: Bool { key == .manual }

    /// Clicking a column header: a new key starts in its default direction, the same key flips,
    /// and a third click goes back to the manual order.
    func toggled(_ key: TaskSortKey) -> TaskSort {
        guard key != .manual else { return .manual }
        guard self.key == key else { return TaskSort(key: key) }
        if ascending == key.defaultAscending { return TaskSort(key: key, ascending: !ascending) }
        return .manual
    }

    private enum CodingKeys: String, CodingKey { case key, ascending }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = c.decode(.key, or: TaskSortKey.manual)
        self.init(key: key, ascending: c.decodeOptional(.ascending))
    }
}
