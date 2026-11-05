import AppKit
import SwiftUI

/// The header, two lines on every screen so they all read the same:
///   1 (52pt)  the title (project, All projects, Today or a saved view), the numbers
///             of the active sprint, and the Sprint menu on the right
///   2 (42pt)  the tabs (List · Sprints), underlined, with the tools of the
///             tab after them: search and filters, Group and Sort
/// Today has no tabs, so it has the first line only. The New task composer lives in the groups.
struct TasksHeader: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    private var hasTabs: Bool { !model.tabs.isEmpty }

    /// The active sprint's menu, where the project (or every project) plans in sprints.
    private var showsSprint: Bool {
        model.scopeUsesSprints && !model.scope.isToday
    }

    var body: some View {
        VStack(spacing: 0) {
            titleLine
            if hasTabs { toolLine }
        }
        // Drag the window from anywhere on the header that isn't a control
        .background(WindowDragArea())
        .overlay(alignment: .bottom) { FocusDivider() }
        .zIndex(1)
    }

    // MARK: Line 1

    private var titleLine: some View {
        let project = model.scope.projectId.flatMap { store.project($0) }
        return HStack(spacing: 14) {
            if model.scope.isToday {
                TodayHeaderTitle()
            } else if let view = model.activeView(store) {
                SavedViewHeaderTitle(view: view)
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
            }
            HeaderStats(scope: model.scope, showsSprint: showsSprint)
            Spacer(minLength: 12)
            if !hasTabs, let keys = model.collapsibleGroupKeys(store) {
                CollapseAllButton(keys: keys)
            }
            if showsSprint {
                SprintHeaderItems(scope: model.scope)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 52)
    }

    // MARK: Line 2

    private var toolLine: some View {
        HStack(spacing: 10) {
            HeaderTabs()
            Rectangle().fill(Focus.hairline).frame(width: 1, height: 16).padding(.horizontal, 4)
            tools
        }
        .padding(.horizontal, 28)
        .frame(height: 42)
    }

    @ViewBuilder
    private var tools: some View {
        let keys = model.collapsibleGroupKeys(store)
        switch model.effectiveTab {
        case .list:
            if model.showsFilterBar, !(store.isLoaded && store.projects.isEmpty && model.scope.projectId == nil) {
                TaskFilterBar().frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 12)
            }
            if let keys { CollapseAllButton(keys: keys) }
        case .sprints:
            Spacer(minLength: 12)
            if let keys { CollapseAllButton(keys: keys) }
            SprintHeaderItems(scope: model.scope, showsChip: false, showsActions: true)
        case .overview:
            OverviewHeaderTools()
        }
    }
}

/// List · Sprints as underlined tabs.
private struct HeaderTabs: View {
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        HStack(spacing: 20) {
            ForEach(model.tabs, id: \.self) { tab in
                let selected = tab == model.effectiveTab
                Button { model.tab = tab } label: {
                    Text(tab.title)
                        .font(Focus.control)
                        .foregroundColor(selected ? Focus.text : Focus.text2)
                        .frame(height: 42)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? Focus.text : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

private struct CollapseAllButton: View {
    @EnvironmentObject private var model: TasksViewModel
    let keys: [String]

    var body: some View {
        let allCollapsed = keys.allSatisfy(model.isCollapsed)
        FocusIconButton(
            systemName: allCollapsed ? "arrow.up.and.line.horizontal.and.arrow.down" : "arrow.down.and.line.horizontal.and.arrow.up",
            label: allCollapsed ? "Expand all groups" : "Collapse all groups"
        ) { model.setGroups(keys, collapsed: !allCollapsed) }
    }
}

/// The numbers beside the title: how far the active sprint is, what is overdue, the time tracked
/// in the sprint and the days left. Without sprints (and on Today) the ones that still apply.
private struct HeaderStats: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope
    let showsSprint: Bool

    var body: some View {
        // Minutes are the finest unit shown, so a minute's tick is enough (not the second ticker)
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = context.date
            HStack(spacing: 0) {
                if scope.isToday {
                    let plan = store.todayPlan(now: now)
                    stat(Focus.durationString(minutes: Int((plan.plannedSeconds / 60).rounded())), "planned")
                    overdue(plan.overdue.count)
                } else if model.activeView(store) == nil {
                    if showsSprint {
                        stat(store.sprintCompletion(scope: scope).percentText, "\(store.sprint.name) done")
                    }
                    overdue(store.tasks(in: scope).filter { store.isOverdue($0, now: now) }.count)
                    if showsSprint {
                        let tracked = Int((store.trackedInSprint(projectId: scope.projectId, now: now) / 60).rounded())
                        stat(Focus.durationString(minutes: tracked), "tracked")
                        let left = max(0, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                                                         to: Calendar.current.startOfDay(for: store.sprint.endDate)).day ?? 0) + 1)
                        stat("\(left) \(left == 1 ? "day" : "days")", "left")
                    }
                }
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private func overdue(_ count: Int) -> some View {
        if count > 0 { stat("\(count)", "overdue", tint: Focus.risk) }
    }

    private func stat(_ value: String, _ label: String, tint: Color = Focus.text) -> some View {
        HStack(spacing: 6) {
            Text(value).font(Focus.rowStrong.monospacedDigit()).foregroundColor(tint)
            Text(label).font(Focus.meta).foregroundColor(Focus.text3)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 16)
        .padding(.trailing, 2)
        .overlay(alignment: .leading) { Rectangle().fill(Focus.hairline).frame(width: 1, height: 14) }
        .padding(.leading, 14)
    }
}

/// All projects › Overview: how many projects need attention, and the sort of the cards.
private struct OverviewHeaderTools: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        let attention = model.overviewSummary.attention
        Text(summary(count: model.overviewSummary.count, attention: attention))
            .font(Focus.meta)
            .foregroundColor(attention > 0 ? Focus.progress : Focus.text3)
            .lineLimit(1)
        Spacer(minLength: 12)
        Text("Sort").font(Focus.meta).foregroundColor(Focus.text3)
        FocusTabs(options: PortfolioSort.allCases.map { (value: $0, label: $0.title) }, selection: $model.overviewSort)
            .fixedSize()
            .accessibilityLabel("Sort projects")
    }

    private func summary(count: Int, attention: Int) -> String {
        let projects = "\(count) \(count == 1 ? "project" : "projects")"
        switch attention {
        case 0: return "\(projects) · all on track"
        case 1: return "\(projects) · 1 needs attention"
        default: return "\(projects) · \(attention) need attention"
        }
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

/// The active sprint in the header: a chip with its name and completion that opens the sprint menu
/// (dates, goal, the plan against capacity, Plan sprints, Complete sprint). The Sprints tab also
/// shows Plan sprints and Complete sprint as buttons. The sprint is the workspace's, so it reads the
/// same in every project.
struct SprintHeaderItems: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope
    var showsChip = true
    /// The Sprints tab: its two actions sit in its tool line
    var showsActions = false

    @State private var showingMenu = false
    @State private var planning = false

    var body: some View {
        let sprint = store.sprint
        HStack(spacing: 8) {
          if showsChip {
            Button { showingMenu = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Focus.text3)
                    Text(sprint.name).font(Focus.control).foregroundColor(Focus.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Focus.text3)
                }
                .padding(.horizontal, 10)
                .frame(height: Focus.controlHeight)
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("\(sprint.name) · \(sprint.dateRange)")
            .popover(isPresented: $showingMenu, arrowEdge: .bottom) {
                SprintMenu(scope: scope, close: { showingMenu = false })
                    .environmentObject(store)
                    .environmentObject(model)
            }
          }
            if showsActions {
                Button("Plan sprints") { planning = true }
                    .buttonStyle(.focus(.ghost))
                    .help("Create sprints ahead and set their goals")
                    .popover(isPresented: $planning, arrowEdge: .bottom) { SprintPlanner() }
                Button("Complete sprint") { model.completingSprint = true }
                    .buttonStyle(.focus())
                    .help("Close \(store.sprintName()) for every project and start \(store.sprint.nextName) today")
            }
        }
    }
}

/// Popover of the sprint chip: dates (click to change), goal (edit in place) and the plan line.
struct SprintMenu: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope
    let close: () -> Void

    @State private var goalDraft = ""
    @State private var editingDates = false
    @State private var planning = false
    @FocusState private var goalFocused: Bool

    var body: some View {
        let sprint = store.sprint
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sprint.name).font(Focus.groupTitle).foregroundColor(Focus.text)
                FocusCellButton(help: "Change sprint dates", action: { editingDates = true }) {
                    Text(sprint.dateRange).font(Focus.body).foregroundColor(Focus.text3).fixedSize()
                }
                .fixedSize()
                .popover(isPresented: $editingDates, arrowEdge: .bottom) { SprintDatesEditor() }
            }
            VStack(alignment: .leading, spacing: 4) {
                FocusCaption(text: "Goal")
                TextField(SprintState.goalPlaceholder, text: $goalDraft)
                    .focused($goalFocused)
                    .focusField()
                    .onSubmit(commitGoal)
                    .onChange(of: goalFocused) { focused in if !focused { commitGoal() } }
            }
            LiveTime { now in
                let line = store.sprintPlanLine(scope: scope, now: now)
                Text(store.sprintCompletion(scope: scope).percentText + " done · " + line.text)
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(CapacityColors.color(line.level))
                    .fixedSize(horizontal: false, vertical: true)
            }
            SprintMixSection(scope: scope)
            FocusDivider()
            HStack(spacing: 8) {
                Button("Plan sprints") { planning = true }
                    .buttonStyle(.focus(.ghost))
                    .popover(isPresented: $planning, arrowEdge: .bottom) { SprintPlanner() }
                Spacer(minLength: 0)
                Button("Complete sprint") {
                    close()
                    model.completingSprint = true
                }
                .buttonStyle(.focus())
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Focus.raised)
        .focusLight()
        .onAppear { goalDraft = store.sprint.goal }
        // Closing the popover by clicking away may not end the field's focus first
        .onDisappear(perform: commitGoal)
    }

    /// Saves the goal once, whichever of ↵, leaving the field or closing the popover comes first.
    private func commitGoal() {
        guard goalDraft != store.sprint.goal else { return }
        store.setSprintGoal(goalDraft)
    }
}

/// Popover: the sprints planned after the active one, each with its dates and a goal, and buttons to
/// create more (one, or four: a month of weekly sprints) or take the last one away. Every sprint is
/// as long as the active one, so set that first (click the dates).
struct SprintPlanner: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        let upcoming = store.upcomingSprints()
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan sprints").font(Focus.groupTitle).foregroundColor(Focus.text)
                Text("Each sprint lasts \(store.sprint.lengthLabel), like \(store.sprintName()). Change the length in its dates.")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            FocusDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(upcoming) { sprint in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(sprint.name).font(Focus.rowStrong).foregroundColor(Focus.text)
                                Text(sprint.dateRange).font(Focus.meta).foregroundColor(Focus.text3)
                                Spacer(minLength: 0)
                                Text(String(store.sprintTasks(ahead: sprint.ahead).count) + " tasks")
                                    .font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text3)
                            }
                            TextField(SprintState.goalPlaceholder, text: Binding(
                                get: { store.upcomingSprints().first { $0.ahead == sprint.ahead }?.goal ?? "" },
                                set: { store.setUpcomingGoal(ahead: sprint.ahead, goal: $0) }
                            ))
                            .focusField()
                            .accessibilityLabel("Goal of \(sprint.name)")
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 320)
            FocusDivider()
            HStack(spacing: 8) {
                Button("New sprint") { store.addUpcomingSprints(1) }
                    .buttonStyle(.focus())
                Button("Add 4 sprints") { store.addUpcomingSprints(4) }
                    .buttonStyle(.focus(.ghost))
                    .help("Plan a month ahead when sprints are a week long")
                Spacer(minLength: 0)
                if upcoming.count > 1 {
                    Button("Remove last") { store.removeLastUpcomingSprint() }
                        .buttonStyle(.focus(.ghost))
                        .help("Take \(upcoming.last?.name ?? "the last sprint") away; its tasks go to the backlog")
                }
            }
            .padding(12)
        }
        .frame(width: 340)
        .background(Focus.raised)
        .focusLight()
    }
}

/// Popover: the active sprint's start date and length (1–4 weeks), and where that puts the end.
struct SprintDatesEditor: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        let sprint = store.sprint
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                FocusCaption(text: "Number")
                FocusStepper(value: sprint.number, label: "Sprint number") { store.setSprintNumber($0) }
                FocusCaption(text: "Length").padding(.top, 6)
                FocusTabs(
                    options: SprintState.lengthChoices.map { (value: $0, label: SprintState.lengthLabel($0)) },
                    selection: Binding(get: { sprint.lengthWeeks }, set: { store.setSprintLength(weeks: $0) })
                )
                .fixedSize()
                FocusCaption(text: "Starts").padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            FocusCalendar(selection: sprint.startDate) { store.setSprintStart(date: $0) }
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

    @State private var unfinished: UnfinishedSprintTasks = .moveToNextSprint
    @State private var goal = ""
    @FocusState private var goalFocused: Bool

    var body: some View {
        let sprint = store.sprint
        let active = store.sprintTasks(slot: .active)
        let done = active.filter(\.isClosed).count
        let open = active.count - done
        let next = store.sprintTasks(slot: .next).count
        let velocity = store.recentVelocityMinutes(includingActive: true)
        let nextPlan = store.nextSprintPlanMinutes(unfinished: unfinished)
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
        let name = store.sprint.nextName
        let capacity = store.sprintCapacityMinutes()
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
        model.completeSprint(unfinished: unfinished, nextGoal: goal, store: store)
        model.completingSprint = false
        dismiss()
    }
}


/// A background that moves the window when dragged (double-click zooms it, like a title bar).
/// Controls drawn above it keep their clicks.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
