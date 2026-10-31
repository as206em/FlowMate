import Foundation

// The ⌘K palette: one fuzzy list over Today, projects, milestones, tasks of every project and
// commands. ↵ goes there (or runs the command), ⇧↵ opens the item's panel over the current view,
// a leading ">" lists commands only, and the empty palette shows recent picks.
// ⌘F stays the filter of the view on screen; ⌘K jumps anywhere.

/// A command the palette can run.
enum PaletteCommand: Hashable, Sendable {
    case newTask, newProject
    case newMilestone(UUID)
    case completeSprint(UUID)
    case showOverdue
    case groupBy(TaskGrouping)
    case switchTab(TasksViewModel.Tab)
    /// All projects › Overview, from anywhere
    case goToOverview
    /// List or hide a project's milestones in the sidebar
    case toggleMilestones(UUID)
    case toggleArchived
    case pauseAllTimers
    case openSettings
    case showShortcuts
    case focusSidebar
    /// The single-key actions on the selected tasks
    case quickAction(TaskQuickAction)
    case toggleDone
    case toggleToday
    case toggleTimer
    case duplicate
    case delete
    /// The Labels sheet
    case manageLabels
    /// Save what's on screen as a view (when the filters differ from the defaults)
    case saveView
    /// The saved view on screen: take the current filters, or go back to the saved ones
    case updateView, revertView
}

extension TasksViewModel {
    /// Opens Settings (AppState sets it; the window has no other way to reach it).
    static var openSettings: @MainActor () -> Void = {}

    // MARK: - Opening

    /// ⌘K: opens the palette on an empty query. The selection it was opened with is what its
    /// task commands act on.
    func openPalette(store: TaskStore) {
        paletteTargets = keyboardTargets(store)
        closeQuickPicker()
        sidebarCursor = nil
        paletteQuery = ""
        paletteHighlight = nil
        showingPalette = true
        defaults?.set(true, forKey: Self.paletteHintDismissedKey)
    }

    func closePalette() {
        showingPalette = false
        paletteQuery = ""
        paletteHighlight = nil
    }

    /// The "Press ⌘K to jump anywhere" hint is shown until it's dismissed or the palette is used.
    nonisolated static let paletteHintDismissedKey = "FlowMate.paletteHintDismissed"

    // MARK: - Results

    /// The palette's rows: recent picks when empty, else the best matches first. A leading ">"
    /// lists only commands.
    func paletteResults(_ store: TaskStore, limit: Int = 40) -> MenuSearchResultsModel {
        var query = paletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandsOnly = query.hasPrefix(">")
        if commandsOnly { query = String(query.dropFirst()).trimmingCharacters(in: .whitespaces) }
        let commands = paletteCommands(store)

        if query.isEmpty {
            if commandsOnly { return MenuSearchResultsModel(ranked: commands.map(MenuSearchItem.command)) }
            let recent = paletteRecents.compactMap { paletteItem(forKey: $0, store: store) }
            // Nothing picked yet: Today and the projects, then the commands for the selection
            let fallback: [MenuSearchItem] = [.today] + store.savedViews.map { .savedView($0.id) } + store.projects.map { .project($0.id) }
            let base = recent.isEmpty ? fallback : recent
            let suggested = commands.filter { if case .quickAction = $0 { return true }; return $0 == .newTask }
            return MenuSearchResultsModel(ranked: Array((base + suggested.map(MenuSearchItem.command)).prefix(limit)))
        }

        var scored: [(item: MenuSearchItem, score: Int)] = commandsOnly ? [] : store.paletteMatches(query)
        for command in commands {
            let names = [paletteTitle(command, store: store)] + paletteKeywords(command)
            guard let score = FuzzyMatch.score(query, in: names) else { continue }
            scored.append((.command(command), score))
        }
        let ranked = scored.enumerated()
            .sorted { a, b in
                if a.element.score != b.element.score { return a.element.score > b.element.score }
                let ka = Self.kindOrder(a.element.item), kb = Self.kindOrder(b.element.item)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element.item)
        return MenuSearchResultsModel(ranked: Array(ranked.prefix(limit)))
    }

    /// Ties go to places before commands before tasks.
    private static func kindOrder(_ item: MenuSearchItem) -> Int {
        switch item {
        case .today: return 0
        case .project: return 1
        case .savedView: return 2
        case .milestone: return 3
        case .label: return 4
        case .command: return 5
        case .task: return 6
        case .add: return 7
        }
    }

    /// The row ↵ runs: the one ↑/↓ moved to, else the first.
    func paletteCurrent(_ store: TaskStore) -> MenuSearchItem? {
        paletteResults(store).validated(paletteHighlight)
    }

    func movePaletteHighlight(_ offset: Int, store: TaskStore) {
        let results = paletteResults(store)
        paletteHighlight = results.moving(results.validated(paletteHighlight), by: offset)
    }

    /// The commands that make sense now: creating, the views of this scope, the timers, and the
    /// single-key actions when tasks are selected.
    func paletteCommands(_ store: TaskStore) -> [PaletteCommand] {
        var commands: [PaletteCommand] = [.newTask, .newProject]
        let projects = store.projects
        if let projectId = scope.projectId, store.project(projectId)?.isArchived == false {
            commands.append(.newMilestone(projectId))
        }
        commands += projects.filter { $0.id != scope.projectId }.map { .newMilestone($0.id) }
        let targets = paletteTargets.filter { store.task($0) != nil }
        if !targets.isEmpty {
            // "Move to sprint…" only when a target's project uses sprints
            let sprints = targets.contains { store.task($0).map { store.usesSprints($0.projectId) } ?? false }
            commands += TaskQuickAction.allCases
                .filter { ($0 != .project || projects.count > 1) && ($0 != .sprint || sprints) }
                .map(PaletteCommand.quickAction)
            commands += [.toggleDone, .toggleToday]
            if targets.count == 1 { commands.append(.toggleTimer) }
            commands += [.duplicate, .delete]
        }
        if store.hasRunningTimers { commands.append(.pauseAllTimers) }
        if !scope.isToday {
            commands.append(.showOverdue)
            commands += availableGroupings.filter { $0 != grouping || effectiveTab != .list }.map(PaletteCommand.groupBy)
        }
        if !(scope == .all && effectiveTab == .overview) { commands.append(.goToOverview) }
        // Overview has its own command ("Go to Overview"), which works from any scope
        commands += tabs.filter { ($0 != effectiveTab || scope.isToday) && $0 != .overview }.map(PaletteCommand.switchTab)
        if let projectId = scope.projectId, !scope.isMilestone, let project = store.project(projectId),
           !project.isArchived, project.usesSprints {
            commands.append(.completeSprint(projectId))
        }
        commands += projects.map { .toggleMilestones($0.id) }
        if !store.archivedProjects.isEmpty { commands.append(.toggleArchived) }
        if canSaveView { commands.append(.saveView) }
        if isViewModified(store) { commands += [.updateView, .revertView] }
        commands.append(.manageLabels)
        commands += [.focusSidebar, .showShortcuts, .openSettings]
        return commands
    }

    func paletteTitle(_ command: PaletteCommand, store: TaskStore) -> String {
        let count = paletteTargets.filter { store.task($0) != nil }.count
        let subject = count > 1 ? "\(count) tasks" : "task"
        func name(_ id: UUID) -> String { store.project(id)?.name ?? "project" }
        switch command {
        case .newTask: return "New task"
        case .newProject: return "New project"
        case let .newMilestone(id): return "New milestone in \(name(id))"
        case let .completeSprint(id): return "Complete \(store.sprintName(id)) of \(name(id))…"
        case .showOverdue: return "Show overdue tasks"
        case let .groupBy(grouping): return "Group by \(grouping.title.lowercased())"
        case let .switchTab(tab): return "Switch to \(tab.title)"
        case .goToOverview: return "Go to Overview"
        case let .toggleMilestones(id): return isProjectExpanded(id) ? "Hide milestones of \(name(id)) in the sidebar" : "Show milestones of \(name(id)) in the sidebar"
        case .toggleArchived: return showingArchived ? "Hide archived projects" : "Show archived projects"
        case .pauseAllTimers: return "Pause all timers"
        case .openSettings: return "Open settings"
        case .showShortcuts: return "Show keyboard shortcuts"
        case .focusSidebar: return "Move to the sidebar"
        case let .quickAction(action):
            switch action {
            case .project: return "Move \(subject) to project…"
            case .timeSpent: return "Adjust time spent…"
            default: return "Set \(action.title.lowercased()) of \(subject)…"
            }
        case .toggleDone: return "Mark \(subject) done, or reopen"
        case .toggleToday: return "Add \(subject) to Today, or remove"
        case .toggleTimer: return "Start or pause the timer"
        case .duplicate: return "Duplicate \(subject)"
        case .delete: return "Delete \(subject)"
        case .manageLabels: return "Manage labels…"
        case .saveView: return "Save view…"
        case .updateView: return "Update view \(activeView(store)?.name ?? "")"
        case .revertView: return "Revert view \(activeView(store)?.name ?? "")"
        }
    }

    /// Other words a command answers to
    private func paletteKeywords(_ command: PaletteCommand) -> [String] {
        switch command {
        case .newTask: return ["add task", "create"]
        case .newProject: return ["add project", "create"]
        case .newMilestone: return ["add milestone", "create"]
        case .completeSprint: return ["finish sprint", "close sprint"]
        case .showOverdue: return ["late", "filter"]
        case .groupBy: return ["grouping"]
        case let .switchTab(tab): return [tab.title, "view"]
        case .goToOverview: return ["portfolio", "all projects", "dashboard", "slipping"]
        case .toggleMilestones: return ["sidebar", "expand", "collapse"]
        case .toggleArchived: return ["sidebar", "archive"]
        case .pauseAllTimers: return ["stop timers"]
        case .openSettings: return ["preferences"]
        case .showShortcuts: return ["help", "keys"]
        case .focusSidebar: return ["sidebar"]
        case let .quickAction(action): return [action.title]
        case .toggleDone: return ["complete", "finish", "done"]
        case .toggleToday: return ["focus", "pin"]
        case .toggleTimer: return ["play", "track"]
        case .duplicate: return ["copy"]
        case .delete: return ["remove", "trash"]
        case .manageLabels: return ["labels", "tags", "rename label", "delete label"]
        case .saveView: return ["smart list", "save filter", "new view"]
        case .updateView: return ["save view", "smart list"]
        case .revertView: return ["reset view", "discard"]
        }
    }

    /// The command's keys, as key caps (shown on its row)
    func paletteKeys(_ command: PaletteCommand) -> [String] {
        switch command {
        case .newTask: return ["⌘", "N"]
        case .newProject: return ["⇧", "⌘", "N"]
        case let .switchTab(tab): return tabs.firstIndex(of: tab).map { ["⌘", "\($0 + 1)"] } ?? []
        case .goToOverview: return scope == .all ? ["⌘", "1"] : []
        case .pauseAllTimers: return ["⇧", "Space"]
        case .showShortcuts: return ["⌘", "/"]
        case .focusSidebar: return ["⌘", "0"]
        case let .quickAction(action): return action.keys
        case .toggleDone: return ["X"]
        case .toggleToday: return ["⌘", "T"]
        case .toggleTimer: return ["Space"]
        case .duplicate: return ["⌘", "D"]
        case .delete: return ["⌘", "⌫"]
        default: return []
        }
    }

    // MARK: - Running

    /// ↵ (go or run) or ⇧↵ (`inPanel`: open the item's panel without leaving the view on screen).
    func runPaletteItem(_ item: MenuSearchItem, inPanel: Bool = false, store: TaskStore) {
        closePalette()
        if let key = Self.paletteKey(item) { rememberPaletteItem(key) }
        switch item {
        case .add:
            break
        case .today:
            select(.today)
        case let .project(id):
            guard store.project(id) != nil else { return }
            if inPanel { openProject(id) } else { select(.project(id)) }
        case let .milestone(id):
            guard store.milestone(id) != nil else { return }
            if inPanel { openMilestone(id) } else { showMilestone(id, store: store) }
        case let .task(id):
            guard let task = store.task(id) else { return }
            if !inPanel, !store.tasks(in: scope).contains(where: { $0.id == id }) || scope.isToday {
                // Go to its project; Today keeps it on Today when it's listed there
                let onToday = scope.isToday && visibleTasks(store).contains { $0.id == id }
                if !onToday { select(.project(task.projectId)) }
            }
            openTask(id)
        case let .command(command):
            run(command, store: store)
        case let .label(id):
            showLabel(id, store: store)
        case let .savedView(id):
            applySavedView(id, store: store)
        }
    }

    func run(_ command: PaletteCommand, store: TaskStore) {
        switch command {
        case .newTask:
            startNewTask(store)
        case .newProject:
            requestFocus(.newProject)
        case let .newMilestone(projectId):
            guard store.project(projectId) != nil else { return }
            closePanel()
            expandedProjects.insert(projectId)
            requestFocus(.newMilestone(projectId))
        case let .completeSprint(projectId):
            completingSprintProjectId = projectId
        case .showOverdue:
            if scope.isToday { select(.all) }
            if !showsFilterBar { tab = .list }
            closePanel()
            var filter = self.filter
            filter.due = [.overdue]
            self.filter = filter
        case let .groupBy(grouping):
            if scope.isToday { select(.all) }
            tab = .list
            options.grouping = grouping
        case let .switchTab(tab):
            closePanel()
            self.tab = tab
        case .goToOverview:
            showOverview()
        case let .toggleMilestones(projectId):
            toggleProjectExpanded(projectId)
        case .toggleArchived:
            showingArchived.toggle()
        case .pauseAllTimers:
            let count = store.runningTasks.count
            store.pauseAllTimers()
            if count > 0 { show(Toast(message: count == 1 ? "Timer paused" : "\(count) timers paused")) }
        case .openSettings:
            Self.openSettings()
        case .showShortcuts:
            showingShortcuts = true
        case .focusSidebar:
            focusSidebar(store: store)
        case let .quickAction(action):
            openQuickPicker(action, store: store)
        case .toggleDone:
            toggleDone(store: store)
        case .toggleToday:
            let ids = todayTargets(store)
            if !ids.isEmpty { toggleToday(ids, store: store) }
        case .toggleTimer:
            if let id = targetTaskId(store) { store.toggleTimer(id) }
        case .duplicate:
            if isMultiSelecting, !isPanelOpen { duplicateSelected(store) } else if let id = targetTaskId(store) { duplicateTask(id, store: store) }
        case .delete:
            if isMultiSelecting, !isPanelOpen { deleteSelected(store) } else if let id = targetTaskId(store) { deleteTask(id, store: store) }
        case .manageLabels:
            showingLabelsManager = true
        case .saveView:
            if canSaveView { savingView = SaveViewRequest(kind: .new) }
        case .updateView:
            updateActiveView(store)
        case .revertView:
            revertActiveView(store)
        }
    }

    // MARK: - Recent picks

    /// How a pick is remembered; commands aren't (their meaning depends on the selection).
    static func paletteKey(_ item: MenuSearchItem) -> String? {
        switch item {
        case .today: return "today"
        case let .project(id): return "project:\(id.uuidString)"
        case let .milestone(id): return "milestone:\(id.uuidString)"
        case let .task(id): return "task:\(id.uuidString)"
        case let .label(id): return "label:\(id.uuidString)"
        case let .savedView(id): return "view:\(id.uuidString)"
        case .add, .command: return nil
        }
    }

    /// A remembered pick that still exists.
    func paletteItem(forKey key: String, store: TaskStore) -> MenuSearchItem? {
        if key == "today" { return .today }
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "project": return store.project(id) != nil ? .project(id) : nil
        case "milestone": return store.milestone(id) != nil ? .milestone(id) : nil
        case "task": return store.task(id) != nil ? .task(id) : nil
        case "label": return store.label(id) != nil ? .label(id) : nil
        case "view": return store.savedView(id) != nil ? .savedView(id) : nil
        default: return nil
        }
    }
}
