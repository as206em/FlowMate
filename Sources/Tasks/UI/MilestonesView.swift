import SwiftUI

/// Milestones in scope: open ones by due date, then completed ones. In All projects they're in a
/// section per project (sidebar order). Each row shows progress; a click shows the milestone's
/// page. The last row adds a milestone (in All projects it has a project chip). Right-click for
/// Show tasks, Details, Mark complete, Due date and Delete.
struct MilestonesView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var pendingDelete: Milestone?

    var body: some View {
        let sections = store.milestonesByProject(in: model.scope)
        let grouped = model.scope.projectId == nil
        VStack(alignment: .leading, spacing: 0) {
            if grouped {
                ForEach(sections, id: \.project.id) { section in
                    sectionHeader(section.project, count: section.milestones.count)
                    panel(section.milestones, addRow: false)
                        .padding(.bottom, 22)
                }
                if sections.isEmpty {
                    panel([], addRow: true)
                } else {
                    // One add row under the sections, with a project chip
                    VStack(spacing: 0) { NewMilestoneRow() }
                        .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
                        .focusPanel()
                }
            } else {
                panel(sections.first?.milestones ?? [], addRow: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .milestoneDeleteAlert($pendingDelete)
    }

    /// A project's section heading in All projects: its tile, name and milestone count. A click shows the project.
    private func sectionHeader(_ project: Project, count: Int) -> some View {
        Button { model.select(.project(project.id)) } label: {
            HStack(spacing: 8) {
                FocusProjectTile(name: project.name, colorHex: project.colorHex)
                Text(project.name).font(Focus.groupTitle).foregroundColor(Focus.text).lineLimit(1)
                Text("\(count)").font(Focus.row.monospacedDigit()).foregroundColor(Focus.text3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(project.name)")
    }

    private func panel(_ milestones: [Milestone], addRow: Bool) -> some View {
        VStack(spacing: 0) {
            if milestones.isEmpty {
                Text(emptyText)
                    .font(Focus.body)
                    .foregroundColor(Focus.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                FocusDivider()
            }
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                MilestoneSummaryRow(milestone: milestone, height: 58) {
                    model.showMilestone(milestone.id, store: store)
                }
                .contextMenu { menu(milestone) }
                if addRow || index < milestones.count - 1 { FocusDivider() }
            }
            if addRow { NewMilestoneRow() }
        }
        .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        .focusPanel()
    }

    private var emptyText: String {
        store.projects.isEmpty && model.scope.projectId == nil
            ? "No milestones yet. Create a project first, then add milestones to it."
            : "No milestones yet. A milestone groups the tasks for one release or goal, with a due date and progress. Name one in the row below."
    }

    @ViewBuilder
    private func menu(_ milestone: Milestone) -> some View {
        Button("Show tasks") { model.showMilestone(milestone.id, store: store) }
        Button("Details…") { model.openMilestone(milestone.id) }
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
        Menu("Color") {
            ForEach(Milestone.palette, id: \.self) { hex in
                Button {
                    store.setMilestoneColor(milestone.id, colorHex: hex)
                } label: {
                    if hex == milestone.colorHex {
                        Label(Focus.colorName(hex), systemImage: "checkmark")
                    } else {
                        Text(Focus.colorName(hex))
                    }
                }
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
                .accessibilityHint("Return adds it. Shift-Return adds it and shows its page.")
            if focused, !name.isEmpty {
                FocusKey(text: "⇧↵ add and open")
            }
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

    /// ↵ adds it with an Open toast; ⇧↵ adds it and shows its page
    private func add() {
        let open = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        guard let target, model.addMilestone(name, projectId: target.id, open: open, store: store) != nil else { return }
        name = ""
        if !open { focused = true }
    }
}
