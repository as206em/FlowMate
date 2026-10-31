import SwiftUI

/// Floating bar for two or more selected tasks (⌘-click, ⇧-click, ⌘A):
/// "3 selected · Status · Priority · Milestone · Sprint · Due · Move to · Delete · ×".
/// Every action is one undo step with an "Undo" toast.
struct TaskBulkBar: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var open: Menu?

    private enum Menu: Hashable { case status, priority, milestone, sprint, due, project }

    var body: some View {
        let ids = model.selectedIds(store)
        FocusActionBar {
            Text("\(ids.count) selected")
                .font(Focus.control.monospacedDigit())
                .foregroundColor(Focus.text)
                .padding(.horizontal, 8)
            FocusBarSeparator()
            menuButton("Status", .status, help: "Change the status (S)") { statusMenu(ids) }
            menuButton("Priority", .priority, help: "Set the priority (P, or 1–3)") { priorityMenu }
            menuButton("Milestone", .milestone, help: "Set the milestone (M)") { milestoneMenu(ids) }
            menuButton("Sprint", .sprint, help: "Move to a sprint (R)") { sprintMenu(ids) }
            menuButton("Due", .due, help: "Set the due date (D)") { dueMenu }
            if store.projects.count > 1 {
                menuButton("Move to", .project, help: "Move to another project (⇧M)") { projectMenu }
            }
            FocusBarSeparator()
            let allPinned = ids.compactMap { store.task($0) }.allSatisfy { store.isInFocus($0) }
            FocusBarButton(title: "Today", systemImage: allPinned ? "sun.max.fill" : "sun.max") {
                model.toggleToday(ids, store: store)
            }
            .help(allPinned ? "Take the selected tasks off Today (⌘T)" : "Pin the selected tasks to Today (⌘T)")
            FocusBarSeparator()
            FocusBarButton(title: "Delete", systemImage: "trash", risk: true) { model.deleteSelected(store) }
                .help("Delete the selected tasks (⌘⌫)")
            FocusBarSeparator()
            FocusKey(text: "esc")
            FocusIconButton(systemName: "xmark", label: "Clear selection", size: 30) { model.clearSelection() }
                .help("Clear the selection (esc or ⇧⌘A)")
        }
        // Single-key pickers for the selection (S, P, M…) hang above the bar
        .quickPickerAnchor(.bulk)
    }

    private func menuButton<Content: View>(_ title: String, _ menu: Menu, help: String,
                                           @ViewBuilder content: @escaping () -> Content) -> some View {
        FocusBarButton(title: title, menu: true) { open = menu }
            .help(help)
            .popover(isPresented: Binding(get: { open == menu }, set: { if !$0, open == menu { open = nil } }), arrowEdge: .top) {
                content()
                    .environmentObject(store)
                    .environmentObject(model)
            }
    }

    private func done() { open = nil }

    private func tasks(_ n: Int) -> String { TaskStore.taskCount(n) }

    // MARK: - Menus

    /// One project's tasks: its workflow. Tasks of several projects: the statuses every one of
    /// their workflows has (same name and category), then the categories, which move each task to
    /// the first status of that category in its own project.
    private func statusMenu(_ ids: [UUID]) -> some View {
        let single = store.commonProjectId(ids) != nil
        let common = store.commonStatuses(for: ids)
        return FocusPopoverMenu(width: 220, maxHeight: 420) {
            if !single, !common.isEmpty {
                FocusMenuSection(title: "Shared statuses", first: true)
            }
            ForEach(common) { status in
                FocusMenuItem {
                    model.bulk({ "\(tasks($0)) moved to \(status.name)" }, store: store) { store.setStatus($0, status) }
                    done()
                } label: {
                    WorkflowStatusIcon(status: status, size: 14)
                    Text(status.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                }
            }
            if !single {
                FocusMenuSection(title: "By category", first: common.isEmpty)
                ForEach(StatusCategory.ordered) { category in
                    FocusMenuItem {
                        model.bulk({ "\(tasks($0)) moved to \(category.title.lowercased())" }, store: store) {
                            store.setCategory($0, category)
                        }
                        done()
                    } label: {
                        FocusStatusIcon(kind: category.focusKind, size: 14)
                        Text(category.title).font(Focus.control).foregroundColor(Focus.text)
                    }
                    .help("Each task moves to the first \(category.title.lowercased()) status of its project")
                }
            }
        }
    }

    private var priorityMenu: some View {
        FocusPopoverMenu(width: 200) {
            ForEach(TaskPriority.ordered) { priority in
                FocusMenuItem {
                    model.bulk({ "\(tasks($0)) set to \(priority.title.lowercased()) priority" }, store: store) {
                        store.setPriority($0, priority)
                    }
                    done()
                } label: {
                    FocusPriorityBars(level: priority.focusLevel)
                    Text(priority.title).font(Focus.control).foregroundColor(Focus.text)
                }
            }
        }
    }

    /// The shared project's milestones; with tasks from several projects only "No milestone".
    private func milestoneMenu(_ ids: [UUID]) -> some View {
        let projectId = store.commonProjectId(ids)
        return FocusPopoverMenu(width: 240, maxHeight: 360) {
            FocusMenuItem {
                model.bulk({ "Milestone cleared on \(tasks($0))" }, store: store) { store.setMilestone($0, nil) }
                done()
            } label: {
                Image(systemName: "diamond").font(.system(size: 11, weight: .semibold)).foregroundColor(Focus.text3)
                Text("No milestone").font(Focus.control).foregroundColor(Focus.text2)
            }
            if let projectId {
                ForEach(store.milestones(of: projectId).filter { !$0.isCompleted }) { milestone in
                    FocusMenuItem {
                        model.bulk({ "\(tasks($0)) added to \(milestone.name)" }, store: store) { store.setMilestone($0, milestone.id) }
                        done()
                    } label: {
                        Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundColor(Color(hex: milestone.colorHex))
                        Text(milestone.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                    }
                }
            } else {
                Text("Select tasks from one project to set a milestone.")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }
        }
    }

    private func sprintMenu(_ ids: [UUID]) -> some View {
        let projectId = store.commonProjectId(ids)
        return FocusPopoverMenu(width: 220) {
            ForEach(SprintSlot.plannable) { slot in
                let title = projectId.map { store.sprintLabel(slot, projectId: $0) } ?? Self.slotTitle(slot)
                FocusMenuItem {
                    model.bulk({ "\(tasks($0)) moved to \(title)" }, store: store) { store.setSprintSlot($0, slot) }
                    done()
                } label: {
                    Text(title).font(Focus.control).foregroundColor(Focus.text)
                    if slot != .backlog {
                        Text(slot == .active ? "active" : "next").font(Focus.meta).foregroundColor(Focus.text3)
                    }
                }
            }
        }
    }

    private static func slotTitle(_ slot: SprintSlot) -> String {
        switch slot {
        case .active: return "Active sprint"
        case .next: return "Next sprint"
        case .backlog, .closed: return "Backlog"
        }
    }

    private var dueMenu: some View {
        DateEditor(date: nil, set: { date in
            let label = date.map { TaskDates.dueLabel($0) } ?? "no date"
            model.bulk({ "\(tasks($0)) due \(label)" }, store: store) { store.setDueDate($0, date) }
        }, close: done)
    }

    private var projectMenu: some View {
        FocusPopoverMenu(width: 220, maxHeight: 360) {
            ForEach(store.projects) { project in
                FocusMenuItem {
                    model.bulk({ "\(tasks($0)) moved to \(project.name)" }, store: store) { store.setProject($0, project.id) }
                    done()
                } label: {
                    FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 14)
                    Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                }
            }
        }
    }
}
