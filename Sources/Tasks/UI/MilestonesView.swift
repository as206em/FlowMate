import SwiftUI

/// Milestones in scope: open ones by due date, then completed ones. Each row shows progress; a
/// click opens the milestone panel. The last row adds a milestone (in All projects it has a
/// project chip). Right-click for Open, Show tasks, Mark complete and Delete.
struct MilestonesView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var pendingDelete: Milestone?

    var body: some View {
        let milestones = store.milestones(in: model.scope)
        VStack(spacing: 0) {
            if milestones.isEmpty {
                Text(emptyText)
                    .font(Focus.body)
                    .foregroundColor(Focus.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                FocusDivider()
            }
            ForEach(milestones) { milestone in
                MilestoneSummaryRow(milestone: milestone, showProject: model.scope.projectId == nil, height: 58) {
                    model.openMilestone(milestone.id)
                }
                .contextMenu { menu(milestone) }
                FocusDivider()
            }
            NewMilestoneRow()
        }
        .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        .focusPanel()
        .frame(maxWidth: .infinity, alignment: .leading)
        .milestoneDeleteAlert($pendingDelete)
    }

    private var emptyText: String {
        store.projects.isEmpty && model.scope.projectId == nil
            ? "No milestones yet. Create a project first, then add milestones to it."
            : "No milestones yet. A milestone groups the tasks for one release or goal, with a due date and progress. Name one in the row below."
    }

    @ViewBuilder
    private func menu(_ milestone: Milestone) -> some View {
        Button("Open") { model.openMilestone(milestone.id) }
        Button("Show tasks in List") { model.showTasks(ofMilestone: milestone) }
        Divider()
        if milestone.isCompleted {
            Button("Reopen") { store.reopenMilestone(milestone.id) }
        } else {
            Button("Mark complete") {
                store.completeMilestone(milestone.id)
                model.showUndoToast("Milestone completed", store: store)
            }
        }
        Menu("Due date") {
            ForEach(DuePreset.allCases) { preset in
                Button(preset.title) { store.setMilestoneDue(milestone.id, to: preset.date()) }
            }
            if milestone.dueDate != nil {
                Divider()
                Button("Clear") { store.setMilestoneDue(milestone.id, to: nil) }
            }
        }
        Divider()
        Button("Delete milestone…") { pendingDelete = milestone }
    }
}

/// "New milestone" row. In All projects a project chip picks where it goes (the last project used by default).
private struct NewMilestoneRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var name = ""
    @State private var chosenProjectId: UUID?
    @State private var pickingProject = false
    @FocusState private var focused: Bool

    private var target: Project? {
        if let id = model.scope.projectId { return store.project(id) }
        return chosenProjectId.flatMap { store.project($0) }.flatMap { $0.isArchived ? nil : $0 } ?? store.defaultProject
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Focus.text3)
                .frame(width: 16)
            TextField(target == nil ? "Add a project first" : "New milestone, press enter", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .disabled(target == nil)
                .onSubmit(add)
                .accessibilityLabel("New milestone")
            if model.scope.projectId == nil, let target {
                Button { pickingProject = true } label: {
                    HStack(spacing: 6) {
                        FocusProjectTile(name: target.name, colorHex: target.colorHex, size: 16)
                        Text(target.name).font(Focus.meta).foregroundColor(Focus.text2).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(Focus.text3)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(Focus.hairline, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("The new milestone goes to \(target.name)")
                .accessibilityLabel("Project for new milestone: \(target.name)")
                .popover(isPresented: $pickingProject, arrowEdge: .bottom) {
                    FocusPopoverMenu(width: 220) {
                        ForEach(store.projects) { project in
                            FocusMenuItem(isSelected: project.id == target.id) {
                                chosenProjectId = project.id
                                pickingProject = false
                            } label: {
                                FocusProjectTile(name: project.name, colorHex: project.colorHex)
                                Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 48)
    }

    private func add() {
        guard let target, store.addMilestone(projectId: target.id, name: name) != nil else { return }
        name = ""
        focused = true
    }
}
