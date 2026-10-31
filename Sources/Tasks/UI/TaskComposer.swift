import AppKit
import SwiftUI

/// The New task composer at the end of each list group and board column. At rest it's a light
/// "＋ New task" button; a click (or ⌘N for the first group) opens it into the title, a row of
/// property buttons and a footer with the keys. A click outside or Esc closes it again.
/// Tasks added here take the group's value (its status, sprint, milestone, priority or project).
///
/// Recognised words (see ComposerInput) leave the title and fill their button as soon as a space
/// follows them. A word starting with # @ ! + * % or / opens a menu: ↑/↓ choose, ↵ or Tab pick,
/// Esc closes it, typing filters it. ↵ adds, ⇧↵ adds and opens. ⌘N focuses it.
struct TaskComposer: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Environment(\.composerReservesMenuSpace) private var reservesMenuSpace
    /// The group it belongs to; only one composer is open at a time
    let key: String
    /// What tasks added here get from the group
    var preset: TaskGroupValue?
    /// Opens on ⌘N
    var isDefault = false
    /// "New task in To do"
    var groupName = ""
    /// A Board column: tasks go to the active sprint (the board shows it) unless a word or the
    /// chip says otherwise, whatever the project's default sprint
    var onBoard = false

    @State private var title = ""
    @State private var draft = ComposerDraft()
    @State private var highlight = 0
    /// The text the menu was closed for with Esc; it stays closed until the text changes
    @State private var dismissedFor: String?
    @State private var picking: Picker?
    @State private var newMilestoneName = ""
    @State private var added: Added?
    @FocusState private var focused: Bool

    enum Picker: Hashable { case project, status, sprint, milestone, priority, due, time, labels }

    struct Added: Equatable {
        let title: String
        let taskId: UUID
    }

    static let fieldHeight: CGFloat = 42

    var body: some View {
        let target = targetProject
        Group {
            if isActive, let target {
                VStack(spacing: 0) {
                    fieldRow(target)
                    propertyRow(target)
                    footer
                }
                .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
                .overlay(
                    RoundedRectangle(cornerRadius: Focus.radiusCard)
                        .strokeBorder(focused ? Focus.text3 : Focus.lineStrong, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Focus.radiusCard))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                .overlay(alignment: .topLeading) { suggestionMenu(target) }
                .padding(.bottom, menuSpace)
                .background(ComposerKeyMonitor(isActive: true, handle: handleKey, outsideClick: close))
                .transition(.opacity)
            } else {
                ComposerAddButton(text: title, groupName: groupName, disabled: target == nil) { open() }
            }
        }
        .zIndex(isActive ? 5 : 0)
        .onChange(of: title) { text in textChanged(text, target: target) }
        .onChange(of: model.scope) { _ in
            draft = ComposerDraft()
            title = ""
            if isActive { model.activeComposer = nil }
        }
        .onAppear(perform: takeFocusRequest)
        .onChange(of: model.focusRequest) { _ in takeFocusRequest() }
    }

    private var isActive: Bool { model.activeComposer == key }

    /// In the native table the menu can't hang over the next rows, so the row grows to hold it
    private var menuSpace: CGFloat {
        reservesMenuSpace && !suggestions.isEmpty ? CGFloat(min(suggestions.count, 12)) * 34 + 70 : 0
    }

    /// Opens this composer (closing any other) with the group's values filled in
    private func open() {
        guard targetProject != nil else { return }
        applyPreset()
        withAnimation(Focus.hoverAnimation) { model.activeComposer = key }
        DispatchQueue.main.async { focused = true }
    }

    /// Back to the ＋ button. What was typed stays for next time. Not while a picker or the
    /// suggestion menu is up (the menu hangs outside the composer, so its clicks look "outside").
    private func close() {
        guard isActive, picking == nil, suggestions.isEmpty else { return }
        focused = false
        withAnimation(Focus.hoverAnimation) { model.activeComposer = nil }
    }

    private func applyPreset() {
        draft.apply(preset: preset, in: model.scope)
        if onBoard, draft.slot == nil, !model.scope.isMilestone { draft.slot = .active }
    }

    // MARK: - State

    /// The draft's project, else the project on screen (a milestone page's project), else the last one used
    private var targetProject: Project? {
        if let id = draft.projectId, let project = store.project(id), !project.isArchived { return project }
        if let id = model.scope.projectId { return store.project(id) }
        return store.defaultProject
    }

    private var showsProjectButton: Bool {
        model.scope.projectId == nil || (draft.projectId != nil && draft.projectId != model.scope.projectId)
    }

    private func takeFocusRequest() {
        guard isDefault, model.focusRequest?.field == .newTask else { return }
        model.focusRequest = nil
        open()
    }

    // MARK: - Field

    private func fieldRow(_ target: Project?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Focus.text3)
                .frame(width: 16)
            TextField(target == nil ? "Add a project first" : "New task", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(Focus.text)
                .focused($focused)
                .disabled(target == nil)
                .onSubmit(submit)
                .accessibilityLabel("New task title")
                .accessibilityHint("Type 2h, #next, @milestone, !high, *status, %label, +project or due:fri to set them. Return adds.")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.fieldHeight)
        .contentShape(Rectangle())
        .onTapGesture { if target != nil { focused = true } }
    }

    // MARK: - Property row

    private func propertyRow(_ target: Project) -> some View {
        FlowRow(spacing: 6) {
            if showsProjectButton {
                ComposerPropertyButton(tint: .neutral, isSet: true, isOpen: binding(.project)) {
                    FocusProjectTile(project: target, size: 14)
                    Text(target.name)
                } popover: {
                    FocusPopoverMenu(width: 220, maxHeight: 360) {
                        ForEach(store.projects) { project in
                            FocusMenuItem(isSelected: project.id == target.id) {
                                setProject(project.id)
                                closePicker()
                            } label: {
                                FocusProjectTile(project: project)
                                Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                            }
                        }
                    }
                }
            }

            // Set by a *status word (the group's own status needs no chip: it's the column or group)
            if let status = draft.status, preset != .status(status) {
                ComposerPropertyButton(tint: .neutral, isSet: true, isOpen: binding(.status)) {
                    WorkflowStatusIcon(status: status, size: 12)
                    Text(status.name)
                } popover: {
                    FocusPopoverMenu(width: 210, maxHeight: 360) {
                        ForEach(target.statuses) { option in
                            FocusMenuItem(isSelected: option.id == status.id) {
                                draft.status = option
                                closePicker()
                            } label: {
                                WorkflowStatusIcon(status: option, size: 14)
                                Text(option.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                            }
                        }
                    }
                }
            }

            // A project without sprints has no sprint chip
            if target.usesSprints {
            let slot = draft.slot ?? target.newTaskSlot
            ComposerPropertyButton(tint: slot == .active ? .neutral : .sprint, isSet: true, isOpen: binding(.sprint)) {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                Text(store.sprintLabel(slot, projectId: target.id))
            } popover: {
                FocusPopoverMenu(width: 210) {
                    ForEach(SprintSlot.plannable) { slot in
                        FocusMenuItem(isSelected: slot == (draft.slot ?? target.newTaskSlot)) {
                            draft.slot = slot
                            closePicker()
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

            let milestone = draft.milestoneId.flatMap { store.milestone($0) }
            ComposerPropertyButton(tint: .milestone, isSet: milestone != nil, isOpen: binding(.milestone)) {
                Image(systemName: milestone == nil ? "diamond" : "diamond.fill").font(.system(size: 9, weight: .semibold))
                    .foregroundColor(milestone.map { Color(hex: $0.colorHex) })
                Text(milestone?.name ?? "Milestone")
            } popover: {
                FocusMilestoneChoices(projectId: target.id, selection: draft.milestoneId, newName: $newMilestoneName) { id in
                    draft.milestoneId = id
                    closePicker()
                } create: { name in
                    draft.milestoneId = store.addMilestone(projectId: target.id, name: name)
                    newMilestoneName = ""
                    closePicker()
                }
            }

            ComposerPropertyButton(tint: .priority, isSet: draft.priority != nil, isOpen: binding(.priority)) {
                FocusPriorityBars(level: (draft.priority ?? .medium).focusLevel)
                Text(draft.priority?.title ?? "Priority")
            } popover: {
                FocusPopoverMenu(width: 180) {
                    ForEach(TaskPriority.ordered) { priority in
                        FocusMenuItem(isSelected: draft.priority == priority) {
                            draft.priority = priority
                            closePicker()
                        } label: {
                            FocusPriorityBars(level: priority.focusLevel)
                            Text(priority.title).font(Focus.control).foregroundColor(Focus.text)
                        }
                    }
                    if draft.priority != nil {
                        FocusMenuItem {
                            draft.priority = nil
                            closePicker()
                        } label: {
                            Text("Clear").font(Focus.control).foregroundColor(Focus.text2)
                        }
                    }
                }
            }

            let labels = draft.labelIds.compactMap { store.label($0) }
            let labelNames = labels.map(\.name) + draft.newLabelNames
            ComposerPropertyButton(tint: .label(labels.first?.colorHex), isSet: !labelNames.isEmpty, isOpen: binding(.labels)) {
                if let first = labels.first {
                    Circle().fill(Color(hex: first.colorHex)).frame(width: 7, height: 7)
                } else {
                    Image(systemName: "tag").font(.system(size: 10, weight: .semibold))
                }
                Text(labelNames.isEmpty ? "Labels" : (labelNames.count <= 2 ? labelNames.joined(separator: ", ") : "\(labelNames[0]) +\(labelNames.count - 1)"))
            } popover: {
                LabelsPicker(
                    state: { draft.labelIds.contains($0) ? .on : .off },
                    toggle: { id in
                        if let index = draft.labelIds.firstIndex(of: id) { draft.labelIds.remove(at: index) } else { draft.labelIds.append(id) }
                    },
                    create: { name in draft.addLabel(named: name, existing: store.matchLabel(name)) }
                )
                .environmentObject(store)
            }

            ComposerPropertyButton(tint: .due, isSet: draft.dueDate != nil, isOpen: binding(.due)) {
                Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                Text(draft.dueDate.map { "Due " + TaskDates.dueLabel($0) } ?? "Due date")
            } popover: {
                DateEditor(date: draft.dueDate, set: { draft.dueDate = $0 }, close: closePicker)
            }

            ComposerPropertyButton(tint: .time, isSet: draft.expectedMinutes != nil, isOpen: binding(.time)) {
                Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                Text(draft.expectedMinutes.map { Focus.durationString(minutes: $0) + " expected" }
                     ?? target.defaultExpectedMinutes.map { Focus.durationString(minutes: $0) + " expected" } ?? "Expected time")
            } popover: {
                ComposerTimeChoices(minutes: draft.expectedMinutes) { minutes in
                    draft.expectedMinutes = minutes
                    closePicker()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func binding(_ picker: Picker) -> Binding<Bool> {
        Binding(get: { picking == picker }, set: { open in
            if open { picking = picker } else if picking == picker { picking = nil }
        })
    }

    private func closePicker() {
        picking = nil
        DispatchQueue.main.async { focused = true }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let added {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(Focus.ok)
                Text("Added “\(added.title)”").font(.system(size: 12)).foregroundColor(Focus.text2).lineLimit(1)
                Button("Open") { model.openTask(added.taskId) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Focus.text)
            } else {
                Text("Type 2h, #next, @milestone, !high, %label, *status, +project or due:fri. / lists everything.")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            FocusKey(text: "↵ add")
            FocusKey(text: "⇧↵ add and open")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Focus.sidebar)
        .overlay(alignment: .top) { FocusDivider() }
    }

    // MARK: - Menu

    private var suggestions: [ComposerSuggestion] {
        guard focused, dismissedFor != title, let active = ComposerInput.activeTrigger(title) else { return [] }
        return store.composerSuggestions(active.trigger, query: active.query, projectId: targetProject?.id)
    }

    @ViewBuilder
    private func suggestionMenu(_ target: Project?) -> some View {
        let rows = suggestions
        if !rows.isEmpty {
            let current = min(highlight, rows.count - 1)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    FocusMenuItem(isSelected: false) { pick(row) } label: {
                        Text(row.title).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !row.detail.isEmpty {
                            Text(row.detail).font(Focus.meta).foregroundColor(Focus.text3)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(index == current ? Focus.selected : .clear))
                }
                FocusDivider().padding(.vertical, 4)
                Text("↑↓ choose · ↵ or Tab pick · Esc close")
                    .font(.system(size: 11.5))
                    .foregroundColor(Focus.text3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            .padding(4)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.lineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
            .offset(x: 34, y: Self.fieldHeight + 2)
        }
    }

    private func handleKey(_ key: ComposerKey) -> Bool {
        let rows = suggestions
        guard !rows.isEmpty else {
            if key == .escape {
                close()
                return true
            }
            return false
        }
        let current = min(highlight, rows.count - 1)
        switch key {
        case .up: highlight = max(current - 1, 0)
        case .down: highlight = min(current + 1, rows.count - 1)
        case .returnKey, .tab: pick(rows[current])
        case .escape: dismissedFor = title
        }
        return true
    }

    private func pick(_ row: ComposerSuggestion) {
        let rest = ComposerInput.removingActiveWord(title)
        switch row.action {
        case let .slot(slot): draft.slot = slot
        case let .milestone(id): draft.milestoneId = id
        case let .newMilestone(name):
            if let projectId = targetProject?.id { draft.milestoneId = store.addMilestone(projectId: projectId, name: name) }
        case let .priority(priority): draft.priority = priority
        case let .project(id): setProject(id)
        case let .status(status): draft.status = status
        case let .label(id): if !draft.labelIds.contains(id) { draft.labelIds.append(id) }
        case let .newLabel(name): draft.addLabel(named: name, existing: store.matchLabel(name))
        case let .trigger(trigger):
            title = rest + String(trigger.rawValue)
            highlight = 0
            return
        case .pickDue: picking = .due
        case .pickTime: picking = .time
        }
        title = rest
        highlight = 0
    }

    // MARK: - Typing

    private func textChanged(_ text: String, target: Project?) {
        highlight = 0
        if !text.isEmpty { added = nil }
        guard let target else { return }
        let result = ComposerInput.extract(text) { accepts($0, target: target) }
        guard !result.tokens.isEmpty else { return }
        result.tokens.forEach { apply($0, target: target) }
        title = result.text
    }

    /// A milestone or project word is used only when it names one that exists
    private func accepts(_ token: ComposerToken, target: Project) -> Bool {
        switch token {
        case let .milestone(name): return store.matchMilestone(name, projectId: target.id) != nil
        case let .project(name): return store.matchProject(name) != nil
        case let .status(name): return store.matchStatus(name, projectId: (targetProject ?? target).id) != nil
        // A project without sprints leaves #next and the like in the title
        case .slot: return (targetProject ?? target).usesSprints
        default: return true
        }
    }

    private func apply(_ token: ComposerToken, target: Project) {
        switch token {
        case let .minutes(minutes): draft.expectedMinutes = minutes
        case let .slot(slot): draft.slot = slot
        case let .milestone(name): draft.milestoneId = store.matchMilestone(name, projectId: target.id)?.id
        case let .priority(priority): draft.priority = priority
        case let .due(date): draft.dueDate = date
        case let .project(name): if let id = store.matchProject(name)?.id { setProject(id) }
        case let .status(name): draft.status = store.matchStatus(name, projectId: (targetProject ?? target).id)
        case let .label(name): draft.addLabel(named: name, existing: store.matchLabel(name))
        }
    }

    private func setProject(_ id: UUID) {
        guard id != targetProject?.id else { return }
        draft.projectId = id
        draft.milestoneId = nil
    }

    /// ↵ adds (the last word is read too) and stays ready for the next one; ⇧↵ adds and opens.
    private func submit() {
        guard let target = targetProject, isActive else { return }
        if !suggestions.isEmpty { return }
        let open = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let result = ComposerInput.extract(title, final: true) { accepts($0, target: target) }
        result.tokens.forEach { apply($0, target: target) }
        let name = result.text.trimmingCharacters(in: .whitespaces)
        let projectId = targetProject?.id ?? target.id
        // Pinned at the top by ⌘N: the task goes first in its group, right under the composer
        draft.atTop = model.isComposerPinned(key)
        guard !name.isEmpty, let id = store.addTask(title: name, draft: draft, projectId: projectId) else {
            title = result.text
            return
        }
        title = ""
        // Sprint, milestone and project stay for the next task; the rest starts over
        draft.priority = nil
        draft.dueDate = nil
        draft.expectedMinutes = nil
        draft.clearLabels()
        applyPreset()
        if open {
            added = nil
            focused = false
            model.activeComposer = nil
            // The panel opens with the description ready to write
            model.openNewTask(id)
        } else {
            added = Added(title: name, taskId: id)
            model.flash(id)
            // The list redraws around the new row and can take the keyboard with it; keep the
            // field focused so the next task can be typed straight away
            DispatchQueue.main.async { focused = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if isActive { focused = true } }
        }
    }
}

// MARK: - Pieces

/// The composer at rest: a quiet "＋ New task" line (with what was typed, if anything).
private struct ComposerAddButton: View {
    let text: String
    let groupName: String
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                Text(label).font(Focus.control).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(hovering ? Focus.text : Focus.text3)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help(disabled ? "Add a project first" : "Add a task here")
    }

    private var label: String {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { return "New task: \(text)" }
        return "New task"
    }
}

/// A button in the property row: tinted when set, dashed when empty. Opens its popover.
private struct ComposerPropertyButton<Label: View, Popover: View>: View {
    let tint: ComposerTint
    let isSet: Bool
    @Binding var isOpen: Bool
    @ViewBuilder let label: () -> Label
    @ViewBuilder let popover: () -> Popover

    @State private var hovering = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                label()
                if isSet {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1)
            .foregroundColor(isSet ? tint.text : Focus.text2)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(isSet ? tint.fill : (hovering ? Focus.hover : Focus.raised)))
            .overlay(
                RoundedRectangle(cornerRadius: Focus.radiusControl)
                    .strokeBorder(isSet ? tint.stroke : Color.black.opacity(0.2),
                                  style: StrokeStyle(lineWidth: 1, dash: isSet ? [] : [3, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { popover() }
    }
}

/// Colours of the property buttons; each kind differs in lightness as well as hue.
private enum ComposerTint {
    case neutral, sprint, milestone, priority, due, time
    /// The first label's color (gray without one)
    case label(UInt32?)

    private var base: Color {
        switch self {
        case let .label(hex): return hex.map { Color(hex: $0) } ?? Focus.text3
        case .neutral: return Focus.text
        case .sprint: return Focus.done
        case .milestone: return Color(hex: 0x14B8A6)
        case .priority: return Focus.risk
        case .due: return Color(hex: 0x4EA1F5)
        case .time: return Focus.progress
        }
    }

    var text: Color {
        switch self {
        case .neutral: return Focus.text
        case .sprint: return Color(hex: 0x4B3BC4)
        case .milestone: return Color(hex: 0x0F6B60)
        case .priority: return Color(hex: 0xB42318)
        case .due: return Color(hex: 0x1D5FB0)
        case .time: return Color(hex: 0x8A5300)
        case let .label(hex): return hex.map { Color(hex: $0, darkenedBy: 0.35) } ?? Focus.text2
        }
    }

    private var isNeutral: Bool { if case .neutral = self { return true }; return false }
    var fill: Color { isNeutral ? Focus.sidebar : base.opacity(0.1) }
    var stroke: Color { isNeutral ? Focus.hairline : base.opacity(0.4) }
}

/// Expected time presets, a typed value and Clear.
private struct ComposerTimeChoices: View {
    let minutes: Int?
    let set: (Int?) -> Void

    @State private var typed = ""
    static let presets = [15, 30, 45, 60, 90, 120, 180, 240]

    var body: some View {
        FocusPopoverMenu(width: 200) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 11, weight: .semibold)).foregroundColor(Focus.text3)
                TextField("Type: 1h 30m", text: $typed)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .onSubmit {
                        if let value = TaskDurationParser.minutes(typed), value > 0 { set(value) }
                    }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            FocusDivider().padding(.vertical, 4)
            ForEach(Self.presets, id: \.self) { preset in
                FocusMenuItem(isSelected: minutes == preset) { set(preset) } label: {
                    Text(Focus.durationString(minutes: preset)).font(Focus.control).foregroundColor(Focus.text)
                }
            }
            if minutes != nil {
                FocusMenuItem { set(nil) } label: {
                    Text("Clear").font(Focus.control).foregroundColor(Focus.text2)
                }
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines when the row is full.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// Keys the composer handles itself while its field has focus (the field editor would otherwise
/// eat the arrows and turn ↵ into a submit). Unused keys go on to the field.
enum ComposerKey: Equatable {
    case up, down, returnKey, tab, escape
}

/// Also reports a click elsewhere in the same window (popovers are their own windows, so a click
/// in one doesn't count).
private struct ComposerKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let handle: (ComposerKey) -> Bool
    var outsideClick: () -> Void = {}

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isActive = isActive
        view.handle = handle
        view.outsideClick = outsideClick
    }

    final class MonitorView: NSView {
        var isActive = false
        var handle: ((ComposerKey) -> Bool)?
        var outsideClick: (() -> Void)?
        private var monitor: Any?
        private var mouseMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            monitor = nil
            mouseMonitor = nil
            guard window != nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.isActive, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    DispatchQueue.main.async { self.outsideClick?() }
                }
                return event
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive, let window = self.window, event.window === window else { return event }
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
                guard flags.isEmpty else { return event }
                let key: ComposerKey?
                switch event.keyCode {
                case 126: key = .up
                case 125: key = .down
                case 36, 76: key = .returnKey
                case 48: key = .tab
                case 53: key = .escape
                default: key = nil
                }
                guard let key else { return event }
                return self.handle?(key) == true ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }
    }
}
