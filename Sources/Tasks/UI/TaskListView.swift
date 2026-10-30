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
        } else {
            table
        }
    }

    private var table: some View {
        let groups = model.listGroups(store)
        let filtering = !model.filter.isEmpty
        let hidden = model.hiddenClosedCount(store)
        return TaskTable(
            showProject: model.scope.projectId == nil,
            excluding: excluded,
            sort: Binding(get: { model.sort }, set: { model.sort = $0 }),
            caption: hidden > 0 ? "\(hidden) \(hidden == 1 ? "task" : "tasks") from past sprints hidden. Filter by Sprint › Past sprints to show them." : ""
        ) {
            let firstOpen = groups.first(where: \.acceptsDrop)?.id
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    TaskGroupSection(
                        key: group.id,
                        title: group.title,
                        hint: group.hint,
                        colorHex: group.colorHex,
                        tasks: group.tasks,
                        emptyText: emptyText(group, filtering: filtering),
                        drop: group.acceptsDrop ? .group(group.value, reorder: model.sort.isManual) : nil,
                        composerIsDefault: group.id == firstOpen
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The grouped-by column repeats the group header, so it's hidden (Project stays: its tile helps).
    private var excluded: Set<TaskColumn> {
        switch model.grouping {
        case .milestone: return [.milestone]
        case .sprint: return [.sprint]
        case .priority: return [.priority]
        case .project: return [.project]
        case .status: return []
        }
    }

    /// One empty group among others: what belongs here and how to get it here.
    private func emptyText(_ group: TaskGroup, filtering: Bool) -> String {
        if filtering { return "No tasks here match the filters." }
        guard group.acceptsDrop else { return "No tasks. Past sprints can't take new tasks." }
        switch group.value {
        case .status(.todo): return "Nothing left to start. Drag a task here to reopen it."
        case .status(.inProgress): return "Nothing in progress. Start a timer, or drag a task here."
        case .status(.done): return "Nothing done yet. Drag a task here, or click its status circle."
        case .milestone(nil): return "Every task has a milestone. Drag one here to take it off."
        case .milestone: return "No tasks for this milestone yet. Drag tasks here to add them."
        case .project: return "No tasks in this project. Drag tasks here to move them."
        case .priority: return "No tasks with this priority. Drag a task here to set it."
        case .sprint(.active): return "Nothing planned for this sprint. Drag tasks here."
        case .sprint(.next): return "Nothing planned for the next sprint. Drag tasks here."
        case .sprint: return "Empty. Drag tasks here."
        }
    }
}

/// Sprints view (project scope): Active, Next and Backlog. Drag rows between groups.
struct SprintPlanView: View {
    @EnvironmentObject private var store: TaskStore
    let projectId: UUID

    var body: some View {
        let sprint = store.project(projectId)?.sprint
        // Manual order only: rows are dragged between and within groups here, so headers don't sort
        TaskTable(
            showProject: false,
            excluding: [.sprint],
            caption: "Drag tasks between the active sprint, the next sprint and the backlog."
        ) {
            VStack(alignment: .leading, spacing: 22) {
                group(.active, title: "\(sprint?.name ?? "Sprint") · active", hint: sprint?.dateRange ?? "",
                      empty: "Nothing in this sprint yet. Drag tasks here from Next or Backlog, or add one with the New task field.")
                group(.next, title: "\(sprint?.nextName ?? "Next sprint") · next", hint: sprint?.nextDateRange ?? "",
                      empty: "Nothing planned for the next sprint. Drag tasks here to line them up.")
                group(.backlog, title: "Backlog", hint: "",
                      empty: "No ideas parked for later. Drag tasks here, or pick Backlog on the New task field's sprint chip.")
                pastSprints
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Completed sprints, newest first, collapsed until opened: "Sprint 3 · Oct 12 – Oct 25 · 8 of 10 done".
    @ViewBuilder
    private var pastSprints: some View {
        let past = store.pastSprints(projectId)
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                FocusCaption(text: "Past sprints").padding(.horizontal, 4).padding(.top, 10)
                ForEach(past) { sprint in
                    TaskGroupSection(
                        key: TasksViewModel.pastSprintGroupKey(sprint),
                        title: sprint.name,
                        hint: [sprint.summary, sprint.goal.isEmpty ? nil : sprint.goal].compactMap { $0 }.joined(separator: " · "),
                        tasks: store.tasks(of: sprint),
                        emptyText: "No tasks were in this sprint.",
                        showProject: false
                    )
                }
            }
        }
    }

    private func group(_ slot: SprintSlot, title: String, hint: String, empty: String) -> some View {
        TaskGroupSection(
            key: TasksViewModel.sprintGroupKey(slot),
            title: title,
            hint: hint,
            tasks: store.sprintTasks(projectId: projectId, slot: slot),
            emptyText: empty,
            showProject: false,
            drop: .slot(slot),
            composerIsDefault: slot == .active
        )
    }
}

/// What dropping a task on a group (or a row in it) does.
enum TaskGroupDrop: Equatable {
    /// Sprints view: move to the slot, placed before the row
    case slot(SprintSlot)
    /// List: set the group's value; place before the row only in manual order
    case group(TaskGroupValue, reorder: Bool)
}

/// A collapsible group header over a panel of task rows. With `drop`, rows can be dragged in.
struct TaskGroupSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    let key: String
    let title: String
    var hint = ""
    var colorHex: UInt32?
    let tasks: [TaskItem]
    let emptyText: String
    var showProject: Bool?
    var drop: TaskGroupDrop?
    /// ⌘N opens this group's New task composer
    var composerIsDefault = false

    private var composerKey: String { "composer-" + key }

    var body: some View {
        let open = !model.isCollapsed(key)
        let targeted = drop != nil && model.dropTarget == key
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Focus.hoverAnimation) { model.toggleGroup(key) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Focus.text3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    if let colorHex {
                        FocusProjectTile(name: title, colorHex: colorHex)
                    }
                    Text(title).font(Focus.groupTitle).foregroundColor(Focus.text).lineLimit(1)
                    Text("\(tasks.count)").font(Focus.row.monospacedDigit()).foregroundColor(Focus.text3)
                    if !hint.isEmpty {
                        Text(hint).font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")

            if open {
                VStack(spacing: 0) {
                    if tasks.isEmpty {
                        Text(emptyText)
                            .font(Focus.body)
                            .foregroundColor(Focus.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { FocusDivider() }
                        row(task)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
                .focusPanel()

                // Outside the clipped panel, so its suggestion menu can hang below it
                if let drop {
                    TaskComposer(key: composerKey, preset: Self.preset(drop), isDefault: composerIsDefault, groupName: title)
                        .padding(.top, 6)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusPanel)
                .strokeBorder(targeted ? Focus.text3 : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(-4)
        )
        .modifier(GroupDrop(key: key, drop: drop))
        .zIndex(model.activeComposer == composerKey ? 1 : 0)
    }

    /// The value a task added to the group gets
    static func preset(_ drop: TaskGroupDrop) -> TaskGroupValue {
        switch drop {
        case let .slot(slot): return .sprint(slot)
        case let .group(value, _): return value
        }
    }

    @ViewBuilder
    private func row(_ task: TaskItem) -> some View {
        let row = TaskRow(task: task, showProject: showProject ?? (model.scope.projectId == nil))
            .id(task.id)
        if let drop {
            row
                .taskDraggable(task, model: model)
                .onDrop(of: [.plainText], delegate: TaskDropDelegate(target: key, model: model) { id in
                    guard id != task.id else { return }
                    Self.perform(drop, id: id, before: task.id, store: store)
                })
        } else {
            row
        }
    }

    static func perform(_ drop: TaskGroupDrop, id: UUID, before: UUID?, store: TaskStore) {
        switch drop {
        case let .slot(slot):
            store.moveTask(id, toSlot: slot, before: before)
        case let .group(value, reorder):
            store.moveTask(id, to: value, before: before, reorder: reorder)
        }
    }

    /// Drop on the group itself (header or empty space) appends to it.
    private struct GroupDrop: ViewModifier {
        @EnvironmentObject private var store: TaskStore
        @EnvironmentObject private var model: TasksViewModel
        let key: String
        let drop: TaskGroupDrop?

        func body(content: Content) -> some View {
            if let drop {
                content
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText], delegate: TaskDropDelegate(target: key, model: model) { id in
                        TaskGroupSection.perform(drop, id: id, before: nil, store: store)
                    })
            } else {
                content
            }
        }
    }
}

/// A 46pt task row laid out in the table's columns (TaskColumns.swift): status, project, title with
/// subtask count, milestone, sprint, due, priority, expected/live time and the timer ring.
/// Empty cells show "–". Milestone, sprint, due, priority and expected open a small editor on click;
/// a double-click on the title renames in place. A click anywhere else on the row opens the task
/// (⌘ or ⇧ click selects instead).
struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Environment(\.taskColumnLayout) private var tableLayout
    let task: TaskItem
    let showProject: Bool

    @State private var renaming = false

    var body: some View {
        let layout = tableLayout ?? TaskColumnLayout.make(showProject: showProject, width: 1000)
        FocusRow(highlighted: store.isRunning(task.id), selected: model.isSelected(task.id)) {
            TaskColumnCells(layout: layout) { column in
                cell(column)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.clickTitle(task.id, store: store) }
        .focusPointerCursor()
        .contextMenu { TaskContextMenu(task: task, rename: { renaming = true }) }
    }

    @ViewBuilder
    private func cell(_ column: TaskColumn) -> some View {
        switch column {
        case .status:
            TaskStatusButton(task: task)
        case .project:
            if let project = store.project(of: task) {
                HStack(spacing: 7) {
                    FocusProjectTile(name: project.name, colorHex: project.colorHex)
                    metaText(project.name)
                }
                .help(project.name)
            } else {
                TaskEmptyCell()
            }
        case .title:
            if renaming {
                TaskInlineTitleField(task: task) { renaming = false }
            } else {
                HStack(spacing: 10) {
                    TaskTitleButton(task: task, rename: { renaming = true }) { model.clickTitle(task.id, store: store) }
                        .layoutPriority(1)
                    SubtaskCount(task: task)
                }
            }
        case .milestone:
            TaskEditableCell(help: "Change milestone") {
                if let milestone = store.milestone(of: task) {
                    metaText(milestone.name)
                } else {
                    TaskEmptyCell()
                }
            } editor: { close in
                TaskMilestoneEditor(task: task, close: close)
            }
        case .sprint:
            if task.sprintSlot == .closed {
                metaText(store.sprintLabel(for: task))
            } else {
                TaskEditableCell(help: "Change sprint") {
                    metaText(store.sprintLabel(for: task))
                } editor: { close in
                    TaskSprintEditor(task: task, close: close)
                }
            }
        case .due:
            TaskEditableCell(help: "Change due date") {
                if let due = task.dueDate {
                    if task.isDone {
                        metaText(TaskDates.dueLabel(due))
                    } else {
                        TaskDueTag(task: task, showIcon: false)
                    }
                } else {
                    TaskEmptyCell()
                }
            } editor: { close in
                TaskDueEditor(task: task, close: close)
            }
        case .priority:
            TaskEditableCell(help: "Change priority") {
                HStack(spacing: 7) {
                    FocusPriorityBars(level: task.priority.focusLevel)
                    metaText(task.priority.title)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(task.priority.title) priority")
            } editor: { close in
                TaskPriorityEditor(task: task, close: close)
            }
        case .time:
            // Click the clock (or the estimate) to fix the time spent or change the expected time
            TaskEditableCell(help: "Change time spent or expected time") {
                TaskTimeText(task: task).frame(maxWidth: .infinity, alignment: .trailing)
            } editor: { close in
                TaskTimeEditor(task: task, close: close)
            }
        case .timer:
            if task.isDone {
                Color.clear.frame(width: 32, height: 32)
            } else {
                TaskTimerButton(task: task)
            }
        }
    }

    private func metaText(_ text: String) -> some View {
        Text(text)
            .font(Focus.meta)
            .foregroundColor(Focus.text3)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(text)
    }
}
