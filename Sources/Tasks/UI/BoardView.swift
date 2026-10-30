import AppKit
import SwiftUI

/// Three status columns of active-sprint cards, narrowed and sorted by the filter bar.
/// Drag a card to another column to change its status, or onto a card to place it before that card
/// (in manual order; when sorted, a drop only changes the status).
struct BoardView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Columns stay below as drop targets; this says why they're empty
            if let reason = model.boardEmptyReason(store) {
                TasksEmptyStateView(reason: reason, board: true)
            } else if let caption = model.boardCaption(store) {
                // Board shows only the active sprint; say what it leaves out
                HStack(spacing: 4) {
                    Text(caption)
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                        .lineLimit(1)
                    if let projectId = model.scope.projectId, model.boardWaitingCount(store) > 0 {
                        FocusCrumb(text: "Plan in Sprints", help: "Open the Sprints view") {
                            model.showSprints(of: projectId)
                        }
                    }
                }
                .padding(.top, -8)
                .padding(.bottom, -6)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.ordered) { status in
                    column(status)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .zIndex(model.activeComposer == Self.composerKey(status) ? 1 : 0)
                }
            }
        }
    }

    static func composerKey(_ status: TaskStatus) -> String { "composer-board-\(status.rawValue)" }

    private func column(_ status: TaskStatus) -> some View {
        let tasks = model.boardTasks(store, status: status)
        let manual = model.sort.isManual
        let key = "board-\(status.rawValue)"
        let targeted = model.dropTarget == key
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FocusStatusIcon(kind: status.focusKind, size: 15)
                Text(status.title).font(Focus.groupTitle).foregroundColor(Focus.text)
                Text("\(tasks.count)").font(Focus.row.monospacedDigit()).foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    TaskCard(task: task, showProject: model.scope.projectId == nil)
                        .id(task.id)
                        .taskDraggable(task, model: model)
                        .onDrop(of: [.plainText], delegate: TaskDropDelegate(target: key, model: model) { id in
                            guard id != task.id else { return }
                            store.moveTask(id, toStatus: status, before: task.id, reorder: manual)
                        })
                }
                if tasks.isEmpty {
                    Text(model.filter.isEmpty ? "Drop a task here" : "No matching tasks")
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: Focus.radiusCard)
                                .strokeBorder(Focus.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                }
                TaskComposer(key: Self.composerKey(status), preset: .status(status), isDefault: status == .todo, groupName: status.title)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(minHeight: 520, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Focus.radiusPanel)
                .fill(targeted ? Focus.hover : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusPanel)
                .strokeBorder(targeted ? Focus.text3 : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], delegate: TaskDropDelegate(target: key, model: model) { id in
            store.moveTask(id, toStatus: status, reorder: manual)
        })
    }
}

/// A board card: project/milestone line with priority, title, then due, subtasks, time and the ring.
struct TaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem
    let showProject: Bool

    @State private var hovering = false

    var body: some View {
        let running = store.isRunning(task.id)
        let selected = model.isSelected(task.id)
        let project = store.project(of: task)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let project {
                    FocusProjectTile(name: project.name, colorHex: project.colorHex)
                }
                if showProject, let project {
                    Text(project.name)
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Text("·").font(.system(size: 12)).foregroundColor(Focus.text3)
                }
                // Click to set the milestone
                TaskMilestoneChip(task: task)
                    .padding(.leading, showProject ? -4 : -5)
                Spacer(minLength: 0)
                FocusPriorityBars(level: task.priority.focusLevel)
                    .accessibilityLabel("\(task.priority.title) priority")
            }
            TaskTitleButton(task: task, multiline: true) { model.clickTitle(task.id, store: store) }
            HStack(spacing: 8) {
                TaskDueTag(task: task, showIcon: false)
                SubtaskCount(task: task)
                TaskTimeText(task: task, font: .system(size: 12))
                Spacer(minLength: 0)
                if !task.isDone {
                    TaskTimerButton(task: task, size: 28)
                }
            }
            .frame(minHeight: 28)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Focus.radiusCard)
                .fill(Focus.raised)
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(running ? Focus.liveSoft : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusCard)
                // The keyboard selection shows even on a running card
                .strokeBorder(selected ? Focus.text3 : (running ? Focus.liveGlow : (hovering ? Focus.lineStrong : Focus.hairline)),
                              lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Focus.radiusCard))
        .onHover { hovering = $0 }
        // One gesture, so a single click selects at once instead of waiting out the double-click time
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                model.openTask(task.id)
            } else {
                model.selectByClick(task.id, store: store)
            }
        }
        .contextMenu { TaskContextMenu(task: task) }
    }
}
