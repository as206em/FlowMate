import Foundation

/// A row in the menu bar search results that ↑/↓ can highlight and ↵ activates.
enum MenuSearchItem: Hashable, Sendable {
    /// "Add “x” to Project". Only this row (or ⌘↵) creates a task.
    case add
    case project(UUID)
    /// Opens the milestone's page
    case milestone(UUID)
    case task(UUID)
}

/// The menu bar search results, in display order, and the keyboard highlight rules.
struct MenuSearchResultsModel: Equatable {
    var canAdd: Bool
    var projects: [UUID]
    var milestones: [UUID] = []
    var tasks: [UUID]

    init(canAdd: Bool, projects: [UUID], milestones: [UUID] = [], tasks: [UUID]) {
        self.canAdd = canAdd
        self.projects = projects
        self.milestones = milestones
        self.tasks = tasks
    }

    /// Display order: the Add row, then projects, milestones, then tasks
    var items: [MenuSearchItem] {
        (canAdd ? [.add] : []) + projects.map(MenuSearchItem.project) + milestones.map(MenuSearchItem.milestone)
            + tasks.map(MenuSearchItem.task)
    }

    /// What ↵ opens before the user moves: the first project or task. Never the Add row,
    /// so pressing Enter on a typo doesn't create a task. nil when nothing matches.
    var initialHighlight: MenuSearchItem? {
        items.first { $0 != .add }
    }

    /// ↑/↓: moves the highlight by `offset`, clamped to the list. From no highlight, ↓ starts at the top.
    func moving(_ highlight: MenuSearchItem?, by offset: Int) -> MenuSearchItem? {
        let items = self.items
        guard !items.isEmpty else { return nil }
        guard let highlight, let index = items.firstIndex(of: highlight) else {
            return offset >= 0 ? items.first : items.last
        }
        return items[min(max(index + offset, 0), items.count - 1)]
    }

    /// Keeps a highlight that is still in the list, otherwise falls back to the initial one.
    func validated(_ highlight: MenuSearchItem?) -> MenuSearchItem? {
        if let highlight, items.contains(highlight) { return highlight }
        return initialHighlight
    }
}

extension TaskStore {
    /// Results for the menu bar search: projects and milestones whose name matches (open
    /// milestones of active projects, up to `milestoneLimit`) and up to `taskLimit` tasks.
    func menuSearchResults(_ query: String, canAdd: Bool, taskLimit: Int = 6, milestoneLimit: Int = 4) -> MenuSearchResultsModel {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return MenuSearchResultsModel(canAdd: false, projects: [], tasks: []) }
        return MenuSearchResultsModel(
            canAdd: canAdd,
            projects: projects.filter { $0.name.localizedCaseInsensitiveContains(q) }.map(\.id),
            milestones: Array(milestones(in: .all)
                .filter { !$0.isCompleted && $0.name.localizedCaseInsensitiveContains(q) }
                .prefix(milestoneLimit).map(\.id)),
            tasks: searchTasks(q, limit: taskLimit).map(\.id)
        )
    }
}
