import SwiftUI

/// The project side panel, opened from the sidebar, the header title or a breadcrumb.
/// Left: name, Markdown description, the milestones and the workflow (statuses). Right: color, target date, the sprint
/// (number, start, length, goal), then Show tasks, Archive and Delete.
/// TasksRootView supplies the frame, scrim, slide-in and Esc handling, as for the task panel.
struct ProjectPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let projectId: UUID

    var body: some View {
        if let project = store.project(projectId) {
            VStack(spacing: 0) {
                SidePanelHeader(closeLabel: "Close project", close: { model.closePanel() }) {
                    FocusProjectTile(name: project.name, colorHex: project.colorHex)
                    FocusCrumbCurrent(text: project.name)
                    if project.isArchived { FocusTag(text: "Archived") }
                }
                HStack(spacing: 0) {
                    SidePanelBody {
                        SidePanelTitleEditor(placeholder: "Project name", value: project.name) {
                            store.setProjectName(project.id, $0)
                        }
                        MarkdownDescriptionSection(
                            text: project.notes,
                            placeholder: "What this project is for: the goal, links and notes. Markdown works.",
                            onChange: { store.setProjectNotes(project.id, $0) },
                            onToggleLine: { line in
                                store.setProjectNotes(project.id, MarkdownChecklist.toggling(line: line, in: project.notes))
                            },
                            onEscape: { model.closePanel() },
                            minHeight: 140
                        )
                        ProjectMilestonesSection(project: project)
                        ProjectWorkflowSection(project: project)
                    }
                    ProjectInspector(project: project)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Project details")
        }
    }
}

// MARK: - Milestones

/// The project's milestones with progress; click one to open its panel. The last row adds one.
private struct ProjectMilestonesSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var newName = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        let milestones = store.milestones(of: project.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Milestones").font(Focus.body.weight(.semibold)).foregroundColor(Focus.text)
                let open = milestones.filter { !$0.isCompleted }.count
                Text(milestones.isEmpty ? "" : "\(open) open")
                    .font(Focus.body)
                    .foregroundColor(Focus.text3)
            }
            VStack(spacing: 0) {
                ForEach(milestones) { milestone in
                    MilestoneSummaryRow(milestone: milestone) { model.openMilestone(milestone.id, from: .project(project.id)) }
                    FocusDivider()
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Focus.text3)
                        .frame(width: 16)
                    TextField("Add a milestone", text: $newName)
                        .textFieldStyle(.plain)
                        .font(Focus.body)
                        .foregroundColor(Focus.text)
                        .focused($addFocused)
                        .onSubmit {
                            guard store.addMilestone(projectId: project.id, name: newName) != nil else { return }
                            newName = ""
                            addFocused = true
                        }
                        .accessibilityLabel("New milestone name")
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 42)
            }
            .focusPanel()
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        }
    }
}

/// A milestone line: diamond, name, a progress bar with "3/7", and the due date. Used in the
/// project panel and the Milestones view.
struct MilestoneSummaryRow: View {
    @EnvironmentObject private var store: TaskStore
    let milestone: Milestone
    var showProject = false
    var height: CGFloat = 42
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        let progress = store.milestoneProgress(milestone.id)
        Button(action: open) {
            HStack(spacing: 12) {
                MilestoneIcon(completed: milestone.isCompleted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(milestone.name)
                        .font(Focus.row)
                        .foregroundColor(milestone.isCompleted ? Focus.text3 : Focus.text)
                        .lineLimit(1)
                    if showProject, let project = store.project(milestone.projectId) {
                        HStack(spacing: 6) {
                            FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 14)
                            Text(project.name).font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FocusProgressBar(fraction: progress.fraction).frame(width: 80)
                Text(progress.short)
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .frame(width: 40, alignment: .leading)
                    .help(progress.label)
                Group {
                    if milestone.isCompleted {
                        FocusTag(text: "Completed", systemImage: "checkmark")
                    } else {
                        FocusTag(
                            text: milestone.dueDate.map { "Due " + SprintState.shortDate($0) } ?? "No date",
                            systemImage: milestone.dueDate == nil ? "calendar" : nil,
                            risk: store.isOverdue(milestone)
                        )
                    }
                }
                // A fixed column, so the progress bars line up from row to row
                .frame(width: 112, alignment: .trailing)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: height)
            .background(hovering ? Focus.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .accessibilityLabel("\(milestone.name), \(progress.label)\(milestone.isCompleted ? ", completed" : "")")
        .accessibilityHint("Opens the milestone")
    }
}

/// ◆ for an open milestone, a check in a diamond's place once it's complete.
struct MilestoneIcon: View {
    var completed = false
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: completed ? "checkmark.diamond.fill" : "diamond")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(completed ? Focus.done : Focus.text3)
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}

// MARK: - Inspector

private struct ProjectInspector: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var confirmingDelete = false

    var body: some View {
        SidePanelInspector {
            summary

            VStack(alignment: .leading, spacing: 8) {
                FocusCaption(text: "Color")
                FocusColorSwatches(selection: project.colorHex) { store.setProjectColor(project.id, colorHex: $0) }
            }

            VStack(spacing: 6) {
                SidePanelProperty(label: "Target date") {
                    DateField(
                        date: project.targetDate,
                        risk: project.targetDate.map { TaskDates.isBeforeToday($0) } ?? false,
                        accessibilityName: "Target date"
                    ) { store.setProjectTargetDate(project.id, $0) }
                }
            }

            sprintSection

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    model.select(.project(project.id))
                } label: {
                    Label("Show tasks", systemImage: "list.bullet")
                }
                .buttonStyle(.focus(.ghost))
                if project.isArchived {
                    Button {
                        model.unarchiveProject(project.id, store: store)
                    } label: {
                        Label("Unarchive project", systemImage: "tray.and.arrow.up")
                    }
                    .buttonStyle(.focus(.ghost))
                } else {
                    Button {
                        model.archiveProject(project.id, store: store)
                    } label: {
                        Label("Archive project", systemImage: "archivebox")
                    }
                    .buttonStyle(.focus(.ghost))
                    .help("Hide it from the sidebar, pickers and menu bar. Nothing is deleted.")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete project…", systemImage: "trash").foregroundColor(Focus.risk)
                }
                .buttonStyle(.focus(.ghost))
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { FocusDivider() }
        }
        .projectDeleteAlert(Binding(get: { confirmingDelete ? project : nil }, set: { if $0 == nil { confirmingDelete = false } }))
    }

    private var summary: some View {
        let open = store.openCount(project.id)
        let total = store.tasks(of: project.id).count
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(open) open \(open == 1 ? "task" : "tasks")")
                .font(Focus.header)
                .foregroundColor(Focus.text)
            Text("\(total) in all · created \(SprintState.shortDate(project.createdAt))")
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
        }
    }

    /// Sprint number, start, length and goal. Changing the start or length moves the end and the next sprint.
    private var sprintSection: some View {
        let sprint = project.sprint
        return VStack(alignment: .leading, spacing: 6) {
            FocusCaption(text: "Sprint").padding(.top, 12)
            SidePanelProperty(label: "Number") {
                FocusStepper(value: sprint.number, label: "Sprint number") {
                    store.setSprintNumber(projectId: project.id, number: $0)
                }
            }
            SidePanelProperty(label: "Starts") {
                DateField(date: sprint.startDate, allowsClear: false, accessibilityName: "Sprint start") { date in
                    if let date { store.setSprintStart(projectId: project.id, date: date) }
                }
            }
            SidePanelProperty(label: "Length") {
                FocusPicker(
                    options: SprintState.lengthChoices,
                    selection: Binding(get: { sprint.lengthWeeks }, set: { store.setSprintLength(projectId: project.id, weeks: $0) }),
                    title: { SprintState.lengthLabel($0) }
                )
                .accessibilityLabel("Sprint length")
            }
            SidePanelProperty(label: "Goal") {
                TextField(SprintState.goalPlaceholder, text: Binding(
                    get: { sprint.goal },
                    set: { store.setSprintGoal(projectId: project.id, goal: $0) }
                ))
                .focusField()
                .accessibilityLabel("Sprint goal")
            }
            Text("\(sprint.name) ends \(SprintState.shortDate(sprint.endDate)). \(sprint.nextName) runs \(sprint.nextDateRange).")
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            HStack(spacing: 8) {
                Button("Complete sprint…") { model.completingSprintProjectId = project.id }
                    .buttonStyle(.focus())
                if !project.pastSprints.isEmpty {
                    Button("\(project.pastSprints.count) past") { model.showSprints(of: project.id) }
                        .buttonStyle(.focus(.ghost))
                        .help("Show past sprints")
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { FocusDivider() }
    }
}

// MARK: - Delete confirmation

extension View {
    /// "Delete “Name”?" with what goes with it; Delete removes the project and offers Undo.
    func projectDeleteAlert(_ project: Binding<Project?>) -> some View {
        modifier(ProjectDeleteAlert(project: project))
    }
}

private struct ProjectDeleteAlert: ViewModifier {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Binding var project: Project?

    func body(content: Content) -> some View {
        content.alert(
            "Delete “\(project?.name ?? "")”?",
            isPresented: Binding(get: { project != nil }, set: { if !$0 { project = nil } }),
            presenting: project
        ) { project in
            Button("Delete", role: .destructive) { model.deleteProject(project.id, store: store) }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(message(project))
        }
    }

    private func message(_ project: Project) -> String {
        let tasks = store.tasks(of: project.id).count
        let milestones = store.milestones(of: project.id).count
        var parts: [String] = []
        if tasks > 0 { parts.append("\(tasks) \(tasks == 1 ? "task" : "tasks")") }
        if milestones > 0 { parts.append("\(milestones) \(milestones == 1 ? "milestone" : "milestones")") }
        let what = parts.isEmpty ? "" : "Its \(parts.joined(separator: " and ")) will be deleted too. "
        let archive = project.isArchived ? "" : "To keep them, archive the project instead. "
        return what + archive + "You can undo this with ⌘Z."
    }
}
