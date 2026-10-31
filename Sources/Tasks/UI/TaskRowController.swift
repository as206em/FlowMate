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
            store.toggleTimer(id)
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

    func makeMenu(task id: UUID, rename: @escaping () -> Void) -> NSMenu? {
        guard let store, let model, let task = store.task(id) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false

        if model.isMultiSelecting, model.isSelected(id) {
            let count = model.selectedTaskIds.count
            let header = NSMenuItem(title: "\(count) tasks selected", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(item("Duplicate \(count) tasks") { [weak model, weak store] in
                if let model, let store { model.duplicateSelected(store) }
            })
            menu.addItem(item("Delete \(count) tasks") { [weak model, weak store] in
                if let model, let store { model.deleteSelected(store) }
            })
            let ids = model.selectedIds(store)
            let allPinned = ids.compactMap { store.task($0) }.allSatisfy { store.isInFocus($0) }
            menu.addItem(item(allPinned ? "Remove \(count) tasks from Today" : "Add \(count) tasks to Today") { [weak model, weak store] in
                if let model, let store { model.toggleToday(ids, store: store) }
            })
            menu.addItem(.separator())
        }

        menu.addItem(item("Open") { [weak model] in model?.openTask(id) })
        menu.addItem(item("Rename", action: rename))
        if !task.isClosed || store.isRunning(id) {
            menu.addItem(item(store.isRunning(id) ? "Pause timer" : "Start timer") { [weak store] in store?.toggleTimer(id) })
        }
        if !task.isClosed {
            let pinned = store.isInFocus(task)
            let today = item(pinned ? "Remove from Today" : "Add to Today") { [weak model, weak store] in
                if let model, let store { model.toggleToday([id], store: store) }
            }
            today.keyEquivalent = "t"
            today.keyEquivalentModifierMask = .command
            menu.addItem(today)
            if model.scope.isToday, store.isOverdue(task) || store.isDueToday(task) || pinned {
                menu.addItem(item("Move to tomorrow") { [weak model, weak store] in
                    if let model, let store { model.moveToDay([id], .tomorrow, store: store) }
                })
            }
        }
        menu.addItem(.separator())

        let workflow = store.project(task.projectId)?.statuses ?? []
        menu.addItem(submenu("Status", workflow.map { status in
            item(status.name, checked: status.id == task.statusId) { [weak store] in store?.setStatus(id, status) }
        }))
        menu.addItem(submenu("Priority", TaskPriority.ordered.map { priority in
            item(priority.title, checked: priority == task.priority) { [weak store] in store?.setPriority(id, priority) }
        }))

        var milestoneItems = [item("No milestone", checked: task.milestoneId == nil) { [weak store] in store?.setMilestone(id, nil) }]
        let milestones = store.milestones(of: task.projectId).filter { !$0.isCompleted || $0.id == task.milestoneId }
        if !milestones.isEmpty { milestoneItems.append(.separator()) }
        milestoneItems += milestones.map { milestone in
            item(milestone.name, checked: milestone.id == task.milestoneId) { [weak store] in store?.setMilestone(id, milestone.id) }
        }
        menu.addItem(submenu("Milestone", milestoneItems))

        menu.addItem(submenu("Sprint", SprintSlot.plannable.map { slot in
            item(store.sprintLabel(slot, projectId: task.projectId), checked: slot == task.sprintSlot) { [weak store] in
                store?.setSprintSlot(id, slot)
            }
        }))

        var dueItems = DuePreset.allCases.map { preset in
            item(preset.title) { [weak store] in store?.setDueDate(id, preset.date()) }
        }
        if task.dueDate != nil {
            dueItems.append(.separator())
            dueItems.append(item("Clear") { [weak store] in store?.setDueDate(id, nil) })
        }
        menu.addItem(submenu("Due date", dueItems))

        if store.projects.count > 1 {
            menu.addItem(submenu("Move to project", store.projects.map { project in
                item(project.name, enabled: project.id != task.projectId) { [weak store] in store?.setProject(id, project.id) }
            }))
        }
        menu.addItem(item("Adjust time…") { [weak model] in model?.adjustingTimeTaskId = id })
        menu.addItem(.separator())
        menu.addItem(item("Duplicate") { [weak model, weak store] in
            if let model, let store { model.duplicateTask(id, store: store) }
        })
        menu.addItem(item("Delete task") { [weak model, weak store] in
            if let model, let store { model.deleteTask(id, store: store) }
        })
        return menu
    }

    private func item(_ title: String, checked: Bool = false, enabled: Bool = true,
                      action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
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
