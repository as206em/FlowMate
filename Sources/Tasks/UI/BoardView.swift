import AppKit
import SwiftUI

/// One column per status of the project's workflow (its colors, in its order), or in All
/// projects one per category (Canceled only while a card is canceled), of active-sprint cards
/// narrowed and sorted by the filter bar. Drag a card to another column to change its status, or
/// onto a card to place it before that card (in manual order; when sorted, a drop only changes the
/// status). Columns share the width; when they'd get narrower than `minColumnWidth` the board
/// scrolls sideways instead.
struct BoardView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    static let minColumnWidth: CGFloat = 200
    static let columnSpacing: CGFloat = 16

    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let columns = model.boardColumns(store)
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
            let needed = CGFloat(columns.count) * Self.minColumnWidth + CGFloat(max(0, columns.count - 1)) * Self.columnSpacing
            Group {
                if availableWidth == 0 || needed <= availableWidth {
                    row(columns, width: nil)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        row(columns, width: Self.minColumnWidth).padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { availableWidth = $0 }
            })
        }
    }

    private func row(_ columns: [TaskGroupValue], width: CGFloat?) -> some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            ForEach(columns, id: \.key) { value in
                column(value, isDefault: value == columns.first)
                    .frame(width: width)
                    .frame(maxWidth: width == nil ? .infinity : width, alignment: .top)
                    .zIndex(model.activeComposer == Self.composerKey(value) ? 1 : 0)
            }
        }
    }

    static func composerKey(_ column: TaskGroupValue) -> String { TasksViewModel.boardComposerKey(column) }

    private func column(_ value: TaskGroupValue, isDefault: Bool) -> some View {
        let tasks = model.boardTasks(store, column: value)
        let manual = model.sort.isManual
        let key = "board-\(value.key)"
        let targeted = model.dropTarget == key
        let title = value.statusTitle
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                value.statusIcon(size: 15)
                Text(title).font(Focus.groupTitle).foregroundColor(Focus.text).lineLimit(1)
                Text("\(tasks.count)").font(Focus.row.monospacedDigit()).foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                // ⌘N opens it here, above the cards, so it's on screen however long the column is
                if model.isComposerPinned(Self.composerKey(value)) {
                    TaskComposer(key: Self.composerKey(value), preset: value, isDefault: isDefault, groupName: title, onBoard: true)
                        .id(Self.composerKey(value))
                }
                ForEach(tasks) { task in
                    TaskCard(task: task, showProject: model.scope.projectId == nil, showMilestone: !model.scope.isMilestone)
                        .id(task.id)
                        .taskDraggable(task, model: model)
                        .onDrop(of: [.plainText], delegate: TaskDropDelegate(target: key, model: model) { id in
                            guard id != task.id else { return }
                            drop(id, on: value, before: task.id, reorder: manual)
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
                if !model.isComposerPinned(Self.composerKey(value)) {
                    TaskComposer(key: Self.composerKey(value), preset: value, isDefault: isDefault, groupName: title, onBoard: true)
                }
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
            drop(id, on: value, before: nil, reorder: manual)
        })
    }

    private func drop(_ id: UUID, on value: TaskGroupValue, before: UUID?, reorder: Bool) {
        switch value {
        case let .status(status): store.moveTask(id, toStatus: status, before: before, reorder: reorder)
        case let .category(category): store.moveTask(id, toCategory: category, before: before, reorder: reorder)
        default: break
        }
    }
}

extension TaskGroupValue {
    /// The heading of a status or category column or group ("Review", "Started")
    var statusTitle: String {
        switch self {
        case let .status(status): return status.name
        case let .category(category): return category.title
        default: return ""
        }
    }

    /// Its status icon, in the status's color (a category uses its signal color)
    @ViewBuilder
    func statusIcon(size: CGFloat) -> some View {
        switch self {
        case let .status(status): WorkflowStatusIcon(status: status, size: size)
        case let .category(category): FocusStatusIcon(kind: category.focusKind, size: size)
        default: EmptyView()
        }
    }
}

/// A board card: project/milestone line with priority, title, then due, subtasks, time and the ring.
struct TaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem
    let showProject: Bool
    var showMilestone = true

    @State private var hovering = false

    var body: some View {
        let running = store.isRunning(task.id)
        let selected = model.isSelected(task.id)
        let flashing = model.flashTaskId == task.id
        let project = store.project(of: task)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let project {
                    FocusProjectTile(project: project)
                }
                if showProject, let project {
                    Text(project.name)
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Text("·").font(.system(size: 12)).foregroundColor(Focus.text3)
                }
                // Click to set the milestone. Without one the chip waits for the pointer; on a
                // milestone's page every card has the same one, so it's left out.
                if showMilestone, task.milestoneId != nil || hovering {
                    TaskMilestoneChip(task: task)
                        .padding(.leading, showProject ? -2 : -3)
                }
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
                if !task.isClosed {
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
                // Just added from the composer at the top
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.justAdded).opacity(flashing ? 1 : 0))
                .animation(.easeOut(duration: 0.6), value: flashing)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusCard)
                // The keyboard selection shows even on a running card
                .strokeBorder(selected ? Focus.text3 : (running ? Focus.liveGlow : (hovering ? Focus.lineStrong : Focus.hairline)),
                              lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Focus.radiusCard))
        .quickPickerAnchor(.task(task.id))
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
