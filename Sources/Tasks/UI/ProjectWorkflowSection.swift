import SwiftUI

/// The project panel's Workflow: the project's statuses in board order. Rename one in place, click
/// its icon for a color, pick its kind (Not started, Started, Done, Canceled), drag the handle or
/// use ⋯ to reorder, add one at the bottom, delete one (its tasks move to a status you pick), or
/// apply a preset. Every change is one undo step.
struct ProjectWorkflowSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var newName = ""
    @FocusState private var addFocused: Bool
    @State private var choosingPreset = false
    /// Where a dragged status would land: before this status id, or "end"
    @State private var dropBefore: String?

    static let dragPrefix = "workflow-status:"

    var body: some View {
        let usage = Dictionary(grouping: store.tasks(of: project.id), by: \.statusId).mapValues(\.count)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Workflow").font(Focus.body.weight(.semibold)).foregroundColor(Focus.text)
                Text(summary).font(Focus.body).foregroundColor(Focus.text3).lineLimit(1)
                Spacer(minLength: 8)
                presetButton
            }
            VStack(spacing: 0) {
                ForEach(Array(project.statuses.enumerated()), id: \.element.id) { index, status in
                    WorkflowStatusRow(project: project, status: status, index: index, usage: usage[status.id] ?? 0)
                        .overlay(alignment: .top) { if dropBefore == status.id { dropLine } }
                        .onDrop(of: [.plainText], delegate: WorkflowStatusDropDelegate(
                            target: status.id, current: $dropBefore
                        ) { id in
                            store.moveStatus(projectId: project.id, statusId: id, before: status.id)
                        })
                    FocusDivider()
                }
                addRow
                    .overlay(alignment: .top) { if dropBefore == "end" { dropLine } }
                    .onDrop(of: [.plainText], delegate: WorkflowStatusDropDelegate(target: "end", current: $dropBefore) { id in
                        store.moveStatus(projectId: project.id, statusId: id, before: nil)
                    })
            }
            .focusPanel()
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
            Text("Board columns follow this order. The kind decides what a status does: starting a timer moves a not started task to the first started status, done and canceled pause timers and close with the sprint.")
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "6 statuses · Dev"
    private var summary: String {
        let count = project.statuses.count
        let preset = WorkflowPreset.matching(project.statuses).map { " · \($0.title)" } ?? " · Custom"
        return "\(count) \(count == 1 ? "status" : "statuses")\(preset)"
    }

    private var presetButton: some View {
        Button { choosingPreset = true } label: {
            HStack(spacing: 5) {
                Text("Apply preset")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(Focus.text3)
            }
        }
        .buttonStyle(.focus(.ghost, compact: true))
        .help("Replace the statuses with a ready-made workflow; tasks keep their kind of status")
        .popover(isPresented: $choosingPreset, arrowEdge: .bottom) {
            FocusPopoverMenu(width: 300) {
                FocusMenuSection(title: "Presets", first: true)
                ForEach(WorkflowPreset.allCases) { preset in
                    FocusMenuItem(isSelected: WorkflowPreset.matching(project.statuses) == preset) {
                        apply(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.title).font(Focus.control).foregroundColor(Focus.text)
                            Text(preset.summary).font(.system(size: 11.5)).foregroundColor(Focus.text3).lineLimit(1)
                        }
                    }
                    .frame(height: 40)
                }
            }
        }
    }

    private func apply(_ preset: WorkflowPreset) {
        choosingPreset = false
        let before = store.lastUndoId
        store.applyWorkflowPreset(projectId: project.id, preset)
        guard store.lastUndoId != before else { return }
        model.showUndoToast("\(preset.title) workflow applied", store: store)
    }

    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Focus.text3)
                .frame(width: 16)
            TextField("Add a status", text: $newName)
                .textFieldStyle(.plain)
                .font(Focus.body)
                .foregroundColor(Focus.text)
                .focused($addFocused)
                .onSubmit(add)
                .accessibilityLabel("New status name")
            if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Started · ↵").font(Focus.meta).foregroundColor(Focus.text3)
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .frame(height: 42)
        .help("New statuses are Started; change the kind afterwards")
    }

    private func add() {
        guard store.addStatus(projectId: project.id, name: newName, category: .started) != nil else { return }
        newName = ""
        addFocused = true
    }

    /// Where a dragged status lands: a 2px `text3` line.
    private var dropLine: some View {
        Rectangle().fill(Focus.text3).frame(height: 2).padding(.horizontal, 8).offset(y: -1)
    }

    static func draggedId(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(dragPrefix) else { return nil }
        return String(trimmed.dropFirst(dragPrefix.count))
    }
}

/// Accepts dragged workflow statuses ("workflow-status:<id>"); ignores tasks and subtasks.
private struct WorkflowStatusDropDelegate: DropDelegate {
    let target: String
    @Binding var current: String?
    let perform: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { current = target }
    func dropExited(info: DropInfo) { if current == target { current = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        current = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = ProjectWorkflowSection.draggedId(text) else { return }
            DispatchQueue.main.async { perform(id) }
        }
        return true
    }
}

/// One status: drag handle, icon (click for a color), name (edit in place), kind, task count, ⋯.
private struct WorkflowStatusRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project
    let status: WorkflowStatus
    let index: Int
    let usage: Int

    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool
    @State private var choosingColor = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Focus.text3)
                .frame(width: 14, height: 30)
                .contentShape(Rectangle())
                .opacity(hovering ? 1 : 0)
                .onDrag { NSItemProvider(object: (ProjectWorkflowSection.dragPrefix + status.id) as NSString) }
                .help("Drag to reorder")
                .accessibilityHidden(true)

            Button { choosingColor = true } label: {
                WorkflowStatusIcon(status: status, size: 16)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Color: \(Focus.colorName(status.colorHex))")
            .accessibilityLabel("\(status.name) color, \(Focus.colorName(status.colorHex))")
            .popover(isPresented: $choosingColor, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    FocusCaption(text: "Color")
                    FocusColorSwatches(selection: status.colorHex, palette: Focus.statusPalette) { hex in
                        store.setStatusColor(projectId: project.id, statusId: status.id, colorHex: hex)
                        choosingColor = false
                    }
                }
                .padding(12)
                .background(Focus.raised)
            }

            TextField("Status name", text: $draft)
                .textFieldStyle(.plain)
                .font(Focus.body)
                .foregroundColor(Focus.text)
                .focused($nameFocused)
                .onChange(of: draft) { name in
                    if name != status.name { store.renameStatus(projectId: project.id, statusId: status.id, to: name) }
                }
                .onSubmit { nameFocused = false }
                .onChange(of: nameFocused) { focused in
                    // A blank name isn't saved; show the kept one again
                    if !focused { draft = status.name }
                }
                .onChange(of: status.name) { name in if !nameFocused { draft = name } }
                .onAppear { draft = status.name }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Status name")

            categoryMenu

            Text(usage == 0 ? "–" : "\(usage)")
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(Focus.text3)
                .frame(width: 28, alignment: .trailing)
                .help(usage == 1 ? "1 task" : "\(usage) tasks")

            moreMenu
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 42)
        .background(hovering ? Focus.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .popover(isPresented: $confirmingDelete, arrowEdge: .trailing) {
            WorkflowDeletePopover(project: project, status: status, usage: usage) { confirmingDelete = false }
                .environmentObject(store)
                .environmentObject(model)
        }
    }

    /// The kind, as a quiet dropdown; kinds that would leave no Not started or Done status are off.
    private var categoryMenu: some View {
        Menu {
            ForEach(StatusCategory.ordered) { category in
                Button {
                    store.setStatusCategory(projectId: project.id, statusId: status.id, category)
                } label: {
                    if category == status.category {
                        Label(category.title, systemImage: "checkmark")
                    } else {
                        Text(category.title)
                    }
                }
                .disabled(category != status.category
                          && !store.canChangeCategory(projectId: project.id, statusId: status.id, to: category))
            }
        } label: {
            HStack(spacing: 5) {
                Text(status.category.title).font(Focus.control).foregroundColor(Focus.text2).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 8)
            .frame(width: 118, height: 26, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(Focus.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("What this status means: Not started, Started, Done or Canceled")
        .accessibilityLabel("Kind: \(status.category.title)")
    }

    private var moreMenu: some View {
        let count = project.statuses.count
        let canDelete = store.canDeleteStatus(projectId: project.id, statusId: status.id)
        return Menu {
            Button("Move up") { store.moveStatus(projectId: project.id, statusId: status.id, by: -1) }
                .disabled(index == 0)
            Button("Move down") { store.moveStatus(projectId: project.id, statusId: status.id, by: 1) }
                .disabled(index >= count - 1)
            Divider()
            Button(usage == 0 ? "Delete status" : "Delete status…") { delete() }
                .disabled(!canDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Focus.text2)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(hovering ? 1 : 0.6)
        .help(canDelete ? "Move or delete" : "Move. A workflow keeps at least one Not started and one Done status.")
        .accessibilityLabel("More for \(status.name)")
    }

    /// Unused: goes at once with an Undo toast. In use: asks where its tasks go.
    private func delete() {
        if usage > 0 {
            confirmingDelete = true
            return
        }
        let before = store.lastUndoId
        guard store.deleteStatus(projectId: project.id, statusId: status.id), store.lastUndoId != before else { return }
        model.showUndoToast("Status “\(status.name)” deleted", store: store)
    }
}

/// "Delete “Review”? 3 tasks use it. Move them to [To do ▾]" with Cancel and Delete.
private struct WorkflowDeletePopover: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project
    let status: WorkflowStatus
    let usage: Int
    let close: () -> Void

    @State private var targetId: String = ""

    var body: some View {
        let others = project.statuses.filter { $0.id != status.id }
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete “\(status.name)”?").font(Focus.header).foregroundColor(Focus.text)
            Text("\(TaskStore.taskCount(usage)) \(usage == 1 ? "uses" : "use") this status. Move \(usage == 1 ? "it" : "them") to:")
                .font(Focus.body)
                .foregroundColor(Focus.text2)
                .fixedSize(horizontal: false, vertical: true)
            FocusTintedPicker(
                options: others,
                selection: Binding(
                    get: { others.first { $0.id == targetId } ?? WorkflowRules.first(status.category, in: others) },
                    set: { targetId = $0.id }
                ),
                title: { $0.name },
                tint: { Focus.statusTint($0.colorHex) },
                icon: { WorkflowStatusIcon(status: $0, size: 15) },
                accessibilityName: "Move tasks to"
            )
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: close).buttonStyle(.focus()).keyboardShortcut(.cancelAction)
                Button { delete(others) } label: {
                    Text("Delete status").foregroundColor(Focus.risk)
                }
                .buttonStyle(.focus())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Focus.raised)
    }

    private func delete(_ others: [WorkflowStatus]) {
        let target = others.first { $0.id == targetId } ?? WorkflowRules.first(status.category, in: others)
        let before = store.lastUndoId
        store.deleteStatus(projectId: project.id, statusId: status.id, reassignTo: target.id)
        close()
        guard store.lastUndoId != before else { return }
        model.showUndoToast("Status “\(status.name)” deleted · \(TaskStore.taskCount(usage)) moved to \(target.name)", store: store)
    }
}
