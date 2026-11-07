import AppKit
import SwiftUI

/// UI state for the main window: scope, tab, the open and selected task, filters and transient
/// drag/toast state. Data lives in TaskStore; this only holds what the window is showing.
@MainActor
final class TasksViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        /// All projects only: a card per project (TaskStore.portfolio)
        case overview
        /// The tasks, grouped (Sprint grouping shows the sprint plan, see `showsSprintPlan`)
        case list

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .list: return "Tasks"
            }
        }
    }

    /// A text field a shortcut wants focused (⌘N, ⇧⌘N, ⌘F, the palette's New project). The id
    /// makes repeated requests distinct.
    struct FocusRequest: Equatable {
        enum Field: Equatable { case newTask, newProject, search }
        let field: Field
        let id = UUID()
    }

    /// What a toast's Open button opens.
    enum OpenTarget: Equatable {
        /// The task panel
        case task(UUID)
        /// The project on screen
        case project(UUID)
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

    /// A project side panel (the task panel uses `openTaskId`). Only one panel is open at a time.
    enum DetailPanel: Equatable {
        case project(UUID)
    }

    @Published var scope: TaskScope = .all {
        didSet {
            if scope != oldValue { saveWindowState() }
            // Next best starts closed every time Today opens
            if scope.isToday { collapsedGroups.remove(NextBestPanel.groupKey) }
        }
    }
    /// The saved view on screen (sidebar › Views), or nil. Its scope is `scope`; its filters,
    /// sort, grouping and tab are kept under its own key ("view-<id>"), so the project's own stay
    /// as they were. Any other sidebar item clears it.
    @Published var activeViewId: UUID? {
        didSet { if activeViewId != oldValue { saveWindowState() } }
    }
    /// The Labels sheet (add, rename, recolor, delete)
    @Published var showingLabelsManager = false
    /// The Task types sheet (Edit types… in the type field and the sprint menu)
    @Published var showingTypesManager = false
    /// The Save view sheet (new, or renaming one)
    @Published var savingView: SaveViewRequest?
    /// The tab on screen. Each scope remembers its own (`tabByScope`), so a project opens on its last tab.
    @Published var tab: Tab = .list {
        didSet {
            tabByScope[scopeKey] = tab
            if tab != oldValue { saveWindowState() }
        }
    }
    /// The last tab used per scope ("all" or a project id).
    private(set) var tabByScope: [String: Tab] = [:]
    /// The task shown in the side panel, or nil when it's closed.
    @Published var openTaskId: UUID?
    /// The project shown in the side panel, or nil.
    @Published var openDetail: DetailPanel?
    /// All projects › Overview: "3 projects · 1 needs attention", kept by the Overview as it draws
    /// its cards so the header doesn't build them again.
    @Published var overviewSummary = OverviewSummary()
    /// All projects › Overview: how the project cards are ordered.
    @Published var overviewSort: PortfolioSort = .attention {
        didSet { if overviewSort != oldValue { saveWindowState() } }
    }
    /// The sidebar's Archived section is open.
    @Published var showingArchived = false
    /// The "Complete sprint" dialog is open (it completes the workspace's sprint)
    @Published var completingSprint = false
    /// Today's Start next: tasks passed over with Skip, until the app quits
    @Published var skippedNextBest: Set<UUID> = []
    /// The keyboard selection in List and Sprints (↑/↓, ↵, Space, ⌘⌫, ⌘D): the focused task.
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
    /// Filters, sort and grouping per scope ("all" or a project id), so each project keeps its own
    /// filters and sort. The grouping of every project is one, kept under `projectsKey`.
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
    @Published var sidebarCursor: SidebarItem?
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

    /// Overview exists in All projects only; elsewhere the tasks show.
    var effectiveTab: Tab { Self.tab(tab, in: scope) }

    var tabs: [Tab] { Self.tabs(in: scope) }

    static func tabs(in scope: TaskScope) -> [Tab] {
        switch scope {
        case .today: return []
        case .all: return [.overview, .list]
        case .project: return [.list]
        }
    }

    /// The tab a scope can show for `tab` (the tasks when it has no such tab).
    static func tab(_ tab: Tab, in scope: TaskScope) -> Tab {
        tabs(in: scope).contains(tab) ? tab : .list
    }

    /// The tasks grouped by Sprint: the sprint plan (sprint card, active, next, later
    /// sprints, backlog and, in a project, past sprints) instead of plain groups.
    var showsSprintPlan: Bool { !scope.isToday && effectiveTab == .list && grouping == .sprint }

    /// In a project the sprint plan starts with the Backlog, open, and the sprints follow, closed
    /// (each screen opens with only its first group open, `openOnlyFirstGroup`).
    var sprintPlanBacklogFirst: Bool { scope.projectId != nil }

    // MARK: - Per-project settings the views follow

    /// Projects planned without sprints (Project.usesSprints off): no sprint plan, no sprint
    /// filter, grouping or column. Kept in step with the store by TasksRootView (`syncProjects`).
    @Published private(set) var sprintlessProjects: Set<UUID> = []

    /// Copies the per-project settings the view model needs from the store.
    func syncProjects(_ store: TaskStore) {
        let sprintless = Set(store.allProjects.filter { !$0.usesSprints }.map(\.id))
        if sprintless != sprintlessProjects { sprintlessProjects = sprintless }
        let anySprints = store.allProjects.isEmpty || store.allProjects.contains(where: \.usesSprints)
        if anySprints != anyProjectUsesSprints { anyProjectUsesSprints = anySprints }
    }

    /// At least one project takes part in the workspace's sprint (true with no projects).
    @Published private(set) var anyProjectUsesSprints = true

    /// The scope uses sprints: its project does, or in All projects, any project does.
    var scopeUsesSprints: Bool {
        guard let projectId = scope.projectId else { return anyProjectUsesSprints }
        return !sprintlessProjects.contains(projectId)
    }

    /// Groupings the filter bar and palette offer: no Sprint for a project without sprints.
    var availableGroupings: [TaskGrouping] {
        TaskGrouping.available(in: scope).filter { $0 != .sprint || scopeUsesSprints }
    }

    /// The filter bar shows with the tasks (Today has none).
    var showsFilterBar: Bool { !scope.isToday && effectiveTab == .list }

    /// Shows a scope on the tab it was last used with (its filters and grouping are kept per
    /// scope too). A scope never visited keeps the current tab.
    func select(_ scope: TaskScope) {
        let remembered = tabByScope[scope.key] ?? tab
        activeViewId = nil
        self.scope = scope
        // Today has no tabs: the tab stays for the next scope
        if !scope.isToday { tab = Self.tab(remembered, in: scope) }
        selectedTaskId = nil
        sidebarCursor = nil
        closePanel()
    }

    /// A click on a sidebar project: shows it, or, when it's already on screen, opens its panel
    /// (name, color, description, sprint, archive). The first click never hides the view.
    /// With any panel open (a task's too), the click just closes it.
    func clickSidebarProject(_ id: UUID) {
        if scope == .project(id), !isPanelOpen {
            openProject(id)
        } else {
            select(.project(id))
        }
    }

    /// Opens the task side panel. The hook every title and card calls. Also selects the task.
    /// Replaces a project panel.
    func openTask(_ id: UUID) {
        selectedTaskId = id
        withAnimation(Focus.sheetAnimation) {
            openDetail = nil
            openTaskId = id
        }
    }

    /// Opens the project panel (settings, sprint, archive). Replaces any other panel.
    func openProject(_ id: UUID) {
        withAnimation(Focus.sheetAnimation) {
            openTaskId = nil
            openDetail = .project(id)
        }
    }

    /// Closes the task panel only (a project panel stays).
    func closeTask() {
        guard openTaskId != nil else { return }
        withAnimation(Focus.sheetAnimation) { openTaskId = nil }
    }

    /// Closes whichever side panel is open (×, Esc, scrim).
    func closePanel() {
        guard isPanelOpen else { return }
        withAnimation(Focus.sheetAnimation) {
            openTaskId = nil
            openDetail = nil
        }
    }

    var isPanelOpen: Bool { openTaskId != nil || openDetail != nil }

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

    /// Shows the sprint plan (the tasks grouped by Sprint), of the project when given and of all
    /// projects otherwise (from a past-sprint link or the panel).
    func showSprints(of projectId: UUID? = nil) {
        select(projectId.map { .project($0) } ?? .all)
        tab = .list
        if scopeUsesSprints { options.grouping = .sprint }
    }

    /// The sidebar's items top to bottom: Today, All projects, the saved views and each project
    /// (⌥⌘↑ / ⌥⌘↓ walk this order).
    func sidebarScopes(_ store: TaskStore) -> [SidebarItem] {
        var result: [SidebarItem] = [.today, .all]
        result += store.savedViews.map { .view($0.id) }
        for project in store.projects {
            result.append(.project(project.id))
        }
        if showingArchived { result += store.archivedProjects.map { .project($0.id) } }
        return result
    }

    /// The sidebar item on screen: the saved view when one is, else the scope.
    var sidebarSelection: SidebarItem { activeViewId.map { .view($0) } ?? SidebarItem(scope) }

    /// Shows a sidebar item: a scope, or a saved view (its scope, tab and filters).
    func select(_ item: SidebarItem, store: TaskStore) {
        switch item {
        case let .view(id): applySavedView(id, store: store)
        default: if let scope = item.scope { select(scope) }
        }
    }

    /// Selects the sidebar item `offset` rows from the one on screen. False at either end.
    @discardableResult
    func stepSidebar(_ offset: Int, store: TaskStore) -> Bool {
        let items = sidebarScopes(store)
        guard let index = items.firstIndex(of: sidebarSelection) else {
            guard let first = items.first else { return false }
            select(first, store: store)
            return true
        }
        guard items.indices.contains(index + offset) else { return false }
        select(items[index + offset], store: store)
        return true
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
        keepSelected(selectedTaskIds.filter { store.task($0) != nil })
    }

    /// After a change, forgets selected tasks that left the screen (moved to another project or
    /// filtered out), so the bulk bar goes once nothing it acts on is shown. Tasks in collapsed
    /// groups and past sprints are still on screen. Tabs without task rows keep the selection.
    func pruneSelectionToView(_ store: TaskStore) {
        guard isMultiSelecting else { return }
        var shown: Set<UUID>
        if scope.isToday {
            shown = Set(visibleTasks(store, includingCollapsed: true).map(\.id))
        } else {
            switch effectiveTab {
            case .overview: return
            case .list:
                shown = Set(visibleTasks(store, includingCollapsed: true).map(\.id))
                if showsSprintPlan {
                    for sprint in store.pastSprints() { shown.formUnion(sprintPlanTasks(store.tasks(of: sprint, in: scope), store: store).map(\.id)) }
                }
            }
        }
        keepSelected(selectedTaskIds.filter { store.task($0) != nil && shown.contains($0) })
    }

    private func keepSelected(_ alive: Set<UUID>) {
        guard alive != selectedTaskIds else { return }
        let focus = selectedTaskId.flatMap { alive.contains($0) ? $0 : nil } ?? alive.first
        setSelection(alive, focus: focus, anchor: selectionAnchorId.flatMap { alive.contains($0) ? $0 : nil } ?? focus)
    }

    /// Past-sprint groups ("past-…") and groups of done or canceled statuses ("closed-…") start
    /// collapsed; the others start open.
    func isCollapsed(_ key: String) -> Bool {
        Self.startsCollapsed(key) ? !collapsedGroups.contains(key) : collapsedGroups.contains(key)
    }

    static func startsCollapsed(_ key: String) -> Bool {
        key.hasPrefix("past-") || key.hasPrefix("closed-") || key == NextBestPanel.groupKey
    }

    static func pastSprintGroupKey(_ sprint: PastSprint) -> String { "past-\(sprint.id.uuidString)" }

    /// The keys of the groups the current view can collapse (List, Sprints, Today); nil on the other tabs.
    func collapsibleGroupKeys(_ store: TaskStore) -> [String]? {
        if scope.isToday {
            let keys = Self.todaySections(store.todayPlan(), store: store).map(\.key)
            return store.nextBestCandidates().isEmpty ? keys : keys + [NextBestPanel.groupKey]
        }
        switch effectiveTab {
        case .list where showsSprintPlan:
            let upcoming = store.upcomingSprints().filter { $0.ahead > 1 }.map { Self.upcomingGroupKey($0.ahead) }
            if sprintPlanBacklogFirst {
                let past = store.pastSprints().map(Self.pastSprintGroupKey)
                return [Self.sprintGroupKey(.backlog), Self.sprintGroupKey(.active),
                        Self.sprintGroupKey(.next)] + upcoming + past
            }
            return Self.sprintSlots.map(Self.sprintGroupKey) + upcoming
        case .list:
            // The keys only: group without sorting
            let filter = appliedFilter
            var tasks = store.filtered(store.tasks(in: scope), by: filter)
            if !filter.sprintSlots.contains(.closed) { tasks.removeAll { $0.sprintSlot == .closed } }
            return store.groups(tasks, by: grouping, in: scope).map(\.id)
        case .overview:
            return nil
        }
    }

    /// Identifies the screen on show; it changes whenever a different one opens.
    var screenKey: String { "\(scope.key)|\(activeViewId?.uuidString ?? "")|\(effectiveTab.rawValue)" }

    /// A screen opens with its first group open and the rest closed.
    func openOnlyFirstGroup(_ store: TaskStore) {
        guard store.isLoaded, let keys = collapsibleGroupKeys(store), !keys.isEmpty else { return }
        for (index, key) in keys.enumerated() { setGroups([key], collapsed: index != 0) }
    }

    /// Collapses or expands these groups at once.
    func setGroups(_ keys: [String], collapsed: Bool) {
        for key in keys where isCollapsed(key) != collapsed { toggleGroup(key) }
    }

    func toggleGroup(_ key: String) {
        if collapsedGroups.contains(key) {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    // MARK: - Filters, sort and grouping

    /// Where the tab and options on screen are kept: the saved view's own key while one is on
    /// screen, else the scope's.
    private var scopeKey: String { activeViewId.map(Self.viewKey) ?? scope.key }

    static func viewKey(_ id: UUID) -> String { "view-\(id.uuidString)" }

    static func scopeKey(_ scope: TaskScope) -> String { scope.key }

    /// Where the grouping shared by every project is kept (its options hold only the grouping).
    static let projectsKey = "projects"

    /// A project on screen (not a saved view): its grouping is the one every project shares.
    private var sharesProjectGrouping: Bool { activeViewId == nil && scope.projectId != nil }

    /// The current scope's filters, sort and grouping. In a project the grouping is shared: changing
    /// it in one project changes it in all of them (not in All projects or saved views).
    var options: TaskViewOptions {
        get {
            var options = optionsByScope[scopeKey] ?? .standard
            if sharesProjectGrouping {
                options.grouping = optionsByScope[Self.projectsKey]?.grouping ?? TaskViewOptions.standard.grouping
            }
            return options
        }
        set {
            var newValue = newValue
            if sharesProjectGrouping {
                var shared = TaskViewOptions.standard
                shared.grouping = newValue.grouping
                optionsByScope[Self.projectsKey] = shared == .standard ? nil : shared
                newValue.grouping = TaskViewOptions.standard.grouping
            }
            optionsByScope[scopeKey] = newValue == .standard ? nil : newValue
        }
    }

    var filter: TaskFilter {
        get { options.filter }
        set { options.filter = newValue }
    }

    /// Each group keeps its own sort (click its column headers); not saved between launches.
    @Published private(set) var groupSorts: [String: TaskSort] = [:]

    func groupSort(_ group: String) -> TaskSort { groupSorts["\(scopeKey)|\(group)"] ?? .manual }

    func toggleGroupSort(_ key: TaskSortKey, group: String) {
        let id = "\(scopeKey)|\(group)"
        let next = (groupSorts[id] ?? .manual).toggled(key)
        groupSorts[id] = next.isManual ? nil : next
    }

    /// The group's tasks in its own sort.
    func sortedForGroup(_ tasks: [TaskItem], _ group: String, store: TaskStore) -> [TaskItem] {
        store.sorted(tasks, by: groupSort(group))
    }

    var sort: TaskSort {
        get { options.sort }
        set { options.sort = newValue }
    }

    /// The List's grouping (Status where Sprint isn't offered, in a project without sprints).
    var grouping: TaskGrouping {
        let grouping = options.effectiveGrouping(in: scope)
        return grouping == .sprint && !scopeUsesSprints ? .status : grouping
    }

    /// The filters that apply here: a project without sprints ignores a Sprint filter.
    private var appliedFilter: TaskFilter {
        var filter = self.filter
        if !scopeUsesSprints { filter.sprintSlots = [] }
        return filter
    }

    /// Resets search, chips, sort and grouping for this scope. A project keeps the grouping
    /// every project shares.
    func clearOptions() {
        var cleared = TaskViewOptions.standard
        if sharesProjectGrouping { cleared.grouping = options.grouping }
        options = cleared
    }

    // MARK: - What the views show

    /// List groups after filtering and sorting. Tasks of past (closed) sprints are hidden unless
    /// the Sprint filter asks for them.
    func listGroups(_ store: TaskStore, now: Date = Date()) -> [TaskGroup] {
        let filter = appliedFilter
        var tasks = store.filtered(store.tasks(in: scope), by: filter, now: now)
        if !filter.sprintSlots.contains(.closed) { tasks.removeAll { $0.sprintSlot == .closed } }
        return store.groups(store.sorted(tasks, by: .manual), by: grouping, in: scope).map { group in
            var group = group
            group.tasks = store.sorted(group.tasks, by: groupSort(group.id))
            return group
        }
    }

    /// How many past-sprint tasks the List is hiding (for its caption).
    func hiddenClosedCount(_ store: TaskStore, now: Date = Date()) -> Int {
        let filter = appliedFilter
        guard !filter.sprintSlots.contains(.closed) else { return 0 }
        return store.filtered(store.tasks(in: scope), by: filter, now: now).filter { $0.sprintSlot == .closed }.count
    }

    /// Why a whole List shows nothing, so the view can say so and offer the next step.
    enum EmptyReason: Equatable {
        /// The scope has no tasks at all
        case noTasks
        /// Tasks exist but the search or filter chips hide every one
        case noMatches
    }

    /// nil while the List shows at least one task.
    func listEmptyReason(_ store: TaskStore, now: Date = Date()) -> EmptyReason? {
        guard listGroups(store, now: now).allSatisfy(\.tasks.isEmpty) else { return nil }
        if !filter.isEmpty { return .noMatches }
        return .noTasks
    }

    /// The sprint plan's tasks of one group, narrowed by the search and filter chips.
    func sprintPlanTasks(_ tasks: [TaskItem], store: TaskStore) -> [TaskItem] {
        let filter = appliedFilter
        return filter.isEmpty ? tasks : store.filtered(tasks, by: filter)
    }

    /// The sprint plan's slot groups.
    static let sprintSlots: [SprintSlot] = [.active, .next, .backlog]

    static func sprintGroupKey(_ slot: SprintSlot) -> String { "slot-\(slot.rawValue)" }
    /// A sprint planned further ahead than the next one (ahead 2 or more)
    static func upcomingGroupKey(_ ahead: Int) -> String { "upcoming-\(ahead)" }

    /// The sprint plan's groups top to bottom, open ones only: active, next, later sprints, backlog
    /// (in a project the backlog comes first).
    func sprintGroupTasks(_ store: TaskStore, includingCollapsed: Bool = false) -> [[TaskItem]] {
        sprintGroups(store, includingCollapsed: includingCollapsed).map(\.tasks)
    }

    /// The sprint plan's groups with their keys (see `sprintGroupTasks`).
    func sprintGroups(_ store: TaskStore, includingCollapsed: Bool = false) -> [(key: String, tasks: [TaskItem])] {
        func group(_ key: String, _ tasks: [TaskItem]) -> (key: String, tasks: [TaskItem]) {
            (key, sortedForGroup(sprintPlanTasks(tasks, store: store), key, store: store))
        }
        let backlog = group(Self.sprintGroupKey(.backlog), store.sprintTasks(slot: .backlog, in: scope))
        var groups = sprintPlanBacklogFirst ? [backlog] : []
        groups.append(group(Self.sprintGroupKey(.active), store.sprintTasks(slot: .active, in: scope)))
        groups.append(group(Self.sprintGroupKey(.next), store.sprintTasks(slot: .next, in: scope)))
        for sprint in store.upcomingSprints() where sprint.ahead > 1 {
            groups.append(group(Self.upcomingGroupKey(sprint.ahead), store.sprintTasks(ahead: sprint.ahead, in: scope)))
        }
        if !sprintPlanBacklogFirst { groups.append(backlog) }
        return groups.filter { includingCollapsed || !isCollapsed($0.key) }
    }

    /// Every task the current view shows, top to bottom, skipping collapsed groups.
    /// ↑/↓ walk this order.
    /// `includingCollapsed`: the tasks of collapsed groups too (the ones still in the view).
    func visibleTasks(_ store: TaskStore, now: Date = Date(), includingCollapsed: Bool = false) -> [TaskItem] {
        if scope.isToday {
            return Self.todaySections(store.todayPlan(now: now), store: store).filter { includingCollapsed || !isCollapsed($0.key) }.flatMap(\.tasks)
        }
        switch effectiveTab {
        case .list where showsSprintPlan:
            return sprintGroupTasks(store, includingCollapsed: includingCollapsed).flatMap { $0 }
        case .list:
            // Grouped by label a task can be under several groups; ↑/↓ visit it once
            var seen = Set<UUID>()
            return listGroups(store, now: now).filter { includingCollapsed || !isCollapsed($0.id) }.flatMap(\.tasks).filter { seen.insert($0.id).inserted }
        case .overview:
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
    /// None while a project panel is open, so ⌘⌫ never hits a task behind it.
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

    /// After undo/redo, forget a selection or open panel whose task or project is gone.
    func dropStaleIds(_ store: TaskStore) {
        pruneSelection(store)
        if let id = openTaskId, store.task(id) == nil { closeTask() }
        switch openDetail {
        case let .project(id) where store.project(id) == nil:
            closePanel()
        default:
            break
        }
        if store.isLoaded, let id = activeViewId, store.savedView(id) == nil {
            // The view on screen was deleted (or undone away): its scope stays, with its own filters
            activeViewId = nil
        }
        if let id = scope.projectId, store.project(id) == nil {
            select(.all)
        }
        forgetDeletedScopes(store)
    }

    // MARK: - Restoring the window (scope, tab and filters per scope)

    /// What's kept between launches: the scope, the tab and filters per scope, collapsed groups. The search text isn't: it's for finding
    /// something now. Nor is an open panel: the window opens on the view, not on a dialog.
    struct WindowState: Codable, Equatable {
        var scope = "all"
        var tabs: [String: String] = [:]
        var options: [String: TaskViewOptions] = [:]
        /// nil: never saved (older state), so the defaults (Done collapsed) apply
        var collapsed: [String]?
        var overviewSort: PortfolioSort = .attention
        /// The saved view on screen, if one was
        var view: UUID?

        init(scope: String = "all", tabs: [String: String] = [:], options: [String: TaskViewOptions] = [:],
             collapsed: [String]? = nil, overviewSort: PortfolioSort = .attention,
             view: UUID? = nil) {
            self.scope = scope
            self.tabs = tabs
            self.options = options
            self.collapsed = collapsed
            self.overviewSort = overviewSort
            self.view = view
        }

        private enum CodingKeys: String, CodingKey {
            case scope, tabs, options, collapsed, overviewSort, view
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scope = c.decode(.scope, or: "all")
            tabs = c.decode(.tabs, or: [:])
            collapsed = c.decodeOptional(.collapsed)
            overviewSort = c.decode(.overviewSort, or: .attention)
            view = c.decodeOptional(.view)
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
            overviewSort: overviewSort,
            view: activeViewId
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
        if let collapsed = state.collapsed { collapsedGroups = Set(collapsed).subtracting([NextBestPanel.groupKey]) }
        overviewSort = state.overviewSort
        let restoredScope = TaskScope(storageKey: state.scope) ?? .all
        scope = restoredScope
        // A saved view comes back on its own tab and filters (checked against the data once loaded)
        if let view = state.view, !restoredScope.isToday { activeViewId = view }
        let remembered = tabByScope[scopeKey] ?? .list
        tab = restoredScope.isToday ? (tabByScope[TaskScope.all.key] ?? .list) : Self.tab(remembered, in: restoredScope)
    }

    /// Drops remembered tabs and filters of projects that no longer exist (once data has loaded).
    private func forgetDeletedScopes(_ store: TaskStore) {
        guard store.isLoaded else { return }
        let alive = Set(store.allProjects.map(\.id.uuidString) + ["all", "today", Self.projectsKey]
                        + store.savedViews.map { Self.viewKey($0.id) })
        let tabs = tabByScope.filter { alive.contains($0.key) }
        if tabs != tabByScope { tabByScope = tabs; saveWindowState() }
        let options = optionsByScope.filter { alive.contains($0.key) }
        if options != optionsByScope { optionsByScope = options }
    }

    // MARK: - Projects with feedback

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
        store.deleteProject(id)
        showUndoToast("Project deleted", store: store)
    }

    /// "Clear sample data": removes the first-launch projects (one undo step) and goes back to All.
    func clearSampleData(_ store: TaskStore) {
        let ids = Set(store.sampleProjects.map(\.id))
        if let id = scope.projectId, ids.contains(id) { select(.all) }
        if let open = openTaskId, let task = store.task(open), ids.contains(task.projectId) { closeTask() }
        if case let .project(id) = openDetail, ids.contains(id) { closePanel() }
        guard store.clearSampleData() > 0 else { return }
        selectedTaskId = nil
        showUndoToast("Sample data cleared", store: store)
    }

    func completeSprint(unfinished: UnfinishedSprintTasks, nextGoal: String, store: TaskStore) {
        let name = store.sprintName()
        store.completeSprint(unfinished: unfinished, nextGoal: nextGoal)
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
        shown = effectiveTab == .list && !showsSprintPlan ? listGroups(store, now: now).flatMap(\.tasks) : visibleTasks(store, now: now)
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
    func quickAdd(_ text: String, projectId: UUID, slot: SprintSlot? = nil,
                  open: Bool, store: TaskStore) -> Bool {
        guard let outcome = store.quickAddTask(text, projectId: projectId, sprintSlot: slot) else {
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
        }
    }

    /// Whether the toast's Open still has something to open.
    func canOpen(_ target: OpenTarget, store: TaskStore) -> Bool {
        switch target {
        case let .task(id): return store.task(id) != nil
        case let .project(id): return store.project(id) != nil
        }
    }

    // MARK: - New projects

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

    // MARK: - ⌘N: the composer at the top

    /// The composer ⌘N opens: the first group of the List (the active sprint in the sprint plan). Its group is opened if it was collapsed.
    func defaultComposerKey(_ store: TaskStore) -> String? {
        // Today: the composer of Today, whose tasks are pinned for today
        if scope.isToday { return Self.listComposerKey(Self.todayKey) }
        switch effectiveTab {
        case .list where showsSprintPlan:
            return Self.listComposerKey(Self.sprintGroupKey(sprintPlanBacklogFirst ? .backlog : .active))
        case .list:
            guard let group = listGroups(store).first(where: \.acceptsDrop) else { return nil }
            return Self.listComposerKey(group.id)
        case .overview:
            return nil
        }
    }

    static func listComposerKey(_ group: String) -> String { "composer-" + group }

    /// ⌘N: opens the default composer pinned at the top of its group, so it's on screen however
    /// long the group is.
    func startNewTask(_ store: TaskStore) {
        closePanel()
        if effectiveTab == .overview, !scope.isToday { tab = .list }
        if let key = defaultComposerKey(store) {
            let group = String(key.dropFirst("composer-".count))
            if isCollapsed(group) { toggleGroup(group) }
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

/// All projects › Overview in one line: how many projects, how many need attention.
struct OverviewSummary: Equatable {
    var count = 0
    var attention = 0
}
