import SwiftUI

/// The milestone side panel, opened from the Milestones view, the sidebar, the project panel or a
/// task's breadcrumb. Left: name, Markdown description and its tasks with an "Add task" row.
/// Right: progress, project, due date, Mark complete, Show tasks and Delete.
struct MilestonePanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestoneId: UUID

    var body: some View {
        if let milestone = store.milestone(milestoneId) {
            VStack(spacing: 0) {
                SidePanelHeader(closeLabel: "Close milestone", close: { model.closePanel() }) {
                    if case let .project(backId)? = model.panelBack, let back = store.project(backId) {
                        FocusBackButton(title: back.name, help: "Back to \(back.name)'s settings") { model.goBack() }
                        Rectangle().fill(Focus.hairline).frame(width: 1, height: 18).padding(.horizontal, 4)
                    }
                    if let project = store.project(milestone.projectId) {
                        FocusProjectTile(name: project.name, colorHex: project.colorHex)
                        FocusCrumb(text: project.name, help: "Open project") { model.openProject(project.id) }
                        FocusCrumbSeparator()
                    }
                    FocusCrumbCurrent(text: milestone.name)
                    if milestone.isCompleted { FocusTag(text: "Completed", systemImage: "checkmark") }
                }
                HStack(spacing: 0) {
                    SidePanelBody {
                        SidePanelTitleEditor(placeholder: "Milestone name", value: milestone.name) {
                            store.setMilestoneName(milestone.id, $0)
                        }
                        MarkdownDescriptionSection(
                            text: milestone.notes,
                            placeholder: "What this milestone delivers and how you'll know it's done. Markdown works.",
                            onChange: { store.setMilestoneNotes(milestone.id, $0) },
                            onToggleLine: { line in
                                store.setMilestoneNotes(milestone.id, MarkdownChecklist.toggling(line: line, in: milestone.notes))
                            },
                            onEscape: { model.closePanel() },
                            minHeight: 140
                        )
                        MilestoneTasksSection(milestone: milestone)
                    }
                    MilestoneInspector(milestone: milestone)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Milestone details")
        }
    }
}

// MARK: - Tasks

/// The milestone's tasks (status, title, sprint, due, timer) and an "Add task" row that adds to
/// this milestone in the active sprint.
private struct MilestoneTasksSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestone: Milestone

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        let tasks = store.milestoneTasks(milestone.id)
        let progress = store.milestoneProgress(milestone.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Tasks").font(Focus.body.weight(.semibold)).foregroundColor(Focus.text)
                Text(progress.short).font(Focus.body.monospacedDigit()).foregroundColor(Focus.text3)
            }
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    FocusRow(highlighted: store.isRunning(task.id)) {
                        TaskStatusButton(task: task)
                        TaskTitleButton(task: task) { model.openTask(task.id) }
                            .layoutPriority(1)
                        Text(store.sprintLabel(for: task))
                            .font(Focus.meta)
                            .foregroundColor(Focus.text3)
                            .lineLimit(1)
                            .fixedSize()
                        if task.dueDate != nil, !task.isDone {
                            TaskDueTag(task: task, showIcon: false)
                        }
                        if task.isDone {
                            Color.clear.frame(width: 32, height: 32)
                        } else {
                            TaskTimerButton(task: task)
                        }
                    }
                    .contextMenu { TaskContextMenu(task: task) }
                    FocusDivider()
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Focus.text3)
                        .frame(width: 16)
                    TextField("Add task", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(Focus.body)
                        .foregroundColor(Focus.text)
                        .focused($addFocused)
                        .onSubmit(add)
                        .accessibilityLabel("New task in \(milestone.name)")
                    if addFocused {
                        FocusKey(text: "↵")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 42)
            }
            .focusPanel()
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        }
    }

    private func add() {
        guard store.addTask(title: newTitle, projectId: milestone.projectId, milestoneId: milestone.id) != nil else { return }
        newTitle = ""
        addFocused = true
    }
}

// MARK: - Inspector

private struct MilestoneInspector: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestone: Milestone

    @State private var confirmingDelete = false

    var body: some View {
        let progress = store.milestoneProgress(milestone.id)
        SidePanelInspector {
            VStack(alignment: .leading, spacing: 10) {
                Text(progress.total == 0 ? "No tasks yet" : progress.label)
                    .font(Focus.header)
                    .foregroundColor(Focus.text)
                FocusProgressBar(fraction: progress.fraction, height: 6)
                Text(statusLine)
                    .font(Focus.meta)
                    .foregroundColor(store.isOverdue(milestone) ? Focus.risk : Focus.text3)
            }

            VStack(spacing: 6) {
                if let project = store.project(milestone.projectId) {
                    SidePanelProperty(label: "Project") {
                        Button { model.openProject(project.id) } label: {
                            HStack(spacing: 8) {
                                FocusProjectTile(name: project.name, colorHex: project.colorHex)
                                Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Focus.text3)
                            }
                            .focusField()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open project")
                    }
                }
                SidePanelProperty(label: "Due date") {
                    DateField(
                        date: milestone.dueDate,
                        risk: store.isOverdue(milestone),
                        accessibilityName: "Due date"
                    ) { store.setMilestoneDue(milestone.id, to: $0) }
                }
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { FocusDivider() }

            VStack(alignment: .leading, spacing: 8) {
                if milestone.isCompleted {
                    Button {
                        store.reopenMilestone(milestone.id)
                    } label: {
                        Label("Reopen milestone", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.focus(fullWidth: true))
                } else {
                    Button {
                        store.completeMilestone(milestone.id)
                        model.showUndoToast("Milestone completed", store: store)
                    } label: {
                        Label("Mark complete", systemImage: "checkmark.diamond")
                    }
                    .buttonStyle(.focus(fullWidth: true))
                    .help(progress.done < progress.total ? "\(progress.total - progress.done) tasks aren't done yet" : "")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        model.showTasks(ofMilestone: milestone)
                    } label: {
                        Label("Show tasks in List", systemImage: "list.bullet")
                    }
                    .buttonStyle(.focus(.ghost))
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete milestone…", systemImage: "trash").foregroundColor(Focus.risk)
                    }
                    .buttonStyle(.focus(.ghost))
                }
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { FocusDivider() }
        }
        .milestoneDeleteAlert(Binding(
            get: { confirmingDelete ? milestone : nil },
            set: { if $0 == nil { confirmingDelete = false } }
        ))
    }

    private var statusLine: String {
        if let completed = milestone.completedAt { return "Completed \(SprintState.shortDate(completed))" }
        if store.isOverdue(milestone) { return "Overdue" }
        if let due = milestone.dueDate { return "Open · due \(TaskDates.dueLabel(due))" }
        return "Open"
    }
}

// MARK: - Delete confirmation

extension View {
    /// "Delete “Name”?"; its tasks stay. Delete removes it and offers Undo.
    func milestoneDeleteAlert(_ milestone: Binding<Milestone?>) -> some View {
        modifier(MilestoneDeleteAlert(milestone: milestone))
    }
}

private struct MilestoneDeleteAlert: ViewModifier {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Binding var milestone: Milestone?

    func body(content: Content) -> some View {
        content.alert(
            "Delete “\(milestone?.name ?? "")”?",
            isPresented: Binding(get: { milestone != nil }, set: { if !$0 { milestone = nil } }),
            presenting: milestone
        ) { milestone in
            Button("Delete", role: .destructive) { model.deleteMilestone(milestone.id, store: store) }
            Button("Cancel", role: .cancel) {}
        } message: { milestone in
            let count = store.milestoneProgress(milestone.id).total
            Text(count == 0
                ? "You can undo this with ⌘Z."
                : "Its \(count) \(count == 1 ? "task stays" : "tasks stay") in the project without a milestone. You can undo this with ⌘Z.")
        }
    }
}
