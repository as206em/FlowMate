import SwiftUI
import UniformTypeIdentifiers

// Small pieces shared by the board cards, list rows and the sidebar.

/// Re-renders its content every second while a timer runs. Wrap only the parts that show live time.
struct LiveTime<Content: View>: View {
    @EnvironmentObject private var store: TaskStore
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TickerReader(ticker: store.ticker, content: content)
    }

    private struct TickerReader: View {
        @ObservedObject var ticker: TimerTicker
        let content: (Date) -> Content
        var body: some View { content(ticker.now) }
    }
}

/// The task's play/pause ring, filling toward its expected time.
struct TaskTimerButton: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var size: CGFloat = 32

    var body: some View {
        LiveTime { now in
            FocusTimerRing(
                progress: store.progress(task, now: now),
                isRunning: store.isRunning(task.id),
                size: size,
                label: task.title
            ) {
                store.toggleTimer(task.id)
            }
        }
    }
}

/// Live clock while running, otherwise the estimate ("2h 30m").
struct TaskTimeText: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var font: Font = .system(size: 12.5)

    var body: some View {
        LiveTime { now in
            if store.isRunning(task.id) {
                Text(Focus.clockString(store.elapsed(task, now: now)))
                    .font(font.weight(.semibold).monospacedDigit())
                    .foregroundColor(Focus.liveText)
            } else {
                Text(Focus.durationString(minutes: task.expectedMinutes))
                    .font(font.monospacedDigit())
                    .foregroundColor(Focus.text3)
            }
        }
        .lineLimit(1)
    }
}

/// Due date tag; red when overdue or due today. Hidden for done tasks.
struct TaskDueTag: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var showIcon = true

    var body: some View {
        if let due = task.dueDate, !task.isClosed {
            FocusTag(
                text: TaskDates.dueLabel(due),
                systemImage: showIcon ? "calendar" : nil,
                risk: store.isOverdue(task) || store.isDueToday(task)
            )
        }
    }
}

/// "✓ 2/4" subtask count
struct SubtaskCount: View {
    let task: TaskItem

    var body: some View {
        if let summary = task.subtaskSummary {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                Text(summary).monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundColor(Focus.text3)
            .fixedSize()
            .accessibilityLabel("\(task.subtasksDone) of \(task.subtasks.count) subtasks done")
        }
    }
}

/// A workflow status's icon: its category's shape in its own color.
struct WorkflowStatusIcon: View {
    let status: WorkflowStatus
    var size: CGFloat = 16

    var body: some View {
        FocusStatusIcon(kind: status.category.focusKind, color: Color(hex: status.colorHex), size: size)
    }
}

/// The status icon as a button. A click moves to the next status of the project's workflow
/// (wrapping around); right-click picks any status.
struct TaskStatusButton: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    var body: some View {
        let status = store.status(of: task)
        let next = store.project(task.projectId)?.statusAfter(status.id).name ?? ""
        Button {
            store.cycleStatus(task.id)
        } label: {
            WorkflowStatusIcon(status: status)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(status.name). Click for \(next), right-click for all")
        .contextMenu { TaskStatusMenuItems(task: task) }
        .accessibilityLabel("Status: \(status.name)")
        .accessibilityHint("Changes the status to \(next)")
    }
}

/// The project's statuses as menu items, in workflow order, with a check on the current one.
struct TaskStatusMenuItems: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    var body: some View {
        ForEach(store.project(task.projectId)?.statuses ?? []) { status in
            Button {
                store.setStatus(task.id, status)
            } label: {
                if status.id == task.statusId {
                    Label(status.name, systemImage: "checkmark")
                } else {
                    Text(status.name)
                }
            }
        }
    }
}

/// Task title that opens the side panel. Regular weight, medium while its timer runs.
/// No underline on hover: the row's hover fill and a pointing-hand cursor show it's clickable.
/// With `rename`, a double-click renames in place. The first click opens at once (no waiting for a second).
struct TaskTitleButton: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var multiline = false
    /// nil: Focus.row, or Focus.rowStrong while running
    var font: Font?
    var rename: (() -> Void)?
    let open: () -> Void

    var body: some View {
        if let rename {
            title
                // One single-tap gesture, so the click opens immediately; the second click of a
                // double-click arrives with clickCount 2 and renames instead
                .onTapGesture {
                    if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { rename() } else { open() }
                }
                .focusPointerCursor()
                .help("Click to open, double-click to rename")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(task.title)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Open", open)
                .accessibilityAction(named: "Rename", rename)
        } else {
            Button(action: open) { title }
                .buttonStyle(.plain)
                .focusPointerCursor()
                .accessibilityLabel("Open \(task.title)")
        }
    }

    private var title: some View {
        Text(task.title)
            .font(font ?? (store.isRunning(task.id) ? Focus.rowStrong : Focus.row))
            .foregroundColor(task.isClosed ? Focus.text3 : Focus.text)
            .strikethrough(task.isClosed, color: Focus.text3)
            .lineLimit(multiline ? nil : 1)
            .lineSpacing(multiline ? 2 : 0)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: multiline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// Right-click actions for a task row or card.
struct TaskContextMenu: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem
    /// Shown by list rows, which can rename in place
    var rename: (() -> Void)?

    var body: some View {
        if model.isMultiSelecting, model.isSelected(task.id) {
            let count = model.selectedTaskIds.count
            Text("\(count) tasks selected")
            Button("Duplicate \(count) tasks") { model.duplicateSelected(store) }
            Button("Delete \(count) tasks") { model.deleteSelected(store) }
            Divider()
        }
        Button("Open") { model.openTask(task.id) }
        if let rename {
            Button("Rename", action: rename)
        }
        if !task.isClosed || store.isRunning(task.id) {
            Button(store.isRunning(task.id) ? "Pause timer" : "Start timer") { store.toggleTimer(task.id) }
        }
        Divider()
        Menu("Status") { TaskStatusMenuItems(task: task) }
        Menu("Priority") {
            ForEach(TaskPriority.ordered) { priority in
                Button {
                    store.setPriority(task.id, priority)
                } label: {
                    if priority == task.priority { Label(priority.title, systemImage: "checkmark") } else { Text(priority.title) }
                }
            }
        }
        Menu("Milestone") { TaskMilestoneMenuItems(task: task) }
        Menu("Sprint") {
            ForEach(SprintSlot.plannable) { slot in
                let title = store.sprintLabel(slot, projectId: task.projectId)
                Button {
                    store.setSprintSlot(task.id, slot)
                } label: {
                    if slot == task.sprintSlot { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        }
        Menu("Due date") {
            ForEach(DuePreset.allCases) { preset in
                Button(preset.title) { store.setDueDate(task.id, preset.date()) }
            }
            if task.dueDate != nil {
                Divider()
                Button("Clear") { store.setDueDate(task.id, nil) }
            }
        }
        if store.projects.count > 1 {
            Menu("Move to project") {
                ForEach(store.projects) { project in
                    Button(project.name) { store.setProject(task.id, project.id) }
                        .disabled(project.id == task.projectId)
                }
            }
        }
        Button("Adjust time…") { model.adjustingTimeTaskId = task.id }
        Divider()
        // ⌘D and ⌘⌫ are handled by TasksKeyMonitor for the selected task
        Button("Duplicate") { model.duplicateTask(task.id, store: store) }
        Button("Delete task") { model.deleteTask(task.id, store: store) }
    }
}

// MARK: - Drag and drop

extension View {
    /// Makes a task row or card draggable. The id travels as plain text; the model remembers it too.
    func taskDraggable(_ task: TaskItem, model: TasksViewModel) -> some View {
        onDrag {
            model.draggingTaskId = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
    }
}

/// Drop handling shared by board columns, sprint groups and the rows inside them.
struct TaskDropDelegate: DropDelegate {
    /// Outline key for the container this drop belongs to
    let target: String
    let model: TasksViewModel
    let perform: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        model.dropTarget = target
    }

    func dropExited(info: DropInfo) {
        if model.dropTarget == target { model.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.dropTarget = nil
        // The dragged item is the source of truth; `draggingTaskId` can be stale after a cancelled drag.
        model.draggingTaskId = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String,
                  let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            DispatchQueue.main.async { perform(id) }
        }
        return true
    }
}
