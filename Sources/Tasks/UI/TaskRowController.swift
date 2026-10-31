import AppKit
import SwiftUI

/// What a click on a task row does, shared by all the AppKit row views of a table.
/// Everything here runs on demand (a click, a right-click), never while scrolling.
@MainActor
final class TaskRowController: NSObject {
    weak var store: TaskStore?
    weak var model: TasksViewModel?
    private var popover: NSPopover?

    // MARK: Clicks

    /// A click at `column` of the row (nil: the gap between columns or outside any).
    func click(task id: UUID, column: TaskColumn?, rect: NSRect, in view: NSView, clickCount: Int,
               modifiers: NSEvent.ModifierFlags, rename: () -> Void) {
        guard let store, let model, let task = store.task(id) else { return }
        switch column {
        case .status?:
            store.cycleStatus(id)
        case .timer? where !task.isClosed:
            // ⌥-click: this timer runs, every other one pauses
            if modifiers.contains(.option) { store.startTimerExclusively(id) } else { store.toggleTimer(id) }
        case .milestone?, .due?, .priority?, .time?:
            showEditor(column!, taskId: id, rect: rect, in: view)
        case .sprint? where task.sprintSlot != .closed:
            showEditor(.sprint, taskId: id, rect: rect, in: view)
        case .title? where clickCount >= 2:
            rename()
        default:
            model.clickTitle(id, store: store, modifiers: modifiers)
        }
    }

    /// The hover button at the end of the title.
    func perform(_ action: RowQuickAction, task id: UUID) {
        guard let store, let model else { return }
        switch action {
        case .tomorrow: model.moveToDay([id], .tomorrow, store: store)
        }
    }

    // MARK: Editors

    private func showEditor(_ column: TaskColumn, taskId: UUID, rect: NSRect, in view: NSView) {
        guard let store, let model else { return }
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let close: () -> Void = { [weak popover] in popover?.close() }
        let content = LiveTaskEditor(taskId: taskId) { task in
            switch column {
            case .milestone: AnyView(TaskMilestoneEditor(task: task, close: close))
            case .sprint: AnyView(TaskSprintEditor(task: task, close: close))
            case .due: AnyView(TaskDueEditor(task: task, close: close))
            case .priority: AnyView(TaskPriorityEditor(task: task, close: close))
            default: AnyView(TaskTimeEditor(task: task, close: close))
            }
        }
        .environmentObject(store)
        .environmentObject(model)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        self.popover = popover
    }

    // MARK: Rename

    func rename(_ id: UUID, to title: String) {
        store?.renameTaskOnce(id, title)
    }

    // MARK: Context menu

    /// The row's right-click menu. Each item shows the key that does the same from the keyboard;
    /// the property items open the same single-key pickers (S, P, M, R, D, E, T, ⇧M).
    func makeMenu(task id: UUID, rename: @escaping () -> Void) -> NSMenu? {
        guard let store, let model, let task = store.task(id) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        // The selection when this row is part of it, else just this row
        let selection = model.isMultiSelecting && model.isSelected(id)
        let ids = selection ? model.selectedIds(store) : [id]

        if selection {
            let count = ids.count
            let header = NSMenuItem(title: "\(count) tasks selected", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(item("Duplicate \(count) tasks", key: "d", modifiers: .command) { [weak model, weak store] in
                if let model, let store { model.duplicateSelected(store) }
            })
            menu.addItem(item("Delete \(count) tasks", key: "\u{8}", modifiers: .command) { [weak model, weak store] in
                if let model, let store { model.deleteSelected(store) }
            })
            let allPinned = ids.compactMap { store.task($0) }.allSatisfy { store.isInFocus($0) }
            menu.addItem(item(allPinned ? "Remove \(count) tasks from Today" : "Add \(count) tasks to Today", key: "t", modifiers: .command) {
                [weak model, weak store] in
                if let model, let store { model.toggleToday(ids, store: store) }
            })
            menu.addItem(.separator())
        } else {
            menu.addItem(item("Open", key: "\r") { [weak model] in model?.openTask(id) })
            menu.addItem(item("Rename", action: rename))
            if !task.isClosed || store.isRunning(id) {
                menu.addItem(item(store.isRunning(id) ? "Pause timer" : "Start timer", key: " ") { [weak store] in store?.toggleTimer(id) })
                if !task.isClosed {
                    menu.addItem(item("Start, pausing all others", key: " ", modifiers: .option) { [weak store] in
                        store?.startTimerExclusively(id)
                    })
                }
            }
            if !task.isClosed {
                let pinned = store.isInFocus(task)
                menu.addItem(item(pinned ? "Remove from Today" : "Add to Today", key: "t", modifiers: .command) { [weak model, weak store] in
                    if let model, let store { model.toggleToday([id], store: store) }
                })
                if model.scope.isToday, store.isOverdue(task) || store.isDueToday(task) || pinned {
                    menu.addItem(item("Move to tomorrow") { [weak model, weak store] in
                        if let model, let store { model.moveToDay([id], .tomorrow, store: store) }
                    })
                }
            }
        }
        let allDone = ids.compactMap { store.task($0) }.allSatisfy { $0.statusCategory == .done }
        menu.addItem(item(allDone ? "Reopen" : "Mark done", key: "x") { [weak store, weak model] in
            guard let store, let model else { return }
            let before = store.lastUndoId
            let done = store.toggleDone(ids)
            if store.lastUndoId != before {
                let subject = ids.count == 1 ? "Task" : TaskStore.taskCount(ids.count)
                model.showUndoToast(done ? "\(subject) marked done" : "\(subject) reopened", store: store)
            }
        })
        menu.addItem(.separator())

        for action in TaskQuickAction.allCases {
            if action == .project, store.projects.count < 2 { continue }
            if action == .sprint, task.sprintSlot == .closed, !selection { continue }
            let title = action == .timeSpent ? "Adjust time…" : action.title + "…"
            let modifiers: NSEvent.ModifierFlags = action == .project ? .shift : []
            menu.addItem(item(title, key: action.menuKeyEquivalent.lowercased(), modifiers: modifiers) { [weak model, weak store] in
                guard let model, let store else { return }
                // After the menu has closed, so the picker can take the keyboard
                DispatchQueue.main.async { model.presentQuickPicker(action, ids: ids, store: store) }
            })
        }
        menu.addItem(.separator())
        if !selection {
            menu.addItem(item("Duplicate", key: "d", modifiers: .command) { [weak model, weak store] in
                if let model, let store { model.duplicateTask(id, store: store) }
            })
            menu.addItem(item("Delete task", key: "\u{8}", modifiers: .command) { [weak model, weak store] in
                if let model, let store { model.deleteTask(id, store: store) }
            })
        }
        return menu
    }

    /// A menu item that runs a closure, showing `key` (with `modifiers`) as its shortcut.
    private func item(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], checked: Bool = false,
                      enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, modifiers: modifiers, handler: action)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }
}

/// A menu item that runs a closure. Its key equivalent is shown in the menu (and works while the
/// menu is open); the same key works on the selection once it's closed.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", modifiers: NSEvent.ModifierFlags = [], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

/// An editor popover's content that always shows the task as it is now.
private struct LiveTaskEditor: View {
    @EnvironmentObject private var store: TaskStore
    let taskId: UUID
    let content: (TaskItem) -> AnyView

    var body: some View {
        if let task = store.task(taskId) { content(task) }
    }
}
