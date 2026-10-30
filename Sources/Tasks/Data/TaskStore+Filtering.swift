import Foundation

// The filter bar (search, chips, group by) and the edits List groups make when you drop on them.
extension TaskStore {
    // MARK: - Filtering

    /// Tasks matching the filter, in the order given. Ids of deleted milestones or projects are
    /// ignored, so a stale chip never hides everything.
    func filtered(_ tasks: [TaskItem], by filter: TaskFilter, now: Date = Date()) -> [TaskItem] {
        guard !filter.isEmpty else { return tasks }
        let words = filter.trimmedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let milestoneIds = Set(workspace.milestones.map(\.id))
        let milestones = filter.milestones.filter { $0.map(milestoneIds.contains) ?? true }
        let projectIds = filter.projectIds.intersection(workspace.projects.map(\.id))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? today.addingTimeInterval(7 * 86_400)

        return tasks.filter { task in
            if !filter.statuses.isEmpty, !filter.statuses.contains(task.status) { return false }
            if !filter.priorities.isEmpty, !filter.priorities.contains(task.priority) { return false }
            if !milestones.isEmpty, !milestones.contains(task.milestoneId) { return false }
            if !filter.sprintSlots.isEmpty, !filter.sprintSlots.contains(task.sprintSlot) { return false }
            if !projectIds.isEmpty, !projectIds.contains(task.projectId) { return false }
            if !filter.due.isEmpty {
                let matches = filter.due.contains { due in
                    switch due {
                    case .overdue: return isOverdue(task, now: now)
                    case .thisWeek: return task.dueDate.map { $0 >= today && $0 < weekEnd } ?? false
                    case .noDate: return task.dueDate == nil
                    }
                }
                if !matches { return false }
            }
            if !words.isEmpty {
                let fields = [task.title, task.notes] + task.subtasks.map(\.title)
                for word in words where !fields.contains(where: { $0.localizedStandardContains(word) }) {
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Grouping

    /// Splits tasks into List groups. Groups you can drop into are listed even when empty;
    /// closed sprints only when they have tasks. Task order inside a group is kept.
    func groups(_ tasks: [TaskItem], by grouping: TaskGrouping, in scope: TaskScope) -> [TaskGroup] {
        func group(_ value: TaskGroupValue, _ title: String, hint: String = "", color: UInt32? = nil,
                   drop: Bool = true, where match: (TaskItem) -> Bool) -> TaskGroup {
            TaskGroup(value: value, title: title, hint: hint, colorHex: color, acceptsDrop: drop,
                      tasks: tasks.filter(match))
        }
        switch grouping {
        case .status:
            return TaskStatus.ordered.map { status in group(.status(status), status.title) { $0.status == status } }
        case .priority:
            return TaskPriority.ordered.map { p in group(.priority(p), p.title) { $0.priority == p } }
        case .project:
            let projects = scope.projectId.flatMap { project($0) }.map { [$0] } ?? self.projects
            return projects.map { p in group(.project(p.id), p.name, color: p.colorHex) { $0.projectId == p.id } }
        case .milestone:
            let inScope = milestones(in: scope)
            var result = inScope.map { m -> TaskGroup in
                let hint = [scope.projectId == nil ? project(m.projectId)?.name : nil,
                            m.dueDate.map { "Due " + SprintState.shortDate($0) }]
                    .compactMap { $0 }.joined(separator: " · ")
                return group(.milestone(m.id), m.name, hint: hint,
                             color: scope.projectId == nil ? project(m.projectId)?.colorHex : nil) { $0.milestoneId == m.id }
            }
            result.append(group(.milestone(nil), "No milestone") { $0.milestoneId == nil })
            return result
        case .sprint:
            let sprint = scope.projectId.flatMap { project($0)?.sprint }
            var result = [
                group(.sprint(.active), sprint.map { "\($0.name) · active" } ?? "Active sprint",
                      hint: sprint?.dateRange ?? "") { $0.sprintSlot == .active },
                group(.sprint(.next), sprint.map { "\($0.nextName) · next" } ?? "Next sprint",
                      hint: sprint?.nextDateRange ?? "") { $0.sprintSlot == .next },
                group(.sprint(.backlog), "Backlog") { $0.sprintSlot == .backlog },
            ]
            let closed = group(.sprint(.closed), "Past sprints", drop: false) {
                $0.sprintSlot == .closed
            }
            if !closed.tasks.isEmpty { result.append(closed) }
            return result
        }
    }

    // MARK: - Moving between groups

    /// Drops a task on a List group: sets the group's value, then places it before `beforeTaskId`
    /// (or last). Pass `reorder: false` when the list is sorted. One undo step.
    /// A milestone of another project moves the task to that project first.
    func moveTask(_ id: UUID, to value: TaskGroupValue, before beforeTaskId: UUID? = nil,
                  reorder: Bool = true, now: Date = Date()) {
        guard let task = task(id) else { return }
        undoGroup("Move task") {
            switch value {
            case let .status(status):
                if task.status != status { setStatus(id, status, now: now) }
            case let .priority(priority):
                setPriority(id, priority)
            case let .project(projectId):
                setProject(id, projectId)
            case let .sprint(slot):
                guard slot != .closed else { break }
                setSprintSlot(id, slot)
            case let .milestone(milestoneId):
                if let milestoneId, let milestone = milestone(milestoneId), milestone.projectId != task.projectId {
                    setProject(id, milestone.projectId)
                }
                setMilestone(id, milestoneId)
            }
            if reorder { self.reorder(id, before: beforeTaskId) }
        }
    }
}

// MARK: - Due date presets

/// Quick choices above the calendar in due date popovers.
enum DuePreset: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, nextWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .nextWeek: return "Next week"
        }
    }

    /// Midnight of the preset day. Next week is the first day of next week (Monday in most regions).
    func date(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return today
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .nextWeek:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
            let next = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? today
            return calendar.startOfDay(for: next)
        }
    }
}
