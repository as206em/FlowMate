import Foundation

// Tasks and subtasks
extension TaskStore {
    // MARK: - Tasks

    /// Quick add: the project's default sprint (the active one unless set; always active without
    /// sprints), the project's first Not started status (or `status`, matched in the project),
    /// medium priority, the project's default expected time (60m unless set), appended at the end
    /// (or, with `atTop`, placed before every other task, so it heads its group in manual order).
    /// Returns nil for a blank title or unknown project.
    @discardableResult
    func addTask(
        title: String,
        projectId: UUID,
        milestoneId: UUID? = nil,
        sprintSlot: SprintSlot? = nil,
        status: WorkflowStatus? = nil,
        atTop: Bool = false,
        now: Date = Date()
    ) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let project = project(projectId) else { return nil }
        let status = status.map { project.status($0.id) ?? WorkflowRules.remap($0, into: project.statuses) } ?? project.defaultStatus
        let validMilestone = milestoneId.flatMap { milestone($0)?.projectId == projectId ? $0 : nil }
        // Without sprints every new task is current work; a past sprint never takes new tasks
        let slot = project.usesSprints ? Project.cleanSlot(sprintSlot ?? project.defaultSprintSlot) : .active
        let task = TaskItem(projectId: projectId, milestoneId: validMilestone, sprintSlot: slot,
                            status: status, priority: .medium, title: title,
                            expectedMinutes: project.newTaskExpectedMinutes,
                            createdAt: now,
                            sortIndex: atTop ? (workspace.tasks.map(\.sortIndex).min() ?? 0) - 1
                                             : (workspace.tasks.map(\.sortIndex).max() ?? 0) + 1)
        mutate("Add task") { $0.tasks.append(task) }
        return task.id
    }

    func deleteTask(_ id: UUID) {
        mutate("Delete task") { ws in
            ws.tasks.removeAll { $0.id == id }
            ws.runningTimers[id] = nil
        }
    }

    func setTitle(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateTask(id, action: "Rename task", coalesce: "title-\(id)") { $0.title = trimmed }
    }

    /// A one-off rename (inline title edit): its own undo step, never merged with typing in the panel.
    func renameTaskOnce(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateTask(id, action: "Rename task") { $0.title = trimmed }
    }

    /// Markdown description
    func setNotes(_ id: UUID, _ notes: String) {
        updateTask(id, action: "Edit description", coalesce: "notes-\(id)") { $0.notes = notes }
    }

    /// Flips the `- [ ]` / `- [x]` checkbox on line `lineIndex` (0-based) of the notes, for the Preview mode.
    func toggleNotesChecklist(_ id: UUID, line lineIndex: Int) {
        guard let task = task(id) else { return }
        updateTask(id, action: "Check item") { $0.notes = MarkdownChecklist.toggling(line: lineIndex, in: task.notes) }
    }

    func setPriority(_ id: UUID, _ priority: TaskPriority) {
        updateTask(id, action: "Change priority") { $0.priority = priority }
    }

    func setDueDate(_ id: UUID, _ dueDate: Date?) {
        updateTask(id, action: "Change due date") { $0.dueDate = dueDate }
    }

    func setExpectedMinutes(_ id: UUID, _ minutes: Int) {
        updateTask(id, action: "Change expected time") { $0.expectedMinutes = max(1, minutes) }
    }

    /// Sets the milestone; ignores milestones from another project.
    func setMilestone(_ id: UUID, _ milestoneId: UUID?) {
        guard let task = task(id) else { return }
        if let milestoneId, milestone(milestoneId)?.projectId != task.projectId { return }
        updateTask(id, action: "Change milestone") { $0.milestoneId = milestoneId }
    }

    /// Moves a task to another project. Its milestone is cleared (milestones belong to one project)
    /// and its status maps onto the new workflow by category: the status with the same name and
    /// category, else the first status of that category. Everything else (sprint slot, time, a
    /// running timer) comes along.
    func setProject(_ id: UUID, _ projectId: UUID) {
        guard let destination = project(projectId), let current = task(id) else { return }
        let status = WorkflowRules.remap(self.status(of: current), into: destination.statuses)
        let sourceUsesSprints = usesSprints(current.projectId)
        updateTask(id, action: "Move to project") { task in
            guard task.projectId != projectId else { return }
            task.projectId = projectId
            task.statusId = status.id
            task.statusCategory = status.category
            task.milestoneId = nil
            // Labels, time entries and Today pinning are workspace-wide and stay as they are.
            if task.sprintSlot == .closed {
                // Past sprints belong to the old project; the task goes to the new one's backlog
                // (or its plain list when it has no sprints)
                task.sprintSlot = destination.usesSprints ? .backlog : .active
                task.closedSprintNumber = nil
            } else if !destination.usesSprints {
                // A project without sprints keeps every open task current
                task.sprintSlot = .active
            } else if !sourceUsesSprints {
                // Coming from a project without sprints: the slot meant nothing there; work in
                // flight goes to the active sprint, the rest where new tasks of the project go
                task.sprintSlot = task.statusCategory == .started || task.focusDate != nil ? .active : destination.defaultSprintSlot
            }
        }
    }

    func setSprintSlot(_ id: UUID, _ slot: SprintSlot) {
        updateTask(id, action: "Change sprint") { $0.sprintSlot = slot; $0.laterSprint = nil }
    }

    /// Board drag and drop: new status, placed before `beforeTaskId` (or at the end when nil).
    /// Pass `reorder: false` when the view is sorted, so only the status changes.
    func moveTask(_ id: UUID, toStatus status: WorkflowStatus, before beforeTaskId: UUID? = nil,
                  reorder: Bool = true, now: Date = Date()) {
        undoGroup("Move task") {
            setStatus(id, status, now: now)
            if reorder { self.reorder(id, before: beforeTaskId) }
        }
    }

    /// Sprints view drag and drop: new slot, placed before `beforeTaskId` (or at the end when nil).
    func moveTask(_ id: UUID, toSlot slot: SprintSlot, before beforeTaskId: UUID? = nil) {
        undoGroup("Move task") {
            setSprintSlot(id, slot)
            reorder(id, before: beforeTaskId)
        }
    }

    /// Places the task just before another one in the global order (or last when nil).
    func reorder(_ id: UUID, before beforeTaskId: UUID?) {
        guard beforeTaskId != id else { return }
        let newIndex = sortIndex(before: beforeTaskId, excluding: id)
        mutate("Reorder task") { ws in
            guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { return }
            ws.tasks[i].sortIndex = newIndex
        }
    }

    /// Copies a task just below the original: same fields, the first Not started status, no time spent,
    /// subtasks unchecked. Returns the copy's id.
    @discardableResult
    func duplicateTask(_ id: UUID, now: Date = Date()) -> UUID? {
        guard let original = task(id) else { return nil }
        var copy = original
        copy.id = UUID()
        let status = project(original.projectId)?.defaultStatus ?? .todo
        copy.statusId = status.id
        copy.statusCategory = status.category
        // Time entries stay with the original (the copy has none, so no time spent)
        copy.spentSeconds = 0
        copy.completedAt = nil
        copy.createdAt = now
        copy.updatedAt = now
        copy.subtasks = original.subtasks.map { Subtask(title: $0.title) }
        if copy.sprintSlot == .closed { copy.sprintSlot = .backlog }
        copy.sortIndex = sortIndex(after: id)
        mutate("Duplicate task") { $0.tasks.append(copy) }
        return copy.id
    }

    // MARK: - Sort order

    /// Closest two neighbors may get before midpoints stop being exact; below it, renumber.
    static let minSortGap = 1e-6

    /// A sortIndex that lands just before `anchorId` (or last when nil), ignoring `movingId`.
    func sortIndex(before anchorId: UUID?, excluding movingId: UUID? = nil) -> Double {
        rebalanceSortIndexesIfCrowded()
        let others = workspace.tasks.filter { $0.id != movingId }
        guard let anchorId, let anchor = others.first(where: { $0.id == anchorId }) else {
            return (others.map(\.sortIndex).max() ?? 0) + 1
        }
        let previous = others.map(\.sortIndex).filter { $0 < anchor.sortIndex }.max()
        return previous.map { ($0 + anchor.sortIndex) / 2 } ?? anchor.sortIndex - 1
    }

    /// A sortIndex that lands just after `taskId` (a duplicate or a converted subtask).
    func sortIndex(after taskId: UUID) -> Double {
        rebalanceSortIndexesIfCrowded()
        guard let task = task(taskId) else { return (workspace.tasks.map(\.sortIndex).max() ?? 0) + 1 }
        let following = workspace.tasks.map(\.sortIndex).filter { $0 > task.sortIndex }.min()
        return following.map { (task.sortIndex + $0) / 2 } ?? task.sortIndex + 1
    }

    /// Midpoints halve the gap on every drop into the same spot; once two neighbors get too close
    /// (or equal), renumber every task 1, 2, 3… in its current order. Not an undo step: the order
    /// doesn't change.
    func rebalanceSortIndexesIfCrowded() {
        let sorted = workspace.tasks.enumerated()
            .sorted { ($0.element.sortIndex, $0.offset) < ($1.element.sortIndex, $1.offset) }
        let crowded = zip(sorted, sorted.dropFirst())
            .contains { $1.element.sortIndex - $0.element.sortIndex < Self.minSortGap }
        guard crowded else { return }
        let order = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.element.id, Double($0 + 1)) })
        mutate(recordsUndo: false) { ws in
            for i in ws.tasks.indices { ws.tasks[i].sortIndex = order[ws.tasks[i].id] ?? ws.tasks[i].sortIndex }
        }
    }

    // MARK: - Subtasks

    @discardableResult
    func addSubtask(_ taskId: UUID, title: String) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, task(taskId) != nil else { return nil }
        let subtask = Subtask(title: title)
        updateTask(taskId, action: "Add subtask") { $0.subtasks.append(subtask) }
        return subtask.id
    }

    func toggleSubtask(_ taskId: UUID, _ subtaskId: UUID) {
        updateTask(taskId, action: "Check subtask") { task in
            guard let i = task.subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
            task.subtasks[i].isDone.toggle()
        }
    }

    func renameSubtask(_ taskId: UUID, _ subtaskId: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateTask(taskId, action: "Rename subtask") { task in
            guard let i = task.subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
            task.subtasks[i].title = title
        }
    }

    func removeSubtask(_ taskId: UUID, _ subtaskId: UUID) {
        updateTask(taskId, action: "Remove subtask") { $0.subtasks.removeAll { $0.id == subtaskId } }
    }
}

/// Markdown checklist helpers shared by the store and the preview renderer.
enum MarkdownChecklist {
    /// Toggles `[ ]` <-> `[x]` on a `- [ ] item` line; other lines are returned unchanged.
    static func toggling(line lineIndex: Int, in markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return markdown }
        let line = lines[lineIndex]
        guard let match = line.range(of: #"^\s*[-*]\s+\[[ xX]\]"#, options: .regularExpression) else { return markdown }
        let prefix = String(line[match])
        let toggled = prefix.hasSuffix("[ ]")
            ? prefix.replacingOccurrences(of: "[ ]", with: "[x]")
            : prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
        lines[lineIndex] = toggled + line[match.upperBound...]
        return lines.joined(separator: "\n")
    }
}
