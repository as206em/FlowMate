import SwiftUI

/// The tasks view: a column table of tasks in groups (Sprint by default, Status in a project
/// without sprints; the filter bar picks another). Grouped by Sprint it is the sprint plan.
/// Drag a row onto another group to change that value, or within a group to reorder (manual sort).
/// Click a column header to sort inside each group; a third click returns to the manual order.
struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        if model.showsSprintPlan {
            SprintPlanView(scope: model.scope)
        } else if let reason = model.listEmptyReason(store) {
            TasksEmptyStateView(reason: reason)
                .padding(.top, 16)
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
        builder.spacer("top", 8)
        if let notice = emptySprintNotice() {
            builder.append(notice)
            builder.spacer("after-notice", 14)
        }
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
                drop: group.acceptsDrop ? .group(group.value, reorder: model.groupSort(group.id).isManual) : nil,
                composerIsDefault: group.id == firstOpen,
                composerOnTop: model.isComposerPinned(TasksViewModel.listComposerKey(group.id)),
                open: !model.isCollapsed(group.id),
                gap: index == 0 ? 0 : 24,
                sortable: true,
                display: RowDisplay.maker(store: store, model: model)
            )
        }
        builder.spacer("bottom", 72)
        return TaskTable(
            showProject: showProject,
            excluding: excluded(groups),
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
        case .sprint: columns = [.sprint]
        case .priority: columns = [.priority]
        case .project: columns = [.project]
        case .label, .none: columns = []
        case .status: columns = []
        }
        // Sprint planning lives in the Sprint grouping
        if model.grouping != .sprint { columns.insert(.sprint) }
        return columns
    }

    /// A project whose sprint has nothing of it while its backlog has work: say so, with a way there.
    private func emptySprintNotice() -> TaskTableRow? {
        guard let projectId = model.scope.projectId, model.scopeUsesSprints, model.filter.isEmpty,
              let project = store.project(projectId) else { return nil }
        let active = store.sprintTasks(slot: .active, in: model.scope).filter { !$0.isClosed }
        let waiting = store.sprintTasks(slot: .backlog, in: model.scope).filter { !$0.isClosed }.count
        guard active.isEmpty, waiting > 0 else { return nil }
        return .notice(id: "empty-sprint",
                       text: "Nothing from \(project.name) is in \(store.sprint.name). \(TaskStore.taskCount(waiting)) \(waiting == 1 ? "waits" : "wait") in the backlog.",
                       action: .planInSprints)
    }

    /// An empty status group, by what its status means.
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
        case .project: return "No tasks in this project. Drag tasks here to move them."
        case .priority: return "No tasks with this priority. Drag a task here to set it."
        case .sprint(.active): return "Nothing planned for this sprint. Drag tasks here."
        case .sprint(.next): return "Nothing planned for the next sprint. Drag tasks here."
        case .sprint: return "Empty. Drag tasks here."
        case .label(nil): return "Every task has a label. Drag one here to take its labels off."
        case .label: return "No tasks with this label. Drag a task here to add it."
        case .ungrouped: return "No tasks."
        }
    }
}

/// The tasks grouped by Sprint: one sprint card with every number (dates, plan against capacity, Make / Reach,
/// per-project capacity, Fill sprint and the ⋯ menu), then the active sprint's tasks, Next, later
/// sprints and the Backlog (in a project the Backlog comes first). In a project, the old sprints close
/// the page in one folded group with a Sprint column; the velocity chart shows once there are three to compare.
/// The search and filter chips narrow every group.
struct SprintPlanView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope

    var body: some View {
        let sprint = store.sprint
        var builder = TaskTableBuilder()
        builder.spacer("top", 4)
        builder.append(.sprintCard(scope))
        builder.spacer("after-card", 16)
        // A project starts with its Backlog, open; the sprints follow, closed, then the old sprints.
        // All projects shows only the sprints ahead and the backlog (no Suggested, no old sprints)
        let backlogFirst = model.sprintPlanBacklogFirst
        if backlogFirst { backlog(&builder, gap: 0) }
        group(&builder, .active, title: "\(sprint.name) · planned", hint: "",
              empty: "Nothing in this sprint yet. Drag tasks here from the backlog, or add one with the New task field.",
              gap: backlogFirst ? 24 : 0, liveHint: nil, composerIsDefault: !backlogFirst)
        let upcoming = store.upcomingSprints()
        group(&builder, .next, title: "\(sprint.nextName) · next", hint: upcoming.first?.hint ?? sprint.nextDateRange,
              empty: "Nothing planned for the next sprint. Drag tasks here to line them up.", gap: 24,
              liveHint: .sprintLoad(scope: scope, slot: .next))
        for later in upcoming where later.ahead > 1 {
            laterGroup(&builder, later)
        }
        if !backlogFirst { backlog(&builder, gap: 24) }
        if backlogFirst { pastSprints(&builder) }
        builder.spacer("bottom", 72)
        return TaskTable(
            showProject: scope.projectId == nil,
            excluding: sprintPlanExcluded,
            including: [.score],
            rows: builder.rows,
            drops: builder.drops,
            draggable: builder.draggable
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// In a project the Sprint column stays, so a backlog task
    /// shows "Backlog" and a click there moves it into a sprint; All projects leaves it out.
    private var sprintPlanExcluded: Set<TaskColumn> {
        var columns: Set<TaskColumn> = []
        if !model.sprintPlanBacklogFirst { columns.insert(.sprint) }
        return columns
    }

    /// Every completed sprint in one group, collapsed until opened: "Old sprints  24  5 sprints ·
    /// 19 done · 64h planned · 70h tracked". Its tasks come newest sprint first, each once, and the
    /// Sprint column names the old sprint a task was last in. The velocity chart closes the page once
    /// there are three sprints to compare.
    private func pastSprints(_ builder: inout TaskTableBuilder) {
        let past = store.pastSprints()
        guard !past.isEmpty else { return }
        let key = TasksViewModel.pastSprintsGroupKey
        let entries = store.pastSprintTasks(in: scope)
        let sprintOf = Dictionary(entries.map { ($0.task.id, $0.sprint) }, uniquingKeysWith: { first, _ in first })
        let tasks = model.sortedForGroup(model.sprintPlanTasks(entries.map(\.task), store: store), key, store: store)
        let display = RowDisplay.maker(store: store, model: model, scores: true)
        builder.group(
            key: key,
            title: "Old sprints",
            hint: Self.pastSprintsHint(past),
            tasks: tasks,
            emptyText: "No tasks were in the old sprints.",
            showProject: scope.projectId == nil,
            drop: nil,
            open: !model.isCollapsed(key),
            gap: 24,
            sortable: true,
            display: { task in
                var row = display(task)
                if let sprint = sprintOf[task.id] { row.sprintLabel = sprint.name }
                return row
            }
        )
        if past.count >= 3 {
            builder.spacer("before-velocity", 24)
            builder.velocity()
        }
    }

    /// "5 sprints · 19 done · 64h planned · 70h tracked", after the header's own task count.
    static func pastSprintsHint(_ past: [PastSprint]) -> String {
        let planned = past.reduce(0) { $0 + $1.plannedMinutes }
        let tracked = Int((past.reduce(0) { $0 + $1.trackedSeconds } / 60).rounded())
        let done = past.reduce(0) { $0 + $1.doneTaskIds.count }
        return [past.count == 1 ? "1 sprint" : "\(past.count) sprints", "\(done) done",
                "\(Focus.durationString(minutes: planned)) planned", "\(Focus.durationString(minutes: tracked)) tracked"]
            .joined(separator: " · ")
    }

    /// A sprint planned further ahead: tasks go in by dragging or the sprint picker (no inline composer).
    private func laterGroup(_ builder: inout TaskTableBuilder, _ later: UpcomingSprint) {
        let key = TasksViewModel.upcomingGroupKey(later.ahead)
        builder.group(
            key: key,
            title: later.name,
            hint: later.hint,
            tasks: model.sortedForGroup(model.sprintPlanTasks(store.sprintTasks(ahead: later.ahead, in: scope), store: store), key, store: store),
            emptyText: "Nothing planned for \(later.name). Drag tasks here.",
            showProject: scope.projectId == nil,
            drop: .upcoming(later.ahead),
            open: !model.isCollapsed(key),
            gap: 24,
            liveHint: .sprintLoad(scope: scope, slot: .next, ahead: later.ahead),
            sortable: true,
            display: RowDisplay.maker(store: store, model: model, scores: true)
        )
    }

    private func backlog(_ builder: inout TaskTableBuilder, gap: CGFloat) {
        group(&builder, .backlog, title: "Backlog", hint: "",
              empty: "No ideas parked for later. Drag tasks here, or pick Backlog on the New task field's sprint chip.", gap: gap,
              liveHint: .sprintLoad(scope: scope, slot: .backlog), composerIsDefault: gap == 0)
    }

    private func group(_ builder: inout TaskTableBuilder, _ slot: SprintSlot, title: String, hint: String, empty: String, gap: CGFloat,
                       liveHint: GroupLiveHint?, composerIsDefault: Bool = false) {
        let key = TasksViewModel.sprintGroupKey(slot)
        builder.group(
            key: key,
            title: title,
            hint: hint,
            tasks: model.sortedForGroup(model.sprintPlanTasks(store.sprintTasks(slot: slot, in: scope), store: store), key, store: store),
            emptyText: empty,
            showProject: scope.projectId == nil,
            drop: .slot(slot),
            composerIsDefault: composerIsDefault,
            composerOnTop: model.isComposerPinned(TasksViewModel.listComposerKey(key)),
            open: !model.isCollapsed(key),
            gap: gap,
            liveHint: liveHint,
            sortable: true,
            display: RowDisplay.maker(store: store, model: model, scores: true)
        )
    }
}

/// What dropping a task on a group (or a row in it) does.
enum TaskGroupDrop: Equatable {
    /// Sprint plan: move to the slot, placed before the row
    case slot(SprintSlot)
    /// Sprint plan: move to the sprint planned this many places after the active one (2 or more)
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
    static func maker(store: TaskStore, model: TasksViewModel, today: Bool = false, scores: Bool = false) -> (TaskItem) -> RowDisplay {
        let behind = scores ? store.sprintMix().behind : nil
        let projects = Dictionary(store.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let workflows = Dictionary(store.allProjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let labels = Dictionary(store.workspace.labels.map { ($0.id, RowLabel(name: $0.name, colorHex: $0.colorHex)) },
                                uniquingKeysWith: { first, _ in first })
        let types = Dictionary(store.taskTypes.map { ($0.id, RowType(name: $0.name, colorHex: $0.colorHex, bucket: $0.bucket)) },
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
                    ? .tomorrow : nil,
                score: scores && !task.isClosed ? store.nextBestScore(task, behind: behind, now: now) : nil,
                type: task.typeId.flatMap { types[$0] }
            )
        }
    }
}
