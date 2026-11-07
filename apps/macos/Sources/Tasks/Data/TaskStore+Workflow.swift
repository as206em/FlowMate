import Foundation

// Statuses per project: reading a task's status, changing it by status or by category, and
// editing a project's workflow (add, rename, color, category, reorder, delete, presets).
// Every workflow edit is one undo step; Workspace.normalizeStatuses (run by `mutate`) keeps tasks
// pointing at valid statuses.
extension TaskStore {
    // MARK: - Reading

    /// The task's status in its project's workflow.
    func status(of task: TaskItem) -> WorkflowStatus {
        project(task.projectId)?.status(of: task) ?? WorkflowRules.first(task.statusCategory, in: WorkflowPreset.simple.statuses)
    }

    /// The workflow of a single-project scope; nil in All projects, which works by category.
    func statuses(in scope: TaskScope) -> [WorkflowStatus]? {
        scope.projectId.flatMap { project($0)?.statuses }
    }

    /// The categories All projects shows as board columns and list groups: Not started, Started
    /// and Done always, Canceled only while a task is canceled (`tasks` decides).
    func categoryColumns(for tasks: [TaskItem]) -> [StatusCategory] {
        StatusCategory.ordered.filter { $0 != .canceled || tasks.contains(where: \.isCanceled) }
    }

    /// How many tasks use a status (any sprint, closed ones included).
    func statusUsage(projectId: UUID, statusId: String) -> Int {
        workspace.tasks.filter { $0.projectId == projectId && $0.statusId == statusId }.count
    }

    /// Statuses a set of tasks can all move to: one project's whole workflow, or for tasks of
    /// several projects the statuses (by name and category) every one of those workflows has.
    func commonStatuses(for ids: [UUID]) -> [WorkflowStatus] {
        let projectIds = Set(existing(ids).compactMap { task($0)?.projectId })
        let workflows = projectIds.compactMap { project($0)?.statuses }
        guard let first = workflows.first else { return [] }
        if workflows.count == 1 { return first }
        return first.filter { status in
            workflows.dropFirst().allSatisfy { list in
                list.contains { $0.category == status.category && $0.name.compare(status.name, options: .caseInsensitive) == .orderedSame }
            }
        }
    }

    // MARK: - Changing a task's status

    /// Changes status. A status of another project lands on the matching status of this one
    /// (same name and category, else the first of the category). Moving to a done or canceled
    /// status pauses the timer; reopening a task from a closed sprint puts it in the backlog.
    func setStatus(_ id: UUID, _ status: WorkflowStatus, now: Date = Date()) {
        guard let task = task(id), let project = project(task.projectId) else { return }
        let target = project.status(status.id) ?? WorkflowRules.remap(status, into: project.statuses)
        undoGroup("Change status") {
            if target.isClosed { pauseTimer(id, now: now) }
            updateTask(id, now: now) { task in
                task.statusId = target.id
                task.statusCategory = target.category
                if !target.isClosed, task.sprintSlot == .closed { task.sprintSlot = .backlog }
            }
        }
    }

    /// Moves a task to the first status of a category in its project (All projects board and
    /// bulk edits across workflows). Nothing changes when it's already in that category.
    func setCategory(_ id: UUID, _ category: StatusCategory, now: Date = Date()) {
        guard let task = task(id), task.statusCategory != category, let project = project(task.projectId) else { return }
        setStatus(id, project.firstStatus(category), now: now)
    }

    /// The status circle: the next status of the project's workflow, wrapping around.
    func cycleStatus(_ id: UUID, now: Date = Date()) {
        guard let task = task(id), let project = project(task.projectId) else { return }
        setStatus(id, project.statusAfter(project.status(of: task).id), now: now)
    }

    /// Board drag to a category column (All projects), placed before `beforeTaskId`.
    func moveTask(_ id: UUID, toCategory category: StatusCategory, before beforeTaskId: UUID? = nil,
                  reorder: Bool = true, now: Date = Date()) {
        undoGroup("Move task") {
            setCategory(id, category, now: now)
            if reorder { self.reorder(id, before: beforeTaskId) }
        }
    }

    /// Several tasks to one status (matched per project as in `setStatus`). One undo step.
    func setStatus(_ ids: [UUID], _ status: WorkflowStatus, now: Date = Date()) {
        undoGroup("Change status") {
            for id in existing(ids) { setStatus(id, status, now: now) }
        }
    }

    /// Several tasks to the first status of a category in each one's project. One undo step.
    func setCategory(_ ids: [UUID], _ category: StatusCategory, now: Date = Date()) {
        undoGroup("Change status") {
            for id in existing(ids) { setCategory(id, category, now: now) }
        }
    }

    // MARK: - Editing a workflow

    /// Adds a status after the last one of its category (so the board keeps Not started → Started
    /// → Done → Canceled unless you reorder it). Returns its id, or nil for a blank name.
    @discardableResult
    func addStatus(projectId: UUID, name: String, category: StatusCategory = .started, colorHex: UInt32? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, project(projectId) != nil else { return nil }
        let status = WorkflowStatus(name: name, colorHex: colorHex, category: category)
        mutate("Add status") { ws in
            guard let p = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            var list = ws.projects[p].statuses
            let index: Int
            if let last = list.lastIndex(where: { $0.category == category }) {
                index = last + 1
            } else {
                // After every status of an earlier category
                index = (list.lastIndex { $0.category.rank < category.rank }).map { $0 + 1 } ?? 0
            }
            list.insert(status, at: index)
            ws.projects[p].statuses = list
        }
        return status.id
    }

    /// Renames a status. Typing in the Workflow list renames as you go; quick edits share one undo step.
    func renameStatus(projectId: UUID, statusId: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        editStatus(projectId, statusId, action: "Rename status", coalesce: "status-name-\(projectId)-\(statusId)") { $0.name = name }
    }

    func setStatusColor(projectId: UUID, statusId: String, colorHex: UInt32) {
        editStatus(projectId, statusId, action: "Change status color") { $0.colorHex = colorHex }
    }

    /// Whether a status's category can change: the workflow must keep a Not started and a Done status.
    func canChangeCategory(projectId: UUID, statusId: String, to category: StatusCategory) -> Bool {
        guard let project = project(projectId), var status = project.status(statusId) else { return false }
        status.category = category
        let list = project.statuses.map { $0.id == statusId ? status : $0 }
        return WorkflowRules.isValid(list)
    }

    /// Changes what a status means. Its tasks follow: becoming done or canceled pauses their
    /// timers. Refused when it would leave the workflow without a Not started or Done status.
    @discardableResult
    func setStatusCategory(projectId: UUID, statusId: String, _ category: StatusCategory, now: Date = Date()) -> Bool {
        guard canChangeCategory(projectId: projectId, statusId: statusId, to: category) else { return false }
        undoGroup("Change status category") {
            if category.isClosed {
                for task in runningTasks where task.projectId == projectId && task.statusId == statusId {
                    pauseTimer(task.id, now: now)
                }
            }
            editStatus(projectId, statusId, action: "Change status category") { $0.category = category }
        }
        return true
    }

    /// Moves a status to a new position in the workflow (board column order).
    func moveStatus(projectId: UUID, statusId: String, to index: Int) {
        mutate("Reorder statuses") { ws in
            guard let p = ws.projects.firstIndex(where: { $0.id == projectId }),
                  let from = ws.projects[p].statuses.firstIndex(where: { $0.id == statusId }) else { return }
            var list = ws.projects[p].statuses
            let status = list.remove(at: from)
            list.insert(status, at: max(0, min(index, list.count)))
            ws.projects[p].statuses = list
        }
    }

    /// Up (−1) or down (+1) one place.
    func moveStatus(projectId: UUID, statusId: String, by offset: Int) {
        guard let from = project(projectId)?.statuses.firstIndex(where: { $0.id == statusId }) else { return }
        moveStatus(projectId: projectId, statusId: statusId, to: from + offset)
    }

    /// Drag in the Workflow list: places the status before another one (or last when nil).
    func moveStatus(projectId: UUID, statusId: String, before beforeId: String?) {
        guard statusId != beforeId, let project = project(projectId) else { return }
        let others = project.statuses.filter { $0.id != statusId }
        let index = beforeId.flatMap { id in others.firstIndex { $0.id == id } } ?? others.count
        moveStatus(projectId: projectId, statusId: statusId, to: index)
    }

    /// Whether the status can go: the workflow must keep a Not started and a Done status.
    func canDeleteStatus(projectId: UUID, statusId: String) -> Bool {
        guard let project = project(projectId), project.status(statusId) != nil else { return false }
        return WorkflowRules.isValid(project.statuses.filter { $0.id != statusId })
    }

    /// Deletes a status. Its tasks move to `reassignTo` (another status of the project), or when
    /// nil to the first remaining status of the same category. One undo step; moving them to a
    /// done or canceled status pauses their timers. Returns false when refused.
    @discardableResult
    func deleteStatus(projectId: UUID, statusId: String, reassignTo targetId: String? = nil, now: Date = Date()) -> Bool {
        guard canDeleteStatus(projectId: projectId, statusId: statusId),
              let project = project(projectId), let removed = project.status(statusId) else { return false }
        let remaining = project.statuses.filter { $0.id != statusId }
        let target = targetId.flatMap { id in remaining.first { $0.id == id } } ?? WorkflowRules.first(removed.category, in: remaining)
        undoGroup("Delete status") {
            if target.isClosed {
                for task in runningTasks where task.projectId == projectId && task.statusId == statusId {
                    pauseTimer(task.id, now: now)
                }
            }
            mutate("Delete status") { ws in
                guard let p = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
                ws.projects[p].statuses = remaining
                for i in ws.tasks.indices where ws.tasks[i].projectId == projectId && ws.tasks[i].statusId == statusId {
                    ws.tasks[i].statusId = target.id
                    ws.tasks[i].statusCategory = target.category
                    ws.tasks[i].updatedAt = now
                    if !target.isClosed, ws.tasks[i].sprintSlot == .closed { ws.tasks[i].sprintSlot = .backlog }
                }
            }
        }
        return true
    }

    /// Replaces the project's workflow with a preset. Each task moves to the preset status with
    /// the same name and category, else the first one of its category. One undo step.
    func applyWorkflowPreset(projectId: UUID, _ preset: WorkflowPreset, now: Date = Date()) {
        guard let project = project(projectId) else { return }
        let statuses = preset.statuses
        let mapping = Dictionary(uniqueKeysWithValues: project.statuses.map { ($0.id, WorkflowRules.remap($0, into: statuses)) })
        undoGroup("Apply \(preset.title) workflow") {
            for task in runningTasks where task.projectId == projectId {
                if let target = mapping[task.statusId], target.isClosed { pauseTimer(task.id, now: now) }
            }
            mutate("Apply \(preset.title) workflow") { ws in
                guard let p = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
                ws.projects[p].statuses = statuses
                for i in ws.tasks.indices where ws.tasks[i].projectId == projectId {
                    let target = mapping[ws.tasks[i].statusId] ?? WorkflowRules.first(ws.tasks[i].statusCategory, in: statuses)
                    guard target.id != ws.tasks[i].statusId || target.category != ws.tasks[i].statusCategory else { continue }
                    ws.tasks[i].statusId = target.id
                    ws.tasks[i].statusCategory = target.category
                    ws.tasks[i].updatedAt = now
                }
            }
        }
    }

    private func editStatus(_ projectId: UUID, _ statusId: String, action: String, coalesce: String? = nil,
                            _ change: (inout WorkflowStatus) -> Void) {
        mutate(action, coalesce: coalesce) { ws in
            guard let p = ws.projects.firstIndex(where: { $0.id == projectId }),
                  let s = ws.projects[p].statuses.firstIndex(where: { $0.id == statusId }) else { return }
            change(&ws.projects[p].statuses[s])
        }
    }
}
