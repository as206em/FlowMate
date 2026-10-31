import SwiftUI

/// List view: a column table of tasks in groups (Status by default; the filter bar picks another).
/// Drag a row onto another group to change that value, or within a group to reorder (manual sort).
/// Click a column header to sort inside each group; a third click returns to the manual order.
struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        if let reason = model.listEmptyReason(store) {
            TasksEmptyStateView(reason: reason)
                .padding(.top, model.showsFilterBar ? 16 : 24)
                .padding(.horizontal, TaskTableCell.sidePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            table
        }
    }

    private var table: some View {
        let groups = model.listGroups(store)
        let filtering = !model.filter.isEmpty
        let hidden = model.hiddenClosedCount(store)
        let firstOpen = groups.first(where: \.acceptsDrop)?.id
        let showProject = model.scope.projectId == nil
        var builder = TaskTableBuilder()
        builder.spacer("top", 6)
        for (index, group) in groups.enumerated() {
            builder.group(
                key: group.id,
                title: group.title,
                hint: group.hint,
                colorHex: group.colorHex,
                icon: group.icon,
                statusKind: group.statusKind,
                statusColorHex: group.statusColorHex,
                labelColorHex: group.labelColorHex,
                tasks: group.tasks,
                emptyText: emptyText(group, filtering: filtering),
                showProject: showProject,
                drop: group.acceptsDrop ? .group(group.value, reorder: model.sort.isManual) : nil,
                composerIsDefault: group.id == firstOpen,
                composerOnTop: model.isComposerPinned(TasksViewModel.listComposerKey(group.id)),
                open: !model.isCollapsed(group.id),
                gap: index == 0 ? 0 : 22,
                display: RowDisplay.maker(store: store, model: model)
            )
        }
        builder.spacer("bottom", 72)
        return TaskTable(
            showProject: showProject,
            excluding: excluded(groups),
            sort: Binding(get: { model.sort }, set: { model.sort = $0 }),
            caption: hidden > 0 ? "\(hidden) \(hidden == 1 ? "task" : "tasks") from past sprints hidden. Filter by Sprint › Past sprints to show them." : "",
            rows: builder.rows,
            drops: builder.drops
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The grouped-by column repeats the group header, so it's hidden (Project stays: its tile helps).
    private func excluded(_ groups: [TaskGroup]) -> Set<TaskColumn> {
        var columns: Set<TaskColumn>
        switch model.grouping {
        case .milestone: columns = [.milestone]
        case .sprint: columns = [.sprint]
        case .priority: columns = [.priority]
        case .project: columns = [.project]
        case .label: columns = []
        case .status: columns = []
        }
        // Labels only while a task on screen has one
        if !groups.contains(where: { $0.tasks.contains { !$0.labelIds.isEmpty } }) { columns.insert(.labels) }
        // On a milestone's page every row has the same milestone
        if model.scope.isMilestone { columns.insert(.milestone) }
        // A project without sprints has no sprint to show
        if !model.scopeUsesSprints { columns.insert(.sprint) }
        return columns
    }

    /// An empty status group or board column, by what its status means.
    static func emptyStatusText(_ category: StatusCategory, name: String) -> String {
        switch category {
        case .notStarted: return "Nothing waiting in \(name). Drag a task here to move it back."
        case .started: return "Nothing in \(name). Start a timer, or drag a task here."
        case .done: return "Nothing done yet. Drag a task here, or click its status circle."
        case .canceled: return "Nothing canceled. Drag a task here to drop it from the plan."
        }
    }

    /// One empty group among others: what belongs here and how to get it here.
    private func emptyText(_ group: TaskGroup, filtering: Bool) -> String {
        if filtering { return "No tasks here match the filters." }
        guard group.acceptsDrop else { return "No tasks. Past sprints can't take new tasks." }
        switch group.value {
        case let .status(status): return Self.emptyStatusText(status.category, name: status.name)
        case let .category(category): return Self.emptyStatusText(category, name: category.title)
        case .milestone(nil): return "Every task has a milestone. Drag one here to take it off."
        case .milestone: return "No tasks for this milestone yet. Drag tasks here to add them."
        case .project: return "No tasks in this project. Drag tasks here to move them."
        case .priority: return "No tasks with this priority. Drag a task here to set it."
        case .sprint(.active): return "Nothing planned for this sprint. Drag tasks here."
        case .sprint(.next): return "Nothing planned for the next sprint. Drag tasks here."
        case .sprint: return "Empty. Drag tasks here."
        case .label(nil): return "Every task has a label. Drag one here to take its labels off."
        case .label: return "No tasks with this label. Drag a task here to add it."
        }
    }
}

/// Sprints view: Active, Next and Backlog of the workspace's sprint, with the tasks of every project
/// in scope (or one project's), each header with its task count and expected time against the
/// capacity of those projects ("7 tasks · 11h of 20h"). Drag rows between groups; the numbers
/// follow. Past sprints follow with their numbers and the velocity chart.
struct SprintPlanView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope

    var body: some View {
        let sprint = store.sprint
        var builder = TaskTableBuilder()
        builder.spacer("top", 6)
        if scope.projectId == nil { builder.burnup() }
        group(&builder, .active, title: "\(sprint.name) · active", hint: sprint.dateRange,
              empty: "Nothing in this sprint yet. Drag tasks here from Next or Backlog, or add one with the New task field.", gap: 0)
        let upcoming = store.upcomingSprints()
        group(&builder, .next, title: "\(sprint.nextName) · next", hint: upcoming.first?.hint ?? sprint.nextDateRange,
              empty: "Nothing planned for the next sprint. Drag tasks here to line them up.", gap: 22)
        for later in upcoming where later.ahead > 1 {
            laterGroup(&builder, later)
        }
        group(&builder, .backlog, title: "Backlog", hint: "",
              empty: "No ideas parked for later. Drag tasks here, or pick Backlog on the New task field's sprint chip.", gap: 22)
        pastSprints(&builder)
        builder.spacer("bottom", 72)
        // Manual order only: rows are dragged between and within groups here, so headers don't sort
        return TaskTable(
            showProject: scope.projectId == nil,
            excluding: store.tasks(in: scope).contains { !$0.labelIds.isEmpty } ? [.sprint] : [.sprint, .labels],
            rows: builder.rows,
            drops: builder.drops
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Completed sprints, newest first, collapsed until opened:
    /// "Sprint 3  10  8 done · 18h planned · 21h tracked · Oct 12 – Oct 25", after the velocity chart.
    private func pastSprints(_ builder: inout TaskTableBuilder) {
        let past = store.pastSprints()
        guard !past.isEmpty else { return }
        builder.sectionTitle("Past sprints")
        builder.velocity()
        for sprint in past {
            let key = TasksViewModel.pastSprintGroupKey(sprint)
            builder.group(
                key: key,
                title: sprint.name,
                hint: [sprint.headerHint, sprint.goal.isEmpty ? nil : sprint.goal].compactMap { $0 }.joined(separator: " · "),
                tasks: store.tasks(of: sprint, in: scope),
                emptyText: "No tasks were in this sprint.",
                showProject: scope.projectId == nil,
                drop: nil,
                open: !model.isCollapsed(key),
                gap: 12,
                display: RowDisplay.maker(store: store, model: model)
            )
        }
    }

    /// A sprint planned further ahead: tasks go in by dragging or the sprint picker (no inline composer).
    private func laterGroup(_ builder: inout TaskTableBuilder, _ later: UpcomingSprint) {
        let key = TasksViewModel.upcomingGroupKey(later.ahead)
        builder.group(
            key: key,
            title: later.name,
            hint: later.hint,
            tasks: store.sprintTasks(ahead: later.ahead, in: scope),
            emptyText: "Nothing planned for \(later.name). Drag tasks here.",
            showProject: scope.projectId == nil,
            drop: .upcoming(later.ahead),
            open: !model.isCollapsed(key),
            gap: 22,
            liveHint: .sprintLoad(scope: scope, slot: .next, ahead: later.ahead),
            display: RowDisplay.maker(store: store, model: model)
        )
    }

    private func group(_ builder: inout TaskTableBuilder, _ slot: SprintSlot, title: String, hint: String, empty: String, gap: CGFloat) {
        let key = TasksViewModel.sprintGroupKey(slot)
        builder.group(
            key: key,
            title: title,
            hint: hint,
            tasks: store.sprintTasks(slot: slot, in: scope),
            emptyText: empty,
            showProject: scope.projectId == nil,
            drop: .slot(slot),
            composerIsDefault: slot == .active,
            composerOnTop: model.isComposerPinned(TasksViewModel.listComposerKey(key)),
            open: !model.isCollapsed(key),
            gap: gap,
            liveHint: .sprintLoad(scope: scope, slot: slot),
            display: RowDisplay.maker(store: store, model: model)
        )
    }
}

/// What dropping a task on a group (or a row in it) does.
enum TaskGroupDrop: Equatable {
    /// Sprints view: move to the slot, placed before the row
    case slot(SprintSlot)
    /// Sprints view: move to the sprint planned this many places after the active one (2 or more)
    case upcoming(Int)
    /// List: set the group's value; place before the row only in manual order
    case group(TaskGroupValue, reorder: Bool)
    /// Today's My focus: pin the task for today, placed before the row
    case focus
}

/// What dropping a task on a group does. The group UI itself is built by TaskTableBuilder
/// and drawn by NativeTaskTable.
enum TaskGroupSection {
    /// The value a task added to the group gets
    static func preset(_ drop: TaskGroupDrop) -> TaskGroupValue {
        switch drop {
        case let .slot(slot): return .sprint(slot)
        // Not used: later sprints have no inline composer (see TaskTableBuilder.group)
        case .upcoming: return .sprint(.next)
        case let .group(value, _): return value
        // Today's composer adds to the active sprint (and pins the task, see ComposerDraft)
        case .focus: return .sprint(.active)
        }
    }

    @MainActor
    /// `source`: the drop of the group the task was dragged out of (same table), so moving
    /// between label groups swaps the label instead of adding a second one.
    static func perform(_ drop: TaskGroupDrop, id: UUID, before: UUID?, from source: TaskGroupDrop? = nil, store: TaskStore) {
        switch drop {
        case let .slot(slot):
            store.moveTask(id, toSlot: slot, before: before)
        case let .upcoming(ahead):
            store.moveTask(id, toUpcoming: ahead, before: before)
        case let .group(value, reorder):
            var from: TaskGroupValue?
            if case let .group(sourceValue, _)? = source { from = sourceValue }
            store.moveTask(id, to: value, before: before, reorder: reorder, from: from)
        case .focus:
            store.moveInFocus(id, before: before)
        }
    }
}

extension RowDisplay {
    /// Looks up everything a row shows that isn't on the task itself. The lookups are built once
    /// per table rebuild, not once per task.
    /// `today`: rows of the Today page, which add "From yesterday" to pinned tasks carried over
    /// and the "→ Tomorrow" hover button to overdue, due and pinned ones.
    @MainActor
    static func maker(store: TaskStore, model: TasksViewModel, today: Bool = false) -> (TaskItem) -> RowDisplay {
        let projects = Dictionary(store.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let milestones = Dictionary(store.workspace.milestones.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let workflows = Dictionary(store.allProjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let labels = Dictionary(store.workspace.labels.map { ($0.id, RowLabel(name: $0.name, colorHex: $0.colorHex)) },
                                uniquingKeysWith: { first, _ in first })
        let running = store.workspace.runningTimers
        let selected = model.selectedTaskIds
        let flashing = model.flashTaskId
        let now = Date()
        return { task in
            let project = projects[task.projectId]
            let workflow = workflows[task.projectId]
            let status = workflow?.status(of: task) ?? WorkflowRules.first(task.statusCategory, in: WorkflowPreset.simple.statuses)
            return RowDisplay(
                projectName: project?.name,
                projectColorHex: project?.colorHex,
                projectIcon: project?.icon,
                milestoneName: task.milestoneId.flatMap { milestones[$0]?.name },
                milestoneColorHex: task.milestoneId.flatMap { milestones[$0]?.colorHex },
                sprintLabel: store.sprintLabel(for: task),
                dueLabel: task.dueDate.map { TaskDates.dueLabel($0) },
                dueIsRisk: store.isOverdue(task) || store.isDueToday(task),
                runningSince: running[task.id],
                selected: selected.contains(task.id),
                status: status,
                nextStatusName: workflow?.statusAfter(status.id).name ?? "",
                flashing: task.id == flashing,
                note: today ? store.focusCarryLabel(task, now: now) : nil,
                labels: task.labelIds.isEmpty ? [] : task.labelIds.compactMap { labels[$0] }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                quickAction: today && !task.isClosed
                    && (store.isOverdue(task, now: now) || store.isDueToday(task, now: now) || store.isInFocus(task, now: now))
                    ? .tomorrow : nil
            )
        }
    }
}
