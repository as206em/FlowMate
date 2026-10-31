import SwiftUI

// Small editors that open from a list cell or a card chip, so quick changes don't need the panel:
// due date (with presets), priority, expected time, milestone and sprint.

/// Today, Tomorrow, Next week and Clear above a calendar.
struct TaskDueEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    var body: some View {
        DateEditor(date: task.dueDate, set: { store.setDueDate(task.id, $0) }, close: close)
    }
}

/// A date popover: presets (Today, Tomorrow, Next week) and Clear above a calendar. Used for task
/// due dates, milestone due dates, project target dates and the sprint start.
struct DateEditor: View {
    let date: Date?
    var showsPresets = true
    var allowsClear = true
    /// A field on top that reads typed dates ("fri", "nov 18", "3d"); ↵ applies it.
    var allowsTyping = true
    let set: (Date?) -> Void
    let close: () -> Void

    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if allowsTyping {
                typedField
                FocusDivider()
            }
            if showsPresets || allowsClear {
                VStack(spacing: 0) {
                    if showsPresets {
                        ForEach(DuePreset.allCases) { preset in
                            let presetDate = preset.date()
                            FocusMenuItem(isSelected: date.map { Calendar.current.isDate($0, inSameDayAs: presetDate) } ?? false) {
                                set(presetDate)
                                close()
                            } label: {
                                // Not a Spacer: the item adds its own, and two would center the date
                                Text(preset.title).font(Focus.control).foregroundColor(Focus.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(SprintState.shortDate(presetDate)).font(Focus.meta).foregroundColor(Focus.text3)
                            }
                        }
                    }
                    if allowsClear {
                        FocusMenuItem {
                            set(nil)
                            close()
                        } label: {
                            Text("Clear").font(Focus.control).foregroundColor(date == nil ? Focus.text3 : Focus.text)
                        }
                        .disabled(date == nil)
                    }
                }
                .padding(4)
                FocusDivider()
            }
            FocusCalendar(selection: date) { day in
                set(Calendar.current.startOfDay(for: day))
                close()
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 280)
        .background(Focus.raised)
        .focusLight()
    }

    /// "Type a date" with what it reads as on the right ("Fri, Oct 31"), or "?" when it can't tell.
    private var typedField: some View {
        let parsed = TaskDateParser.parse(typed)
        return HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Focus.text3)
            TextField("Type a date: fri, nov 18, 3d", text: $typed)
                .textFieldStyle(.plain)
                .font(Focus.control)
                .foregroundColor(Focus.text)
                .focused($typing)
                .onSubmit {
                    guard let parsed else { return }
                    set(parsed)
                    close()
                }
                .accessibilityLabel("Type a date")
            if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(parsed.map(DateEditor.typedLabel) ?? "?")
                    .font(Focus.meta)
                    .foregroundColor(parsed == nil ? Focus.risk : Focus.text3)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .onAppear { DispatchQueue.main.async { typing = true } }
    }

    /// "Fri, Oct 31" (with the year when it isn't this year)
    static func typedLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEE, MMM d" : "EEE, MMM d, yyyy"
        return formatter.string(from: date)
    }
}

/// A field-sized date button for panel inspectors ("No date" when empty); click for presets and a
/// calendar, × clears it.
struct DateField: View {
    let date: Date?
    var placeholder = "No date"
    var risk = false
    var showsPresets = true
    var allowsClear = true
    var accessibilityName = "Date"
    let set: (Date?) -> Void

    @State private var picking = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button { picking = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Focus.text3)
                    Text(label)
                        .font(Focus.control)
                        .foregroundColor(date == nil ? Focus.text3 : (risk ? Focus.risk : Focus.text))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accessibilityName): \(label)")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                DateEditor(date: date, showsPresets: showsPresets, allowsClear: allowsClear, set: set) { picking = false }
            }

            if allowsClear, date != nil {
                Button { set(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Focus.text3)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel("Clear \(accessibilityName.lowercased())")
            }
        }
        .focusField(focused: hovering || picking)
        .onHover { hovering = $0 }
    }

    private var label: String {
        guard let date else { return placeholder }
        let label = TaskDates.dueLabel(date)
        // Relative labels get the date too, so the field is never ambiguous
        return label == SprintState.shortDate(date) ? label : "\(label), \(SprintState.shortDate(date))"
    }
}

struct TaskPriorityEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    var body: some View {
        FocusPopoverMenu(width: 180) {
            ForEach(TaskPriority.ordered) { priority in
                FocusMenuItem(isSelected: priority == task.priority) {
                    store.setPriority(task.id, priority)
                    close()
                } label: {
                    FocusPriorityBars(level: priority.focusLevel)
                    Text(priority.title).font(Focus.control).foregroundColor(Focus.text)
                }
            }
        }
    }
}

/// Expected time: presets (15m – 8h) and a custom entry ("1h 15m").
struct TaskExpectedEditor: View {
    let task: TaskItem
    let close: () -> Void

    var body: some View {
        FocusPopoverMenu(width: 200) {
            TaskExpectedChoices(task: task, first: true, close: close)
        }
    }
}

/// The Expected section shared by the expected and time popovers.
struct TaskExpectedChoices: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var first = false
    let close: () -> Void

    @State private var custom = ""

    var body: some View {
        let choices = TaskItem.expectedChoices.contains(task.expectedMinutes)
            ? TaskItem.expectedChoices
            : (TaskItem.expectedChoices + [task.expectedMinutes]).sorted()
        FocusMenuSection(title: "Expected", first: first)
        ForEach(choices, id: \.self) { minutes in
            FocusMenuItem(isSelected: minutes == task.expectedMinutes) {
                store.setExpectedMinutes(task.id, minutes)
                close()
            } label: {
                Text(Focus.durationString(minutes: minutes)).font(Focus.control.monospacedDigit()).foregroundColor(Focus.text)
            }
        }
        FocusDivider().padding(.vertical, 4)
        let parsed = TaskDurationParser.minutes(custom).flatMap { $0 > 0 ? $0 : nil }
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Focus.text3)
            TextField("Custom, e.g. 1h 15m", text: $custom)
                .textFieldStyle(.plain)
                .font(Focus.control)
                .onSubmit {
                    guard let parsed else { return }
                    store.setExpectedMinutes(task.id, parsed)
                    custom = ""
                    close()
                }
                .accessibilityLabel("Custom expected time")
            if !custom.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(parsed.map { Focus.durationString(minutes: $0) } ?? "?")
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(parsed == nil ? Focus.risk : Focus.text3)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .help("Type a time such as 1h 15m, 75m or 1:15, then press Return")
    }
}

struct TaskSprintEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    var body: some View {
        FocusPopoverMenu(width: 200) {
            ForEach(SprintSlot.plannable) { slot in
                FocusMenuItem(isSelected: slot == task.sprintSlot) {
                    store.setSprintSlot(task.id, slot)
                    close()
                } label: {
                    Text(store.sprintLabel(slot, projectId: task.projectId)).font(Focus.control).foregroundColor(Focus.text)
                    if slot != .backlog {
                        Text(slot == .active ? "active" : "next").font(Focus.meta).foregroundColor(Focus.text3)
                    }
                }
            }
        }
    }
}

/// The task's project milestones, None, and a field that adds a milestone and assigns it.
struct TaskMilestoneEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    @State private var newName = ""

    var body: some View {
        FocusMilestoneChoices(
            projectId: task.projectId,
            selection: task.milestoneId,
            newName: $newName
        ) { id in
            store.setMilestone(task.id, id)
            close()
        } create: { name in
            store.undoGroup("Add milestone") {
                if let id = store.addMilestone(projectId: task.projectId, name: name) {
                    store.setMilestone(task.id, id)
                }
            }
            close()
        }
    }
}

/// Milestone menu shared by the task cell editor and the New task field's milestone chip.
struct FocusMilestoneChoices: View {
    @EnvironmentObject private var store: TaskStore
    let projectId: UUID
    let selection: UUID?
    @Binding var newName: String
    let choose: (UUID?) -> Void
    let create: (String) -> Void

    var body: some View {
        FocusPopoverMenu(width: 240, maxHeight: 360) {
            FocusMenuItem(isSelected: selection == nil) { choose(nil) } label: {
                Image(systemName: "diamond").font(.system(size: 11, weight: .semibold)).foregroundColor(Focus.text3)
                Text("No milestone").font(Focus.control).foregroundColor(Focus.text2)
            }
            ForEach(store.milestones(of: projectId).filter { !$0.isCompleted || $0.id == selection }) { milestone in
                FocusMenuItem(isSelected: milestone.id == selection) { choose(milestone.id) } label: {
                    Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundColor(Focus.text3)
                    Text(milestone.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let due = milestone.dueDate {
                        Text(SprintState.shortDate(due)).font(Focus.meta).foregroundColor(Focus.text3)
                    }
                }
            }
            FocusDivider().padding(.vertical, 4)
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundColor(Focus.text3)
                TextField("New milestone", text: $newName)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .onSubmit {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        newName = ""
                        create(name)
                    }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
    }
}

/// Context menu items: None plus the task's project milestones, with a check on the current one.
struct TaskMilestoneMenuItems: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    var body: some View {
        checked("No milestone", task.milestoneId == nil) { store.setMilestone(task.id, nil) }
        let milestones = store.milestones(of: task.projectId).filter { !$0.isCompleted || $0.id == task.milestoneId }
        if !milestones.isEmpty { Divider() }
        ForEach(milestones) { milestone in
            checked(milestone.name, milestone.id == task.milestoneId) { store.setMilestone(task.id, milestone.id) }
        }
    }

    @ViewBuilder
    private func checked(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if on { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

/// A board card chip that shows the task's milestone and opens the milestone menu.
struct TaskMilestoneChip: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let milestone = store.milestone(of: task)
        Button { open = true } label: {
            HStack(spacing: 4) {
                Image(systemName: milestone == nil ? "diamond" : "diamond.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(milestone?.name ?? "Milestone").lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundColor(milestone == nil ? Focus.text3 : Focus.text2)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(milestone == nil && !hovering ? 0.75 : 1)
        .onHover { hovering = $0 }
        .help(milestone == nil ? "Set milestone" : "Milestone: \(milestone!.name)")
        .accessibilityLabel(milestone.map { "Milestone: \($0.name)" } ?? "Set milestone")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TaskMilestoneEditor(task: task) { open = false }
        }
    }
}

