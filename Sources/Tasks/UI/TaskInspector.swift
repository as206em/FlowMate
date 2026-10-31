import AppKit
import SwiftUI

/// The 320pt right column of the task panel: the large timer ring and the task's properties.
struct TaskInspector: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    var body: some View {
        SidePanelInspector {
                timer
                VStack(spacing: 6) {
                    property("Status", key: "S") { statusPicker }
                    property("Priority", key: "P, or 1–3") { priorityPicker }
                    property("Milestone", key: "M") { milestonePicker }
                    if store.usesSprints(task.projectId) || task.sprintSlot == .closed {
                        property("Sprint", key: "R") { sprintPicker }
                    }
                    property("Due date", key: "D") { TaskDueDateField(task: task) }
                    if !task.isClosed {
                        property("Today") { TaskTodayField(task: task) }
                    }
                    property("Expected", key: "E") { expectedPicker }
                    property("Labels", key: "L") { TaskLabelsField(task: task) }
                    property("Project") { projectPicker }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { FocusDivider() }

                TaskDatesSection(task: task)

                HStack(spacing: 4) {
                    Button {
                        model.duplicateTask(task.id, store: store)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.focus(.ghost))
                    .help("Copy this task with its subtasks unchecked (⌘D)")
                    Button(role: .destructive) {
                        model.deleteTask(task.id, store: store)
                    } label: {
                        Label("Delete task", systemImage: "trash")
                            .foregroundColor(Focus.risk)
                    }
                    .buttonStyle(.focus(.ghost))
                    .help("Delete this task (⌘⌫). Undo brings it back.")
                }
        }
    }

    // MARK: Timer

    private var timer: some View {
        LiveTime { now in
            let running = store.isRunning(task.id)
            let others = store.runningTasks.filter { $0.id != task.id }.count
            VStack(spacing: 14) {
                FocusLargeTimerRing(
                    progress: store.progress(task, now: now),
                    isRunning: running,
                    clock: Focus.clockString(store.elapsed(task, now: now)),
                    caption: "of \(Focus.durationString(minutes: task.expectedMinutes)) expected"
                ) {
                    if NSEvent.modifierFlags.contains(.option) {
                        store.startTimerExclusively(task.id)
                    } else {
                        store.toggleTimer(task.id)
                    }
                }
                .help(running ? "Pause timer (Space)" : "Start timer (Space). ⌥-click or ⌥Space pauses every other timer.")
                HStack(spacing: 6) {
                    Text(running ? "Click the timer to pause" : "Click the timer to start")
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                    Text("·").font(.system(size: 12)).foregroundColor(Focus.text3)
                    AdjustTimeButton(task: task)
                }
                .padding(.top, -4)
                if others > 0 {
                    Text("\(others) other \(others == 1 ? "task is" : "tasks are") running too. Timers never stop each other.")
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Properties

    private func property<Content: View>(_ label: String, key: String? = nil,
                                         @ViewBuilder content: @escaping () -> Content) -> some View {
        SidePanelProperty(label: label, content: content)
            .help(key.map { "\(label): press \($0) to change it from the keyboard" } ?? "")
    }

    private var statusPicker: some View {
        FocusTintedPicker(
            options: store.project(task.projectId)?.statuses ?? [store.status(of: task)],
            selection: Binding(get: { store.status(of: task) }, set: { store.setStatus(task.id, $0) }),
            title: { $0.name },
            tint: { Focus.statusTint($0.colorHex) },
            icon: { WorkflowStatusIcon(status: $0, size: 15) },
            accessibilityName: "Status"
        )
    }

    private var priorityPicker: some View {
        FocusTintedPicker(
            options: TaskPriority.ordered,
            selection: Binding(get: { task.priority }, set: { store.setPriority(task.id, $0) }),
            title: { $0.title },
            tint: { $0.focusLevel.tint },
            icon: { FocusPriorityBars(level: $0.focusLevel) },
            accessibilityName: "Priority"
        )
    }

    private var milestonePicker: some View {
        let ids: [UUID?] = [nil] + store.milestones(of: task.projectId)
            .filter { !$0.isCompleted || $0.id == task.milestoneId }.map(\.id)
        return FocusPicker(
            options: ids,
            selection: Binding(get: { task.milestoneId }, set: { store.setMilestone(task.id, $0) }),
            title: { id in id.flatMap { store.milestone($0)?.name } ?? "None" }
        )
        .accessibilityLabel("Milestone")
    }

    /// Moves the task to another project. Its milestone is cleared; the hint says so.
    private var projectPicker: some View {
        FocusPicker(
            options: store.projects.map(\.id) + (store.isArchived(task.projectId) ? [task.projectId] : []),
            selection: Binding(get: { task.projectId }, set: { store.setProject(task.id, $0) }),
            title: { store.project($0)?.name ?? "" }
        )
        .help(task.milestoneId == nil ? "Move to another project (⇧M)" : "Move to another project (⇧M). The milestone is cleared.")
        .accessibilityLabel("Project")
    }

    private var sprintPicker: some View {
        // A closed task keeps showing its slot so the picker never lies
        let slots = task.sprintSlot == .closed ? SprintSlot.plannable + [.closed] : SprintSlot.plannable
        return FocusPicker(
            options: slots,
            selection: Binding(get: { task.sprintSlot }, set: { store.setSprintSlot(task.id, $0) }),
            title: { slot in
                let name = store.sprintLabel(slot, projectId: task.projectId)
                switch slot {
                case .active: return "\(name) (active)"
                case .next: return "\(name) (next)"
                case .backlog, .closed: return name
                }
            }
        )
        .accessibilityLabel("Sprint")
    }

    /// Presets and a custom entry ("1h 15m") in a popover.
    private var expectedPicker: some View {
        TaskExpectedField(task: task)
    }
}

/// The task's due date field; it turns red when overdue or due today.
private struct TaskDueDateField: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    var body: some View {
        DateField(
            date: task.dueDate,
            risk: store.isOverdue(task) || store.isDueToday(task),
            accessibilityName: "Due date"
        ) { store.setDueDate(task.id, $0) }
    }
}

/// Field-sized toggle: "Add to Today" (⌘T), or "In Today" (with "From yesterday" when it was
/// pinned on an earlier day) and an × that removes it.
private struct TaskTodayField: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    @State private var hovering = false

    var body: some View {
        let pinned = store.isInFocus(task)
        Button { model.toggleToday([task.id], store: store) } label: {
            HStack(spacing: 7) {
                Image(systemName: pinned ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(pinned ? Focus.progress : Focus.text3)
                Text(pinned ? "In Today" : "Add to Today")
                    .font(Focus.control)
                    .foregroundColor(pinned ? Focus.text : Focus.text2)
                if pinned, let carried = store.focusCarryLabel(task) {
                    Text(carried).font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if pinned {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(hovering ? Focus.text : Focus.text3)
                } else {
                    FocusKey(text: "⌘T")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusField(focused: hovering)
        .onHover { hovering = $0 }
        .help(pinned ? "Remove from Today (⌘T)" : "Pin to Today: it shows under My focus until it's done (⌘T)")
        .accessibilityLabel(pinned ? "In Today. Remove from Today" : "Add to Today")
    }
}

/// Field-sized button with the expected time; opens the presets and the custom entry.
private struct TaskExpectedField: View {
    let task: TaskItem

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 7) {
                Text(Focus.durationString(minutes: task.expectedMinutes))
                    .font(Focus.control.monospacedDigit())
                    .foregroundColor(Focus.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Focus.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusField(focused: hovering || open)
        .onHover { hovering = $0 }
        .accessibilityLabel("Expected time: \(Focus.durationString(minutes: task.expectedMinutes))")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TaskExpectedEditor(task: task) { open = false }
        }
    }
}

/// "Adjust time" under the large ring: fix the time spent (a forgotten timer).
private struct AdjustTimeButton: View {
    let task: TaskItem

    @State private var open = false

    var body: some View {
        Button("Adjust time") { open = true }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Focus.text2)
            .focusPointerCursor()
            .help("Fix the time spent, e.g. after a forgotten timer")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                FocusPopoverMenu(width: 260) {
                    FocusMenuSection(title: "Time spent", first: true)
                    TaskTimeSpentEditor(task: task, autofocus: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
    }
}
