import Foundation

// Menu bar and first-run polish: sample data, the menu's In progress list and keyboard rows,
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

// MARK: - Menu bar in-progress tasks and keyboard rows

/// A row in the menu bar dropdown (search empty) that ↑/↓ can highlight.
enum MenuRowItem: Hashable, Sendable {
    /// A task whose timer runs (tinted, with the live clock)
    case running(UUID)
    /// An In progress task whose timer is paused
    case task(UUID)

    var taskId: UUID {
        switch self {
        case let .running(id), let .task(id): return id
        }
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
    /// The menu's task list: every running task (earliest started first), then the other started
    /// tasks (any Started status) of all active projects, most recently changed first.
    var menuInProgressTasks: (running: [TaskItem], paused: [TaskItem]) {
        let running = runningTasks
        let activeProjects = Set(projects.map(\.id))
        let paused = workspace.tasks
            .filter { $0.statusCategory == .started && !isRunning($0.id) && activeProjects.contains($0.projectId) }
            .sorted { $0.updatedAt == $1.updatedAt ? $0.sortIndex < $1.sortIndex : $0.updatedAt > $1.updatedAt }
        return (running, paused)
    }

    /// Menu rows top to bottom, as ↑/↓ walk them: running timers, then the paused In progress tasks.
    func menuBrowseItems() -> MenuBrowseModel {
        let listed = menuInProgressTasks
        return MenuBrowseModel(items: listed.running.map { .running($0.id) } + listed.paused.map { .task($0.id) })
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
