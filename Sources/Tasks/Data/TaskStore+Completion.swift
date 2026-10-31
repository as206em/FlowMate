import Foundation

// Completion rates of a project, a milestone and the sprint, and the sprint's burnup.

extension TaskStore {
    func projectCompletion(_ projectId: UUID) -> Completion {
        Completion(workspace.tasks.filter { $0.projectId == projectId })
    }

    func milestoneCompletion(_ milestoneId: UUID) -> Completion {
        Completion(workspace.tasks.filter { $0.milestoneId == milestoneId })
    }

    /// The active sprint's tasks in `scope` (all projects, or one).
    func sprintCompletion(scope: TaskScope = .all) -> Completion {
        Completion(sprintTasks(slot: .active, in: scope))
    }

    /// Done and planned time of the active sprint, per day from its start to today.
    func sprintBurnup(now: Date = Date(), calendar: Calendar = .current) -> SprintBurnup {
        let sprint = workspace.sprint
        let start = calendar.startOfDay(for: sprint.startDate)
        let end = calendar.startOfDay(for: sprint.endDate)
        let today = calendar.startOfDay(for: now)
        let last = min(max(today, start), end)
        let tasks = sprintTasks(slot: .active).filter { !$0.isCanceled }
        let log = workspace.sprintScope.filter { $0.sprint == sprint.number }.sorted { $0.day < $1.day }
        let plannedNow = tasks.reduce(0) { $0 + $1.expectedMinutes }

        var days: [SprintBurnup.Day] = []
        var date = start
        while date <= last {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            // Finished tasks that joined the sprint after finishing count from the first day
            let done = tasks.filter { $0.isDone && ($0.completedAt ?? $0.updatedAt) < dayEnd }
                .reduce(0) { $0 + $1.expectedMinutes }
            let planned = log.last { $0.day <= date }?.plannedMinutes ?? log.first?.plannedMinutes ?? plannedNow
            // Never less planned than done (a task finished before it joined)
            days.append(.init(date: date, doneHours: Double(done) / 60, plannedHours: Double(max(planned, done)) / 60))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return SprintBurnup(days: days, start: start, end: end, today: last, plannedHours: Double(plannedNow) / 60)
    }
}
