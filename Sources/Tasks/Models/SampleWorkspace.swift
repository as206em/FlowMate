import Foundation

extension Workspace {
    /// First-launch content: one project with a few clearly labelled example tasks.
    static func sample(now: Date = Date()) -> Workspace {
        let project = Project(
            name: "FlowMate",
            colorHex: Focus.projectPalette[0],
            sprint: SprintState(number: 1, startDate: SprintState.defaultStart(for: now), goal: "Try out tasks and timers"),
            createdAt: now
        )
        let milestone = Milestone(
            projectId: project.id,
            name: "Getting started",
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Calendar.current.startOfDay(for: now))
        )

        func task(_ index: Int, _ title: String, slot: SprintSlot = .active, status: TaskStatus = .todo,
                  priority: TaskPriority = .medium, expected: Int = 30, notes: String = "",
                  subtasks: [Subtask] = []) -> TaskItem {
            TaskItem(projectId: project.id, milestoneId: milestone.id, sprintSlot: slot, status: status,
                     priority: priority, title: title, notes: notes, subtasks: subtasks,
                     expectedMinutes: expected, createdAt: now, sortIndex: Double(index))
        }

        let tasks = [
            task(0, "Example: start a timer on this task", priority: .high, expected: 15, notes: """
                ## This is sample data
                Press play to start a timer. Several timers can run at the same time, and **none of them stops another**.

                - [ ] Start this timer
                - [ ] Start a second one from the menu bar
                """),
            task(1, "Example: drag me to In progress", subtasks: [
                Subtask(title: "Open the Board view"),
                Subtask(title: "Drag this card to another column"),
            ]),
            task(2, "Example: a finished task", status: .done, priority: .low, expected: 15),
            task(3, "Example: planned for the next sprint", slot: .next, priority: .low, expected: 60),
            task(4, "Example: an idea in the backlog", slot: .backlog, priority: .low, expected: 120),
        ]

        return Workspace(projects: [project], milestones: [milestone], tasks: tasks,
                         preferences: WorkspacePreferences(sampleProjectIds: [project.id]))
    }
}
