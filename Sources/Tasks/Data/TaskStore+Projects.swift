import Foundation

// Projects, milestones and sprints
extension TaskStore {
    // MARK: - Projects

    /// Adds a project with the next unused palette color. Returns nil for a blank name.
    @discardableResult
    func addProject(name: String, now: Date = Date()) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let project = Project(name: name, colorHex: nextProjectColor(),
                              sprint: SprintState(number: 1, startDate: SprintState.defaultStart(for: now)),
                              createdAt: now)
        mutate("Add project") { $0.projects.append(project) }
        return project.id
    }

    /// First palette color no project uses yet, cycling when all are taken.
    func nextProjectColor() -> UInt32 {
        let palette = Focus.projectPalette
        let used = Set(workspace.projects.map(\.colorHex))
        return palette.first { !used.contains($0) } ?? palette[workspace.projects.count % palette.count]
    }

    func renameProject(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate("Rename project") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            ws.projects[i].name = name
        }
    }

    func setProjectColor(_ id: UUID, colorHex: UInt32) {
        mutate("Change color") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            ws.projects[i].colorHex = colorHex
        }
    }

    /// Markdown description
    func setProjectNotes(_ id: UUID, _ notes: String) {
        mutate("Edit description", coalesce: "project-notes-\(id)") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            ws.projects[i].notes = notes
        }
    }

    /// Renames while typing in the project panel; quick edits share one undo step.
    func setProjectName(_ id: UUID, _ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate("Rename project", coalesce: "project-name-\(id)") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            ws.projects[i].name = name
        }
    }

    func setProjectTargetDate(_ id: UUID, _ date: Date?) {
        mutate("Change target date") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            ws.projects[i].targetDate = date.map { Calendar.current.startOfDay(for: $0) }
        }
    }

    /// Hides the project from the sidebar list, pickers, All projects and the menu bar, keeping
    /// all its data. Its running timers are paused (time is kept). One undo step.
    func archiveProject(_ id: UUID, now: Date = Date()) {
        guard let project = project(id), !project.isArchived else { return }
        undoGroup("Archive project") {
            for task in runningTasks where task.projectId == id { pauseTimer(task.id, now: now) }
            mutate("Archive project") { ws in
                guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
                ws.projects[i].archivedAt = now
            }
        }
    }

    func unarchiveProject(_ id: UUID) {
        mutate("Unarchive project") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            ws.projects[i].archivedAt = nil
        }
    }

    /// Sidebar drag: places the project before another one (or last when nil).
    func moveProject(_ id: UUID, before beforeId: UUID?) {
        guard id != beforeId else { return }
        mutate("Reorder projects") { ws in
            guard let from = ws.projects.firstIndex(where: { $0.id == id }) else { return }
            let project = ws.projects.remove(at: from)
            if let beforeId, let to = ws.projects.firstIndex(where: { $0.id == beforeId }) {
                ws.projects.insert(project, at: to)
            } else {
                ws.projects.append(project)
            }
        }
    }

    /// Deletes the project with its milestones, tasks and their timers. Confirm in the UI first.
    func deleteProject(_ id: UUID) {
        mutate("Delete project") { ws in
            let taskIds = Set(ws.tasks.filter { $0.projectId == id }.map(\.id))
            ws.projects.removeAll { $0.id == id }
            ws.milestones.removeAll { $0.projectId == id }
            ws.tasks.removeAll { $0.projectId == id }
            ws.runningTimers = ws.runningTimers.filter { !taskIds.contains($0.key) }
        }
    }

    // MARK: - Milestones

    @discardableResult
    func addMilestone(projectId: UUID, name: String, dueDate: Date? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let project = project(projectId) else { return nil }
        let used = workspace.milestones.filter { $0.projectId == projectId }.map(\.colorHex)
        let milestone = Milestone(projectId: projectId, name: name, dueDate: dueDate,
                                  colorHex: Milestone.nextColor(projectColor: project.colorHex, used: used))
        mutate("Add milestone") { $0.milestones.append(milestone) }
        return milestone.id
    }

    func renameMilestone(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate("Rename milestone") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].name = name
        }
    }

    func setMilestoneColor(_ id: UUID, colorHex: UInt32) {
        guard colorHex != Milestone.unsetColor else { return }
        mutate("Change milestone color") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].colorHex = colorHex
        }
    }

    func setMilestoneDue(_ id: UUID, to dueDate: Date?) {
        mutate("Change milestone date") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].dueDate = dueDate
        }
    }

    /// Markdown description
    func setMilestoneNotes(_ id: UUID, _ notes: String) {
        mutate("Edit description", coalesce: "milestone-notes-\(id)") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].notes = notes
        }
    }

    /// Renames while typing in the milestone panel; quick edits share one undo step.
    func setMilestoneName(_ id: UUID, _ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate("Rename milestone", coalesce: "milestone-name-\(id)") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].name = name
        }
    }

    /// "Mark complete": the milestone shows as completed. Its tasks are left as they are.
    func completeMilestone(_ id: UUID, now: Date = Date()) {
        mutate("Complete milestone") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }), ws.milestones[i].completedAt == nil else { return }
            ws.milestones[i].completedAt = now
        }
    }

    func reopenMilestone(_ id: UUID) {
        mutate("Reopen milestone") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].completedAt = nil
        }
    }

    /// Deletes the milestone; its tasks stay and lose their milestone.
    func deleteMilestone(_ id: UUID, now: Date = Date()) {
        mutate("Delete milestone") { ws in
            ws.milestones.removeAll { $0.id == id }
            for i in ws.tasks.indices where ws.tasks[i].milestoneId == id {
                ws.tasks[i].milestoneId = nil
                ws.tasks[i].updatedAt = now
            }
        }
    }

    // MARK: - Sprints

    func setSprintGoal(projectId: UUID, goal: String) {
        mutate("Edit sprint goal", coalesce: "goal-\(projectId)") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].sprint.goal = goal
        }
    }

    /// Sprint length in weeks (1–4). The start stays; the end and the next sprint move.
    func setSprintLength(projectId: UUID, weeks: Int) {
        mutate("Change sprint length") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].sprint.lengthWeeks = SprintState.clampedLength(weeks)
        }
    }

    /// Moves the active sprint's start (midnight of that day). The length stays.
    func setSprintStart(projectId: UUID, date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        mutate("Change sprint dates") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].sprint.startDate = day
        }
    }

    /// Renumbers the active sprint (at least 1).
    func setSprintNumber(projectId: UUID, number: Int) {
        mutate("Change sprint number") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].sprint.number = max(1, number)
        }
    }

    /// Closes the active sprint and starts the next one today. One undo step.
    /// - Done and canceled tasks in the active sprint become `closed` (remembering the sprint
    ///   number); only done ones count as done in the sprint's history.
    /// - Unfinished active tasks follow `unfinished`: stay for the new sprint, go to the backlog,
    ///   or close with the old sprint.
    /// - Next-sprint tasks become active.
    /// - The sprint is kept in `pastSprints` with its dates, goal and tasks.
    /// - The new sprint gets the next number, starts on the day you complete it (so dates never
    ///   drift), keeps the project's length, and takes `nextGoal`.
    func completeSprint(projectId: UUID, unfinished: UnfinishedSprintTasks = .moveToNextSprint,
                        nextGoal: String = "", now: Date = Date()) {
        undoGroup("Complete sprint") {
            // Unfinished tasks closing with the sprint are hidden from List, so their timers stop
            // first. A pause isn't undone, so the session stays in the time log.
            if unfinished == .keepInSprint {
                for task in runningTasks where task.projectId == projectId && task.sprintSlot == .active && !task.isClosed {
                    pauseTimer(task.id, now: now)
                }
            }
            completeSprintStep(projectId: projectId, unfinished: unfinished, nextGoal: nextGoal, now: now)
        }
    }

    private func completeSprintStep(projectId: UUID, unfinished: UnfinishedSprintTasks, nextGoal: String, now: Date) {
        mutate("Complete sprint") { ws in
            guard let p = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            let old = ws.projects[p].sprint
            var sprintTasks: [UUID] = []
            var doneTasks: [UUID] = []
            for i in ws.tasks.indices.sorted(by: { ws.tasks[$0].sortIndex < ws.tasks[$1].sortIndex })
            where ws.tasks[i].projectId == projectId {
                switch ws.tasks[i].sprintSlot {
                case .active:
                    sprintTasks.append(ws.tasks[i].id)
                    if ws.tasks[i].isClosed {
                        if ws.tasks[i].isDone { doneTasks.append(ws.tasks[i].id) }
                        ws.tasks[i].sprintSlot = .closed
                        ws.tasks[i].closedSprintNumber = old.number
                        ws.tasks[i].updatedAt = now
                    } else {
                        switch unfinished {
                        case .moveToNextSprint:
                            break
                        case .moveToBacklog:
                            ws.tasks[i].sprintSlot = .backlog
                            ws.tasks[i].updatedAt = now
                        case .keepInSprint:
                            ws.tasks[i].sprintSlot = .closed
                            ws.tasks[i].closedSprintNumber = old.number
                            ws.tasks[i].updatedAt = now
                        }
                    }
                case .next:
                    ws.tasks[i].sprintSlot = .active
                    ws.tasks[i].updatedAt = now
                default:
                    break
                }
            }
            let today = Calendar.current.startOfDay(for: now)
            // It ran until the day it was completed
            let end = max(old.startDate, today)
            ws.projects[p].pastSprints.append(PastSprint(
                number: old.number, startDate: old.startDate, endDate: end,
                goal: old.goal.trimmingCharacters(in: .whitespacesAndNewlines),
                taskIds: sprintTasks, doneTaskIds: doneTasks, completedAt: now
            ))
            var sprint = old
            sprint.number += 1
            sprint.startDate = today
            sprint.goal = nextGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            ws.projects[p].sprint = sprint
        }
    }
}

/// What "Complete sprint" does with tasks in the sprint that aren't done.
enum UnfinishedSprintTasks: String, CaseIterable, Identifiable, Sendable {
    /// They stay planned and carry into the new sprint
    case moveToNextSprint
    case moveToBacklog
    /// They close with the old sprint, unfinished (hidden from List like other closed tasks)
    case keepInSprint

    var id: String { rawValue }
}
