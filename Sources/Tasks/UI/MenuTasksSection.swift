import AppKit
import SwiftUI

// The task part of the menu bar dropdown: search / quick add and the tasks in progress.
// Matches docs/design/reference/FocusMenu.dc.html.

/// Opens the main window from the menu, optionally on a task or a project.
@MainActor
enum MenuNavigation {
    static func openTask(_ id: UUID) {
        MenuBarPanel.close()
        TasksWindow.show(openTask: id)
    }

    /// Opens the project on its own last tab with its own filters (both kept per project).
    static func openProject(_ id: UUID, focus: TasksViewModel.FocusRequest.Field? = nil) {
        MenuBarPanel.close()
        TasksWindow.viewModel.select(.project(id))
        TasksWindow.show()
        if let focus { TasksWindow.viewModel.requestFocus(focus) }
    }

    /// Opens the milestone's page (its own last tab and filters).
    static func openMilestone(_ id: UUID) {
        MenuBarPanel.close()
        TasksWindow.viewModel.showMilestone(id, store: TaskStore.shared)
        TasksWindow.show()
    }

    /// Opens the Today page.
    static func openToday() {
        MenuBarPanel.close()
        TasksWindow.viewModel.select(.today)
        TasksWindow.show()
    }

    static func openApp(focus: TasksViewModel.FocusRequest.Field? = nil) {
        MenuBarPanel.close()
        TasksWindow.show()
        if let focus { TasksWindow.viewModel.requestFocus(focus) }
    }
}

/// The menu's own state, kept while the panel closes and opens: the keyboard highlight and the
/// last "Added to …" note.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()

    /// "Added to Atlas · High" under the field, with Open
    struct AddedNote: Equatable {
        let id = UUID()
        let message: String
        let taskId: UUID
    }

    /// Keyboard highlight while the search is empty (↑/↓ move, Space timer, ↵ open, ←/→ fold)
    @Published var highlight: MenuRowItem?
    @Published var added: AddedNote?
    /// Changes when the "Menu bar search" hotkey opens the panel, so the field takes focus
    @Published var focusSearch = UUID()
}

/// Keys the menu handles itself while the search field has focus.
enum MenuKey: Equatable {
    case up, down, left, right, space, escape, tab
    /// ⌥Space: start the highlighted timer and pause every other one
    case optionSpace
    /// ⌘1–⌘9: the timer of the Nth listed task
    case commandNumber(Int)
    case returnKey(command: Bool)
}

/// Search field that filters projects and tasks, with the quick-add target shown inside it.
/// While typing, ↑/↓ move the highlight in the results, ↵ opens the highlighted project or task,
/// and ⌘↵ adds the text as a task. Plain ↵ never creates a task unless the "Add" row is highlighted.
/// With the field empty, ↑/↓ move through the menu rows instead (see StatusMenuView).
struct MenuSearchField: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var query: String
    let target: Project?
    let setTarget: (UUID) -> Void
    /// Key hint on the right ("↵ open", "␣ timer"), or nil
    let hint: String?
    /// Fallback when the key monitor didn't see ↵
    let submit: (_ command: Bool) -> Void
    /// Returns true when the key was used
    let handleKey: (MenuKey) -> Bool

    @FocusState private var focused: Bool
    @State private var pickingTarget = false
    @ObservedObject private var menuState = MenuState.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Focus.text3)
            TextField(target == nil ? "Search tasks" : "Search, or add a task…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(Focus.text)
                .focused($focused)
                .onSubmit { submit(NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) }
                .accessibilityLabel("Search or add a task")
                .accessibilityHint("Return opens the highlighted result. Command-Return adds a task to \(target?.name ?? "a project").")
            if let hint {
                FocusKey(text: hint).fixedSize()
            }
            if let target {
                targetChip(target)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .overlay(alignment: .bottom) { FocusDivider() }
        .background(MenuSearchKeyMonitor(isActive: focused, handle: handleKey))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: menuState.focusSearch) { _ in DispatchQueue.main.async { focused = true } }
    }

    /// Where new tasks go, inside the field: the last project used. Click to change it.
    private func targetChip(_ target: Project) -> some View {
        Button { pickingTarget.toggle() } label: {
            HStack(spacing: 5) {
                FocusProjectTile(name: target.name, colorHex: target.colorHex, size: 14)
                Text(target.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Focus.text2)
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(Focus.sidebar))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(Focus.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New tasks go to \(target.name). Click to change.")
        .accessibilityLabel("Add tasks to \(target.name)")
        .popover(isPresented: $pickingTarget, arrowEdge: .bottom) {
            FocusPopoverMenu(width: 220) {
                FocusMenuSection(title: "Add new tasks to", first: true)
                ForEach(store.projects) { project in
                    FocusMenuItem(isSelected: project.id == target.id) {
                        setTarget(project.id)
                        pickingTarget = false
                    } label: {
                        FocusProjectTile(name: project.name, colorHex: project.colorHex)
                        Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Watches the menu keys in the menu panel's window only, while the search field has focus.
/// The field editor would otherwise eat the arrows and turn ↵ into a submit. A key the handler
/// doesn't use goes on to the field (← → move the caret, Space types).
private struct MenuSearchKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let handle: (MenuKey) -> Bool

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isActive = isActive
        view.handle = handle
    }

    final class MonitorView: NSView {
        var isActive = false
        var handle: ((MenuKey) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive, let window = self.window, event.window === window else { return event }
                // Leave IME composition (marked text) alone
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                guard let key = Self.key(for: event) else { return event }
                return self.handle?(key) == true ? nil : event
            }
        }

        static func key(for event: NSEvent) -> MenuKey? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let plain = flags.subtracting([.numericPad, .function]).isEmpty
            let mods = flags.intersection([.command, .option, .control, .shift])
            if mods == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
                return .commandNumber(digit)
            }
            if mods == .option, event.keyCode == 49 { return .optionSpace }
            switch event.keyCode {
            case 48 where plain: return .tab
            case 126 where plain: return .up
            case 125 where plain: return .down
            case 123 where plain: return .left
            case 124 where plain: return .right
            case 49 where plain: return .space
            case 53 where plain: return .escape
            case 36, 76: return .returnKey(command: flags.contains(.command))
            default: return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

/// While typing: the "Add “x” to Project" row, then matching projects and tasks.
/// The highlighted row (keyboard) gets the hover fill; ↵ activates it.
struct MenuSearchResults: View {
    @EnvironmentObject private var store: TaskStore
    let query: String
    let results: MenuSearchResultsModel
    let highlight: MenuSearchItem?
    let target: Project?
    let setTarget: (UUID) -> Void
    let activate: (MenuSearchItem) -> Void

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = results.projects.compactMap { store.project($0) }
        let milestones = results.milestones.compactMap { store.milestone($0) }
        let tasks = results.tasks.compactMap { store.task($0) }

        VStack(alignment: .leading, spacing: 2) {
            if let target, results.canAdd {
                MenuItemRow(highlighted: highlight == .add, action: { activate(.add) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Focus.text2)
                        .frame(width: 20, height: 20)
                    let plan = store.planQuickAdd(q, projectId: target.id)
                    let title = plan.title
                    // A +project word sends it elsewhere: the row names that project
                    let destination = store.project(plan.projectId) ?? target
                    let parts = store.quickAddPreview(q, projectId: target.id).filter { !$0.hasPrefix("→ ") }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 0) {
                            (Text("Add “") + Text(title.isEmpty ? q : title).foregroundColor(Focus.text) + Text("” to "))
                                .font(Focus.row)
                                .foregroundColor(Focus.text2)
                                .lineLimit(1)
                            targetMenu(destination)
                        }
                        if !parts.isEmpty {
                            Text(parts.joined(separator: " · "))
                                .font(.system(size: 11.5))
                                .foregroundColor(Focus.text3)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    FocusKey(text: highlight == .add ? "↵" : "⌘↵")
                }
            }

            if !projects.isEmpty {
                FocusCaption(text: "Projects").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                ForEach(projects) { project in
                    MenuItemRow(highlighted: highlight == .project(project.id), action: { activate(.project(project.id)) }) {
                        FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 20)
                        Text(project.name).font(Focus.rowStrong).foregroundColor(Focus.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(store.openCount(project.id))")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(Focus.text3)
                    }
                }
            }

            if !milestones.isEmpty {
                FocusCaption(text: "Milestones").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                ForEach(milestones) { milestone in
                    MenuItemRow(highlighted: highlight == .milestone(milestone.id), action: { activate(.milestone(milestone.id)) }) {
                        MilestoneIcon(milestone, size: 12).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(milestone.name).font(.system(size: 13)).foregroundColor(Focus.text).lineLimit(1)
                            Text(store.project(milestone.projectId)?.name ?? "")
                                .font(.system(size: 11.5))
                                .foregroundColor(Focus.text3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(store.milestoneProgress(milestone.id).short)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(Focus.text3)
                    }
                }
            }

            if !tasks.isEmpty {
                FocusCaption(text: "Tasks").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                ForEach(tasks) { task in
                    MenuItemRow(highlighted: highlight == .task(task.id), action: { activate(.task(task.id)) }) {
                        WorkflowStatusIcon(status: store.status(of: task), size: 14).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.system(size: 13, weight: store.isRunning(task.id) ? .medium : .regular))
                                .foregroundColor(task.isClosed ? Focus.text3 : Focus.text)
                                .lineLimit(1)
                            Text(store.project(of: task)?.name ?? "")
                                .font(.system(size: 11.5))
                                .foregroundColor(Focus.text3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        TaskTimeText(task: task, font: .system(size: 12))
                        if !task.isClosed {
                            TaskTimerButton(task: task, size: 24)
                        }
                    }
                }
            }

            if projects.isEmpty && milestones.isEmpty && tasks.isEmpty {
                Text(target == nil
                     ? "No matches. Create a project in FlowMate to add tasks."
                     : "No matches. Press ⌘↵ to add it as a task.")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func targetMenu(_ target: Project) -> some View {
        Menu {
            ForEach(store.projects) { project in
                Button(project.name) { setTarget(project.id) }
            }
        } label: {
            Text(target.name).font(Focus.row.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Choose the project")
    }
}

/// "Today 3h 20m · 2 due" at the top of the menu's tasks; a click opens the Today page.
struct MenuTodaySummary: View {
    @EnvironmentObject private var store: TaskStore
    @State private var hovering = false

    var body: some View {
        Button { MenuNavigation.openToday() } label: {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Focus.text2)
                    .frame(width: 20)
                LiveTime { now in
                    let counts = store.dueCounts(now: now)
                    Text(store.menuTodaySummary(now: now))
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundColor(counts.overdue > 0 ? Focus.riskTint.text : Focus.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(hovering ? Focus.text2 : Focus.text3)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open Today in FlowMate")
        .accessibilityLabel("\(store.menuTodaySummary()). Open Today")
    }
}

/// "In progress": every task in progress across all projects. Running timers come first, tinted,
/// with their live clock; the paused ones follow. Click a row to open it; the ring starts or pauses.
/// Then "Up next": overdue, due today and pinned tasks, then the top of the active sprints, each
/// with a play ring, so a menu with nothing running still says what to start.
struct MenuInProgressSection: View {
    @EnvironmentObject private var store: TaskStore
    @ObservedObject private var menu = MenuState.shared

    var body: some View {
        let listed = store.menuInProgressTasks
        let upNext = store.upNext()
        VStack(alignment: .leading, spacing: 4) {
            if !store.projects.isEmpty {
                MenuTodaySummary()
                    .padding(.bottom, 2)
            }
            if !listed.running.isEmpty || !listed.paused.isEmpty || !store.awayGaps.isEmpty || upNext.isEmpty {
                inProgress(listed, hasUpNext: !upNext.isEmpty)
            }
            if !upNext.isEmpty {
                upNextSection(upNext)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func inProgress(_ listed: (running: [TaskItem], paused: [TaskItem]), hasUpNext: Bool) -> some View {
        HStack(spacing: 6) {
            FocusCaption(text: "In progress")
            if !listed.running.isEmpty {
                Text("· \(listed.running.count) running".uppercased())
                    .font(Focus.caption)
                    .tracking(0.5)
                    .foregroundColor(Focus.liveText)
            }
            Spacer()
            if !listed.running.isEmpty {
                Button("Pause all") { store.pauseAllTimers() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)

        // "Timers ran while your Mac slept 2h 05m · Keep · Discard"
        if !store.awayGaps.isEmpty {
            AwayPrompt(compact: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }

        if listed.running.isEmpty && listed.paused.isEmpty && !hasUpNext {
            emptyState
        }
        ForEach(listed.running) { task in
            runningRow(task)
            MenuLongRunLine(task: task)
        }
        ForEach(listed.paused) { task in
            pausedRow(task)
        }
    }

    private func upNextSection(_ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FocusCaption(text: "Up next")
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(tasks) { task in
                upNextRow(task)
            }
        }
    }

    /// Why a task is up next: "Overdue · Oct 28", "Due today", "Today" (pinned) or its sprint.
    private func reason(_ task: TaskItem) -> (text: String, risk: Bool) {
        if store.isOverdue(task), let due = task.dueDate { return ("Overdue · " + TaskDates.dueLabel(due), true) }
        if store.isDueToday(task) { return ("Due today", true) }
        if store.isInFocus(task) { return ("Today", false) }
        return (store.sprintLabel(for: task), false)
    }

    private func upNextRow(_ task: TaskItem) -> some View {
        let project = store.project(of: task)
        let why = reason(task)
        return HStack(spacing: 10) {
            TaskTimerButton(task: task, size: 28)
            Button { MenuNavigation.openTask(task.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(Focus.row)
                        .foregroundColor(Focus.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let project {
                            FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 12)
                            Text(project.name).lineLimit(1)
                            Text("·")
                        }
                        Text(why.text)
                            .foregroundColor(why.risk ? Focus.risk : Focus.text3)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in FlowMate")
            Text(Focus.durationString(minutes: task.expectedMinutes))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(Focus.text3)
        }
        .modifier(MenuHover(highlighted: menu.highlight == .upNext(task.id)))
        .id(MenuRowItem.upNext(task.id))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.projects.isEmpty {
                Text(store.archivedProjects.isEmpty
                     ? "No projects yet. A project holds tasks, sprints and timers."
                     : "Every project is archived. Unarchive one in FlowMate, or start a new one.")
                Button("Create a project") { MenuNavigation.openApp() }
                    .buttonStyle(.focus())
            } else {
                Text("Nothing in progress or planned. Pin tasks to Today in FlowMate (⌘T), or start a timer on any task.")
            }
        }
        .font(Focus.meta)
        .foregroundColor(Focus.text3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func runningRow(_ task: TaskItem) -> some View {
        let highlighted = menu.highlight == .running(task.id)
        return HStack(spacing: 10) {
            TaskTimerButton(task: task, size: 32)
            Button { MenuNavigation.openTask(task.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(Focus.rowStrong)
                        .foregroundColor(Focus.text)
                        .lineLimit(1)
                    Text("\(store.project(of: task)?.name ?? "") · \(Focus.durationString(minutes: task.expectedMinutes)) expected")
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in FlowMate")
            LiveTime { now in
                Text(Focus.clockString(store.elapsed(task, now: now)))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundColor(Focus.liveText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Focus.liveSoft))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(highlighted ? Focus.liveText.opacity(0.5) : .clear, lineWidth: 1.5)
        )
        .id(MenuRowItem.running(task.id))
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private func pausedRow(_ task: TaskItem) -> some View {
        let project = store.project(of: task)
        return HStack(spacing: 10) {
            TaskTimerButton(task: task, size: 32)
            Button { MenuNavigation.openTask(task.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(Focus.row)
                        .foregroundColor(Focus.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let project {
                            FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 12)
                            Text(project.name).lineLimit(1)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in FlowMate")
            TaskTimeText(task: task, font: .system(size: 12))
        }
        .modifier(MenuHover(highlighted: menu.highlight == .task(task.id)))
        .id(MenuRowItem.task(task.id))
    }
}

// MARK: - Row chrome

/// A full-width menu row button with the 8-radius hover fill. `highlighted` shows the same
/// fill for the keyboard highlight.
struct MenuItemRow<Content: View>: View {
    var highlighted = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(MenuHover(highlighted: highlighted))
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

/// 7/8 padding and a hover fill, as `.item` in the reference
private struct MenuHover: ViewModifier {
    var highlighted = false
    var leading: CGFloat = 8
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering || highlighted ? Focus.hover : .clear))
            .onHover { hovering = $0 }
    }
}

/// Under a running timer in the menu: "Still working on this? Keep · Stop at…" once it has run
/// past the prompt time. Quiet: it only shows here and in the window, and never stops the timer.
private struct MenuLongRunLine: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    var body: some View {
        LiveTime { now in
            if store.longRunningTasks(now: now).contains(where: { $0.id == task.id }) {
                LongRunPrompt(task: task, compact: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
    }
}

/// The menu bar title while timers run, when "Show the timer in the menu bar" is on:
/// the most recently started timer's clock, plus how many others run ("1:12:05 +1").
struct MenuBarClockText: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var ticker: TimerTicker

    var body: some View {
        Text(Self.title(store: store, now: ticker.now))
            .monospacedDigit()
    }

    static func title(store: TaskStore, now: Date) -> String {
        let running = store.runningTasks
        guard let latest = running.max(by: { (store.startedAt($0.id) ?? .distantPast) < (store.startedAt($1.id) ?? .distantPast) }) else {
            return ""
        }
        let clock = Focus.clockString(store.elapsed(latest, now: now))
        return running.count > 1 ? "\(clock) +\(running.count - 1)" : clock
    }
}
