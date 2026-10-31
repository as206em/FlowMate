import Foundation

// Saved views and labels in the window: applying a view from the sidebar (scope, tab and its own
// filters), "Modified · Update view · Revert" once its filters change, Save view…, and the label
// actions that give feedback (toasts with Undo).

/// One item of the sidebar, top to bottom: Today, All projects, a saved view, a project or a
/// milestone listed under its project. ⌘0's cursor and ⌥⌘↑/↓ walk these.
enum SidebarItem: Hashable, Sendable {
    case today
    case all
    case view(UUID)
    case project(UUID)
    case milestone(UUID, projectId: UUID)

    init(_ scope: TaskScope) {
        switch scope {
        case .today: self = .today
        case .all: self = .all
        case let .project(id): self = .project(id)
        case let .milestone(id, projectId): self = .milestone(id, projectId: projectId)
        }
    }

    /// The scope it shows; nil for a saved view (its own scope comes from the view).
    var scope: TaskScope? {
        switch self {
        case .today: return .today
        case .all: return .all
        case .view: return nil
        case let .project(id): return .project(id)
        case let .milestone(id, projectId): return .milestone(id, projectId: projectId)
        }
    }
}

/// The Save view sheet: a new view from what's on screen, or renaming one.
struct SaveViewRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        case new
        case rename(UUID)
    }

    let id = UUID()
    let kind: Kind
}

extension TasksViewModel {
    // MARK: - Applying

    /// The saved view on screen, if it still exists.
    func activeView(_ store: TaskStore) -> SavedView? {
        activeViewId.flatMap { store.savedView($0) }
    }

    static func tab(_ layout: SavedView.Layout) -> Tab { layout == .board ? .board : .list }

    /// A click on a sidebar view: its scope, on its tab, with its filters, sort and grouping
    /// (fresh from the view each time, so a click also reverts unsaved changes).
    func applySavedView(_ id: UUID, store: TaskStore) {
        guard let view = store.savedView(id) else { return }
        select(view.scope)
        activeViewId = id
        optionsByScope[Self.viewKey(id)] = view.options == .standard ? nil : view.options
        tab = Self.tab(view.layout)
    }

    /// The tab on screen as a view layout (Board, else List).
    var currentLayout: SavedView.Layout { effectiveTab == .board ? .board : .list }

    /// The view on screen differs from what it saved (filters, sort, grouping or Board/List):
    /// the filter bar shows "Modified · Update view · Revert".
    func isViewModified(_ store: TaskStore) -> Bool {
        guard let view = activeView(store) else { return false }
        return options != view.options || currentLayout != view.layout
    }

    /// "Update view": the view takes the filters and tab on screen. One undo step.
    func updateActiveView(_ store: TaskStore) {
        guard let view = activeView(store), isViewModified(store) else { return }
        store.updateSavedView(view.id, layout: currentLayout, options: options)
        showUndoToast("Updated \(view.name)", store: store)
    }

    /// "Revert": back to what the view saved.
    func revertActiveView(_ store: TaskStore) {
        guard let view = activeView(store) else { return }
        options = view.options
        tab = Self.tab(view.layout)
    }

    /// Right-click › Update to current: the view takes the filters and tab on screen, whichever
    /// view (or scope) they belong to, keeping its own scope.
    func updateView(_ id: UUID, toCurrent store: TaskStore) {
        guard let view = store.savedView(id), showsFilterBar else { return }
        store.updateSavedView(id, layout: currentLayout, options: options)
        showUndoToast("Updated \(view.name)", store: store)
    }

    // MARK: - Saving

    /// "Save view…" is offered while the filters, sort or grouping differ from the defaults (and
    /// no saved view is on screen: that one has Update instead).
    var canSaveView: Bool {
        showsFilterBar && activeViewId == nil && options.isCustomized
    }

    /// Saves what's on screen as a new view and shows it (selected in the sidebar). nil for a blank name.
    @discardableResult
    func saveCurrentView(name: String, icon: String?, store: TaskStore) -> UUID? {
        guard showsFilterBar, !scope.isToday else { return nil }
        let options = self.options
        let layout = currentLayout
        guard let id = store.addSavedView(name: name, icon: icon, scope: scope, layout: layout, options: options) else { return nil }
        activeViewId = id
        optionsByScope[Self.viewKey(id)] = options == .standard ? nil : options
        tab = Self.tab(layout)
        show(Toast(message: "Saved view \(store.savedView(id)?.name ?? "")", undoId: store.lastUndoId))
        return id
    }

    /// An empty Views section's suggestion: makes it (All projects, List) and shows it.
    @discardableResult
    func addSuggestedView(_ suggestion: SavedViewSuggestion, store: TaskStore) -> UUID? {
        guard let id = store.addSavedView(name: suggestion.name, icon: suggestion.icon, scope: .all, layout: .list,
                                          options: suggestion.options) else { return nil }
        applySavedView(id, store: store)
        return id
    }

    func duplicateSavedView(_ id: UUID, store: TaskStore) {
        guard store.duplicateSavedView(id) != nil else { return }
        showUndoToast("View duplicated", store: store)
    }

    /// Deletes a view; the scope it showed stays on screen with its own filters. Undo brings it back.
    func deleteSavedView(_ id: UUID, store: TaskStore) {
        guard let view = store.savedView(id) else { return }
        if activeViewId == id {
            activeViewId = nil
            // The tab of the scope itself, as it was
            tab = Self.tab(tabByScope[scope.key] ?? tab, in: scope, sprints: scopeUsesSprints)
        }
        optionsByScope[Self.viewKey(id)] = nil
        store.deleteSavedView(id)
        showUndoToast("Deleted view \(view.name)", store: store)
    }

    // MARK: - Labels with feedback

    /// A picker toggle on tasks. With `toast` (several tasks), says what happened with Undo.
    func toggleLabel(_ labelId: UUID, on ids: [UUID], store: TaskStore, toast: Bool = false) {
        guard let label = store.label(labelId) else { return }
        let before = store.lastUndoId
        let added = store.toggleLabel(labelId, on: ids)
        guard toast, store.lastUndoId != before else { return }
        let subject = ids.count == 1 ? "task" : TaskStore.taskCount(ids.count)
        showUndoToast(added ? "Labeled \(subject) \(label.name)" : "Removed \(label.name) from \(subject)", store: store)
    }

    /// "Create label “x”" in a picker: makes it and adds it to the tasks.
    func createLabel(_ name: String, adding ids: [UUID], store: TaskStore, toast: Bool = false) {
        let before = store.lastUndoId
        guard let id = store.createLabel(name, adding: ids), toast, store.lastUndoId != before else { return }
        showUndoToast("Created label \(store.label(id)?.name ?? name)", store: store)
    }

    /// Deletes a label everywhere (tasks, filters, views); Undo brings it back on every task.
    func deleteLabel(_ id: UUID, store: TaskStore) {
        guard let label = store.label(id) else { return }
        let count = store.labelUsage()[id] ?? 0
        store.deleteLabel(id)
        for key in optionsByScope.keys { optionsByScope[key]?.filter.labels.remove(id) }
        showUndoToast(count > 0 ? "Deleted \(label.name) from \(TaskStore.taskCount(count))" : "Deleted label \(label.name)", store: store)
    }

    /// ⌘K on a label (or Show tasks in the Labels sheet): All projects' List with only that label.
    func showLabel(_ id: UUID, store: TaskStore) {
        guard store.label(id) != nil else { return }
        select(.all)
        tab = .list
        var filter = TaskFilter()
        filter.labels = [id]
        self.filter = filter
    }
}
