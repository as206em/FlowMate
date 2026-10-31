import AppKit
import SwiftUI

/// UI state for the main window: scope, tab, the open and selected task, filters and transient
/// drag/toast state. Data lives in TaskStore; this only holds what the window is showing.
@MainActor
final class TasksViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        /// All projects only: a card per project (TaskStore.portfolio)
        case overview
        case board, list, sprints, milestones

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .board: return "Board"
            case .list: return "List"
            case .sprints: return "Sprints"
            case .milestones: return "Milestones"
            }
        }
    }

    /// A text field a shortcut wants focused (⌘N, ⇧⌘N, ⌘F, the palette's New milestone). The id
    /// makes repeated requests distinct.
    struct FocusRequest: Equatable {
        enum Field: Equatable { case newTask, newProject, search, newMilestone(UUID) }
        let field: Field
        let id = UUID()
    }

    /// What a toast's Open button opens.
    enum OpenTarget: Equatable {
        /// The task panel
        case task(UUID)
        /// The project on screen
        case project(UUID)
        /// The milestone's page
        case milestone(UUID)
    }

    /// The bottom toast ("Task deleted · Undo").
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        /// The undo step the toast's Undo button reverts; nil hides the button.
        var undoId: UUID?
        /// What the toast's Open button opens ("Added to Atlas · Open"). Used when there's no Undo.
        var open: OpenTarget?

        init(message: String, undoId: UUID? = nil, openTaskId: UUID? = nil, open: OpenTarget? = nil) {
            self.message = message
            self.undoId = undoId
            self.open = open ?? openTaskId.map { .task($0) }
        }

        /// The task the Open button opens, if it opens a task.
        var openTaskId: UUID? {
            if case let .task(id)? = open { return id }
            return nil
        }
    }

    /// A project or milestone side panel (the task panel uses `openTaskId`). Only one panel is open at a time.
    enum DetailPanel: Equatable {
        case project(UUID)
        case milestone(UUID)
    }

    @Published var scope: TaskScope = .all {
        didSet { if scope != oldValue { saveWindowState() } }
    }
    /// The tab on screen. Each scope remembers its own (`tabByScope`), so a project opens on its last tab.
    @Published var tab: Tab = .board {
        didSet {
            tabByScope[scopeKey] = tab
            if tab != oldValue { saveWindowState() }
        }
    }
    /// The last tab used per scope ("all", a project id or "milestone-<id>").
    private(set) var tabByScope: [String: Tab] = [:]
    /// The task shown in the side panel, or nil when it's closed.
    @Published var openTaskId: UUID?
    /// The project or milestone shown in the side panel, or nil.
    @Published var openDetail: DetailPanel?
    /// The panel the open one was reached from (a milestone opened from its project panel); its
    /// header shows a Back button to it.
    @Published var panelBack: DetailPanel?
    /// Projects whose milestones are listed under them in the sidebar.
    @Published var expandedProjects: Set<UUID> = [] {
        didSet { if expandedProjects != oldValue { saveWindowState() } }
    }
    /// All projects › Overview: how the project cards are ordered.
    @Published var overviewSort: PortfolioSort = .attention {
        didSet { if overviewSort != oldValue { saveWindowState() } }
    }
    /// Milestones tab: a list of rows, or the roadmap timeline (one choice for every scope).
    @Published var milestonesLayout: MilestonesLayout = .list {
        didSet { if milestonesLayout != oldValue { saveWindowState() } }
    }
    /// The roadmap timeline's zoom.
    @Published var timelineZoom: TimelineZoom = .quarter {
        didSet { if timelineZoom != oldValue { saveWindowState() } }
    }
    /// The sidebar's Archived section is open.
    @Published var showingArchived = false
    /// "Complete sprint" dialog for this project
    @Published var completingSprintProjectId: UUID?
    /// The keyboard selection in List, Board and Sprints (↑/↓, ↵, Space, ⌘⌫, ⌘D): the focused task.
    /// Setting it directly selects only that task; ⌘-click and ⇧-click add to `selectedTaskIds`.
    @Published var selectedTaskId: UUID? {
        didSet {
            guard !adjustingSelection else { return }
            selectedTaskIds = selectedTaskId.map { [$0] } ?? []
            selectionAnchorId = selectedTaskId
        }
    }
    /// Every selected task (⌘-click, ⇧-click, ⌘A). Two or more show the bulk bar.
    @Published private(set) var selectedTaskIds: Set<UUID> = []
    /// "Adjust time…" sheet for this task (right-click menu)
    @Published var adjustingTimeTaskId: UUID?
    /// List/sprint groups toggled away from how they start, by key. Groups that start collapsed
    /// (done and canceled statuses, past sprints) are listed here once opened.
    @Published var collapsedGroups: Set<String> = [] {
        didSet { if collapsedGroups != oldValue { saveWindowState() } }
    }
    /// Filters, sort and grouping per scope ("all" or a project id), so each project keeps its own.
    @Published var optionsByScope: [String: TaskViewOptions] = [:] {
        didSet { if optionsByScope != oldValue { saveWindowState() } }
    }
    /// Drop target under the pointer, for the dashed outline ("status-todo", "slot-next", …).
    @Published var dropTarget: String?
    @Published var focusRequest: FocusRequest?
    /// The New task composer that's open (its group's key); nil when all show their ＋ button
    @Published var activeComposer: String? {
        didSet { if activeComposer != pinnedComposer { pinnedComposer = nil } }
    }
    /// The composer ⌘N opened at the top of its group (the first group or column of the view)
    /// instead of after its last task. Tasks added there go first. Back to the bottom once it closes.
    @Published private(set) var pinnedComposer: String?
    /// A task just added from the pinned composer: the view scrolls to it and highlights it briefly.
    @Published private(set) var flashTaskId: UUID?
    /// A task opened with ⇧↵ from the composer: its panel starts with the description being written.
    var describeTaskId: UUID?
    @Published var toast: Toast?
    /// The keyboard shortcuts popover (⌘/ or the ? button)
    @Published var showingShortcuts = false
    /// The single-key picker that's open (S, P, M, R, D, E, T, ⇧M), anchored to its row or the bulk bar
    @Published var quickPicker: QuickPickerRequest?
    /// ⌘0: the sidebar has the keyboard; this item has the focus ring (↑↓ move, ↵ shows it, Esc leaves)
    @Published var sidebarCursor: TaskScope?
    /// The ⌘K palette is open
    @Published var showingPalette = false
    @Published var paletteQuery = "" {
        didSet { if paletteQuery != oldValue { paletteHighlight = nil } }
    }
    /// The palette row ↑/↓ moved to; nil means its first row
    @Published var paletteHighlight: MenuSearchItem?
    /// The tasks a palette action applies to, kept from when the palette opened
    var paletteTargets: [UUID] = []
    /// Items picked from the palette, newest first ("project:<id>", "task:<id>", …)
    private(set) var paletteRecents: [String] = []

    /// Task being dragged. Set when a drag starts so drops don't need to decode the item provider.
    var draggingTaskId: UUID?
    /// Where ⇧-click ranges start: the last plainly or ⌘-clicked task.
    private(set) var selectionAnchorId: UUID?
    private var adjustingSelection = false

    /// Where the scope, tabs and filters are kept between launches (nil: not kept, as in tests).
    let defaults: UserDefaults?
    private let stateKey: String
    private var restoring = false

    nonisolated static let windowStateKey = "FlowMate.tasksWindowState"
    nonisolated static let paletteRecentsKey = "FlowMate.paletteRecents"

    /// Remembers a palette pick for the empty palette's Recent list (up to 8).
    func rememberPaletteItem(_ key: String) {
        paletteRecents.removeAll { $0 == key }
        paletteRecents.insert(key, at: 0)
        if paletteRecents.count > 8 { paletteRecents.removeLast(paletteRecents.count - 8) }
        defaults?.set(paletteRecents, forKey: Self.paletteRecentsKey)
    }

    /// - Parameter defaults: restores the last scope, the tab per scope and the filters per scope
    ///   from here, and saves them on every change. UI state only; the workspace file isn't touched.
    init(defaults: UserDefaults? = nil, stateKey: String = TasksViewModel.windowStateKey) {
        self.defaults = defaults
        self.stateKey = stateKey
        restoreWindowState()
        paletteRecents = defaults?.stringArray(forKey: Self.paletteRecentsKey) ?? []
    }

    /// Sprints only exists in project scope, and a milestone's page has only Board and List;
    /// fall back to List elsewhere.
    var effectiveTab: Tab { Self.tab(tab, in: scope) }

    var tabs: [Tab] { Self.tabs(in: scope) }

    static func tabs(in scope: TaskScope) -> [Tab] {
        switch scope {
        case .today: return []
        case .all: return [.overview, .board, .list, .milestones]
        case .project: return [.board, .list, .sprints, .milestones]
        case .milestone: return [.board, .list]
        }
    }

    /// The tab a scope can show for `tab` (List when it has no such tab).
    static func tab(_ tab: Tab, in scope: TaskScope) -> Tab {
        tabs(in: scope).contains(tab) ? tab : .list
    }

    /// The filter bar shows on List and Board (Today has neither).
    var showsFilterBar: Bool { !scope.isToday && (effectiveTab == .list || effectiveTab == .board) }

    /// Shows a scope on the tab it was last used with (its filters are kept per scope too).
    /// A scope never visited keeps the current tab.
    func select(_ scope: TaskScope) {
        // A milestone page opens on List the first time: it lists every task of the milestone
        let remembered = tabByScope[scope.key] ?? (scope.isMilestone ? .list : tab)
        self.scope = scope
        // Today has no tabs: the tab stays for the next scope
        if !scope.isToday { tab = Self.tab(remembered, in: scope) }
        selectedTaskId = nil
        sidebarCursor = nil
        if case let .milestone(_, projectId) = scope { expandedProjects.insert(projectId) }
        closePanel()
    }

    /// Shows a milestone's page: its tasks on Board and List, with its progress and time above.
    func showMilestone(_ id: UUID, store: TaskStore) {
        guard let scope = store.scope(ofMilestone: id) else { return }
        select(scope)
    }

    /// A click on a sidebar milestone: shows its page, or, when it's already on screen, opens its
    /// panel (like a second click on a project).
    func clickSidebarMilestone(_ id: UUID, store: TaskStore) {
        if scope.milestoneId == id, openDetail != .milestone(id) {
            openMilestone(id)
        } else {
            showMilestone(id, store: store)
        }
    }

    /// A click on a sidebar project: shows it, or, when it's already on screen, opens its panel
    /// (name, color, description, sprint, milestones, archive). The first click never hides the view.
    func clickSidebarProject(_ id: UUID) {
        if scope == .project(id), openDetail != .project(id) {
            openProject(id)
        } else {
            select(.project(id))
        }
    }

    /// Opens the task side panel. The hook every title and card calls. Also selects the task.
    /// Replaces a project or milestone panel.
    func openTask(_ id: UUID) {
        selectedTaskId = id
        panelBack = nil
        withAnimation(Focus.sheetAnimation) {
            openDetail = nil
            openTaskId = id
        }
    }

    /// Opens the project panel (settings, milestones, sprint, archive). Replaces any other panel.
    func openProject(_ id: UUID) {
        panelBack = nil
        withAnimation(Focus.sheetAnimation) {
            openTaskId = nil
            openDetail = .project(id)
        }
    }

    /// Opens the milestone panel (details, progress, its tasks). Replaces any other panel.
    /// `from` is the panel to go Back to (the project panel it was opened from).
    func openMilestone(_ id: UUID, from back: DetailPanel? = nil) {
        panelBack = back
        withAnimation(Focus.sheetAnimation) {
            openTaskId = nil
            openDetail = .milestone(id)
        }
    }

    /// Closes the task panel only (a project or milestone panel stays).
    func closeTask() {
        guard openTaskId != nil else { return }
        withAnimation(Focus.sheetAnimation) { openTaskId = nil }
    }

    /// Back to the panel this one was opened from.
    func goBack() {
        guard let back = panelBack else { return }
        panelBack = nil
        withAnimation(Focus.sheetAnimation) {
            openTaskId = nil
            openDetail = back
        }
    }

    /// Closes whichever side panel is open (×, Esc, scrim).
    func closePanel() {
        guard isPanelOpen else { return }
        panelBack = nil
        withAnimation(Focus.sheetAnimation) {
            openTaskId = nil
            openDetail = nil
        }
    }

    var isPanelOpen: Bool { openTaskId != nil || openDetail != nil }

    /// "Show tasks" in a milestone panel or menu: the milestone's page.
    func showTasks(ofMilestone milestone: Milestone) {
        select(.milestone(milestone.id, projectId: milestone.projectId))
    }

    /// All projects › Overview (⌘K "Go to Overview").
    func showOverview() {
        select(.all)
        tab = .overview
    }

    /// An Overview card's overdue count: the project's List showing only its overdue tasks.
    func showOverdueTasks(of projectId: UUID) {
        select(.project(projectId))
        tab = .list
        var filter = self.filter
        filter.due = [.overdue]
        self.filter = filter
    }

    /// Opens the project in the main view (Sprints tab) from a past-sprint link or the panel.
    func showSprints(of projectId: UUID) {
        select(.project(projectId))
        tab = .sprints
    }

    /// The sidebar's items top to bottom: Today, All projects, each project, and the milestones
    /// listed under the projects that show them (⌥⌘↑ / ⌥⌘↓ walk this order).
    func sidebarScopes(_ store: TaskStore) -> [TaskScope] {
        var result: [TaskScope] = [.today, .all]
        for project in store.projects {
            result.append(.project(project.id))
            if isProjectExpanded(project.id) {
                result += store.milestones(of: project.id).map { .milestone($0.id, projectId: project.id) }
            }
        }
        if showingArchived { result += store.archivedProjects.map { .project($0.id) } }
        return result
    }

    /// Selects the sidebar item `offset` rows from the one on screen. False at either end.
    @discardableResult
    func stepSidebar(_ offset: Int, store: TaskStore) -> Bool {
        let scopes = sidebarScopes(store)
        guard let index = scopes.firstIndex(of: scope) else {
            guard let first = scopes.first else { return false }
            select(first)
            return true
        }
        guard scopes.indices.contains(index + offset) else { return false }
        select(scopes[index + offset])
        return true
    }

    func isProjectExpanded(_ id: UUID) -> Bool { expandedProjects.contains(id) }

    func toggleProjectExpanded(_ id: UUID) {
        if expandedProjects.contains(id) { expandedProjects.remove(id) } else { expandedProjects.insert(id) }
    }

    /// A click on a row or card: selects it (⌘ adds or removes it, ⇧ selects the range from the last
    /// click) and ends typing in any field, so ↑/↓ and Space work next.
    func selectByClick(_ id: UUID, store: TaskStore, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        select(id, modifiers: modifiers, store: store)
        if let window = NSApp.keyWindow, window.firstResponder is NSTextView {
            window.makeFirstResponder(nil)
        }
    }

    /// A click on a title: opens the task, unless ⌘ or ⇧ is held, which selects instead.
    func clickTitle(_ id: UUID, store: TaskStore, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            selectByClick(id, store: store, modifiers: modifiers)
        } else {
            openTask(id)
        }
    }

    // MARK: - Multiple selection

    /// Selection logic for a click: plain selects one, ⌘ toggles, ⇧ selects the visible range from
    /// the anchor (adding to the selection when ⌘ is held too).
    func select(_ id: UUID, modifiers: NSEvent.ModifierFlags, store: TaskStore) {
        if modifiers.contains(.shift), let anchor = selectionAnchorId {
            let ids = visibleTasks(store).map(\.id)
            if let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: id) {
                let range = Set(ids[min(a, b)...max(a, b)])
                setSelection(modifiers.contains(.command) ? selectedTaskIds.union(range) : range, focus: id, anchor: anchor)
                return
            }
        }
        if modifiers.contains(.command) {
            var ids = selectedTaskIds
            if ids.contains(id) {
                ids.remove(id)
                setSelection(ids, focus: selectedTaskId == id ? visibleTasks(store).map(\.id).first(where: ids.contains) : selectedTaskId, anchor: id)
            } else {
                ids.insert(id)
                setSelection(ids, focus: id, anchor: id)
            }
            return
        }
        selectedTaskId = id
    }

    /// ⌘A: every task the view shows (open groups only).
    func selectAll(_ store: TaskStore) {
        let ids = visibleTasks(store).map(\.id)
        guard !ids.isEmpty else { return }
        setSelection(Set(ids), focus: selectedTaskId.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0], anchor: ids[0])
    }

    /// Selects these tasks (e.g. every overdue one) so the bulk bar can change them at once.
    func select(ids: [UUID]) {
        guard let first = ids.first else { return }
        setSelection(Set(ids), focus: first, anchor: first)
    }

    /// ⇧↑ / ⇧↓: grows or shrinks the selection from the anchor.
    func extendSelection(_ offset: Int, store: TaskStore) -> Bool {
        let ids = visibleTasks(store).map(\.id)
        guard let current = selectedTaskId, let index = ids.firstIndex(of: current) else {
            return moveSelection(offset, store: store) != nil
        }
        let next = ids[min(max(index + offset, 0), ids.count - 1)]
        let anchor = selectionAnchorId.flatMap { ids.contains($0) ? $0 : nil } ?? current
        guard let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: next) else { return false }
        setSelection(Set(ids[min(a, b)...max(a, b)]), focus: next, anchor: anchor)
        return true
    }

    func clearSelection() {
        selectedTaskId = nil
    }

    func isSelected(_ id: UUID) -> Bool { selectedTaskIds.contains(id) }

    /// Two or more tasks are selected: the bulk bar shows.
    var isMultiSelecting: Bool { selectedTaskIds.count > 1 }

    /// The selected tasks in on-screen order (then any not visible, e.g. hidden by a collapse).
    func selectedIds(_ store: TaskStore) -> [UUID] {
        let visible = visibleTasks(store).map(\.id).filter(selectedTaskIds.contains)
        let rest = selectedTaskIds.subtracting(visible).filter { store.task($0) != nil }.sorted { $0.uuidString < $1.uuidString }
        return visible + rest
    }

    private func setSelection(_ ids: Set<UUID>, focus: UUID?, anchor: UUID?) {
        adjustingSelection = true
        selectedTaskId = focus
        adjustingSelection = false
        selectedTaskIds = ids
        selectionAnchorId = anchor
    }

    /// Forgets selected tasks that no longer exist.
    func pruneSelection(_ store: TaskStore) {
        let alive = selectedTaskIds.filter { store.task($0) != nil }
        guard alive != selectedTaskIds else { return }
        let focus = selectedTaskId.flatMap { alive.contains($0) ? $0 : nil } ?? alive.first
        setSelection(alive, focus: focus, anchor: selectionAnchorId.flatMap { alive.contains($0) ? $0 : nil } ?? focus)
    }

    /// Past-sprint groups ("past-…") and groups of done or canceled statuses ("closed-…") start
    /// collapsed; the others start open.
    func isCollapsed(_ key: String) -> Bool {
        Self.startsCollapsed(key) ? !collapsedGroups.contains(key) : collapsedGroups.contains(key)
    }

    static func startsCollapsed(_ key: String) -> Bool { key.hasPrefix("past-") || key.hasPrefix("closed-") }

    static func pastSprintGroupKey(_ sprint: PastSprint) -> String { "past-\(sprint.id.uuidString)" }

    func toggleGroup(_ key: String) {
        if collapsedGroups.contains(key) {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    // MARK: - Filters, sort and grouping

    private var scopeKey: String { scope.key }

    static func scopeKey(_ scope: TaskScope) -> String { scope.key }

    /// The current scope's filters, sort and grouping.
    var options: TaskViewOptions {
        get { optionsByScope[scopeKey] ?? .standard }
        set { optionsByScope[scopeKey] = newValue == .standard ? nil : newValue }
    }

    var filter: TaskFilter {
        get { options.filter }
        set { options.filter = newValue }
    }

    var sort: TaskSort {
        get { options.sort }
        set { options.sort = newValue }
    }

    var grouping: TaskGrouping { options.effectiveGrouping(in: scope) }

    /// Resets search, chips, sort and grouping for this scope.
    func clearOptions() {
        options = .standard
    }

    // MARK: - What the views show

    /// List groups after filtering and sorting. Tasks of past (closed) sprints are hidden unless
    /// the Sprint filter asks for them.
    func listGroups(_ store: TaskStore, now: Date = Date()) -> [TaskGroup] {
        var tasks = store.filtered(store.tasks(in: scope), by: filter, now: now)
        if !filter.sprintSlots.contains(.closed) { tasks.removeAll { $0.sprintSlot == .closed } }
        return store.groups(store.sorted(tasks, by: sort), by: grouping, in: scope)
    }

    /// How many past-sprint tasks the List is hiding (for its caption).
    func hiddenClosedCount(_ store: TaskStore, now: Date = Date()) -> Int {
        guard !filter.sprintSlots.contains(.closed) else { return 0 }
        return store.filtered(store.tasks(in: scope), by: filter, now: now).filter { $0.sprintSlot == .closed }.count
    }

    /// Board columns: the project's statuses in workflow order, or in All projects (where
    /// workflows differ) the categories, with Canceled only while an active-sprint task is canceled.
    func boardColumns(_ store: TaskStore) -> [TaskGroupValue] {
        if let statuses = store.statuses(in: scope) { return statuses.map { .status($0) } }
        let active = store.tasks(in: scope).filter { $0.sprintSlot == .active }
        return store.categoryColumns(for: active).map { .category($0) }
    }

    /// One board column: active-sprint tasks with the status (or category), filtered and sorted.
    /// The Sprint chip doesn't apply here: Board always shows the active sprint.
    func boardTasks(_ store: TaskStore, column: TaskGroupValue, now: Date = Date()) -> [TaskItem] {
        var filter = self.filter
        filter.sprintSlots = []
        let tasks: [TaskItem]
        switch column {
        case let .status(status): tasks = store.boardTasks(in: scope, status: status)
        case let .category(category): tasks = store.boardTasks(in: scope, category: category)
        default: tasks = []
        }
        return store.sorted(store.filtered(tasks, by: filter, now: now), by: sort)
    }

    /// Every card on the board, column by column.
    func allBoardTasks(_ store: TaskStore, now: Date = Date()) -> [TaskItem] {
        boardColumns(store).flatMap { boardTasks(store, column: $0, now: now) }
    }

    /// Open tasks in the scope that Board leaves out because they sit in Next or Backlog
    /// (narrowed by the same chips as the board).
    func boardWaitingCount(_ store: TaskStore, now: Date = Date()) -> Int {
        var filter = self.filter
        filter.sprintSlots = []
        guard !scope.isMilestone else { return 0 }
        let waiting = store.tasks(in: scope).filter { ($0.sprintSlot == .next || $0.sprintSlot == .backlog) && !$0.isClosed }
        return store.filtered(waiting, by: filter, now: now).count
    }

    /// The line above Board: "Showing Sprint 4 · 12 more in Next and Backlog".
    /// nil while the board's empty state already explains it.
    func boardCaption(_ store: TaskStore, now: Date = Date()) -> String? {
        if case .sprintEmpty = boardEmptyReason(store, now: now) { return nil }
        // A milestone's board isn't limited to the sprint
        if scope.isMilestone { return nil }
        let sprint: String
        if let projectId = scope.projectId {
            sprint = store.sprintName(projectId)
        } else {
            sprint = "each project's active sprint"
        }
        guard !sprint.isEmpty else { return nil }
        let waiting = boardWaitingCount(store, now: now)
        guard waiting > 0 else { return "Showing \(sprint)" }
        return "Showing \(sprint) · \(waiting) more in Next and Backlog"
    }

    /// Why a whole List or Board shows nothing, so the view can say so and offer the next step.
    enum EmptyReason: Equatable {
        /// The scope has no tasks at all
        case noTasks
        /// Tasks exist but the search or filter chips hide every one
        case noMatches
        /// Board: nothing in the active sprint; `waiting` open tasks sit in Next and Backlog
        case sprintEmpty(waiting: Int)
    }

    /// nil while the List shows at least one task.
    func listEmptyReason(_ store: TaskStore, now: Date = Date()) -> EmptyReason? {
        guard listGroups(store, now: now).allSatisfy(\.tasks.isEmpty) else { return nil }
        if !filter.isEmpty { return .noMatches }
        return .noTasks
    }

    /// nil while any Board column has a card.
    func boardEmptyReason(_ store: TaskStore, now: Date = Date()) -> EmptyReason? {
        guard allBoardTasks(store, now: now).isEmpty else { return nil }
        var chips = filter
        chips.sprintSlots = []
        if !chips.isEmpty { return .noMatches }
        let all = store.tasks(in: scope)
        if all.isEmpty || scope.isMilestone { return .noTasks }
        return .sprintEmpty(waiting: all.filter { ($0.sprintSlot == .next || $0.sprintSlot == .backlog) && !$0.isClosed }.count)
    }

    /// Sprint view groups (manual order, no filters).
    static let sprintSlots: [SprintSlot] = [.active, .next, .backlog]

    static func sprintGroupKey(_ slot: SprintSlot) -> String { "slot-\(slot.rawValue)" }

    /// Every task the current view shows, top to bottom, skipping collapsed groups.
    /// ↑/↓ walk this order.
    func visibleTasks(_ store: TaskStore, now: Date = Date()) -> [TaskItem] {
        if scope.isToday {
            return Self.todaySections(store.todayPlan(now: now)).filter { !isCollapsed($0.key) }.flatMap(\.tasks)
        }
        switch effectiveTab {
        case .list:
            return listGroups(store, now: now).filter { !isCollapsed($0.id) }.flatMap(\.tasks)
        case .board:
            return allBoardTasks(store, now: now)
        case .sprints:
            guard let projectId = scope.projectId else { return [] }
            return Self.sprintSlots
                .filter { !isCollapsed(Self.sprintGroupKey($0)) }
                .flatMap { store.sprintTasks(projectId: projectId, slot: $0) }
        case .milestones, .overview:
            return []
        }
    }

    /// Moves the selection by `offset` rows. With nothing selected, ↓ picks the first row and ↑ the last.
    /// Returns the new selection.
    @discardableResult
    func moveSelection(_ offset: Int, store: TaskStore) -> UUID? {
        let ids = visibleTasks(store).map(\.id)
        guard !ids.isEmpty else { return nil }
        let next: UUID
        if let current = selectedTaskId, let index = ids.firstIndex(of: current) {
            next = ids[min(max(index + offset, 0), ids.count - 1)]
        } else {
            next = offset >= 0 ? ids[0] : ids[ids.count - 1]
        }
        selectedTaskId = next
        return next
    }

    /// The task a keyboard action applies to: the open one, else the selected one.
    /// None while a project or milestone panel is open, so ⌘⌫ never hits a task behind it.
    func targetTaskId(_ store: TaskStore) -> UUID? {
        guard openDetail == nil else { return nil }
        return [openTaskId, selectedTaskId].compactMap { $0 }.first { store.task($0) != nil }
    }

    // MARK: - Actions with feedback

    func requestFocus(_ field: FocusRequest.Field) {
        focusRequest = FocusRequest(field: field)
    }

    /// Deletes at once and offers Undo in a toast. The selection moves to the next row.
    func deleteTask(_ id: UUID, store: TaskStore) {
        guard store.task(id) != nil else { return }
        if selectedTaskId == id {
            let ids = visibleTasks(store).map(\.id)
            if let i = ids.firstIndex(of: id) {
                selectedTaskId = i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil)
            } else {
                selectedTaskId = nil
            }
        }
        if openTaskId == id { closeTask() }
        store.deleteTask(id)
        showUndoToast("Task deleted", store: store)
    }

    /// Duplicates the task, selects the copy and opens it if a panel was open.
    func duplicateTask(_ id: UUID, store: TaskStore) {
        guard let copy = store.duplicateTask(id) else { return }
        selectedTaskId = copy
        if openTaskId != nil { openTask(copy) }
        showUndoToast("Task duplicated", store: store)
    }

    func undo(_ store: TaskStore) {
        guard let name = store.undo() else { return }
        dropStaleIds(store)
        show(Toast(message: "Undid \(name.lowercased())"))
    }

    func redo(_ store: TaskStore) {
        guard let name = store.redo() else { return }
        dropStaleIds(store)
        show(Toast(message: "Redid \(name.lowercased())"))
    }

    /// A toast whose Undo reverts the store's newest step.
    func showUndoToast(_ message: String, store: TaskStore) {
        show(Toast(message: message, undoId: store.lastUndoId))
    }

    func show(_ toast: Toast) {
        withAnimation(Focus.menuAnimation) { self.toast = toast }
    }

    func dismissToast(_ id: UUID? = nil) {
        guard toast != nil, id == nil || toast?.id == id else { return }
        withAnimation(Focus.menuAnimation) { toast = nil }
    }

    /// The toast's Undo: only when its step is still the newest, so it never undoes something else.
    func undoFromToast(_ store: TaskStore) {
        guard let undoId = toast?.undoId, store.lastUndoId == undoId else {
            dismissToast()
            return
        }
        store.undo()
        dropStaleIds(store)
        dismissToast()
    }

    /// After undo/redo, forget a selection or open panel whose task, project or milestone is gone.
    func dropStaleIds(_ store: TaskStore) {
        pruneSelection(store)
        if let id = openTaskId, store.task(id) == nil { closeTask() }
        switch openDetail {
        case let .project(id) where store.project(id) == nil, let .milestone(id) where store.milestone(id) == nil:
            closePanel()
        default:
            break
        }
        if let id = scope.projectId, store.project(id) == nil {
            select(.all)
        } else if case let .milestone(id, projectId) = scope, store.milestone(id)?.projectId != projectId {
            // The milestone on screen was deleted: back to its project
            select(.project(projectId))
        }
        forgetDeletedScopes(store)
    }

    // MARK: - Restoring the window (scope, tab and filters per scope)

    /// What's kept between launches: the scope, the tab and filters per scope, collapsed groups and
    /// the sidebar projects showing their milestones. The search text isn't: it's for finding
    /// something now. Nor is an open panel: the window opens on the view, not on a dialog.
    struct WindowState: Codable, Equatable {
        var scope = "all"
        var tabs: [String: String] = [:]
        var options: [String: TaskViewOptions] = [:]
        /// nil: never saved (older state), so the defaults (Done collapsed) apply
        var collapsed: [String]?
        var expanded: [String] = []
        var overviewSort: PortfolioSort = .attention
        var milestonesLayout: MilestonesLayout = .list
        var timelineZoom: TimelineZoom = .quarter

        init(scope: String = "all", tabs: [String: String] = [:], options: [String: TaskViewOptions] = [:],
             collapsed: [String]? = nil, expanded: [String] = [], overviewSort: PortfolioSort = .attention,
             milestonesLayout: MilestonesLayout = .list, timelineZoom: TimelineZoom = .quarter) {
            self.scope = scope
            self.tabs = tabs
            self.options = options
            self.collapsed = collapsed
            self.expanded = expanded
            self.overviewSort = overviewSort
            self.milestonesLayout = milestonesLayout
            self.timelineZoom = timelineZoom
        }

        private enum CodingKeys: String, CodingKey {
            case scope, tabs, options, collapsed, expanded, overviewSort, milestonesLayout, timelineZoom
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scope = c.decode(.scope, or: "all")
            tabs = c.decode(.tabs, or: [:])
            collapsed = c.decodeOptional(.collapsed)
            expanded = c.decode(.expanded, or: [])
            overviewSort = c.decode(.overviewSort, or: .attention)
            milestonesLayout = c.decode(.milestonesLayout, or: .list)
            timelineZoom = c.decode(.timelineZoom, or: .quarter)
            // One broken entry doesn't lose the others
            let raw: [String: LossyOptions] = c.decode(.options, or: [:])
            options = raw.compactMapValues(\.value)
        }

        private struct LossyOptions: Decodable {
            let value: TaskViewOptions?
            init(from decoder: Decoder) throws { value = try? TaskViewOptions(from: decoder) }
        }
    }

    var windowState: WindowState {
        var options = optionsByScope
        for key in options.keys { options[key]?.filter.query = "" }
        return WindowState(
            scope: scope.storageKey,
            tabs: tabByScope.mapValues(\.rawValue),
            options: options.filter { $0.value != .standard },
            collapsed: collapsedGroups.sorted(),
            expanded: expandedProjects.map(\.uuidString).sorted(),
            overviewSort: overviewSort,
            milestonesLayout: milestonesLayout,
            timelineZoom: timelineZoom
        )
    }

    private func saveWindowState() {
        guard !restoring, let defaults else { return }
        guard let data = try? JSONEncoder().encode(windowState) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private func restoreWindowState() {
        guard let defaults, let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else { return }
        restoring = true
        defer { restoring = false }
        tabByScope = state.tabs.compactMapValues(Tab.init(rawValue:))
        optionsByScope = state.options
        if let collapsed = state.collapsed { collapsedGroups = Set(collapsed) }
        expandedProjects = Set(state.expanded.compactMap(UUID.init(uuidString:)))
        overviewSort = state.overviewSort
        milestonesLayout = state.milestonesLayout
        timelineZoom = state.timelineZoom
        let restoredScope = TaskScope(storageKey: state.scope) ?? .all
        scope = restoredScope
        let remembered = tabByScope[restoredScope.key] ?? (restoredScope.isMilestone ? .list : .board)
        tab = restoredScope.isToday ? (tabByScope[TaskScope.all.key] ?? .board) : Self.tab(remembered, in: restoredScope)
    }

    /// Drops remembered tabs and filters of projects that no longer exist (once data has loaded).
    private func forgetDeletedScopes(_ store: TaskStore) {
        guard store.isLoaded else { return }
        let alive = Set(store.allProjects.map(\.id.uuidString) + ["all", "today"]
                        + store.workspace.milestones.map { TaskScope.milestone($0.id, projectId: $0.projectId).key })
        let tabs = tabByScope.filter { alive.contains($0.key) }
        if tabs != tabByScope { tabByScope = tabs; saveWindowState() }
        let options = optionsByScope.filter { alive.contains($0.key) }
        if options != optionsByScope { optionsByScope = options }
        let expanded = expandedProjects.filter { alive.contains($0.uuidString) }
        if expanded != expandedProjects { expandedProjects = expanded }
    }

    // MARK: - Projects and milestones with feedback

    /// Archives and goes back to All projects if it was the one on screen; Undo brings it back.
    func archiveProject(_ id: UUID, store: TaskStore) {
        if scope.projectId == id { select(.all) }
        if openDetail == .project(id) { closePanel() }
        if let open = openTaskId, store.task(open)?.projectId == id { closeTask() }
        store.archiveProject(id)
        showUndoToast("Project archived", store: store)
    }

    /// Brings an archived project back to the sidebar's project list; Undo archives it again.
    func unarchiveProject(_ id: UUID, store: TaskStore) {
        guard store.isArchived(id) else { return }
        store.unarchiveProject(id)
        showUndoToast("Project unarchived", store: store)
    }

    func deleteProject(_ id: UUID, store: TaskStore) {
        if scope.projectId == id { select(.all) }
        if let open = openTaskId, store.task(open)?.projectId == id { closeTask() }
        if openDetail == .project(id) { closePanel() }
        if case let .milestone(mid) = openDetail, store.milestone(mid)?.projectId == id { closePanel() }
        store.deleteProject(id)
        showUndoToast("Project deleted", store: store)
    }

    /// "Clear sample data": removes the first-launch projects (one undo step) and goes back to All.
    func clearSampleData(_ store: TaskStore) {
        let ids = Set(store.sampleProjects.map(\.id))
        if let id = scope.projectId, ids.contains(id) { select(.all) }
        if let open = openTaskId, let task = store.task(open), ids.contains(task.projectId) { closeTask() }
        if case let .project(id) = openDetail, ids.contains(id) { closePanel() }
        if case let .milestone(id) = openDetail, let m = store.milestone(id), ids.contains(m.projectId) { closePanel() }
        guard store.clearSampleData() > 0 else { return }
        selectedTaskId = nil
        showUndoToast("Sample data cleared", store: store)
    }

    func deleteMilestone(_ id: UUID, store: TaskStore) {
        if openDetail == .milestone(id) { closePanel() }
        if case let .milestone(mid, projectId) = scope, mid == id { select(.project(projectId)) }
        store.deleteMilestone(id)
        showUndoToast("Milestone deleted", store: store)
    }

    func completeSprint(_ projectId: UUID, unfinished: UnfinishedSprintTasks, nextGoal: String, store: TaskStore) {
        guard let name = store.project(projectId)?.sprint.name else { return }
        store.completeSprint(projectId: projectId, unfinished: unfinished, nextGoal: nextGoal)
        showUndoToast("\(name) completed", store: store)
    }

    // MARK: - Stepping through tasks in the panel (⌘[ and ⌘])

    /// Where the open task sits in the current view: (index, count), or nil when it isn't shown there.
    func openTaskPosition(_ store: TaskStore) -> (index: Int, count: Int)? {
        guard let id = openTaskId else { return nil }
        let ids = visibleTasks(store).map(\.id)
        return ids.firstIndex(of: id).map { ($0, ids.count) }
    }

    /// Opens the previous (−1) or next (+1) task of the current view in the panel.
    /// Returns false at either end or when the open task isn't in the view.
    @discardableResult
    func stepOpenTask(_ offset: Int, store: TaskStore) -> Bool {
        guard let id = openTaskId else { return false }
        let ids = visibleTasks(store).map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return false }
        let next = ids[index + offset]
        selectedTaskId = next
        openTaskId = next
        return true
    }

    // MARK: - Bulk actions with feedback

    /// Runs a bulk edit on the selected tasks and shows "3 tasks moved to Done · Undo".
    func bulk(_ message: (Int) -> String, store: TaskStore, _ edit: ([UUID]) -> Void) {
        let ids = selectedIds(store)
        guard !ids.isEmpty else { return }
        let before = store.lastUndoId
        edit(ids)
        guard store.lastUndoId != before else { return }
        showUndoToast(message(ids.count), store: store)
    }

    /// Deletes the selected tasks at once (⌘⌫ or the bulk bar); Undo brings them back.
    func deleteSelected(_ store: TaskStore) {
        let ids = selectedIds(store)
        guard !ids.isEmpty else { return }
        if let open = openTaskId, ids.contains(open) { closeTask() }
        store.deleteTasks(ids)
        selectedTaskId = nil
        showUndoToast("\(TaskStore.taskCount(ids.count)) deleted", store: store)
    }

    func duplicateSelected(_ store: TaskStore) {
        let ids = selectedIds(store)
        let copies = store.duplicateTasks(ids)
        guard !copies.isEmpty else { return }
        select(ids: copies)
        showUndoToast("\(TaskStore.taskCount(copies.count)) duplicated", store: store)
    }

    /// Reschedules every overdue task the view shows (the Overdue chip's Reschedule menu).
    func rescheduleOverdue(to date: Date?, store: TaskStore, now: Date = Date()) {
        let shown: [TaskItem]
        switch effectiveTab {
        case .list: shown = listGroups(store, now: now).flatMap(\.tasks)
        case .board: shown = allBoardTasks(store, now: now)
        default: shown = visibleTasks(store, now: now)
        }
        let ids = shown.filter { store.isOverdue($0, now: now) }.map(\.id)
        guard !ids.isEmpty else { return }
        store.setDueDate(ids, date)
        let target = date.map { TaskDates.dueLabel($0, now: now) } ?? "no date"
        showUndoToast("\(TaskStore.taskCount(ids.count)) moved to \(target)", store: store)
    }

    // MARK: - Quick add

    /// The New task field: adds with tokens, selects the task, and says where it went with an Open
    /// button. `open` (⇧↵) opens the panel right away. Returns false when nothing was added.
    @discardableResult
    func quickAdd(_ text: String, projectId: UUID, milestoneId: UUID?, slot: SprintSlot,
                  open: Bool, store: TaskStore) -> Bool {
        guard let outcome = store.quickAddTask(text, projectId: projectId, milestoneId: milestoneId, sprintSlot: slot) else {
            return false
        }
        selectedTaskId = outcome.taskId
        if open {
            openTask(outcome.taskId)
            return true
        }
        let project = store.project(outcome.projectId)?.name ?? "project"
        var message = "Added to \(project)"
        if !outcome.applied.isEmpty { message += " · " + outcome.applied.joined(separator: " · ") }
        if let unmatched = outcome.unmatchedMilestone { message += " · no milestone \(unmatched)" }
        show(Toast(message: message, openTaskId: outcome.taskId))
        return true
    }

    func openFromToast(_ store: TaskStore) {
        guard let target = toast?.open else { return }
        dismissToast()
        open(target, store: store)
    }

    func open(_ target: OpenTarget, store: TaskStore) {
        switch target {
        case let .task(id): openTask(id)
        case let .project(id): select(.project(id))
        case let .milestone(id): showMilestone(id, store: store)
        }
    }

    /// Whether the toast's Open still has something to open.
    func canOpen(_ target: OpenTarget, store: TaskStore) -> Bool {
        switch target {
        case let .task(id): return store.task(id) != nil
        case let .project(id): return store.project(id) != nil
        case let .milestone(id): return store.milestone(id) != nil
        }
    }

    // MARK: - New projects and milestones

    /// The New project field. ↵ adds it and says so ("Added Atlas · Open"); ⇧↵ (`open`) adds it,
    /// shows it and opens its panel. Returns the new project, nil for a blank name.
    @discardableResult
    func addProject(_ name: String, open: Bool, store: TaskStore) -> UUID? {
        guard let id = store.addProject(name: name) else { return nil }
        if open {
            select(.project(id))
            openProject(id)
        } else {
            show(Toast(message: "Added \(store.project(id)?.name ?? "project")", open: .project(id)))
        }
        return id
    }

    /// The New milestone fields (sidebar, Milestones tab, project panel). ↵ adds it and says so
    /// ("Added Beta · Open"); ⇧↵ (`open`) adds it and shows its page.
    @discardableResult
    func addMilestone(_ name: String, projectId: UUID, open: Bool, store: TaskStore) -> UUID? {
        guard let id = store.addMilestone(projectId: projectId, name: name) else { return nil }
        if open {
            showMilestone(id, store: store)
        } else {
            show(Toast(message: "Added \(store.milestone(id)?.name ?? "milestone")", open: .milestone(id)))
        }
        return id
    }

    // MARK: - ⌘N: the composer at the top

    /// The composer ⌘N opens: the first group of the List (or the first column of the Board, the
    /// active sprint in Sprints). Its group is opened if it was collapsed.
    func defaultComposerKey(_ store: TaskStore) -> String? {
        // Today: the composer of My focus, whose tasks are pinned for today
        if scope.isToday { return Self.listComposerKey(Self.todayFocusKey) }
        switch effectiveTab {
        case .list:
            guard let group = listGroups(store).first(where: \.acceptsDrop) else { return nil }
            return Self.listComposerKey(group.id)
        case .board:
            return boardColumns(store).first.map { Self.boardComposerKey($0) }
        case .sprints:
            return scope.projectId == nil ? nil : Self.listComposerKey(Self.sprintGroupKey(.active))
        case .milestones, .overview:
            return nil
        }
    }

    static func listComposerKey(_ group: String) -> String { "composer-" + group }
    static func boardComposerKey(_ column: TaskGroupValue) -> String { "composer-board-\(column.key)" }

    /// ⌘N: opens the default composer pinned at the top of its group, so it's on screen however
    /// long the group is.
    func startNewTask(_ store: TaskStore) {
        closePanel()
        if effectiveTab == .milestones || effectiveTab == .overview, !scope.isToday { tab = .list }
        if let key = defaultComposerKey(store) {
            let group = String(key.dropFirst("composer-".count))
            if effectiveTab != .board, isCollapsed(group) { toggleGroup(group) }
            activeComposer = key
            pinnedComposer = key
        }
        requestFocus(.newTask)
    }

    /// Whether this group's composer sits at the top (⌘N) instead of after its tasks.
    func isComposerPinned(_ key: String) -> Bool { pinnedComposer == key }

    /// A task added from the pinned composer: scroll to it and highlight it for a moment.
    func flash(_ id: UUID) {
        flashTaskId = id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if self?.flashTaskId == id { self?.flashTaskId = nil }
        }
    }

    /// ⇧↵ in the composer: opens the new task with its description ready to write.
    func openNewTask(_ id: UUID) {
        describeTaskId = id
        openTask(id)
    }

    // MARK: - Subtasks

    func convertSubtask(_ subtaskId: UUID, of taskId: UUID, store: TaskStore) {
        guard let id = store.convertSubtaskToTask(taskId, subtaskId) else { return }
        show(Toast(message: "Converted to a task", undoId: store.lastUndoId, openTaskId: id))
    }
}
