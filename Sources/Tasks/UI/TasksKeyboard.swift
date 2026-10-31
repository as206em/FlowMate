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

    /// Shortcuts that still work while a text field has focus. The others belong to the text
    /// (arrows, Return, Space, ⌘⌫, ⌘Z) and pass through.
    var worksWhileTyping: Bool {
        switch self {
        case .newTask, .newProject, .find, .tab1, .tab2, .tab3, .tab4, .help: return true
        // ⌘[ and ⌘] aren't text editing keys, so they step through tasks even from the panel's fields
        case .previousTask, .nextTask: return true
        default: return false
        }
    }

    /// Shortcuts that select or move through text, so read-only selectable text (a description
    /// preview) keeps them while it has focus.
    var belongsToSelectableText: Bool {
        switch self {
        case .selectAll, .selectPrevious, .selectNext, .extendUp, .extendDown: return true
        default: return false
        }
    }

    /// Shortcuts on a plain key (arrows, Return, Space, Esc). A focused control (a button or
    /// checkbox reached with Tab) uses those keys itself, so they pass through to it.
    var usesPlainKey: Bool {
        switch self {
        case .selectPrevious, .selectNext, .open, .toggleTimer, .clearSelection, .extendUp, .extendDown: return true
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

    // Virtual key codes for keys without stable characters
    private static let upArrowKey: UInt16 = 126
    private static let downArrowKey: UInt16 = 125
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
            case returnKey, keypadEnterKey: return .open
            case spaceKey: return .toggleTimer
            case escapeKey: return .clearSelection
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
        let panelOpen = isPanelOpen
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
            // Today has no search: find in All projects
            if scope.isToday { select(.all) }
            if !showsFilterBar { tab = .list }
            closePanel()
            requestFocus(.search)
        case .tab1, .tab2, .tab3, .tab4:
            guard let index = shortcut.tabIndex, index < tabs.count else { return false }
            closePanel()
            tab = tabs[index]
        case .selectPrevious, .selectNext:
            // In the panel the arrows scroll; ⌘[ and ⌘] (later) step between tasks
            guard !panelOpen, moveSelection(shortcut == .selectNext ? 1 : -1, store: store) != nil else { return false }
        case .open:
            guard !panelOpen, let id = selectedTaskId, store.task(id) != nil else { return false }
            openTask(id)
        case .extendUp, .extendDown:
            guard !panelOpen else { return false }
            return extendSelection(shortcut == .extendDown ? 1 : -1, store: store)
        case .selectAll:
            guard !panelOpen, !visibleTasks(store).isEmpty else { return false }
            selectAll(store)
        case .previousTask, .nextTask:
            guard openTaskId != nil else { return false }
            stepOpenTask(shortcut == .nextTask ? 1 : -1, store: store)
        case .previousScope, .nextScope:
            return stepSidebar(shortcut == .nextScope ? 1 : -1, store: store)
        case .toggleTimer:
            // Timers start one at a time; with several selected, Space does nothing
            guard !isMultiSelecting || openTaskId != nil else { return false }
            guard let id = targetTaskId(store), let task = store.task(id) else { return false }
            // Done tasks have no timer button; a running one can still be paused
            guard !task.isClosed || store.isRunning(id) else { return false }
            store.toggleTimer(id)
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
        case .help:
            showingShortcuts.toggle()
        case .clearSelection:
            // With the panel open, Esc closes it (TasksRootView)
            guard !panelOpen, selectedTaskId != nil else { return false }
            selectedTaskId = nil
        }
        return true
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
        if isTyping(in: window), !shortcut.worksWhileTyping { return false }
        if shortcut.usesPlainKey, controlHasFocus(in: window) { return false }
        // ⌘A and the arrows in read-only selectable text (a Markdown preview) act on that text
        if isSelectingText(in: window), shortcut.belongsToSelectableText { return false }
        return model.perform(shortcut, store: store)
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
