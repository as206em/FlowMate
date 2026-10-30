import Foundation

// Sorting for the list columns. Pure and deterministic: ties keep the manual order.
extension TaskStore {
    /// Sorts tasks by a column. Empty values (no due date, no milestone) always go last,
    /// whichever direction is chosen.
    func sorted(_ tasks: [TaskItem], by sort: TaskSort) -> [TaskItem] {
        let manual = tasks.sorted { $0.sortIndex < $1.sortIndex }
        guard !sort.isManual else { return manual }
        let position = Dictionary(uniqueKeysWithValues: manual.enumerated().map { ($1.id, $0) })
        let key = sortValueProvider(sort.key)
        return manual.sorted { a, b in
            switch (key(a), key(b)) {
            case let (x?, y?):
                if x != y { return sort.ascending ? x < y : y < x }
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            return position[a.id, default: 0] < position[b.id, default: 0]
        }
    }

    /// The comparable value of one column for a task; nil means "empty".
    private func sortValueProvider(_ key: TaskSortKey) -> (TaskItem) -> SortValue? {
        switch key {
        case .manual:
            return { .number($0.sortIndex) }
        case .status:
            return { .number(Double(TaskStatus.ordered.firstIndex(of: $0.status) ?? 0)) }
        case .title:
            return { .text($0.title) }
        case .project:
            let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
            return { names[$0.projectId].map(SortValue.text) }
        case .milestone:
            let names = Dictionary(uniqueKeysWithValues: workspace.milestones.map { ($0.id, $0.name) })
            return { task in task.milestoneId.flatMap { names[$0] }.map(SortValue.text) }
        case .sprint:
            // Plan order: active, next, backlog, then closed
            let order: [SprintSlot] = [.active, .next, .backlog, .closed]
            return { .number(Double(order.firstIndex(of: $0.sprintSlot) ?? order.count)) }
        case .due:
            return { $0.dueDate.map { .number($0.timeIntervalSinceReferenceDate) } }
        case .priority:
            return { .number(Double($0.priority.rank)) }
        case .expected:
            return { .number(Double($0.expectedMinutes)) }
        case .created:
            return { .number($0.createdAt.timeIntervalSinceReferenceDate) }
        case .updated:
            return { .number($0.updatedAt.timeIntervalSinceReferenceDate) }
        }
    }
}

/// A value a column sorts by: numbers compare numerically, text case-insensitively.
private enum SortValue: Equatable, Comparable {
    case number(Double)
    case text(String)

    static func == (lhs: SortValue, rhs: SortValue) -> Bool {
        switch (lhs, rhs) {
        case let (.number(a), .number(b)): return a == b
        case let (.text(a), .text(b)): return a.localizedStandardCompare(b) == .orderedSame
        default: return false
        }
    }

    static func < (lhs: SortValue, rhs: SortValue) -> Bool {
        switch (lhs, rhs) {
        case let (.number(a), .number(b)): return a < b
        case let (.text(a), .text(b)): return a.localizedStandardCompare(b) == .orderedAscending
        case (.number, .text): return true
        case (.text, .number): return false
        }
    }
}
