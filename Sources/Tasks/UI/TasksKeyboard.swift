import AppKit
import SwiftUI

/// The main window's keyboard shortcuts. The app has no visible main menu (LSUIElement), so a
/// local key monitor scoped to the tasks window handles them (see TasksKeyMonitor).
enum TasksShortcut: Equatable, CaseIterable {
    case undo, redo
    case newTask, newProject, find
    case tab1, tab2, tab3, tab4
    case selectPrevious, selectNext, open, toggleTimer
    case extendUp, extendDown, selectAll
    case previousTask, nextTask
    /// ⌥⌘↑ / ⌥⌘↓: the sidebar item above or below (All projects, projects, listed milestones)
    case previousScope, nextScope
    case delete, duplicate
    /// ⌘T: add the selected tasks to Today, or remove them
    case toggleToday
    case help, clearSelection
    /// Single keys on the selection or the open task: S, P, M, R, D, E, T, L, ⇧M
    case pickStatus, pickPriority, pickMilestone, pickSprint, pickDue, pickExpected, pickTimeSpent, pickLabels, pickProject
    /// X: done, or back to Not started
    case toggleDone
    /// 1–4: priority by level (4 does nothing while there are three levels)
    case priority1, priority2, priority3, priority4
    /// ⌥↑ / ⌥↓: move the selected rows inside their group
    case moveUp, moveDown
    /// ⇧⌘A: select nothing
    case deselectAll
    /// ⌘K: the palette
    case palette
    /// ⌘0: the sidebar takes the keyboard
    case focusSidebar
    /// ⌘I: open or close the panel of the selected item
    case togglePanel
    /// ⇧Space: pause every timer; ⌥Space: run only this one
    case pauseAllTimers, soloTimer
    /// ← / →: fold a project's milestones while the sidebar has the keyboard
    case left, right

    /// Shortcuts that still work while a text field has focus. The others belong to the text
    /// (arrows, Return, Space, letters, ⌘⌫, ⌘Z) and pass through.
    var worksWhileTyping: Bool {
        switch self {
        case .newTask, .newProject, .find, .tab1, .tab2, .tab3, .tab4, .help, .palette, .focusSidebar: return true
        // ⌘[ and ⌘] aren't text editing keys, so they step through tasks even from the panel's fields
        case .previousTask, .nextTask: return true
        default: return false
        }
    }

    /// Shortcuts that select or move through text, so read-only selectable text (a description
    /// preview) keeps them while it has focus.
    var belongsToSelectableText: Bool {
        switch self {
        case .selectAll, .selectPrevious, .selectNext, .extendUp, .extendDown, .left, .right: return true
        default: return false
        }
    }

    /// Shortcuts on a plain key (arrows, Return, Space, Esc). A focused control (a button or
    /// checkbox reached with Tab) uses those keys itself, so they pass through to it.
    var usesPlainKey: Bool {
        switch self {
        case .selectPrevious, .selectNext, .open, .toggleTimer, .clearSelection, .extendUp, .extendDown,
             .pauseAllTimers, .soloTimer, .left, .right:
            return true
        default: return false
        }
    }

    var tabIndex: Int? {
        switch self {
        case .tab1: return 0
        case .tab2: return 1
        case .tab3: return 2
        case .tab4: return 3
        default: return nil
        }
    }

    /// The picker a single key opens
    var quickAction: TaskQuickAction? {
        switch self {
        case .pickStatus: return .status
        case .pickPriority: return .priority
        case .pickMilestone: return .milestone
        case .pickSprint: return .sprint
        case .pickDue: return .due
        case .pickExpected: return .expected
        case .pickTimeSpent: return .timeSpent
        case .pickLabels: return .labels
        case .pickProject: return .project
        default: return nil
        }
    }

    var priorityLevel: Int? {
        switch self {
        case .priority1: return 1
        case .priority2: return 2
        case .priority3: return 3
        case .priority4: return 4
        default: return nil
        }
    }

    // Virtual key codes for keys without stable characters
    private static let upArrowKey: UInt16 = 126
    private static let downArrowKey: UInt16 = 125
    private static let leftArrowKey: UInt16 = 123
    private static let rightArrowKey: UInt16 = 124
    private static let returnKey: UInt16 = 36
    private static let keypadEnterKey: UInt16 = 76
    private static let spaceKey: UInt16 = 49
    private static let deleteKey: UInt16 = 51
    private static let escapeKey: UInt16 = 53

    /// Maps a key press to a shortcut. `characters` is the key ignoring modifiers.
    static func match(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> TasksShortcut? {
        let mods = modifiers.intersection([.command, .shift, .option, .control])
        let key = characters.lowercased()
        switch mods {
        case []:
            switch keyCode {
            case upArrowKey: return .selectPrevious
            case downArrowKey: return .selectNext
            case leftArrowKey: return .left
            case rightArrowKey: return .right
            case returnKey, keypadEnterKey: return .open
            case spaceKey: return .toggleTimer
            case escapeKey: return .clearSelection
            default: break
            }
            switch key {
            case "s": return .pickStatus
            case "p": return .pickPriority
            case "m": return .pickMilestone
            case "r": return .pickSprint
            case "d": return .pickDue
            case "e": return .pickExpected
            case "t": return .pickTimeSpent
            case "l": return .pickLabels
            case "x": return .toggleDone
            case "1": return .priority1
            case "2": return .priority2
            case "3": return .priority3
            case "4": return .priority4
            default: return nil
            }
        case [.command]:
            if keyCode == deleteKey { return .delete }
            switch key {
            case "z": return .undo
            case "a": return .selectAll
            case "[": return .previousTask
            case "]": return .nextTask
            case "n": return .newTask
            case "f": return .find
            case "d": return .duplicate
            case "t": return .toggleToday
            case "k": return .palette
            case "i": return .togglePanel
            case "0": return .focusSidebar
            case "/": return .help
            case "1": return .tab1
            case "2": return .tab2
            case "3": return .tab3
            case "4": return .tab4
            default: return nil
            }
        case [.shift]:
            switch keyCode {
            case upArrowKey: return .extendUp
            case downArrowKey: return .extendDown
            case spaceKey: return .pauseAllTimers
            default: break
            }
            return key == "m" ? .pickProject : nil
        case [.option]:
            switch keyCode {
            case upArrowKey: return .moveUp
            case downArrowKey: return .moveDown
            case spaceKey: return .soloTimer
            default: return nil
            }
        case [.command, .option]:
            switch keyCode {
            case upArrowKey: return .previousScope
            case downArrowKey: return .nextScope
            default: return nil
            }
        case [.command, .shift]:
            switch key {
            case "z": return .redo
            case "n": return .newProject
            case "a": return .deselectAll
            case "/", "?": return .help
            default: return nil
            }
        default:
            return nil
        }
    }
}

extension TasksViewModel {
    /// Runs a shortcut. Returns false when it doesn't apply right now, so the key passes through.
    @discardableResult
    func perform(_ shortcut: TasksShortcut, store: TaskStore) -> Bool {
        // The palette has the keyboard: only ⌘K (which closes it) gets through
        if showingPalette {
            guard shortcut == .palette else { return false }
            closePalette()
            return true
        }
        // ⌘0 gave the sidebar the keyboard: arrows, ↵ and Esc work there
        if sidebarCursor != nil, let handled = performInSidebar(shortcut, store: store) {
            return handled
        }
        let panelOpen = isPanelOpen
        if let action = shortcut.quickAction {
            return openQuickPicker(action, store: store)
        }
        if let level = shortcut.priorityLevel {
            return setPriorityLevel(level, store: store)
        }
        switch shortcut {
        case .undo:
            guard store.canUndo else { return false }
            undo(store)
        case .redo:
            guard store.canRedo else { return false }
            redo(store)
        case .newTask:
            // The composer opens at the top of the first group, below the panel's scrim; Milestones has none
            startNewTask(store)
        case .newProject:
            requestFocus(.newProject)
        case .find:
            // ⌘F filters the view on screen (⌘K jumps anywhere). Today has no search: find in All projects
            if scope.isToday { select(.all) }
            if !showsFilterBar { tab = .list }
            closePanel()
            requestFocus(.search)
        case .tab1, .tab2, .tab3, .tab4:
            guard let index = shortcut.tabIndex, index < tabs.count else { return false }
            closePanel()
            tab = tabs[index]
        case .selectPrevious, .selectNext:
            let offset = shortcut == .selectNext ? 1 : -1
            // With a task open the selection moves and the panel follows; a project or milestone
            // panel keeps the arrows for scrolling
            if openTaskId != nil, openDetail == nil { return stepOpenTask(offset, store: store) }
            guard !panelOpen, moveSelection(offset, store: store) != nil else { return false }
        case .open:
            guard !panelOpen, let id = selectedTaskId, store.task(id) != nil else { return false }
            openTask(id)
        case .extendUp, .extendDown:
            guard !panelOpen else { return false }
            return extendSelection(shortcut == .extendDown ? 1 : -1, store: store)
        case .selectAll:
            guard !panelOpen, !visibleTasks(store).isEmpty else { return false }
            selectAll(store)
        case .deselectAll:
            guard !selectedTaskIds.isEmpty, !panelOpen else { return false }
            clearSelection()
        case .previousTask, .nextTask:
            let offset = shortcut == .nextTask ? 1 : -1
            if openTaskId != nil { return stepOpenTask(offset, store: store) }
            return stepMilestonePanel(offset, store: store)
        case .previousScope, .nextScope:
            return stepSidebar(shortcut == .nextScope ? 1 : -1, store: store)
        case .toggleTimer:
            // Timers start one at a time; with several selected, Space does nothing
            guard !isMultiSelecting || openTaskId != nil else { return false }
            guard let id = targetTaskId(store), let task = store.task(id) else { return false }
            // Done tasks have no timer button; a running one can still be paused
            guard !task.isClosed || store.isRunning(id) else { return false }
            store.toggleTimer(id)
        case .soloTimer:
            guard !isMultiSelecting || openTaskId != nil else { return false }
            guard let id = targetTaskId(store), let task = store.task(id), !task.isClosed || store.isRunning(id) else { return false }
            store.startTimerExclusively(id)
        case .pauseAllTimers:
            guard store.hasRunningTimers else { return false }
            let count = store.runningTasks.count
            store.pauseAllTimers()
            show(Toast(message: count == 1 ? "Timer paused" : "\(count) timers paused"))
        case .delete:
            if isMultiSelecting, !panelOpen {
                deleteSelected(store)
                return true
            }
            guard let id = targetTaskId(store) else { return false }
            deleteTask(id, store: store)
        case .duplicate:
            if isMultiSelecting, !panelOpen {
                duplicateSelected(store)
                return true
            }
            guard let id = targetTaskId(store) else { return false }
            duplicateTask(id, store: store)
        case .toggleToday:
            let ids = todayTargets(store)
            guard !ids.isEmpty else { return false }
            toggleToday(ids, store: store)
        case .toggleDone:
            return toggleDone(store: store)
        case .moveUp, .moveDown:
            return moveSelectionWithinGroup(shortcut == .moveDown ? 1 : -1, store: store)
        case .palette:
            openPalette(store: store)
        case .focusSidebar:
            closePanel()
            focusSidebar(store: store)
        case .togglePanel:
            return togglePanel(store: store)
        case .help:
            showingShortcuts.toggle()
        case .clearSelection:
            // With the panel open, Esc closes it (TasksRootView)
            guard !panelOpen, selectedTaskId != nil else { return false }
            selectedTaskId = nil
        case .left, .right:
            return false
        case .pickStatus, .pickPriority, .pickMilestone, .pickSprint, .pickDue, .pickExpected, .pickTimeSpent, .pickLabels, .pickProject,
             .priority1, .priority2, .priority3, .priority4:
            return false
        }
        return true
    }

    /// Keys while the sidebar has the keyboard (⌘0). nil: not a sidebar key, handle it as usual.
    private func performInSidebar(_ shortcut: TasksShortcut, store: TaskStore) -> Bool? {
        switch shortcut {
        case .selectPrevious: return moveSidebarCursor(-1, store: store)
        case .selectNext: return moveSidebarCursor(1, store: store)
        case .right: return expandSidebarCursor(true, store: store)
        case .left: return expandSidebarCursor(false, store: store)
        case .open:
            activateSidebarCursor(store: store)
            return true
        case .clearSelection:
            sidebarCursor = nil
            return true
        case .focusSidebar:
            sidebarCursor = nil
            return true
        default:
            // Anything else gives the keyboard back to the list first
            sidebarCursor = nil
            return nil
        }
    }
}

/// Listens for key presses in the tasks window only, and never while a sheet or alert is up.
/// Shortcuts that belong to text pass through while a text field or the editor has focus.
@MainActor
final class TasksKeyMonitor {
    private var monitor: Any?
    private weak var window: NSWindow?
    private let model: TasksViewModel
    private let store: TaskStore

    init(window: NSWindow, model: TasksViewModel, store: TaskStore) {
        self.window = window
        self.model = model
        self.store = store
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// True when the key ran a shortcut and should go no further.
    private func consumes(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.isKeyWindow, window.attachedSheet == nil,
              let shortcut = TasksShortcut.match(
                  keyCode: event.keyCode,
                  characters: event.charactersIgnoringModifiers ?? "",
                  modifiers: event.modifierFlags
              ) else { return false }
        guard Self.applies(shortcut, typing: isTyping(in: window), controlFocused: controlHasFocus(in: window),
                           selectingText: isSelectingText(in: window)) else { return false }
        return model.perform(shortcut, store: store)
    }

    /// Whether a shortcut is the window's, given what has the keyboard: while typing in a field or
    /// the Markdown editor only the ones that work while typing (single keys, arrows, Space and
    /// ⌘Z belong to the text); a focused control keeps its plain keys; read-only selectable text
    /// (a description preview) keeps ⌘A and the arrows.
    nonisolated static func applies(_ shortcut: TasksShortcut, typing: Bool, controlFocused: Bool, selectingText: Bool) -> Bool {
        if typing, !shortcut.worksWhileTyping { return false }
        if shortcut.usesPlainKey, controlFocused { return false }
        if selectingText, shortcut.belongsToSelectableText { return false }
        return true
    }

    /// Non-editable but selectable text has focus (e.g. after clicking into a description preview).
    private func isSelectingText(in window: NSWindow) -> Bool {
        guard let text = window.firstResponder as? NSTextView else { return false }
        return !text.isEditable && text.isSelectable
    }

    /// A button, checkbox, pop-up or other control has keyboard focus (Full Keyboard Access).
    private func controlHasFocus(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder, !(responder is NSTextView) else { return false }
        return responder is NSControl
    }

    /// A text field's field editor or the Markdown editor has focus.
    private func isTyping(in window: NSWindow) -> Bool {
        guard let text = window.firstResponder as? NSTextView else { return false }
        return text.isEditable || text.hasMarkedText()
    }
}
