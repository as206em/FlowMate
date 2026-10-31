import Foundation

// Sprints planned ahead. The workspace has one active sprint (number N); sprints N+1 … N+k follow
// it back to back, each as long as the active one. "Next" is the first of them. A task sits in one
// of them with sprintSlot `next` (laterSprint nil for N+1, the number for a later one).
// Planning a month in weekly sprints is: length 1 week, then "Add 4 sprints".

/// A sprint planned after the active one.
struct UpcomingSprint: Identifiable, Equatable, Sendable {
    /// Places after the active sprint: 1 is the next one
    let ahead: Int
    let number: Int
    let name: String
    /// "Nov 9 – Nov 15"
    let dateRange: String
    let goal: String

    var id: Int { number }
    var isNext: Bool { ahead == 1 }
    /// The group header hint: the dates, then the goal when there is one
    var hint: String { goal.isEmpty ? dateRange : "\(dateRange) · \(goal)" }
}

/// Where a task can sit in the sprint plan, as pickers offer it.
enum SprintChoice: Hashable, Sendable {
    case active
    /// A sprint planned ahead (1 = next)
    case upcoming(Int)
    case backlog
    /// A past sprint: shown, never picked
    case closed
}

extension TaskStore {
    static let maxUpcomingSprints = 26

    /// The sprints planned ahead, soonest first (always at least the next one).
    func upcomingSprints() -> [UpcomingSprint] {
        let sprint = workspace.sprint
        return (1...max(1, workspace.upcomingCount)).map { ahead in
            let number = sprint.number + ahead
            return UpcomingSprint(
                ahead: ahead, number: number, name: sprint.name(ahead: ahead), dateRange: sprint.dateRange(ahead: ahead),
                goal: workspace.upcomingGoals[number]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
    }

    /// Which upcoming sprint a task is planned in (1 = next); nil when it isn't in one.
    func upcomingAhead(of task: TaskItem) -> Int? {
        guard task.sprintSlot == .next else { return nil }
        guard let later = task.laterSprint else { return 1 }
        return min(max(later - workspace.sprint.number, 1), max(1, workspace.upcomingCount))
    }

    /// Tasks in `scope` planned in the upcoming sprint `ahead`.
    func sprintTasks(ahead: Int, in scope: TaskScope = .all) -> [TaskItem] {
        tasks(in: scope).filter { usesSprints($0.projectId) && upcomingAhead(of: $0) == ahead }
    }

    /// The picker rows: Active, every upcoming sprint, Backlog.
    func sprintChoices() -> [SprintChoice] {
        [.active] + upcomingSprints().map { SprintChoice.upcoming($0.ahead) } + [.backlog]
    }

    func sprintChoice(of task: TaskItem) -> SprintChoice {
        switch task.sprintSlot {
        case .active: return .active
        case .backlog: return .backlog
        case .next: return .upcoming(upcomingAhead(of: task) ?? 1)
        case .closed: return .closed
        }
    }

    func sprintTitle(_ choice: SprintChoice) -> String {
        switch choice {
        case .active: return sprint.name
        case let .upcoming(ahead): return sprint.name(ahead: ahead)
        case .backlog: return "Backlog"
        case .closed: return "Past sprint"
        }
    }

    /// "active", "next", "in 2 sprints", or "" for the backlog: the quiet text after a picker row.
    func sprintTag(_ choice: SprintChoice) -> String {
        switch choice {
        case .active: return "active"
        case .upcoming(1): return "next"
        case let .upcoming(ahead): return "\(sprint.dateRange(ahead: ahead))"
        case .backlog, .closed: return ""
        }
    }

    // MARK: - Moving tasks

    /// Moves tasks to a sprint of the plan. Tasks of past sprints stay where they are.
    func setSprint(_ ids: [UUID], _ choice: SprintChoice) {
        undoGroup("Change sprint") {
            for id in existing(ids) where task(id)?.sprintSlot != .closed { setSprint(id, choice) }
        }
    }

    func setSprint(_ id: UUID, _ choice: SprintChoice) {
        let number = workspace.sprint.number
        updateTask(id, action: "Change sprint") { task in
            switch choice {
            case .active: task.sprintSlot = .active; task.laterSprint = nil
            case .backlog: task.sprintSlot = .backlog; task.laterSprint = nil
            case .closed: break
            case let .upcoming(ahead):
                task.sprintSlot = .next
                task.laterSprint = ahead > 1 ? number + ahead : nil
            }
        }
    }

    /// Sprints view drag and drop onto an upcoming sprint, placed before `beforeTaskId`.
    func moveTask(_ id: UUID, toUpcoming ahead: Int, before beforeTaskId: UUID? = nil) {
        undoGroup("Move task") {
            setSprint(id, .upcoming(ahead))
            reorder(id, before: beforeTaskId)
        }
    }

    // MARK: - Planning sprints

    /// Plans `count` more sprints after the last one. One undo step.
    func addUpcomingSprints(_ count: Int = 1) {
        guard count > 0 else { return }
        mutate(count == 1 ? "New sprint" : "New sprints") { ws in
            ws.upcomingCount = min(ws.upcomingCount + count, Self.maxUpcomingSprints)
        }
    }

    /// Takes the last planned sprint away (never the next one); its tasks go to the backlog.
    func removeLastUpcomingSprint(now: Date = Date()) {
        guard workspace.upcomingCount > 1 else { return }
        mutate("Remove sprint") { ws in
            let number = ws.sprint.number + ws.upcomingCount
            for i in ws.tasks.indices where ws.tasks[i].sprintSlot == .next && ws.tasks[i].laterSprint == number {
                ws.tasks[i].sprintSlot = .backlog
                ws.tasks[i].laterSprint = nil
                ws.tasks[i].updatedAt = now
            }
            ws.upcomingGoals[number] = nil
            ws.upcomingCount -= 1
        }
    }

    /// The goal of the upcoming sprint `ahead` places after the active one.
    func setUpcomingGoal(ahead: Int, goal: String) {
        mutate("Edit sprint goal", coalesce: "upcoming-goal-\(ahead)") { ws in
            let number = ws.sprint.number + ahead
            let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            ws.upcomingGoals[number] = trimmed.isEmpty ? nil : goal
        }
    }
}
