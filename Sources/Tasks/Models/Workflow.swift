import Foundation

// Statuses per project (a custom workflow). Every project owns an ordered list of statuses;
// each status belongs to one of four categories, and all behaviour follows the category, never
// the name: starting a timer, pausing on done, Complete sprint, overdue, the menu bar's play
// button, collapsing finished groups and the All projects board.

/// What a status means to the app.
enum StatusCategory: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case notStarted, started, done, canceled

    static var fallback: StatusCategory { .notStarted }
    var id: String { rawValue }

    /// The one display order used everywhere: Not started → Started → Done → Canceled.
    static let ordered: [StatusCategory] = [.notStarted, .started, .done, .canceled]

    var title: String {
        switch self {
        case .notStarted: return "Not started"
        case .started: return "Started"
        case .done: return "Done"
        case .canceled: return "Canceled"
        }
    }

    /// Done or canceled: no timer, no overdue, collapsed in List, closed by Complete sprint.
    var isClosed: Bool { self == .done || self == .canceled }

    /// The color a new status of this category gets.
    var defaultColorHex: UInt32 {
        switch self {
        case .notStarted, .canceled: return WorkflowStatus.grayHex
        case .started: return WorkflowStatus.amberHex
        case .done: return WorkflowStatus.purpleHex
        }
    }

    var focusKind: FocusStatusKind {
        switch self {
        case .notStarted: return .todo
        case .started: return .inProgress
        case .done: return .done
        case .canceled: return .canceled
        }
    }

    /// Sort rank (Not started first)
    var rank: Int { Self.ordered.firstIndex(of: self) ?? 0 }
}

/// One column of a project's workflow ("Review", started, teal).
struct WorkflowStatus: Identifiable, Codable, Hashable, Sendable {
    /// Unique inside its project. Preset statuses use readable ids ("todo", "review"); ones you
    /// add get a UUID string. Tasks store this id.
    var id: String
    var name: String
    /// 0xRRGGBB from Focus.statusPalette
    var colorHex: UInt32
    var category: StatusCategory

    init(id: String = UUID().uuidString, name: String, colorHex: UInt32? = nil, category: StatusCategory) {
        self.id = id
        self.name = name
        self.colorHex = colorHex ?? category.defaultColorHex
        self.category = category
    }

    static let grayHex: UInt32 = 0x6E6E78
    static let amberHex: UInt32 = 0xB76E00
    static let purpleHex: UInt32 = 0x6D5AE6
    static let tealHex: UInt32 = 0x14B8A6

    // The Simple preset (and what every older file migrates to). The ids match the old fixed
    // statuses, so old data maps one to one.
    static let todo = WorkflowStatus(id: "todo", name: "To do", colorHex: grayHex, category: .notStarted)
    static let inProgress = WorkflowStatus(id: "inProgress", name: "In progress", colorHex: amberHex, category: .started)
    static let done = WorkflowStatus(id: "done", name: "Done", colorHex: purpleHex, category: .done)
    static let canceled = WorkflowStatus(id: "canceled", name: "Canceled", colorHex: grayHex, category: .canceled)

    var isClosed: Bool { category.isClosed }

    private enum CodingKeys: String, CodingKey { case id, name, colorHex, category }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = c.decode(.category, or: .notStarted)
        let name: String = c.decode(.name, or: "")
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.title : name
        colorHex = c.decode(.colorHex, or: category.defaultColorHex)
    }
}

/// Ready-made workflows to apply to a project.
enum WorkflowPreset: String, CaseIterable, Identifiable, Sendable {
    case simple, dev, kanban

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .dev: return "Dev"
        case .kanban: return "Kanban"
        }
    }

    var statuses: [WorkflowStatus] {
        switch self {
        case .simple:
            return [.todo, .inProgress, .done]
        case .dev:
            return [
                WorkflowStatus(id: "backlog", name: "Backlog", colorHex: WorkflowStatus.grayHex, category: .notStarted),
                .todo,
                .inProgress,
                WorkflowStatus(id: "review", name: "Review", colorHex: WorkflowStatus.tealHex, category: .started),
                .done,
                .canceled,
            ]
        case .kanban:
            return [.todo,
                    WorkflowStatus(id: "doing", name: "Doing", colorHex: WorkflowStatus.amberHex, category: .started),
                    .done]
        }
    }

    /// "To do · In progress · Done"
    var summary: String { statuses.map(\.name).joined(separator: " · ") }

    /// The preset a list matches exactly (names, categories and order), if any.
    static func matching(_ statuses: [WorkflowStatus]) -> WorkflowPreset? {
        allCases.first { preset in
            let p = preset.statuses
            return p.count == statuses.count && zip(p, statuses).allSatisfy {
                $0.name == $1.name && $0.category == $1.category
            }
        }
    }
}

/// Rules every workflow keeps: unique ids, a name, at least one Not started and one Done status.
enum WorkflowRules {
    /// Categories a workflow must always have.
    static let required: [StatusCategory] = [.notStarted, .done]

    /// A valid copy of the list: duplicate ids dropped, blank names filled in, and a missing
    /// Not started or Done status added (To do first, Done after the last status).
    static func repaired(_ statuses: [WorkflowStatus]) -> [WorkflowStatus] {
        var seen = Set<String>()
        var list = statuses.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        for i in list.indices where list[i].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list[i].name = list[i].category.title
        }
        if list.isEmpty { return WorkflowPreset.simple.statuses }
        if !list.contains(where: { $0.category == .notStarted }) {
            list.insert(uniqueCopy(of: .todo, in: list), at: 0)
        }
        if !list.contains(where: { $0.category == .done }) {
            list.append(uniqueCopy(of: .done, in: list))
        }
        return list
    }

    /// True when the list can be kept as it is.
    static func isValid(_ statuses: [WorkflowStatus]) -> Bool {
        required.allSatisfy { c in statuses.contains { $0.category == c } }
            && Set(statuses.map(\.id)).count == statuses.count
    }

    private static func uniqueCopy(of status: WorkflowStatus, in list: [WorkflowStatus]) -> WorkflowStatus {
        guard list.contains(where: { $0.id == status.id }) else { return status }
        var copy = status
        copy.id = UUID().uuidString
        return copy
    }

    /// Where a task with `status` lands in `statuses`: the status with the same name and category,
    /// else the first status of the same category, else the closest category (Started → Not
    /// started, Canceled → Done).
    static func remap(_ status: WorkflowStatus, into statuses: [WorkflowStatus]) -> WorkflowStatus {
        if let same = statuses.first(where: {
            $0.category == status.category && $0.name.compare(status.name, options: .caseInsensitive) == .orderedSame
        }) { return same }
        return first(status.category, in: statuses)
    }

    /// The first status of a category in the list, falling back to the closest category.
    static func first(_ category: StatusCategory, in statuses: [WorkflowStatus]) -> WorkflowStatus {
        if let match = statuses.first(where: { $0.category == category }) { return match }
        let fallback: StatusCategory
        switch category {
        case .notStarted, .started: fallback = .notStarted
        case .done, .canceled: fallback = .done
        }
        return statuses.first { $0.category == fallback } ?? statuses.first ?? .todo
    }
}

extension Project {
    func status(_ id: String) -> WorkflowStatus? { statuses.first { $0.id == id } }

    /// The task's status in this project (repaired by category when its id is unknown).
    func status(of task: TaskItem) -> WorkflowStatus {
        status(task.statusId) ?? WorkflowRules.first(task.statusCategory, in: statuses)
    }

    /// The first status of a category (or the closest one, see WorkflowRules.first).
    func firstStatus(_ category: StatusCategory) -> WorkflowStatus { WorkflowRules.first(category, in: statuses) }

    /// Whether the workflow has a status of this category at all.
    func hasCategory(_ category: StatusCategory) -> Bool { statuses.contains { $0.category == category } }

    /// Where new tasks start: the first Not started status.
    var defaultStatus: WorkflowStatus { firstStatus(.notStarted) }

    /// The status circle's click: the next status in the workflow's order, wrapping around.
    func statusAfter(_ id: String) -> WorkflowStatus {
        guard let i = statuses.firstIndex(where: { $0.id == id }) else { return defaultStatus }
        return statuses[(i + 1) % statuses.count]
    }

    /// Position in the workflow, for sorting.
    func statusIndex(_ id: String) -> Int { statuses.firstIndex { $0.id == id } ?? statuses.count }
}

extension Workspace {
    /// Keeps every workflow valid and every task pointing at a status of its own project, with its
    /// stored category matching that status. A task whose status is gone lands on the first status
    /// of the category it had. Cheap enough to run after every change.
    mutating func normalizeStatuses() {
        var byProject: [UUID: [WorkflowStatus]] = [:]
        for i in projects.indices {
            if !WorkflowRules.isValid(projects[i].statuses) {
                projects[i].statuses = WorkflowRules.repaired(projects[i].statuses)
            }
            byProject[projects[i].id] = projects[i].statuses
        }
        for i in tasks.indices {
            guard let statuses = byProject[tasks[i].projectId] else { continue }
            if let status = statuses.first(where: { $0.id == tasks[i].statusId }) {
                if tasks[i].statusCategory != status.category { tasks[i].statusCategory = status.category }
            } else {
                let status = WorkflowRules.first(tasks[i].statusCategory, in: statuses)
                tasks[i].statusId = status.id
                tasks[i].statusCategory = status.category
            }
        }
    }
}
