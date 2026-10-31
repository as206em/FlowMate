import Foundation

/// A row in the menu bar search results (and the ⌘K palette) that ↑/↓ can highlight and ↵ activates.
enum MenuSearchItem: Hashable, Sendable {
    /// "Add “x” to Project". Only this row (or ⌘↵) creates a task.
    case add
    /// The Today page (palette)
    case today
    case project(UUID)
    /// Opens the milestone's page
    case milestone(UUID)
    case task(UUID)
    /// A command (palette)
    case command(PaletteCommand)
    /// A label (palette): All projects' List filtered to it
    case label(UUID)
    /// A saved view (palette): shows it
    case savedView(UUID)
}

/// The menu bar search results and the ⌘K palette's, in display order, and the keyboard
/// highlight rules both share.
struct MenuSearchResultsModel: Equatable {
    var canAdd: Bool
    var projects: [UUID]
    var milestones: [UUID] = []
    var tasks: [UUID]
    /// The palette's one list, best match first (with Today and commands mixed in). When set it is
    /// the display order instead of the grouped one.
    var ranked: [MenuSearchItem]?

    init(canAdd: Bool, projects: [UUID], milestones: [UUID] = [], tasks: [UUID]) {
        self.canAdd = canAdd
        self.projects = projects
        self.milestones = milestones
        self.tasks = tasks
    }

    /// The palette's list as ranked.
    init(ranked: [MenuSearchItem]) {
        self.init(canAdd: false, projects: [], tasks: [])
        self.ranked = ranked
        for item in ranked {
            switch item {
            case let .project(id): projects.append(id)
            case let .milestone(id): milestones.append(id)
            case let .task(id): tasks.append(id)
            case .add, .today, .command, .label, .savedView: break
            }
        }
    }

    /// Display order: the Add row, then projects, milestones, then tasks (or the palette's ranking)
    var items: [MenuSearchItem] {
        if let ranked { return ranked }
        return (canAdd ? [.add] : []) + projects.map(MenuSearchItem.project) + milestones.map(MenuSearchItem.milestone)
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

    /// The palette's places, scored against the typed text (FuzzyMatch): Today, projects
    /// (archived ones too, lower), milestones (open ones first), saved views, labels and tasks of every project (open
    /// ones first; a task needs a closer match than a place, so a short query isn't all tasks).
    func paletteMatches(_ query: String) -> [(item: MenuSearchItem, score: Int)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var matches: [(item: MenuSearchItem, score: Int)] = []
        if let score = FuzzyMatch.score(q, in: ["Today", "My focus", "Due today", "Overdue"]) {
            matches.append((.today, score + 5))
        }
        for project in allProjects {
            guard let score = FuzzyMatch.score(q, in: project.name) else { continue }
            matches.append((.project(project.id), score + (project.isArchived ? -60 : 4)))
        }
        let archived = Set(archivedProjects.map(\.id))
        for milestone in workspace.milestones where !archived.contains(milestone.projectId) {
            let projectName = self.project(milestone.projectId)?.name ?? ""
            guard let score = FuzzyMatch.score(q, in: [milestone.name, projectName + " " + milestone.name]) else { continue }
            matches.append((.milestone(milestone.id), score + (milestone.isCompleted ? -60 : 2)))
        }
        for view in savedViews {
            guard let score = FuzzyMatch.score(q, in: [view.name, "View " + view.name]) else { continue }
            matches.append((.savedView(view.id), score + 3))
        }
        for label in labels {
            guard let score = FuzzyMatch.score(q, in: [label.name, "%" + label.name, "Label " + label.name]) else { continue }
            matches.append((.label(label.id), score + 1))
        }
        for task in tasks(in: .all) {
            guard let score = FuzzyMatch.score(q, in: task.title), score >= 500 else { continue }
            matches.append((.task(task.id), score - (task.isClosed ? 80 : 0)))
        }
        return matches
    }
}
