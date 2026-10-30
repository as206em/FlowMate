import AppKit
import SwiftUI

/// 54pt header: title, tabs (Board · List · Sprints · Milestones) and the inline "New task" field
/// with its milestone and sprint chips. ⌘N focuses the field.
struct TasksHeader: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var newTitle = ""
    @State private var pickingProject = false
    /// Milestone and sprint for the next new task (chips in the field)
    @State private var newMilestoneId: UUID?
    @State private var newSlot: SprintSlot = .active
    @State private var pickingMilestone = false
    @State private var pickingSlot = false
    @State private var newMilestoneName = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        let project = model.scope.projectId.flatMap { store.project($0) }
        HStack(spacing: 12) {
            if let project {
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
            if project == nil {
                Text("\(store.projects.count) \(store.projects.count == 1 ? "project" : "projects")")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            FocusTabs(
                options: model.tabs.map { (value: $0, label: $0.title) },
                selection: Binding(get: { model.effectiveTab }, set: { model.tab = $0 })
            )
            .fixedSize()
            newTaskField
        }
        .padding(.horizontal, 28)
        .frame(height: 54)
        .overlay(alignment: .bottom) { FocusDivider() }
        .zIndex(1)
        .onAppear(perform: takeFocusRequest)
        .onChange(of: model.focusRequest) { _ in takeFocusRequest() }
        .onChange(of: targetProject?.id) { _ in
            // Milestones belong to one project
            newMilestoneId = nil
        }
    }

    private func takeFocusRequest() {
        guard model.focusRequest?.field == .newTask else { return }
        model.focusRequest = nil
        DispatchQueue.main.async { titleFocused = true }
    }

    /// The project's own tasks go to it; in All projects, the last project used (remembered across launches).
    private var targetProject: Project? {
        if let id = model.scope.projectId { return store.project(id) }
        return store.defaultProject
    }

    private var newTaskField: some View {
        HStack(spacing: 6) {
            if model.scope.projectId == nil, let target = targetProject {
                // A button + popover rather than a Menu: AppKit menus drop the tile's tinted background
                Button {
                    pickingProject.toggle()
                } label: {
                    FocusProjectTile(name: target.name, colorHex: target.colorHex)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New tasks go to \(target.name)")
                .accessibilityLabel("Project for new task: \(target.name)")
                .popover(isPresented: $pickingProject, arrowEdge: .bottom) {
                    FocusPopoverMenu(width: 220) {
                        ForEach(store.projects) { project in
                            FocusMenuItem(isSelected: project.id == target.id) {
                                store.rememberProject(project.id)
                                pickingProject = false
                            } label: {
                                FocusProjectTile(name: project.name, colorHex: project.colorHex)
                                Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Focus.text3)
            }
            TextField(targetProject == nil ? "Add a project first" : "New task", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($titleFocused)
                .disabled(targetProject == nil)
                .onSubmit(addTask)
                .onExitCommand { titleFocused = false }
                .accessibilityLabel("New task title")
                .help("Return adds, ⇧Return adds and opens. Tokens: !high, @milestone, due:fri, ~90m")
            if let target = targetProject {
                milestoneChip(target)
                slotChip(target)
            }
            if targetProject != nil, titleFocused || newTitle.isEmpty {
                FocusKey(text: titleFocused ? "↵" : "⌘N")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: titleFocused ? 340 : 280, height: Focus.controlHeight)
        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusControl)
                .strokeBorder(titleFocused ? Focus.text3 : Focus.lineStrong, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) { tokenPreview }
        .animation(Focus.hoverAnimation, value: titleFocused)
    }

    /// While typing, what the field will do: "Atlas · High · ◆ Beta · Due Fri · 1h 30m · ⇧↵ opens".
    @ViewBuilder
    private var tokenPreview: some View {
        if titleFocused, let target = targetProject, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            let input = QuickAddInput.parse(newTitle)
            let milestone = input.milestoneQuery.map { store.matchMilestone($0, projectId: target.id)?.name ?? "No milestone “\($0)”" }
                ?? newMilestoneId.flatMap { store.milestone($0)?.name }
            let parts = [input.priority?.title,
                         milestone.map { "◆ " + $0 },
                         input.dueDate.map { "Due " + TaskDates.dueLabel($0) },
                         input.expectedMinutes.map { Focus.durationString(minutes: $0) }].compactMap { $0 }
            HStack(spacing: 6) {
                FocusProjectTile(name: target.name, colorHex: target.colorHex, size: 14)
                Text(([target.name] + parts).joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text2)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("⇧↵ adds and opens").font(.system(size: 11.5)).foregroundColor(Focus.text3).fixedSize()
            }
            .padding(.horizontal, 9)
            .frame(width: 340, height: 26, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .offset(y: Focus.controlHeight + 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// ◇ or ◆ Milestone name: which milestone the new task joins
    private func milestoneChip(_ target: Project) -> some View {
        let milestone = newMilestoneId.flatMap { store.milestone($0) }
        return Button { pickingMilestone = true } label: {
            HStack(spacing: 3) {
                Image(systemName: milestone == nil ? "diamond" : "diamond.fill")
                    .font(.system(size: 9, weight: .semibold))
                if let milestone {
                    Text(milestone.name).lineLimit(1).frame(maxWidth: 70, alignment: .leading)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(milestone == nil ? Focus.text3 : Focus.text2)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(milestone == nil ? .clear : Focus.hover))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(milestone.map { "New tasks join \($0.name)" } ?? "Choose a milestone for new tasks")
        .accessibilityLabel("Milestone for new task: \(milestone?.name ?? "none")")
        .popover(isPresented: $pickingMilestone, arrowEdge: .bottom) {
            FocusMilestoneChoices(
                projectId: target.id,
                selection: newMilestoneId,
                newName: $newMilestoneName
            ) { id in
                newMilestoneId = id
                pickingMilestone = false
            } create: { name in
                newMilestoneId = store.addMilestone(projectId: target.id, name: name)
                pickingMilestone = false
            }
        }
    }

    /// "Sprint", "Next" or "Backlog": which part of the sprint plan the new task joins
    private func slotChip(_ target: Project) -> some View {
        Button { pickingSlot = true } label: {
            Text(Self.shortSlotName(newSlot))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(newSlot == .active ? Focus.text3 : Focus.text2)
                .padding(.horizontal, 5)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(newSlot == .active ? .clear : Focus.hover))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New tasks go to \(store.sprintLabel(newSlot, projectId: target.id))")
        .accessibilityLabel("Sprint for new task: \(store.sprintLabel(newSlot, projectId: target.id))")
        .popover(isPresented: $pickingSlot, arrowEdge: .bottom) {
            FocusPopoverMenu(width: 200) {
                ForEach(SprintSlot.plannable) { slot in
                    FocusMenuItem(isSelected: slot == newSlot) {
                        newSlot = slot
                        pickingSlot = false
                    } label: {
                        Text(store.sprintLabel(slot, projectId: target.id)).font(Focus.control).foregroundColor(Focus.text)
                        if slot != .backlog {
                            Text(slot == .active ? "active" : "next").font(Focus.meta).foregroundColor(Focus.text3)
                        }
                    }
                }
            }
        }
    }

    private static func shortSlotName(_ slot: SprintSlot) -> String {
        switch slot {
        case .active: return "Sprint"
        case .next: return "Next"
        case .backlog, .closed: return "Backlog"
        }
    }

    /// ↵ adds and says where it went ("Added to Atlas · Open"); ⇧↵ adds and opens the task.
    private func addTask() {
        guard let project = targetProject else { return }
        let open = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if model.quickAdd(newTitle, projectId: project.id, milestoneId: newMilestoneId, slot: newSlot, open: open, store: store) {
            newTitle = ""
            if open { titleFocused = false }
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
                FocusProjectTile(name: project.name, colorHex: project.colorHex)
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
/// length), goal (click to edit), Complete sprint (opens CompleteSprintSheet).
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
            DatePicker(
                "Sprint start",
                selection: Binding(get: { sprint.startDate }, set: { store.setSprintStart(projectId: project.id, date: $0) }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, 10)
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
        let done = active.filter(\.isDone).count
        let open = active.count - done
        let next = store.sprintTasks(projectId: project.id, slot: .next).count
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
                line(done == 0 ? "No done tasks to close." : "\(tasks(done)) marked done \(done == 1 ? "closes" : "close") with the sprint.")
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
