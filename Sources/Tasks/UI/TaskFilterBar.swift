import SwiftUI

/// The bar under the header on List and Board: search (⌘F), filter chips, Group (List only),
/// Sort, Save view… and Clear. Settings are kept per project (TasksViewModel.optionsByScope).
/// On a saved view whose filters changed: "Modified · Update view · Revert".
struct TaskFilterBar: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @FocusState private var searchFocused: Bool
    @State private var openMenu: Menu?
    /// The bar's width; a narrow window shows Filter, Group and Sort without their labels
    @State private var width: CGFloat = 1000

    /// Narrow: icons for Filter, Group and Sort. A modified saved view's Update and Revert, or
    /// Save view…, need room on the right, so the bar goes compact sooner then.
    private var compact: Bool {
        if model.activeViewId != nil, model.isViewModified(store) { return width < 1200 }
        if model.canSaveView { return width < 1000 }
        return width < 900
    }

    /// Which popover is open
    private enum Menu: Hashable {
        case add, chip(Dimension), group, sort, reschedule
    }

    /// One filter dimension (a chip)
    enum Dimension: String, CaseIterable, Identifiable {
        case status, priority, milestone, sprint, due, label, project
        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: return "Status"
            case .priority: return "Priority"
            case .milestone: return "Milestone"
            case .sprint: return "Sprint"
            case .due: return "Due"
            case .label: return "Label"
            case .project: return "Project"
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            FocusSearchField(
                placeholder: "Search tasks",
                text: Binding(get: { model.filter.query }, set: { model.filter.query = $0 }),
                shortcutHint: "⌘F",
                focused: $searchFocused,
                onSubmit: {
                    // ↵ jumps to the results: leave the field and select the first match
                    searchFocused = false
                    model.selectedTaskId = nil
                    model.moveSelection(1, store: store)
                }
            )
            .frame(width: compact ? 160 : 210)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(activeDimensions) { dimension in
                        chip(dimension)
                    }
                    overdueChip
                    addFilterButton
                }
                .padding(.vertical, 1)
            }
            // Chips that don't fit scroll; the fade says there's more
            .mask(HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
            })

            Spacer(minLength: 8)

            if model.effectiveTab == .list {
                groupButton
            }
            sortButton
            if model.activeViewId != nil {
                SavedViewModifiedControls()
            } else {
                if model.canSaveView {
                    Button(compact ? "Save…" : "Save view…") { model.savingView = SaveViewRequest(kind: .new) }
                        .buttonStyle(.focus(.ghost))
                        .help("Keep these filters, sort and grouping as a view in the sidebar")
                }
                if model.options.isCustomized {
                    Button("Clear") { model.clearOptions() }
                        .buttonStyle(.focus(.ghost))
                        .help("Reset search, filters, sort and grouping")
                }
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 48)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { width = $0 }
        })
        .overlay(alignment: .bottom) { FocusDivider() }
        .onAppear(perform: takeFocusRequest)
        .onChange(of: model.focusRequest) { _ in takeFocusRequest() }
    }

    private func takeFocusRequest() {
        guard model.focusRequest?.field == .search else { return }
        model.focusRequest = nil
        DispatchQueue.main.async { searchFocused = true }
    }

    // MARK: - Chips

    /// Dimensions offered here: Sprint isn't on Board (it shows the active sprint) nor in a project
    /// without sprints, Project only in All projects, Milestone not on a milestone's page.
    private var dimensions: [Dimension] {
        Dimension.allCases.filter { dimension in
            switch dimension {
            case .sprint: return model.effectiveTab != .board && model.scopeUsesSprints
            case .project: return model.scope.projectId == nil && store.projects.count > 1
            // A milestone's page shows only its tasks
            case .milestone: return !model.scope.isMilestone
            case .label: return !store.workspace.labels.isEmpty || !model.filter.labels.isEmpty
            default: return true
            }
        }
    }

    private var activeDimensions: [Dimension] {
        dimensions.filter { isActive($0) }
    }

    private func isActive(_ dimension: Dimension) -> Bool {
        let f = model.filter
        switch dimension {
        case .status: return !f.statuses.isEmpty || !f.categories.isEmpty
        case .priority: return !f.priorities.isEmpty
        case .milestone: return !f.milestones.isEmpty
        case .sprint: return !f.sprintSlots.isEmpty
        case .due: return !f.due.isEmpty
        case .label: return !f.labels.isEmpty
        case .project: return !f.projectIds.isEmpty
        }
    }

    private func clear(_ dimension: Dimension) {
        switch dimension {
        case .status:
            model.filter.statuses = []
            model.filter.categories = []
        case .priority: model.filter.priorities = []
        case .milestone: model.filter.milestones = []
        case .sprint: model.filter.sprintSlots = []
        case .due: model.filter.due = []
        case .label: model.filter.labels = []
        case .project: model.filter.projectIds = []
        }
    }

    /// "To do, In progress" or "3 selected"
    private func summary(_ dimension: Dimension) -> String {
        let f = model.filter
        let names: [String]
        switch dimension {
        case .status:
            // The scope's workflow order; ids from another scope's state by any project's name
            let workflow = store.statuses(in: model.scope) ?? []
            let known = workflow.filter { f.statuses.contains($0.id) }.map(\.name)
            let others = f.statuses.subtracting(workflow.map(\.id)).compactMap { id in
                store.allProjects.lazy.compactMap { $0.status(id)?.name }.first
            }
            names = StatusCategory.ordered.filter(f.categories.contains).map(\.title) + known + Set(others).sorted()
        case .priority: names = TaskPriority.ordered.filter(f.priorities.contains).map(\.title)
        case .milestone:
            names = f.milestones.map { id in id.flatMap { store.milestone($0)?.name } ?? (id == nil ? "None" : "Deleted") }.sorted()
        case .sprint: names = Self.sprintChoices.filter { f.sprintSlots.contains($0.slot) }.map(\.title)
        case .due: names = TaskDueFilter.allCases.filter(f.due.contains).map(\.title)
        case .label: names = store.labels.filter { f.labels.contains($0.id) }.map(\.name)
        case .project: names = store.projects.filter { f.projectIds.contains($0.id) }.map(\.name)
        }
        return names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) selected"
    }

    private func chip(_ dimension: Dimension) -> some View {
        FocusFilterChip(
            title: dimension.title,
            value: summary(dimension),
            isActive: true,
            action: { openMenu = .chip(dimension) },
            clear: { clear(dimension) }
        )
        .popover(isPresented: binding(for: .chip(dimension)), arrowEdge: .bottom) {
            FocusPopoverMenu(width: 240, maxHeight: 420) {
                options(for: dimension, first: true)
            }
        }
    }

    /// "Overdue 4": one click filters to overdue tasks; then "Reschedule…" moves them all at once.
    @ViewBuilder
    private var overdueChip: some View {
        let overdue = overdueCount
        if model.filter.due == [.overdue] {
            if overdue > 0 {
                FocusFilterChip(title: "Reschedule \(overdue)…", systemImage: "calendar", action: { openMenu = .reschedule })
                    .popover(isPresented: binding(for: .reschedule), arrowEdge: .bottom) {
                        DateEditor(date: nil, allowsClear: false, set: { date in
                            model.rescheduleOverdue(to: date, store: store)
                        }, close: { openMenu = nil })
                    }
                    .help("Give every overdue task shown a new due date. ⌘A selects them for other changes.")
            }
        } else if model.filter.due.isEmpty, overdue > 0 {
            Button {
                model.filter.due = [.overdue]
            } label: {
                HStack(spacing: 6) {
                    Text("Overdue").foregroundColor(Focus.text2)
                    Text("\(overdue)").foregroundColor(Focus.risk).monospacedDigit()
                }
                .font(Focus.control)
                .padding(.horizontal, 10)
                .frame(height: Focus.controlHeight)
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.riskTint.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Show only overdue tasks")
            .accessibilityLabel("Overdue, \(overdue) tasks")
        }
    }

    /// Overdue tasks in this view (ignoring the Due filter itself).
    private var overdueCount: Int {
        var filter = model.filter
        filter.due = [.overdue]
        var tasks = store.tasks(in: model.scope)
        if model.effectiveTab == .board {
            filter.sprintSlots = []
            tasks = store.tasks(in: model.scope).filter { $0.sprintSlot == .active }
        } else if !filter.sprintSlots.contains(.closed) {
            tasks.removeAll { $0.sprintSlot == .closed }
        }
        return store.filtered(tasks, by: filter).count
    }

    private var addFilterButton: some View {
        FocusFilterChip(
            title: compact ? "" : (model.filter.chipCount == 0 ? "Filter" : "Add filter"),
            systemImage: "line.3.horizontal.decrease",
            action: { openMenu = .add }
        )
        .popover(isPresented: binding(for: .add), arrowEdge: .bottom) {
            FocusPopoverMenu(width: 240, maxHeight: 480) {
                ForEach(Array(dimensions.enumerated()), id: \.element) { index, dimension in
                    options(for: dimension, first: index == 0)
                }
            }
        }
        .help("Filter by status, priority, milestone, sprint, due date or label")
    }

    private func binding(for menu: Menu) -> Binding<Bool> {
        Binding(get: { openMenu == menu }, set: { if !$0, openMenu == menu { openMenu = nil } })
    }

    // MARK: - Filter options (multi-select; the menu stays open)

    private static let sprintChoices: [(slot: SprintSlot, title: String)] = [
        (.active, "Active sprint"), (.next, "Next sprint"), (.backlog, "Backlog"), (.closed, "Past sprints"),
    ]

    @ViewBuilder
    private func options(for dimension: Dimension, first: Bool) -> some View {
        FocusMenuSection(title: dimension.title, first: first)
        switch dimension {
        case .status:
            if let workflow = store.statuses(in: model.scope) {
                // A project: its own statuses
                ForEach(workflow) { status in
                    toggle(model.filter.statuses.contains(status.id)) { model.filter.statuses.formSymmetricDifference([status.id]) } label: {
                        WorkflowStatusIcon(status: status, size: 14)
                        Text(status.name).lineLimit(1)
                    }
                }
            } else {
                // All projects: workflows differ, so by category
                ForEach(StatusCategory.ordered) { category in
                    toggle(model.filter.categories.contains(category)) { model.filter.categories.formSymmetricDifference([category]) } label: {
                        FocusStatusIcon(kind: category.focusKind, size: 14)
                        Text(category.title)
                    }
                }
            }
        case .priority:
            ForEach(TaskPriority.ordered) { priority in
                toggle(model.filter.priorities.contains(priority)) { model.filter.priorities.formSymmetricDifference([priority]) } label: {
                    FocusPriorityBars(level: priority.focusLevel)
                    Text(priority.title)
                }
            }
        case .milestone:
            toggle(model.filter.milestones.contains(nil)) { model.filter.milestones.formSymmetricDifference([nil]) } label: {
                Text("No milestone").foregroundColor(Focus.text2)
            }
            ForEach(store.milestones(in: model.scope)) { milestone in
                toggle(model.filter.milestones.contains(milestone.id)) {
                    model.filter.milestones.formSymmetricDifference([milestone.id])
                } label: {
                    if model.scope.projectId == nil, let project = store.project(milestone.projectId) {
                        FocusProjectTile(project: project, size: 14)
                    }
                    Image(systemName: "diamond.fill").font(.system(size: 9)).foregroundColor(Color(hex: milestone.colorHex))
                    Text(milestone.name).lineLimit(1)
                }
            }
        case .sprint:
            ForEach(Self.sprintChoices, id: \.slot) { choice in
                toggle(model.filter.sprintSlots.contains(choice.slot)) {
                    model.filter.sprintSlots.formSymmetricDifference([choice.slot])
                } label: {
                    Text(choice.title)
                }
            }
        case .due:
            ForEach(TaskDueFilter.allCases) { due in
                toggle(model.filter.due.contains(due)) { model.filter.due.formSymmetricDifference([due]) } label: {
                    Text(due.title)
                    if due == .overdue {
                        let count = store.filtered(store.tasks(in: model.scope), by: overdueOnly).count
                        if count > 0 {
                            Text("\(count)").font(Focus.meta.monospacedDigit()).foregroundColor(Focus.risk)
                        }
                    }
                }
            }
        case .label:
            // Any of the chosen labels
            ForEach(store.labels) { label in
                toggle(model.filter.labels.contains(label.id)) { model.filter.labels.formSymmetricDifference([label.id]) } label: {
                    Circle().fill(Color(hex: label.colorHex)).frame(width: 8, height: 8).frame(width: 14)
                    Text(label.name).lineLimit(1)
                }
            }
            FocusMenuItem {
                openMenu = nil
                model.showingLabelsManager = true
            } label: {
                Text("Manage labels…").font(Focus.control).foregroundColor(Focus.text2)
            }
        case .project:
            ForEach(store.projects) { project in
                toggle(model.filter.projectIds.contains(project.id)) { model.filter.projectIds.formSymmetricDifference([project.id]) } label: {
                    FocusProjectTile(project: project, size: 14)
                    Text(project.name).lineLimit(1)
                }
            }
        }
    }

    private var overdueOnly: TaskFilter {
        var f = TaskFilter()
        f.due = [.overdue]
        return f
    }

    private func toggle<Label: View>(_ on: Bool, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) -> some View {
        FocusMenuItem(isSelected: on, action: action) {
            label().font(Focus.control).foregroundColor(Focus.text)
        }
    }

    // MARK: - Group and sort

    private var groupButton: some View {
        FocusFilterChip(title: compact ? "" : "Group:", value: model.grouping.title,
                        systemImage: compact ? "rectangle.3.group" : nil, action: { openMenu = .group })
            .popover(isPresented: binding(for: .group), arrowEdge: .bottom) {
                FocusPopoverMenu(width: 200) {
                    FocusMenuSection(title: "Group by", first: true)
                    ForEach(model.availableGroupings) { grouping in
                        FocusMenuItem(isSelected: grouping == model.grouping) {
                            model.options.grouping = grouping
                            openMenu = nil
                        } label: {
                            Text(grouping.title).font(Focus.control).foregroundColor(Focus.text)
                        }
                    }
                }
            }
            .help("Group the list. Drag a task to another group to change it.")
    }

    private var sortButton: some View {
        let sort = model.sort
        return FocusFilterChip(
            title: compact ? "" : "Sort:",
            value: sort.isManual ? "Manual" : "\(sort.key.title) \(sort.ascending ? "↑" : "↓")",
            systemImage: compact ? "arrow.up.arrow.down" : nil,
            action: { openMenu = .sort }
        )
        .popover(isPresented: binding(for: .sort), arrowEdge: .bottom) {
            FocusPopoverMenu(width: 200) {
                FocusMenuSection(title: "Sort by", first: true)
                let keys = TaskSortKey.menuChoices.contains(sort.key) ? TaskSortKey.menuChoices : TaskSortKey.menuChoices + [sort.key]
                ForEach(keys) { key in
                    FocusMenuItem(isSelected: key == sort.key) {
                        model.sort = key == sort.key ? sort : TaskSort(key: key)
                        openMenu = nil
                    } label: {
                        Text(key.title).font(Focus.control).foregroundColor(Focus.text)
                    }
                }
                if !sort.isManual {
                    FocusMenuSection(title: "Order")
                    FocusMenuItem(isSelected: sort.ascending) {
                        model.sort = TaskSort(key: sort.key, ascending: true)
                    } label: {
                        Text(Self.directionTitle(sort.key, ascending: true)).font(Focus.control).foregroundColor(Focus.text)
                    }
                    FocusMenuItem(isSelected: !sort.ascending) {
                        model.sort = TaskSort(key: sort.key, ascending: false)
                    } label: {
                        Text(Self.directionTitle(sort.key, ascending: false)).font(Focus.control).foregroundColor(Focus.text)
                    }
                }
            }
        }
        .help(model.effectiveTab == .board ? "Sort the cards in each column" : "Sort the rows in each group")
    }

    /// "Soonest first", "High to low", "Newest first", "A to Z"
    private static func directionTitle(_ key: TaskSortKey, ascending: Bool) -> String {
        switch key {
        case .priority: return ascending ? "Low to high" : "High to low"
        case .due: return ascending ? "Soonest first" : "Latest first"
        case .created, .updated: return ascending ? "Oldest first" : "Newest first"
        case .expected: return ascending ? "Shortest first" : "Longest first"
        default: return ascending ? "A to Z" : "Z to A"
        }
    }
}
