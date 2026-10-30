import Foundation

// Menu bar and first-run polish: sample data, the menu's project task lists and keyboard rows,
// and the quick-add preview shared by the menu and the floating New task box.

// MARK: - Sample data (first launch)

extension TaskStore {
    /// First-launch sample projects that still exist (archived ones included).
    var sampleProjects: [Project] {
        preferences.sampleProjectIds.compactMap { id in workspace.projects.first { $0.id == id } }
    }

    /// The "This is sample data · Clear sample data" banner shows while a sample project exists.
    var showsSampleDataBanner: Bool { !sampleProjects.isEmpty }

    /// Deletes the sample projects with their milestones, tasks and timers. One undo step.
    /// Returns how many projects were removed.
    @discardableResult
    func clearSampleData() -> Int {
        let ids = Set(sampleProjects.map(\.id))
        guard !ids.isEmpty else { return 0 }
        mutate("Clear sample data") { ws in
            let taskIds = Set(ws.tasks.filter { ids.contains($0.projectId) }.map(\.id))
            ws.projects.removeAll { ids.contains($0.id) }
            ws.milestones.removeAll { ids.contains($0.projectId) }
            ws.tasks.removeAll { ids.contains($0.projectId) }
            ws.runningTimers = ws.runningTimers.filter { !taskIds.contains($0.key) }
            ws.preferences.sampleProjectIds = []
            if let last = ws.preferences.lastProjectId, ids.contains(last) { ws.preferences.lastProjectId = nil }
        }
        return ids.count
    }

    /// "Keep it": the sample projects become ordinary projects and the banner goes away.
    func keepSampleData() {
        guard !preferences.sampleProjectIds.isEmpty else { return }
        mutate(recordsUndo: false) { $0.preferences.sampleProjectIds = [] }
    }
}

// MARK: - Menu bar projects and keyboard rows

/// A row in the menu bar dropdown (search empty) that ↑/↓ can highlight.
enum MenuRowItem: Hashable, Sendable {
    /// A task in the "N running" section at the top
    case running(UUID)
    case project(UUID)
    /// A task listed under its expanded project
    case task(UUID)

    var taskId: UUID? {
        switch self {
        case let .running(id), let .task(id): return id
        case .project: return nil
        }
    }

    var projectId: UUID? {
        if case let .project(id) = self { return id }
        return nil
    }
}

/// Which projects list their tasks in the menu. A running project is open unless you closed it;
/// any other project is closed unless you opened it.
struct MenuExpansion: Equatable {
    var opened: Set<UUID> = []
    var closed: Set<UUID> = []

    func isExpanded(_ id: UUID, running: Bool) -> Bool {
        running ? !closed.contains(id) : opened.contains(id)
    }

    mutating func set(_ id: UUID, expanded: Bool, running: Bool) {
        if expanded {
            closed.remove(id)
            if !running { opened.insert(id) }
        } else {
            opened.remove(id)
            if running { closed.insert(id) }
        }
    }

    mutating func toggle(_ id: UUID, running: Bool) {
        set(id, expanded: !isExpanded(id, running: running), running: running)
    }
}

/// The keyboard order of the menu rows and the highlight rules (↑/↓ clamp; nil starts at an end).
struct MenuBrowseModel: Equatable {
    var items: [MenuRowItem]

    func moving(_ highlight: MenuRowItem?, by offset: Int) -> MenuRowItem? {
        guard !items.isEmpty else { return nil }
        guard let highlight, let index = items.firstIndex(of: highlight) else {
            return offset >= 0 ? items.first : items.last
        }
        return items[min(max(index + offset, 0), items.count - 1)]
    }

    /// A highlight still in the list, else nil (the menu doesn't highlight anything until ↑/↓).
    func validated(_ highlight: MenuRowItem?) -> MenuRowItem? {
        guard let highlight, items.contains(highlight) else { return nil }
        return highlight
    }
}

extension TaskStore {
    /// The tasks a project lists when expanded in the menu, so you can pick which one its play
    /// button starts: running ones and the open tasks of the active sprint; when the sprint has
    /// none, the open tasks planned next and then the backlog.
    func menuProjectTasks(_ projectId: UUID) -> (tasks: [TaskItem], fromSprint: Bool) {
        let all = tasks(of: projectId)
        let sprint = all.filter { ($0.sprintSlot == .active && !$0.isDone) || isRunning($0.id) }
        if !sprint.isEmpty { return (sprint, true) }
        let later = all.filter { $0.sprintSlot == .next && !$0.isDone } + all.filter { $0.sprintSlot == .backlog && !$0.isDone }
        return (later, false)
    }

    /// Menu rows top to bottom, as ↑/↓ walk them: running timers, then each project followed by
    /// its tasks when expanded (up to `taskLimit`).
    func menuBrowseItems(expansion: MenuExpansion, taskLimit: Int = 8) -> MenuBrowseModel {
        var items = runningTasks.map { MenuRowItem.running($0.id) }
        for project in projects {
            items.append(.project(project.id))
            if expansion.isExpanded(project.id, running: isProjectRunning(project.id)) {
                items += menuProjectTasks(project.id).tasks.prefix(taskLimit).map { .task($0.id) }
            }
        }
        return MenuBrowseModel(items: items)
    }

    /// Where the menu's quick add goes: the last project used (remembered across launches),
    /// else the first project. Never depends on which timer happens to run.
    var menuQuickAddTarget: Project? { defaultProject }

    /// What a quick-add line will do, in words: ["High", "◆ Beta", "Due Fri", "1h 30m"].
    func quickAddPreview(_ text: String, projectId: UUID, now: Date = Date()) -> [String] {
        let input = QuickAddInput.parse(text, now: now)
        let milestone = input.milestoneQuery.map { matchMilestone($0, projectId: projectId)?.name ?? "No milestone “\($0)”" }
        return [input.priority?.title,
                milestone.map { "◆ " + $0 },
                input.dueDate.map { "Due " + TaskDates.dueLabel($0, now: now) },
                input.expectedMinutes.map { Focus.durationString(minutes: $0) }].compactMap { $0 }
    }
}
