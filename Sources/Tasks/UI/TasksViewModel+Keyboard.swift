import Foundation

// Single-key actions on the selection (Linear-style): S status, P priority, M milestone, R sprint,
// D due date, E expected time, T time spent, ⇧M project, X done, 1–3 priority, ⌥↑/⌥↓ order.
// The pickers' options and what choosing one does live here, so they're testable without views;
// QuickPicker.swift draws them anchored to the row, card, bulk bar or task panel.

/// What a single-key picker edits.
enum TaskQuickAction: String, CaseIterable, Identifiable, Sendable {
    case status, priority, milestone, sprint, due, expected, timeSpent, project

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .priority: return "Priority"
        case .milestone: return "Milestone"
        case .sprint: return "Sprint"
        case .due: return "Due date"
        case .expected: return "Expected time"
        case .timeSpent: return "Time spent"
        case .project: return "Move to project"
        }
    }

    /// The key that opens it, as key caps
    var keys: [String] {
        switch self {
        case .status: return ["S"]
        case .priority: return ["P"]
        case .milestone: return ["M"]
        case .sprint: return ["R"]
        case .due: return ["D"]
        case .expected: return ["E"]
        case .timeSpent: return ["T"]
        case .project: return ["⇧", "M"]
        }
    }

    /// "S", "⇧M": for tooltips
    var keyLabel: String { keys.joined() }

    var placeholder: String {
        switch self {
        case .status: return "Change status…"
        case .priority: return "Set priority…"
        case .milestone: return "Milestone, or a new one…"
        case .sprint: return "Move to sprint…"
        case .due: return "fri, nov 18, tomorrow, 3d…"
        case .expected: return "1h 30m, 45m, 2h…"
        case .timeSpent: return "1h 15m sets it, +15m or -5m adjusts…"
        case .project: return "Move to project…"
        }
    }

    /// The NSMenuItem key equivalent: a plain letter, or "M" (which reads as ⇧M)
    var menuKeyEquivalent: String {
        switch self {
        case .project: return "M"
        default: return keyLabel.lowercased()
        }
    }
}

/// A picker that's open: what it edits, on which tasks, and where it hangs.
struct QuickPickerRequest: Identifiable, Equatable {
    enum Anchor: Equatable {
        /// The task's row or card
        case task(UUID)
        /// The bulk bar (several selected)
        case bulk
        /// The task panel
        case panel
    }

    let id = UUID()
    let action: TaskQuickAction
    let taskIds: [UUID]
    let anchor: Anchor
}

/// What choosing a picker row does.
enum QuickPickValue: Equatable {
    case status(WorkflowStatus)
    /// Tasks of several workflows: each moves to the first status of the category in its project
    case category(StatusCategory)
    case priority(TaskPriority)
    case milestone(UUID?)
    case newMilestone(String)
    case slot(SprintSlot)
    case due(Date?)
    case expected(Int)
    case setSpent(TimeInterval)
    case adjustSpent(TimeInterval)
    case project(UUID)
}

/// One row of a single-key picker.
struct QuickPickOption: Identifiable, Equatable {
    enum Icon: Equatable {
        case none
        case status(WorkflowStatus)
        case category(StatusCategory)
        case priority(TaskPriority)
        case milestone(UInt32?)
        case project(name: String, colorHex: UInt32)
        case symbol(String)
    }

    let id: String
    let title: String
    var detail = ""
    /// Other words it answers to ("high" also finds "!1")
    var keywords: [String] = []
    /// The tasks' current value
    var isCurrent = false
    /// Read from the typed text ("fri" → Fri, Nov 6): shown first and never filtered out
    var isTyped = false
    var icon: Icon = .none
    let value: QuickPickValue
}

extension TasksViewModel {
    // MARK: - Targets

    /// The tasks a single-key action edits: the open task, else the selection (one or many).
    /// None while a project or milestone panel is open.
    func keyboardTargets(_ store: TaskStore) -> [UUID] {
        guard openDetail == nil else { return [] }
        if let open = openTaskId, store.task(open) != nil { return [open] }
        if isMultiSelecting { return selectedIds(store) }
        return selectedTaskId.flatMap { store.task($0) != nil ? [$0] : nil } ?? []
    }

    /// S, P, M, R, D, E, T, ⇧M: opens the picker on the targets, hanging from the row, the bulk bar
    /// or the task panel. False with nothing to edit (the key passes through).
    @discardableResult
    func openQuickPicker(_ action: TaskQuickAction, store: TaskStore) -> Bool {
        presentQuickPicker(action, ids: keyboardTargets(store), store: store)
    }

    /// Opens a picker on these tasks (the row menu's "Status…" uses it for the row it was opened on).
    @discardableResult
    func presentQuickPicker(_ action: TaskQuickAction, ids: [UUID], store: TaskStore) -> Bool {
        var ids = store.existing(ids)
        // Closed tasks of a past sprint stay where they are
        if action == .sprint { ids = ids.filter { store.task($0)?.sprintSlot != .closed } }
        guard !ids.isEmpty else { return false }
        if action == .project, store.projects.count < 2 { return false }
        let anchor: QuickPickerRequest.Anchor
        if let open = openTaskId, ids == [open] {
            anchor = .panel
        } else if ids.count > 1 {
            anchor = isMultiSelecting && !isPanelOpen ? .bulk : .task(ids[0])
        } else {
            anchor = .task(ids[0])
        }
        quickPicker = QuickPickerRequest(action: action, taskIds: ids, anchor: anchor)
        return true
    }

    func closeQuickPicker() {
        quickPicker = nil
    }

    // MARK: - Options

    /// The picker's rows for these tasks, filtered by the typed text (fuzzy), with a row read from
    /// the text itself first where the picker takes typed values (dates, durations, a new milestone).
    func quickPickOptions(_ action: TaskQuickAction, ids: [UUID], query: String, store: TaskStore,
                          now: Date = Date()) -> [QuickPickOption] {
        let tasks = store.existing(ids).compactMap { store.task($0) }
        guard !tasks.isEmpty else { return [] }
        let typed = Self.typedOptions(action, tasks: tasks, query: query, store: store, now: now)
        let base = Self.baseOptions(action, tasks: tasks, store: store, now: now)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return typed + base }
        let ranked = base.enumerated()
            .compactMap { index, option -> (Int, Int, QuickPickOption)? in
                guard let score = FuzzyMatch.score(q, in: [option.title] + option.keywords) else { return nil }
                return (score, index, option)
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .map(\.2)
        // A typed row that repeats a listed one (typing "tomorrow") gives way to it
        let filtered = typed.filter { row in !ranked.contains { $0.value == row.value } }
        return filtered + ranked
    }

    private static func baseOptions(_ action: TaskQuickAction, tasks: [TaskItem], store: TaskStore,
                                    now: Date) -> [QuickPickOption] {
        let ids = tasks.map(\.id)
        let commonProject = store.commonProjectId(ids)
        func all<T: Equatable>(_ value: (TaskItem) -> T, equal target: T) -> Bool { tasks.allSatisfy { value($0) == target } }
        switch action {
        case .status:
            var rows = store.commonStatuses(for: ids).map { status in
                QuickPickOption(id: "status-\(status.id)", title: status.name, detail: commonProject == nil ? "" : status.category.title,
                                keywords: [status.category.title], isCurrent: all({ $0.statusId }, equal: status.id),
                                icon: .status(status), value: .status(status))
            }
            if commonProject == nil {
                rows += StatusCategory.ordered.map { category in
                    QuickPickOption(id: "category-\(category.rawValue)", title: category.title, detail: "each project's first",
                                    isCurrent: all({ $0.statusCategory }, equal: category),
                                    icon: .category(category), value: .category(category))
                }
            }
            return rows
        case .priority:
            return TaskPriority.ordered.enumerated().map { index, priority in
                QuickPickOption(id: "priority-\(priority.rawValue)", title: priority.title, detail: "\(index + 1)",
                                keywords: ["\(index + 1)", "!\(priority.rawValue)"],
                                isCurrent: all({ $0.priority }, equal: priority), icon: .priority(priority), value: .priority(priority))
            }
        case .milestone:
            var rows = [QuickPickOption(id: "milestone-none", title: "No milestone", keywords: ["none", "clear"],
                                        isCurrent: all({ $0.milestoneId }, equal: nil), icon: .milestone(nil), value: .milestone(nil))]
            if let commonProject {
                let current = Set(tasks.compactMap(\.milestoneId))
                rows += store.milestones(of: commonProject).filter { !$0.isCompleted || current.contains($0.id) }.map { milestone in
                    QuickPickOption(id: "milestone-\(milestone.id)", title: milestone.name,
                                    detail: milestone.dueDate.map { SprintState.shortDate($0) } ?? "",
                                    isCurrent: all({ $0.milestoneId }, equal: milestone.id),
                                    icon: .milestone(milestone.colorHex), value: .milestone(milestone.id))
                }
            }
            return rows
        case .sprint:
            return SprintSlot.plannable.map { slot in
                let title = commonProject.map { store.sprintLabel(slot, projectId: $0) } ?? Self.slotTitle(slot)
                let words: [SprintSlot: [String]] = [.active: ["now", "active", "current"], .next: ["next"], .backlog: ["backlog", "later"]]
                return QuickPickOption(id: "slot-\(slot.rawValue)", title: title,
                                       detail: slot == .active ? "active" : slot == .next ? "next" : "",
                                       keywords: words[slot] ?? [], isCurrent: all({ $0.sprintSlot }, equal: slot),
                                       icon: .symbol("arrow.clockwise"), value: .slot(slot))
            }
        case .due:
            var rows = DuePreset.allCases.map { preset in
                let date = preset.date(now: now)
                return QuickPickOption(id: "due-\(preset.rawValue)", title: preset.title, detail: SprintState.shortDate(date),
                                       isCurrent: all({ $0.dueDate }, equal: date), icon: .symbol("calendar"), value: .due(date))
            }
            if tasks.contains(where: { $0.dueDate != nil }) {
                rows.append(QuickPickOption(id: "due-none", title: "No due date", keywords: ["clear", "none", "remove"],
                                            icon: .symbol("xmark"), value: .due(nil)))
            }
            return rows
        case .expected:
            return TaskItem.expectedChoices.map { minutes in
                QuickPickOption(id: "expected-\(minutes)", title: Focus.durationString(minutes: minutes),
                                isCurrent: all({ $0.expectedMinutes }, equal: minutes), icon: .symbol("clock"), value: .expected(minutes))
            }
        case .timeSpent:
            let steps: [Int] = [5, 15, 30, 60, -5, -15]
            return steps.map { minutes in
                let label = (minutes > 0 ? "+" : "−") + Focus.durationString(minutes: abs(minutes))
                return QuickPickOption(id: "spent-\(minutes)", title: label, detail: minutes > 0 ? "add" : "take off",
                                       icon: .symbol(minutes > 0 ? "plus" : "minus"), value: .adjustSpent(TimeInterval(minutes * 60)))
            } + [QuickPickOption(id: "spent-reset", title: "Reset to 0m", keywords: ["zero", "clear"],
                                 icon: .symbol("arrow.counterclockwise"), value: .setSpent(0))]
        case .project:
            return store.projects.map { project in
                QuickPickOption(id: "project-\(project.id)", title: project.name,
                                isCurrent: all({ $0.projectId }, equal: project.id),
                                icon: .project(name: project.name, colorHex: project.colorHex), value: .project(project.id))
            }
        }
    }

    /// A row read from the typed text: "fri" → Fri, Nov 6; "90m" → 1h 30m; "+15m" → add 15m;
    /// a milestone name that doesn't exist → New milestone “Beta”.
    private static func typedOptions(_ action: TaskQuickAction, tasks: [TaskItem], query: String, store: TaskStore,
                                     now: Date) -> [QuickPickOption] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        switch action {
        case .due:
            guard let date = TaskDateParser.parse(text, now: now) else { return [] }
            // "Tomorrow", "In 3 days": a relative label adds something; a plain date would repeat the title
            let relative = TaskDates.dueLabel(date, now: now)
            let detail = DateEditor.typedLabel(date).hasSuffix(relative) ? "" : relative
            return [QuickPickOption(id: "typed-due", title: DateEditor.typedLabel(date), detail: detail,
                                    isTyped: true, icon: .symbol("keyboard"), value: .due(date))]
        case .expected:
            guard let minutes = TaskDurationParser.minutes(text), minutes > 0 else { return [] }
            return [QuickPickOption(id: "typed-expected", title: Focus.durationString(minutes: minutes), detail: "expected",
                                    isTyped: true, icon: .symbol("keyboard"), value: .expected(minutes))]
        case .timeSpent:
            let sign = text.first.flatMap { "+-−".contains($0) ? $0 : nil }
            let amount = sign == nil ? text : String(text.dropFirst())
            guard let seconds = TaskDurationParser.seconds(amount) else { return [] }
            if let sign {
                guard seconds > 0 else { return [] }
                let minus = sign != "+"
                return [QuickPickOption(id: "typed-adjust", title: (minus ? "−" : "+") + TaskDurationParser.format(seconds: seconds),
                                        detail: minus ? "take off" : "add", isTyped: true, icon: .symbol("keyboard"),
                                        value: .adjustSpent(minus ? -seconds : seconds))]
            }
            return [QuickPickOption(id: "typed-spent", title: "Set to " + TaskDurationParser.format(seconds: seconds),
                                    detail: "time spent", isTyped: true, icon: .symbol("keyboard"), value: .setSpent(seconds))]
        case .milestone:
            guard let projectId = store.commonProjectId(tasks.map(\.id)),
                  !store.milestones(of: projectId).contains(where: { $0.name.compare(text, options: .caseInsensitive) == .orderedSame })
            else { return [] }
            return [QuickPickOption(id: "typed-milestone", title: "New milestone “\(text)”", isTyped: true,
                                    icon: .symbol("plus"), value: .newMilestone(text))]
        case .priority:
            // "1", "2", "3" pick the level directly
            guard let level = Int(text), let priority = TaskPriority.level(level) else { return [] }
            return [QuickPickOption(id: "typed-priority", title: priority.title, detail: "\(level)", isTyped: true,
                                    icon: .priority(priority), value: .priority(priority))]
        case .status, .sprint, .project:
            return []
        }
    }

    private static func slotTitle(_ slot: SprintSlot) -> String {
        switch slot {
        case .active: return "Active sprint"
        case .next: return "Next sprint"
        case .backlog, .closed: return "Backlog"
        }
    }

    // MARK: - Choosing

    /// Applies a picker row to the tasks: one undo step, with a toast that offers Undo.
    func applyQuickPick(_ value: QuickPickValue, ids: [UUID], store: TaskStore, now: Date = Date()) {
        let ids = store.existing(ids)
        guard !ids.isEmpty else { return }
        let n = ids.count
        let subject = n == 1 ? "Task" : TaskStore.taskCount(n)
        switch value {
        case let .status(status):
            edit("\(subject) moved to \(status.name)", store: store) { store.setStatus(ids, status, now: now) }
        case let .category(category):
            edit("\(subject) moved to \(category.title.lowercased())", store: store) { store.setCategory(ids, category, now: now) }
        case let .priority(priority):
            edit(n == 1 ? "Priority set to \(priority.title.lowercased())" : "\(subject) set to \(priority.title.lowercased()) priority",
                 store: store) { store.setPriority(ids, priority) }
        case let .milestone(id):
            let name = id.flatMap { store.milestone($0)?.name }
            edit(name.map { "\(subject) added to \($0)" } ?? "Milestone cleared on \(TaskStore.taskCount(n))", store: store) {
                store.setMilestone(ids, id)
            }
        case let .newMilestone(name):
            guard let projectId = store.commonProjectId(ids) else { return }
            edit("\(subject) added to new milestone \(name)", store: store) {
                store.undoGroup("Add milestone") {
                    if let milestone = store.addMilestone(projectId: projectId, name: name) {
                        store.setMilestone(ids, milestone)
                    }
                }
            }
        case let .slot(slot):
            let title = store.commonProjectId(ids).map { store.sprintLabel(slot, projectId: $0) } ?? Self.slotTitle(slot)
            edit("\(subject) moved to \(title)", store: store) { store.setSprintSlot(ids, slot) }
        case let .due(date):
            edit(date.map { "\(subject) due \(TaskDates.dueLabel($0, now: now))" } ?? "Due date cleared on \(TaskStore.taskCount(n))",
                 store: store) { store.setDueDate(ids, date) }
        case let .expected(minutes):
            edit("\(subject) expected \(Focus.durationString(minutes: minutes))", store: store) {
                store.setExpectedMinutes(ids, minutes)
            }
        case let .setSpent(seconds):
            edit("Time spent set to \(TaskDurationParser.format(seconds: seconds))" + (n == 1 ? "" : " on \(TaskStore.taskCount(n))"),
                 store: store) { store.setTimeSpent(ids, seconds: seconds, now: now) }
        case let .adjustSpent(seconds):
            let amount = TaskDurationParser.format(seconds: abs(seconds))
            edit(seconds >= 0 ? "\(amount) added" : "\(amount) taken off", store: store) {
                store.adjustTimeSpent(ids, by: seconds, now: now)
            }
        case let .project(projectId):
            let name = store.project(projectId)?.name ?? "project"
            edit("\(subject) moved to \(name)", store: store) { store.setProject(ids, projectId) }
        }
    }

    /// Runs an edit; when it made an undo step, says so in a toast with Undo.
    func edit(_ message: String, store: TaskStore, _ change: () -> Void) {
        let before = store.lastUndoId
        change()
        guard store.lastUndoId != before else { return }
        showUndoToast(message, store: store)
    }

    // MARK: - X, 1–3

    /// X: done, or back to the first Not started status when all are done already.
    @discardableResult
    func toggleDone(store: TaskStore, now: Date = Date()) -> Bool {
        let ids = keyboardTargets(store)
        guard !ids.isEmpty else { return false }
        let subject = ids.count == 1 ? "Task" : TaskStore.taskCount(ids.count)
        let before = store.lastUndoId
        let done = store.toggleDone(ids, now: now)
        if store.lastUndoId != before {
            showUndoToast(done ? "\(subject) marked done" : "\(subject) reopened", store: store)
        }
        return true
    }

    /// 1, 2, 3: High, Medium, Low. False for a level the priorities don't have (the key passes through).
    @discardableResult
    func setPriorityLevel(_ level: Int, store: TaskStore) -> Bool {
        guard let priority = TaskPriority.level(level) else { return false }
        let ids = keyboardTargets(store)
        guard !ids.isEmpty else { return false }
        applyQuickPick(.priority(priority), ids: ids, store: store)
        return true
    }

    // MARK: - ⌥↑ / ⌥↓

    /// The groups whose order ⌥↑/⌥↓ change, as shown: List groups and Board columns (manual sort
    /// only), the Sprints groups, and Today's My focus. nil when the view has no manual order.
    func reorderableGroups(_ store: TaskStore, now: Date = Date()) -> (groups: [[UUID]], focus: Bool)? {
        if scope.isToday {
            guard !isCollapsed(Self.todayFocusKey) else { return nil }
            return ([store.todayPlan(now: now).focus.map(\.id)], true)
        }
        switch effectiveTab {
        case .list:
            guard sort.isManual else { return nil }
            return (listGroups(store, now: now).filter { !isCollapsed($0.id) }.map { $0.tasks.map(\.id) }, false)
        case .board:
            guard sort.isManual else { return nil }
            return (boardColumns(store).map { boardTasks(store, column: $0, now: now).map(\.id) }, false)
        case .sprints:
            guard let projectId = scope.projectId else { return nil }
            return (Self.sprintSlots.filter { !isCollapsed(Self.sprintGroupKey($0)) }
                .map { store.sprintTasks(projectId: projectId, slot: $0).map(\.id) }, false)
        case .milestones:
            return nil
        }
    }

    /// ⌥↑ / ⌥↓: moves the selected rows up or down inside their group. One undo step.
    @discardableResult
    func moveSelectionWithinGroup(_ offset: Int, store: TaskStore, now: Date = Date()) -> Bool {
        guard openDetail == nil, openTaskId == nil else { return false }
        let ids = Set(keyboardTargets(store))
        guard let focus = selectedTaskId ?? ids.first, !ids.isEmpty else { return false }
        guard let reorderable = reorderableGroups(store, now: now) else {
            if !scope.isToday, effectiveTab == .list || effectiveTab == .board {
                show(Toast(message: "Sort by Manual to move tasks by hand"))
                return true
            }
            return false
        }
        guard let group = reorderable.groups.first(where: { $0.contains(focus) }) else { return false }
        store.moveWithinGroup(ids.intersection(group), offset: offset, order: group, focus: reorderable.focus, now: now)
        return true
    }

    // MARK: - ⌘I and ⌘[ ⌘] on a milestone panel

    /// ⌘I: opens the panel of the selected task (or, with none, of the milestone or project on
    /// screen); closes the open panel.
    @discardableResult
    func togglePanel(store: TaskStore) -> Bool {
        if isPanelOpen {
            closePanel()
            return true
        }
        if let id = selectedTaskId, store.task(id) != nil {
            openTask(id)
            return true
        }
        if let id = scope.milestoneId, store.milestone(id) != nil {
            openMilestone(id)
            return true
        }
        if let id = scope.projectId, store.project(id) != nil {
            openProject(id)
            return true
        }
        return false
    }

    /// ⌘[ / ⌘] with a milestone panel open: the project's previous or next milestone.
    @discardableResult
    func stepMilestonePanel(_ offset: Int, store: TaskStore) -> Bool {
        guard case let .milestone(id)? = openDetail, let milestone = store.milestone(id) else { return false }
        let ids = store.milestones(of: milestone.projectId).map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return false }
        openMilestone(ids[index + offset], from: panelBack)
        return true
    }

    // MARK: - ⌘0: the sidebar

    /// ⌘0: the sidebar takes the keyboard, starting on the item on screen.
    func focusSidebar(store: TaskStore) {
        closeQuickPicker()
        let scopes = sidebarScopes(store)
        sidebarCursor = scopes.contains(scope) ? scope : scopes.first
    }

    /// ↑/↓ in the sidebar.
    @discardableResult
    func moveSidebarCursor(_ offset: Int, store: TaskStore) -> Bool {
        let scopes = sidebarScopes(store)
        guard !scopes.isEmpty else { return false }
        guard let cursor = sidebarCursor, let index = scopes.firstIndex(of: cursor) else {
            sidebarCursor = scopes.first
            return true
        }
        sidebarCursor = scopes[min(max(index + offset, 0), scopes.count - 1)]
        return true
    }

    /// → lists a project's milestones (then steps into them), ← hides them (from a milestone,
    /// back to its project).
    @discardableResult
    func expandSidebarCursor(_ expand: Bool, store: TaskStore) -> Bool {
        switch sidebarCursor {
        case let .project(id)?:
            if expand {
                if isProjectExpanded(id) {
                    return moveSidebarCursor(1, store: store)
                }
                expandedProjects.insert(id)
            } else {
                expandedProjects.remove(id)
            }
            return true
        case let .milestone(_, projectId)?:
            guard !expand else { return false }
            sidebarCursor = .project(projectId)
            return true
        default:
            return false
        }
    }

    /// ↵ in the sidebar: shows the item and gives the keyboard back to the list.
    func activateSidebarCursor(store: TaskStore) {
        guard let cursor = sidebarCursor else { return }
        sidebarCursor = nil
        if cursor != scope { select(cursor) }
    }
}

extension TaskPriority {
    /// 1 is the highest: the keys 1, 2, 3. nil for a level there isn't.
    static func level(_ number: Int) -> TaskPriority? {
        ordered.indices.contains(number - 1) ? ordered[number - 1] : nil
    }
}
