import SwiftUI

/// The project side panel, opened from the sidebar, the header title or a breadcrumb.
/// Left: name, Markdown description and the workflow (statuses). Right: color, icon,
/// target date, the sprint (plan in sprints, hours per week, number, start, length, goal), the
/// defaults (view it opens on, new tasks' time and sprint), then Show tasks, Archive and Delete.
/// TasksRootView supplies the frame, scrim, slide-in and Esc handling, as for the task panel.
struct ProjectPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let projectId: UUID

    var body: some View {
        if let project = store.project(projectId) {
            VStack(spacing: 0) {
                SidePanelHeader(closeLabel: "Close project", close: { model.closePanel() }) {
                    FocusProjectTile(project: project)
                    FocusCrumbCurrent(text: project.name)
                    if project.isArchived { FocusTag(text: "Archived") }
                }
                HStack(spacing: 0) {
                    SidePanelBody {
                        SidePanelTitleEditor(placeholder: "Project name", value: project.name,
                                             dictationId: "project-name-\(project.id)") {
                            store.setProjectName(project.id, $0)
                        }
                        MarkdownDescriptionSection(
                            text: project.notes,
                            dictationId: "project-notes-\(project.id)",
                            placeholder: "What this project is for: the goal, links and notes. Markdown works.",
                            onChange: { store.setProjectNotes(project.id, $0) },
                            onToggleLine: { line in
                                store.setProjectNotes(project.id, MarkdownChecklist.toggling(line: line, in: project.notes))
                            },
                            onEscape: { model.closePanel() },
                            minHeight: 140
                        )
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

// MARK: - Inspector

private struct ProjectInspector: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var confirmingDelete = false

    var body: some View {
        SidePanelInspector {
            summary
            CompletionSummary(title: "Completion", completion: store.projectCompletion(project.id))

            VStack(alignment: .leading, spacing: 8) {
                FocusCaption(text: "Color")
                FocusColorSwatches(selection: project.colorHex) { store.setProjectColor(project.id, colorHex: $0) }
            }

            VStack(alignment: .leading, spacing: 8) {
                FocusCaption(text: "Icon")
                ProjectIconButton(project: project)
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

            ProjectDefaultsSection(project: project)

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

    private var capacityHint: String {
        guard let weekly = project.weeklyCapacityHours else {
            return "Not set."
        }
        guard project.usesSprints else { return "\(SprintPlanRules.hoursText(weekly / 5)) a working day." }
        let total = weekly * Double(store.sprint.lengthWeeks)
        return "\(SprintPlanRules.hoursText(total)) per \(store.sprint.lengthLabel) sprint."
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

    /// Whether the project takes part in the workspace's sprint, and its weekly capacity. The sprint
    /// itself (number, dates, goal) is edited in the sprint menu of All projects.
    private var sprintSection: some View {
        let sprint = store.sprint
        return VStack(alignment: .leading, spacing: 6) {
            FocusCaption(text: "Sprint").padding(.top, 12)
            Toggle(isOn: Binding(get: { project.usesSprints }, set: { on in
                store.setUsesSprints(project.id, on)
                model.showUndoToast(on ? "Sprints on · in \(store.sprintName())" : "Sprints off", store: store)
            })) {
                Text("Plan in sprints").font(Focus.body).foregroundColor(Focus.text)
            }
            .toggleStyle(.focus)
            .frame(minHeight: 34)
            .accessibilityLabel("Plan in sprints")
            VStack(alignment: .leading, spacing: 4) {
                Text("Hours per week on this project").font(Focus.meta).foregroundColor(Focus.text3)
                CapacityField(project: project)
                Text(capacityHint)
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)
            if !project.usesSprints {
                Text("Every open task counts as current work. Turning sprints on puts the work in progress in \(sprint.name); the other open tasks wait in the backlog.")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(sprint.name) · \(sprint.dateRange). The sprint is shared with every project that takes part; its number, dates and goal are in the sprint menu of All projects.")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Sprints") { model.showSprints(of: project.id) }
                    .buttonStyle(.focus(.ghost))
                    .padding(.top, 2)
            }
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
        var parts: [String] = []
        if tasks > 0 { parts.append("\(tasks) \(tasks == 1 ? "task" : "tasks")") }
        let what = parts.isEmpty ? "" : "Its \(parts.joined(separator: " and ")) will be deleted too. "
        let archive = project.isArchived ? "" : "To keep them, archive the project instead. "
        return what + archive + "You can undo this with ⌘Z."
    }
}
