import SwiftUI

// The milestone page: a milestone's tasks on Board and List (TaskScope.milestone), opened from the
// sidebar, the Milestones tab, a panel's Show tasks or the menu bar search.
//
//   TasksHeader          → MilestoneHeaderTitle: project › ◆ milestone, then the tabs
//   MilestonePageHeader  → due date, progress, time tracked vs expected, Mark complete, ⓘ

/// The header's title on a milestone page: the project (a click shows it), then the milestone's
/// diamond and name (a click opens its panel).
struct MilestoneHeaderTitle: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestone: Milestone

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let project = store.project(milestone.projectId) {
                FocusProjectTile(name: project.name, colorHex: project.colorHex)
                FocusCrumb(text: project.name, help: "Show \(project.name)") { model.select(.project(project.id)) }
                FocusCrumbSeparator()
            }
            Button { model.openMilestone(milestone.id) } label: {
                HStack(spacing: 7) {
                    MilestoneIcon(milestone, size: 12)
                    Text(milestone.name)
                        .font(Focus.header)
                        .foregroundColor(milestone.isCompleted ? Focus.text3 : Focus.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(height: Focus.controlHeight)
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .focusPointerCursor()
            .help("Milestone details")
            .accessibilityLabel("\(milestone.name), milestone details")
            if milestone.isCompleted { FocusTag(text: "Completed", systemImage: "checkmark") }
        }
        .layoutPriority(-1)
    }
}

/// The line under the header on a milestone page: due date (click to change), "6 of 11 done" with
/// a bar, the time tracked against the time expected, Mark complete (Reopen) and ⓘ for the panel.
struct MilestonePageHeader: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestone: Milestone

    @State private var editingDue = false

    var body: some View {
        let progress = store.milestoneProgress(milestone.id)
        let overdue = store.isOverdue(milestone)
        HStack(spacing: 14) {
            FocusCellButton(help: "Change due date", action: { editingDue = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                    Text(milestone.dueDate.map { "Due " + TaskDates.dueLabel($0) } ?? "No due date")
                        .font(Focus.body)
                }
                .foregroundColor(overdue ? Focus.risk : (milestone.dueDate == nil ? Focus.text3 : Focus.text2))
                .fixedSize()
            }
            .fixedSize()
            .popover(isPresented: $editingDue, arrowEdge: .bottom) {
                DateEditor(date: milestone.dueDate, set: { store.setMilestoneDue(milestone.id, to: $0) },
                           close: { editingDue = false })
            }
            .accessibilityLabel("Due date: \(milestone.dueDate.map { TaskDates.dueLabel($0) } ?? "none")")

            separator

            HStack(spacing: 8) {
                FocusProgressBar(fraction: progress.fraction).frame(width: 96)
                Text(progress.total == 0 ? "No tasks yet" : "\(progress.done) of \(progress.total) done")
                    .font(Focus.body.monospacedDigit())
                    .foregroundColor(Focus.text2)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(progress.label)

            separator

            LiveTime { now in
                let time = store.milestoneTime(milestone.id, now: now)
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
                    Text(timeText(tracked: time.tracked, expectedMinutes: time.expectedMinutes))
                        .font(Focus.body.monospacedDigit())
                }
                .foregroundColor(time.tracked / 60 > Double(time.expectedMinutes) && time.expectedMinutes > 0 ? Focus.progress : Focus.text2)
                .fixedSize()
                .help("Time tracked on this milestone's tasks, and the time they're expected to take")
            }

            Spacer(minLength: 12)

            if milestone.isCompleted {
                Button {
                    store.reopenMilestone(milestone.id)
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.focus())
            } else {
                Button {
                    store.completeMilestone(milestone.id)
                    model.showUndoToast("Milestone completed", store: store)
                } label: {
                    Label("Mark complete", systemImage: "checkmark.diamond")
                }
                .buttonStyle(.focus())
                .help(progress.done < progress.total ? "\(progress.total - progress.done) tasks aren't done yet" : "")
            }
            FocusIconButton(systemName: "info.circle", label: "Milestone details") { model.openMilestone(milestone.id) }
        }
        .padding(.horizontal, 28)
        .frame(height: 48)
        .overlay(alignment: .bottom) { FocusDivider() }
    }

    private var separator: some View {
        Rectangle().fill(Focus.hairline).frame(width: 1, height: 18)
    }

    /// "4h 10m tracked of 12h expected"
    private func timeText(tracked: TimeInterval, expectedMinutes: Int) -> String {
        let minutes = Int(tracked / 60)
        let spent = minutes == 0 ? "Nothing tracked" : Focus.durationString(minutes: minutes) + " tracked"
        guard expectedMinutes > 0 else { return spent }
        return spent + " of " + Focus.durationString(minutes: expectedMinutes) + " expected"
    }
}
