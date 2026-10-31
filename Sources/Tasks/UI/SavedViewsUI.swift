import SwiftUI

// Saved views in the window: the sidebar's Views section (live counts, drag to reorder,
// right-click Rename · Duplicate · Update to current · Delete), the Save view sheet, the header
// title of a view and the filter bar's "Modified · Update view · Revert".

// MARK: - Filter bar

/// On a saved view: "Modified · Update view · Revert" once its filters, sort, grouping or tab
/// changed; nothing while it's as saved.
struct SavedViewModifiedControls: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        if model.isViewModified(store) {
            HStack(spacing: 4) {
                Circle().fill(Focus.progress).frame(width: 6, height: 6)
                Text("Modified").font(Focus.meta).foregroundColor(Focus.text3).fixedSize()
                    .padding(.trailing, 2)
                Button("Update view") { model.updateActiveView(store) }
                    .buttonStyle(.focus())
                    .help("Save these filters, sort and grouping into the view")
                Button("Revert") { model.revertActiveView(store) }
                    .buttonStyle(.focus(.ghost))
                    .help("Back to the view as saved")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("View modified")
        }
    }
}

// MARK: - Header

/// The header's title on a saved view: its icon and name, then where it looks ("All projects",
/// "Atlas › Beta").
struct SavedViewHeaderTitle: View {
    @EnvironmentObject private var store: TaskStore
    let view: SavedView

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: view.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Focus.text2)
            Text(view.name)
                .font(Focus.header)
                .foregroundColor(Focus.text)
                .lineLimit(1)
            Text(store.savedViewPlace(view))
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .lineLimit(1)
        }
    }
}

// MARK: - Sidebar

/// The sidebar's Views section between All projects and Projects. Empty, it suggests two
/// starters (made only when clicked).
struct SidebarViewsSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        let views = store.savedViews
        FocusCaption(text: "Views")
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .padding(.bottom, 6)
        if views.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Filter a List or Board, then Save view… Or start with:")
                    .font(.system(size: 11.5))
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                ForEach(SavedViewSuggestion.starters) { suggestion in
                    SidebarSuggestionRow(suggestion: suggestion) { model.addSuggestedView(suggestion, store: store) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(views) { view in
                    SidebarViewRow(view: view).id(SidebarItem.view(view.id))
                        .onDrag {
                            model.draggingTaskId = nil
                            return NSItemProvider(object: SidebarViewDrop.payload(view.id) as NSString)
                        }
                        .onDrop(of: [.plainText], delegate: SidebarViewDrop(target: view.id, store: store, model: model))
                        .overlay(alignment: .top) {
                            if model.dropTarget == SidebarViewDrop.key(view.id) {
                                Rectangle().fill(Focus.text3).frame(height: 2).offset(y: -2)
                            }
                        }
                }
                // Room to drop a view last
                Color.clear.frame(height: 4)
                    .onDrop(of: [.plainText], delegate: SidebarViewDrop(target: nil, store: store, model: model))
                    .overlay(alignment: .top) {
                        if model.dropTarget == SidebarViewDrop.key(nil) {
                            Rectangle().fill(Focus.text3).frame(height: 2)
                        }
                    }
            }
        }
    }
}

/// One saved view: icon, name, a dot while modified, the live count.
private struct SidebarViewRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let view: SavedView

    var body: some View {
        let selected = model.sidebarSelection == .view(view.id)
        FocusSidebarItem(selected: selected, focused: model.sidebarCursor == .view(view.id),
                         action: { model.applySavedView(view.id, store: store) }) {
            Image(systemName: view.iconName)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 18)
            Text(view.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected, model.isViewModified(store) {
                Circle().fill(Focus.progress).frame(width: 6, height: 6)
                    .help("Modified: Update view or Revert in the filter bar")
                    .accessibilityLabel("Modified")
            }
            Text("\(store.savedViewCount(view))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Focus.text3)
        }
        .help("\(view.name) · \(store.savedViewPlace(view)) · \(view.layout.title)")
        .contextMenu {
            Button("Rename…") { model.savingView = SaveViewRequest(kind: .rename(view.id)) }
            Button("Duplicate") { model.duplicateSavedView(view.id, store: store) }
            Button("Update to current") { model.updateView(view.id, toCurrent: store) }
                .disabled(!model.showsFilterBar)
            Divider()
            Button("Delete view") { model.deleteSavedView(view.id, store: store) }
        }
    }
}

/// A starter view in the empty Views section: quiet until hovered; a click makes it.
private struct SidebarSuggestionRow: View {
    let suggestion: SavedViewSuggestion
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)
                Image(systemName: suggestion.icon)
                    .font(.system(size: 11.5, weight: .medium))
                Text(suggestion.name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(hovering ? Focus.text : Focus.text3)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add a view of \(suggestion.name.lowercased()) tasks across every project")
        .accessibilityLabel("Add view \(suggestion.name)")
    }
}

/// Drag a view onto another to put it there (or onto the space below the last to move it last).
/// The payload is "view:<uuid>", which task and project drop targets ignore.
private struct SidebarViewDrop: DropDelegate {
    let target: UUID?
    let store: TaskStore
    let model: TasksViewModel

    static let prefix = "view:"
    static func payload(_ id: UUID) -> String { prefix + id.uuidString }
    static func key(_ id: UUID?) -> String { "sidebar-view-\(id?.uuidString ?? "end")" }

    func validateDrop(info: DropInfo) -> Bool { model.draggingTaskId == nil && info.hasItemsConforming(to: [.plainText]) }

    func dropEntered(info: DropInfo) { model.dropTarget = Self.key(target) }

    func dropExited(info: DropInfo) {
        if model.dropTarget == Self.key(target) { model.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.dropTarget = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let target = target
        let store = store
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.hasPrefix(Self.prefix), let id = UUID(uuidString: String(text.dropFirst(Self.prefix.count))) else { return }
            DispatchQueue.main.async { store.moveSavedView(id, before: target) }
        }
        return true
    }
}

// MARK: - Save view sheet

/// "Save view": a name, an icon and what it keeps (where, Board or List, the filters). Renaming
/// an existing view uses the same sheet.
struct SaveViewSheet: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Environment(\.dismiss) private var dismiss
    let request: SaveViewRequest

    @State private var name = ""
    @State private var icon = SavedView.defaultIcon
    @FocusState private var nameFocused: Bool

    private var renaming: SavedView? {
        if case let .rename(id) = request.kind { return store.savedView(id) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(renaming == nil ? "Save view" : "Rename view")
                .font(Focus.pageTitle)
                .foregroundColor(Focus.text)
                .padding(.bottom, 4)
            Text(renaming == nil ? "Keeps this scope, tab, filters, sort and grouping in the sidebar under Views."
                                 : "The view keeps its filters; Update to current changes those.")
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .padding(.bottom, 18)

            FocusLabeled(label: "Name") {
                TextField("High priority bugs", text: $name)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .focusField(focused: nameFocused)
                    .accessibilityLabel("View name")
            }
            .padding(.bottom, 14)

            FocusLabeled(label: "Icon") {
                HStack(spacing: 4) {
                    ForEach(SavedView.icons, id: \.self) { symbol in
                        Button { icon = symbol } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(icon == symbol ? Focus.text : Focus.text3)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: Focus.radiusControl)
                                    .fill(icon == symbol ? Focus.selected : .clear))
                                .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl)
                                    .strokeBorder(icon == symbol ? Focus.lineStrong : .clear, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                    }
                }
            }
            .padding(.bottom, 16)

            summary
                .padding(.bottom, 20)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.focus(.ghost))
                    .keyboardShortcut(.cancelAction)
                Button(renaming == nil ? "Save view" : "Save", action: save)
                    .buttonStyle(.focus(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(SavedView.cleanName(name).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Focus.canvas)
        .focusLight()
        .onAppear {
            if let view = renaming {
                name = view.name
                icon = view.iconName
            } else {
                name = suggestedName
            }
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    /// What the view keeps, in a sunk box: "All projects · List", then the filters in words.
    private var summary: some View {
        let lines = summaryLines
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(Focus.meta).foregroundColor(Focus.text2).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.sidebar))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.hairline, lineWidth: 1))
    }

    private var summaryLines: [String] {
        let options: TaskViewOptions
        let place: String
        let layout: SavedView.Layout
        if let view = renaming {
            options = view.options
            place = store.savedViewPlace(view)
            layout = view.layout
        } else {
            options = model.options
            place = store.savedViewPlace(SavedView(name: "", scope: model.scope))
            layout = model.currentLayout
        }
        var lines = ["\(place) · \(layout.title)"]
        lines += SavedViewDescription.filterLines(options, store: store)
        return lines
    }

    /// A first guess from the filters: "High priority", "Overdue", a label's name…
    private var suggestedName: String {
        SavedViewDescription.suggestedName(model.options, store: store)
    }

    private func save() {
        let clean = SavedView.cleanName(name)
        guard !clean.isEmpty else { return }
        if let view = renaming {
            store.renameSavedView(view.id, to: clean)
            store.setSavedViewIcon(view.id, icon)
        } else {
            model.saveCurrentView(name: clean, icon: icon == SavedView.defaultIcon ? nil : icon, store: store)
        }
        dismiss()
    }
}

/// Saved view settings in words, for the Save view sheet and tests.
enum SavedViewDescription {
    @MainActor
    static func filterLines(_ options: TaskViewOptions, store: TaskStore) -> [String] {
        let f = options.filter
        var lines: [String] = []
        if !f.trimmedQuery.isEmpty { lines.append("Search “\(f.trimmedQuery)”") }
        let statuses = StatusCategory.ordered.filter(f.categories.contains).map(\.title)
            + Set(f.statuses.compactMap { id in store.allProjects.lazy.compactMap { $0.status(id)?.name }.first }).sorted()
        if !statuses.isEmpty { lines.append("Status: " + statuses.joined(separator: ", ")) }
        if !f.priorities.isEmpty { lines.append("Priority: " + TaskPriority.ordered.filter(f.priorities.contains).map(\.title).joined(separator: ", ")) }
        if !f.milestones.isEmpty {
            lines.append("Milestone: " + f.milestones.map { $0.flatMap { store.milestone($0)?.name } ?? "None" }.sorted().joined(separator: ", "))
        }
        if !f.sprintSlots.isEmpty {
            let names: [SprintSlot: String] = [.active: "Active", .next: "Next", .backlog: "Backlog", .closed: "Past sprints"]
            lines.append("Sprint: " + [SprintSlot.active, .next, .backlog, .closed].filter(f.sprintSlots.contains).compactMap { names[$0] }.joined(separator: ", "))
        }
        if !f.due.isEmpty { lines.append("Due: " + TaskDueFilter.allCases.filter(f.due.contains).map(\.title).joined(separator: ", ")) }
        if !f.labels.isEmpty { lines.append("Label: " + store.labels.filter { f.labels.contains($0.id) }.map(\.name).joined(separator: ", ")) }
        if !f.projectIds.isEmpty { lines.append("Project: " + store.projects.filter { f.projectIds.contains($0.id) }.map(\.name).joined(separator: ", ")) }
        var arrange: [String] = []
        if options.grouping != .status { arrange.append("Grouped by \(options.grouping.title.lowercased())") }
        if !options.sort.isManual { arrange.append("Sorted by \(options.sort.key.title.lowercased()) \(options.sort.ascending ? "↑" : "↓")") }
        if !arrange.isEmpty { lines.append(arrange.joined(separator: " · ")) }
        if lines.isEmpty { lines.append("No filters: every task") }
        return lines
    }

    @MainActor
    static func suggestedName(_ options: TaskViewOptions, store: TaskStore) -> String {
        let f = options.filter
        if f.labels.count == 1, let label = f.labels.first.flatMap({ store.label($0) }) { return label.name }
        if f.priorities == [.high] { return "High priority" }
        if f.due == [.overdue] { return "Overdue" }
        if f.due.contains(.thisWeek) { return "Due this week" }
        if !f.trimmedQuery.isEmpty { return f.trimmedQuery }
        if f.milestones.count == 1, let name = f.milestones.first.flatMap({ $0.flatMap { store.milestone($0)?.name } }) { return name }
        return ""
    }
}
