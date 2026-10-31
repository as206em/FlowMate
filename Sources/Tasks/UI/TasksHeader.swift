import AppKit
import SwiftUI

/// 54pt header: the project (or All projects) with the tabs (Board · List · Sprints · Milestones)
/// right after it. The New task composer has its own row under it (TaskComposer).
struct TasksHeader: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        let project = model.scope.projectId.flatMap { store.project($0) }
        let milestone = model.scope.milestoneId.flatMap { store.milestone($0) }
        HStack(spacing: 14) {
            if model.scope.isToday {
                TodayHeaderTitle()
            } else if let view = model.activeView(store) {
                SavedViewHeaderTitle(view: view)
            } else if let milestone {
                MilestoneHeaderTitle(milestone: milestone)
            } else if let project {
                ProjectTitleButton(project: project)
                if project.isArchived {
                    FocusTag(text: "Archived", systemImage: "archivebox")
                    Button("Unarchive") { model.unarchiveProject(project.id, store: store) }
                        .buttonStyle(.focus(.ghost))
                }
            } else {
                Text("All projects")
                    .font(Focus.header)
                    .foregroundColor(Focus.text)
                    .lineLimit(1)
                Text("\(store.projects.count) \(store.projects.count == 1 ? "project" : "projects")")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
            }
            if !model.tabs.isEmpty {
                FocusTabs(
                    options: model.tabs.map { (value: $0, label: $0.title) },
                    selection: Binding(get: { model.effectiveTab }, set: { model.tab = $0 })
                )
                .fixedSize()
                .padding(.leading, 4)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(height: 54)
        .overlay(alignment: .bottom) { FocusDivider() }
        .zIndex(1)
    }
}

/// The project's tile and name in the header; a click opens the project panel.
private struct ProjectTitleButton: View {
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var hovering = false

    var body: some View {
        Button { model.openProject(project.id) } label: {
            HStack(spacing: 10) {
                FocusProjectTile(project: project)
                Text(project.name)
                    .font(Focus.header)
                    .foregroundColor(Focus.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Focus.text3)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Focus.controlHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -6)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help("Project settings")
        .accessibilityLabel("\(project.name), project settings")
    }
}

/// Sprint line above Board and Sprints in project scope: name, dates (click to change the start and
/// length), goal (click to edit), the plan against capacity ("Planned 11h of 20h · tracked 6h",
/// amber near it, red over it), Complete sprint (opens CompleteSprintSheet).
struct SprintHeader: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var editingGoal = false
    @State private var goalDraft = ""
    @State private var editingDates = false
    @FocusState private var goalFocused: Bool

    var body: some View {
        let sprint = project.sprint
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Focus.text3)
            Text(sprint.name).font(Focus.groupTitle).foregroundColor(Focus.text)
            FocusCellButton(help: "Change sprint dates", action: { editingDates = true }) {
                Text(sprint.dateRange).font(Focus.body).foregroundColor(Focus.text3).fixedSize()
            }
            .fixedSize()
            .popover(isPresented: $editingDates, arrowEdge: .bottom) {
                SprintDatesEditor(project: project)
            }
            Text("·").foregroundColor(Focus.text2)
            if editingGoal {
                TextField(SprintState.goalPlaceholder, text: $goalDraft)
                    .focused($goalFocused)
                    .focusField(focused: true)
                    .frame(maxWidth: 420)
                    .onSubmit(commitGoal)
                    .onExitCommand { editingGoal = false }
                    .onChange(of: goalFocused) { focused in if !focused { commitGoal() } }
            } else {
                Button {
                    goalDraft = sprint.goal
                    editingGoal = true
                    DispatchQueue.main.async { goalFocused = true }
                } label: {
                    Text(sprint.displayGoal)
                        .font(Focus.body)
                        .foregroundColor(sprint.goal.isEmpty ? Focus.text3 : Focus.text2)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit sprint goal")
            }
            Spacer(minLength: 12)
            LiveTime { now in
                let line = store.sprintPlanLine(projectId: project.id, now: now)
                Text(line.text)
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(CapacityColors.color(line.level))
                    .lineLimit(1)
                    .fixedSize()
                    .help(project.weeklyCapacityHours == nil
                          ? "Expected time of the active sprint's tasks, and time tracked in its dates. Set hours per week in the project's settings to see the capacity."
                          : "Expected time of the active sprint's tasks against \(SprintPlanRules.hoursText(project.weeklyCapacityHours ?? 0)) a week, and time tracked in its dates")
            }
            Button("Complete sprint") { model.completingSprintProjectId = project.id }
                .buttonStyle(.focus())
        }
        .padding(.bottom, 20)
    }

    private func commitGoal() {
        guard editingGoal else { return }
        store.setSprintGoal(projectId: project.id, goal: goalDraft)
        editingGoal = false
    }
}

/// Popover: the active sprint's start date and length (1–4 weeks), and where that puts the end.
struct SprintDatesEditor: View {
    @EnvironmentObject private var store: TaskStore
    let project: Project

    var body: some View {
        let sprint = store.project(project.id)?.sprint ?? project.sprint
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                FocusCaption(text: "Length")
                FocusTabs(
                    options: SprintState.lengthChoices.map { (value: $0, label: SprintState.lengthLabel($0)) },
                    selection: Binding(get: { sprint.lengthWeeks }, set: { store.setSprintLength(projectId: project.id, weeks: $0) })
                )
                .fixedSize()
                FocusCaption(text: "Starts").padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            FocusCalendar(selection: sprint.startDate) { store.setSprintStart(projectId: project.id, date: $0) }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            FocusDivider()
            Text("\(sprint.name) runs \(sprint.dateRange). \(sprint.nextName) starts \(SprintState.shortDate(sprint.nextStartDate)).")
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
        .frame(width: 290)
        .background(Focus.raised)
        .focusLight()
    }
}

/// The Complete sprint dialog: what closes, what to do with unfinished tasks (next sprint, backlog
/// or keep them in the closing sprint), and the next sprint's goal. One undo step.
struct CompleteSprintSheet: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var unfinished: UnfinishedSprintTasks = .moveToNextSprint
    @State private var goal = ""
    @FocusState private var goalFocused: Bool

    var body: some View {
        let sprint = project.sprint
        let active = store.sprintTasks(projectId: project.id, slot: .active)
        let done = active.filter(\.isClosed).count
        let open = active.count - done
        let next = store.sprintTasks(projectId: project.id, slot: .next).count
        let velocity = store.recentVelocityMinutes(projectId: project.id, includingActive: true)
        let nextPlan = store.nextSprintPlanMinutes(projectId: project.id, unfinished: unfinished)
        let today = Calendar.current.startOfDay(for: Date())
        let newEnd = SprintState.day(today, adding: sprint.lengthInDays - 1)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Complete \(sprint.name)").font(Focus.pageTitle).foregroundColor(Focus.text)
                Text([sprint.dateRange, sprint.goal.isEmpty ? nil : sprint.goal].compactMap { $0 }.joined(separator: " · "))
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 4) {
                line(done == 0 ? "No done tasks to close." : "\(tasks(done)) marked done or canceled \(done == 1 ? "closes" : "close") with the sprint.")
                if next > 0 { line("\(tasks(next)) planned for \(sprint.nextName) \(next == 1 ? "moves" : "move") in.") }
            }

            if open > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    FocusCaption(text: "\(tasks(open)) not done").padding(.bottom, 2).padding(.leading, 10)
                    FocusChoiceRow(title: "Move to \(sprint.nextName)", hint: "They carry into the new sprint.",
                                   selected: unfinished == .moveToNextSprint) { unfinished = .moveToNextSprint }
                    FocusChoiceRow(title: "Move to the backlog", hint: "Plan them again later.",
                                   selected: unfinished == .moveToBacklog) { unfinished = .moveToBacklog }
                    FocusChoiceRow(title: "Keep them in \(sprint.name)", hint: "They close unfinished and stay in its history.",
                                   selected: unfinished == .keepInSprint) { unfinished = .keepInSprint }
                }
                .padding(.horizontal, -10)
            }

            planNote(velocity: velocity, nextPlan: nextPlan)

            FocusLabeled(
                label: "Goal for \(sprint.nextName)",
                hint: "\(sprint.nextName) starts today and runs to \(SprintState.shortDate(newEnd)) (\(sprint.lengthLabel))."
            ) {
                TextField(SprintState.goalPlaceholder, text: $goal)
                    .focused($goalFocused)
                    .focusField(focused: goalFocused)
                    .onSubmit(complete)
            }

            HStack(spacing: 8) {
                Text("You can undo this with ⌘Z.").font(.system(size: 12)).foregroundColor(Focus.text3)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.focus(.ghost))
                    .keyboardShortcut(.cancelAction)
                Button("Complete sprint", action: complete)
                    .buttonStyle(.focus())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Focus.canvas)
        .focusLight()
        .onAppear { DispatchQueue.main.async { goalFocused = true } }
    }

    /// "Recent velocity ~16h per sprint. Sprint 15 starts with 22h planned." with a warning when
    /// that's more than the velocity (or the capacity).
    @ViewBuilder
    private func planNote(velocity: Int?, nextPlan: Int) -> some View {
        let name = project.sprint.nextName
        let capacity = SprintPlanRules.capacityMinutes(weeklyHours: project.weeklyCapacityHours, weeks: project.sprint.lengthWeeks)
        let overVelocity = velocity.map { nextPlan > $0 } ?? false
        let overCapacity = capacity.map { nextPlan > $0 } ?? false
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: overVelocity || overCapacity ? "exclamationmark.triangle.fill" : "speedometer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(overVelocity || overCapacity ? Focus.progress : Focus.text3)
            VStack(alignment: .leading, spacing: 2) {
                Text(velocity.map { "Recent velocity ~\(Focus.durationString(minutes: $0)) per sprint." }
                     ?? "No velocity yet: it shows once a sprint has done tasks.")
                    .font(Focus.body).foregroundColor(Focus.text2)
                Text(planText(name: name, nextPlan: nextPlan, velocity: velocity, capacity: capacity,
                              overVelocity: overVelocity, overCapacity: overCapacity))
                    .font(Focus.meta)
                    .foregroundColor(overVelocity || overCapacity ? Color(hex: 0x8A5300) : Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(overVelocity || overCapacity ? Focus.progressTint.fill : Focus.sidebar))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(overVelocity || overCapacity ? Focus.progressTint.border : Focus.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func planText(name: String, nextPlan: Int, velocity: Int?, capacity: Int?, overVelocity: Bool, overCapacity: Bool) -> String {
        let plan = "\(name) starts with \(Focus.durationString(minutes: nextPlan)) planned"
        if overVelocity, let velocity {
            return plan + ", \(Focus.durationString(minutes: nextPlan - velocity)) more than you usually finish. Consider moving some to the backlog."
        }
        if overCapacity, let capacity {
            return plan + ", over its \(Focus.durationString(minutes: capacity)) capacity."
        }
        if let velocity, nextPlan < velocity {
            return plan + ": room for about \(Focus.durationString(minutes: velocity - nextPlan)) more."
        }
        return plan + "."
    }

    private func line(_ text: String) -> some View {
        Text(text).font(Focus.body).foregroundColor(Focus.text2).fixedSize(horizontal: false, vertical: true)
    }

    private func tasks(_ n: Int) -> String { "\(n) \(n == 1 ? "task" : "tasks")" }

    private func complete() {
        model.completeSprint(project.id, unfinished: unfinished, nextGoal: goal, store: store)
        model.completingSprintProjectId = nil
        dismiss()
    }
}
