import Foundation

// Saved views ("smart lists"): the sidebar's Views section. Stored with the workspace, so they
// travel with the data; every change is an undo step like any other edit.
extension TaskStore {
    var savedViews: [SavedView] { workspace.savedViews }

    func savedView(_ id: UUID) -> SavedView? { workspace.savedViews.first { $0.id == id } }

    /// Adds a view at the end of the Views section. nil for a blank name.
    @discardableResult
    func addSavedView(name: String, icon: String? = nil, scope: TaskScope, layout: SavedView.Layout,
                      options: TaskViewOptions) -> UUID? {
        let name = SavedView.cleanName(name)
        guard !name.isEmpty else { return nil }
        let view = SavedView(name: name, icon: icon, scope: scope, layout: layout, options: options)
        mutate("Save view") { $0.savedViews.append(view) }
        return savedView(view.id)?.id
    }

    func renameSavedView(_ id: UUID, to name: String) {
        let name = SavedView.cleanName(name)
        guard !name.isEmpty else { return }
        editSavedView(id, "Rename view") { $0.name = name }
    }

    func setSavedViewIcon(_ id: UUID, _ icon: String?) {
        editSavedView(id, "Change view icon") { $0.icon = icon == SavedView.defaultIcon ? nil : icon }
    }

    /// "Update view" / "Update to current": the view keeps its scope and takes these settings.
    func updateSavedView(_ id: UUID, layout: SavedView.Layout, options: TaskViewOptions) {
        editSavedView(id, "Update view") {
            $0.layout = layout
            $0.options = options
        }
    }

    /// A copy right after the original ("Atlas bugs copy"). Returns its id.
    @discardableResult
    func duplicateSavedView(_ id: UUID) -> UUID? {
        guard let original = savedView(id) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = SavedView.cleanName(original.name + " copy")
        mutate("Duplicate view") { ws in
            let index = ws.savedViews.firstIndex { $0.id == id }.map { $0 + 1 } ?? ws.savedViews.count
            ws.savedViews.insert(copy, at: index)
        }
        return copy.id
    }

    func deleteSavedView(_ id: UUID) {
        mutate("Delete view") { $0.savedViews.removeAll { $0.id == id } }
    }

    /// Drag in the sidebar: puts the view before `before` (nil: last).
    func moveSavedView(_ id: UUID, before: UUID?) {
        guard id != before, let view = savedView(id) else { return }
        mutate("Move view") { ws in
            ws.savedViews.removeAll { $0.id == id }
            let index = before.flatMap { b in ws.savedViews.firstIndex { $0.id == b } } ?? ws.savedViews.count
            ws.savedViews.insert(view, at: index)
        }
    }

    private func editSavedView(_ id: UUID, _ action: String, _ change: (inout SavedView) -> Void) {
        mutate(action) { ws in
            guard let i = ws.savedViews.firstIndex(where: { $0.id == id }) else { return }
            change(&ws.savedViews[i])
        }
    }

    // MARK: - Counts

    /// The sidebar badge: the tasks the view's List shows (past sprints hidden unless the filter
    /// asks for them, as in List). Without a status filter only open tasks count, like a project's
    /// count; a view filtered by status counts every task it shows.
    func savedViewCount(_ view: SavedView, now: Date = Date()) -> Int {
        let scope = view.scope
        if let projectId = scope.projectId, project(projectId) == nil { return 0 }
        var filter = view.options.filter
        if let projectId = scope.projectId, !usesSprints(projectId) { filter.sprintSlots = [] }
        var shown = filtered(tasks(in: scope), by: filter, now: now)
        if !filter.sprintSlots.contains(.closed) { shown.removeAll { $0.sprintSlot == .closed } }
        if filter.statuses.isEmpty && filter.categories.isEmpty { shown.removeAll(where: \.isClosed) }
        return shown.count
    }

    /// Where a view looks, in words: "All projects", "Atlas", "Atlas › Beta".
    func savedViewPlace(_ view: SavedView) -> String {
        switch view.scope {
        case .today, .all: return "All projects"
        case let .project(id): return project(id)?.name ?? "Project"
        case let .milestone(id, projectId):
            return [project(projectId)?.name, milestone(id)?.name].compactMap { $0 }.joined(separator: " › ")
        }
    }
}
