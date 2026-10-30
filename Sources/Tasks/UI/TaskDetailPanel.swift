import SwiftUI

/// The task side panel content: header with breadcrumbs, title, description and subtasks, plus the inspector.
/// TasksRootView supplies the frame, scrim, slide-in and Esc handling around it.
struct TaskDetailPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let taskId: UUID

    var body: some View {
        if let task = store.task(taskId) {
            VStack(spacing: 0) {
                header(task)
                HStack(spacing: 0) {
                    SidePanelBody { TaskDetailBody(task: task) }
                    TaskInspector(task: task)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Task details")
        }
    }

    /// ⌘[ / ⌘] and the header arrows walk the tasks of the view behind the panel.
    private var stepper: SidePanelStepper? {
        guard let position = model.openTaskPosition(store), position.count > 1 else { return nil }
        return SidePanelStepper(
            position: "\(position.index + 1) of \(position.count)",
            previous: position.index > 0 ? { model.stepOpenTask(-1, store: store) } : nil,
            next: position.index + 1 < position.count ? { model.stepOpenTask(1, store: store) } : nil
        )
    }

    /// Breadcrumbs: project (opens its panel) › milestone (opens its panel, or a picker when none)
    /// › sprint (opens the sprint picker).
    private func header(_ task: TaskItem) -> some View {
        SidePanelHeader(closeLabel: "Close task", close: { model.closePanel() }, stepper: stepper) {
            if let project = store.project(of: task) {
                FocusProjectTile(name: project.name, colorHex: project.colorHex)
                FocusCrumb(text: project.name, help: "Open project") { model.openProject(project.id) }
                FocusCrumbSeparator()
            }
            TaskMilestoneCrumb(task: task)
            FocusCrumbSeparator()
            TaskSprintCrumb(task: task)
        }
    }
}

/// Milestone crumb: opens the milestone panel, or the milestone picker when the task has none.
private struct TaskMilestoneCrumb: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    @State private var picking = false

    var body: some View {
        if let milestone = store.milestone(of: task) {
            FocusCrumb(text: milestone.name, help: "Open milestone") { model.openMilestone(milestone.id) }
        } else {
            FocusCrumb(text: "No milestone", help: "Set milestone", muted: true) { picking = true }
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    TaskMilestoneEditor(task: task) { picking = false }
                }
        }
    }
}

/// Sprint crumb: opens the sprint picker. A task of a past sprint shows which one, and opens Sprints.
private struct TaskSprintCrumb: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    @State private var picking = false

    var body: some View {
        if task.sprintSlot == .closed {
            FocusCrumb(text: store.sprintLabel(for: task) + " · closed", help: "Show past sprints") {
                model.showSprints(of: task.projectId)
            }
        } else {
            FocusCrumb(text: store.sprintLabel(for: task), help: "Change sprint") { picking = true }
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    TaskSprintEditor(task: task) { picking = false }
                }
        }
    }
}

/// The 54pt top bar of every side panel: breadcrumbs on the left, the esc hint and × on the right.
struct SidePanelHeader<Crumbs: View>: View {
    let closeLabel: String
    let close: () -> Void
    /// Previous / next task buttons with "3 of 12" (task panel only)
    var stepper: SidePanelStepper?
    @ViewBuilder let crumbs: () -> Crumbs

    var body: some View {
        HStack(spacing: 6) {
            crumbs()
            Spacer(minLength: 12)
            if let stepper {
                Text(stepper.position)
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .fixedSize()
                    .padding(.trailing, 2)
                FocusIconButton(systemName: "chevron.up", label: "Previous task (⌘[)", size: 26) { stepper.previous?() }
                    .disabled(stepper.previous == nil)
                    .opacity(stepper.previous == nil ? 0.4 : 1)
                FocusIconButton(systemName: "chevron.down", label: "Next task (⌘])", size: 26) { stepper.next?() }
                    .disabled(stepper.next == nil)
                    .opacity(stepper.next == nil ? 0.4 : 1)
                Rectangle().fill(Focus.hairline).frame(width: 1, height: 18).padding(.horizontal, 6)
            }
            FocusKey(text: "esc")
            FocusIconButton(systemName: "xmark", label: closeLabel, size: 30, action: close)
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: 54)
        .background(Focus.raised)
        .overlay(alignment: .bottom) { FocusDivider() }
    }
}

/// Stepping through the view's tasks from the task panel.
struct SidePanelStepper {
    /// "3 of 12"
    let position: String
    let previous: (() -> Void)?
    let next: (() -> Void)?
}

/// The 320pt right column of a side panel: sidebar fill, hairline on the left, scrolling.
struct SidePanelInspector<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content() }
                .padding(.vertical, 24)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Focus.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(Focus.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(Focus.hairline).frame(width: 1) }
    }
}

/// One labelled property in a panel inspector: an 86pt label and a field.
struct SidePanelProperty<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .frame(width: 86, alignment: .leading)
            content()
        }
        .frame(minHeight: 38)
    }
}

/// The left column of a side panel: scrolling content, 680 max, 32pt sides.
struct SidePanelBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) { content() }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.top, 26)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Body

/// Left column: editable title, Markdown description, subtasks.
private struct TaskDetailBody: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SidePanelTitleEditor(placeholder: "Task title", value: task.title) { store.setTitle(task.id, $0) }
            MarkdownDescriptionSection(
                text: task.notes,
                placeholder: Self.placeholder,
                onChange: { store.setNotes(task.id, $0) },
                onToggleLine: { store.toggleNotesChecklist(task.id, line: $0) },
                onEscape: { model.closePanel() }
            )
            SubtasksSection(task: task)
        }
    }

    private static let placeholder = "Write the context, the plan, links and what done looks like. Markdown works: ## heading, **bold**, - list, - [ ] checklist"
}

/// 26pt title of a side panel, edited in place. Empty titles are ignored and revert.
struct SidePanelTitleEditor: View {
    let placeholder: String
    let value: String
    let set: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Focus.taskTitle)
            .tracking(-0.5)
            .foregroundColor(Focus.text)
            .lineSpacing(4)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: draft) { newValue in
                // Return submits instead of adding a line
                if newValue.contains("\n") {
                    draft = newValue.replacingOccurrences(of: "\n", with: " ")
                    focused = false
                    return
                }
                guard newValue != value else { return }
                set(newValue)
            }
            .onChange(of: value) { title in
                if !focused { draft = title }
            }
            .onChange(of: focused) { isFocused in
                if !isFocused { draft = value }
            }
            .onSubmit { focused = false }
            .accessibilityLabel(placeholder)
    }
}

/// Description with Write / Preview tabs and the Markdown toolbar (task, project and milestone panels).
struct MarkdownDescriptionSection: View {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void
    let onToggleLine: (Int) -> Void
    let onEscape: () -> Void
    /// Height of the empty editor and preview
    var minHeight: CGFloat = 250

    @State private var writing = false
    @State private var editorFocused = false
    @State private var editorHeight: CGFloat = 250
    @State private var proxy = MarkdownEditorProxy()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Description").font(Focus.body.weight(.semibold)).foregroundColor(Focus.text)
                Spacer()
                HStack(spacing: 5) {
                    MarkdownMark()
                    Text("Markdown")
                }
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
            }

            VStack(spacing: 0) {
                toolbar
                FocusDivider()
                if writing {
                    MarkdownEditor(
                        text: Binding(get: { text }, set: { onChange($0) }),
                        isFocused: $editorFocused,
                        height: $editorHeight,
                        placeholder: placeholder,
                        proxy: proxy,
                        onEscape: onEscape
                    )
                    .frame(height: max(minHeight, editorHeight))
                    .onAppear { DispatchQueue.main.async { proxy.focus() } }
                } else {
                    MarkdownPreview(markdown: text) { line in
                        onToggleLine(line)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded { writing = true })
                    .help("Double-click to edit")
                }
            }
            .background(Focus.raised)
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
            .overlay(
                RoundedRectangle(cornerRadius: Focus.radiusPanel)
                    .strokeBorder(writing && editorFocused ? Focus.lineStrong : Focus.hairline, lineWidth: 1)
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            MarkdownToolButton(label: "Write", selected: writing) { writing = true }
            MarkdownToolButton(label: "Preview", selected: !writing) { writing = false }
            if writing {
                toolbarSeparator
                MarkdownToolButton(label: "Heading") { Text("H") } action: { proxy.apply(.heading) }
                MarkdownToolButton(label: "Bold") { Text("B").fontWeight(.heavy) } action: { proxy.apply(.bold) }
                MarkdownToolButton(label: "Italic") {
                    Text("I").font(.custom("Georgia", size: 13.5).italic())
                } action: { proxy.apply(.italic) }
                MarkdownToolButton(label: "Code", systemImage: "chevron.left.forwardslash.chevron.right") { proxy.apply(.code) }
                MarkdownToolButton(label: "Link", systemImage: "link") { proxy.apply(.link) }
                toolbarSeparator
                MarkdownToolButton(label: "Bulleted list", systemImage: "list.bullet") { proxy.apply(.bullet) }
                MarkdownToolButton(label: "Checklist", systemImage: "checklist") { proxy.apply(.checklist) }
                MarkdownToolButton(label: "Quote", systemImage: "text.quote") { proxy.apply(.quote) }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(height: 38)
        .background(Focus.canvas)
    }

    private var toolbarSeparator: some View {
        Rectangle().fill(Focus.hairline).frame(width: 1, height: 16).padding(.horizontal, 4)
    }
}

/// 28pt toolbar button; Write/Preview show a raised selected state.
private struct MarkdownToolButton<Content: View>: View {
    let label: String
    var selected = false
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(selected || hovering ? Focus.text : Focus.text2)
                .padding(.horizontal, 7)
                .frame(minWidth: 28, minHeight: 28, maxHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Focus.raised : (hovering ? Focus.hover : .clear))
                )
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Focus.hairline : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension MarkdownToolButton where Content == Text {
    /// Text tab such as Write / Preview
    init(label: String, selected: Bool, action: @escaping () -> Void) {
        self.init(label: label, selected: selected, content: { Text(label) }, action: action)
    }
}

extension MarkdownToolButton where Content == Image {
    /// Icon button
    init(label: String, systemImage: String, action: @escaping () -> Void) {
        self.init(label: label, content: { Image(systemName: systemImage) }, action: action)
    }
}

/// The small "M↓" Markdown mark
private struct MarkdownMark: View {
    var body: some View {
        Text("M↓")
            .font(.system(size: 7.5, weight: .heavy))
            .frame(width: 17, height: 11)
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Focus.text3, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Subtasks

/// Subtasks: click a title to edit it, drag the handle to reorder, and "Convert to task" (hover
/// button or right-click) to make one its own task.
private struct SubtasksSection: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    @State private var newTitle = ""
    @State private var dropTarget: UUID?
    @State private var dropAtEnd = false
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Subtasks").font(Focus.body.weight(.semibold)).foregroundColor(Focus.text)
                Text("\(task.subtasksDone)/\(task.subtasks.count)")
                    .font(Focus.body.monospacedDigit())
                    .foregroundColor(Focus.text3)
                Spacer()
                if task.subtasks.count > 1 {
                    Text("Drag to reorder").font(.system(size: 12)).foregroundColor(Focus.text3)
                }
            }
            VStack(spacing: 0) {
                ForEach(task.subtasks) { subtask in
                    SubtaskRow(task: task, subtask: subtask)
                        .overlay(alignment: .top) {
                            if dropTarget == subtask.id { dropLine }
                        }
                        .onDrop(of: [.plainText], delegate: SubtaskDropDelegate(
                            isTargeted: Binding(get: { dropTarget == subtask.id },
                                                set: { dropTarget = $0 ? subtask.id : (dropTarget == subtask.id ? nil : dropTarget) })
                        ) { id in
                            store.moveSubtask(task.id, id, before: subtask.id)
                        })
                    FocusDivider()
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Focus.text3)
                        .frame(width: 16)
                    TextField("Add a subtask", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(Focus.body)
                        .foregroundColor(Focus.text)
                        .focused($addFocused)
                        .onSubmit(add)
                }
                .padding(.leading, 30)
                .padding(.trailing, 10)
                .frame(height: 42)
                .overlay(alignment: .top) { if dropAtEnd { dropLine } }
                .onDrop(of: [.plainText], delegate: SubtaskDropDelegate(isTargeted: $dropAtEnd) { id in
                    store.moveSubtask(task.id, id, before: nil)
                })
            }
            .focusPanel()
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        }
    }

    /// Where a dragged subtask lands: a 2px `text3` line.
    private var dropLine: some View {
        Rectangle().fill(Focus.text3).frame(height: 2).padding(.horizontal, 8).offset(y: -1)
    }

    private func add() {
        guard store.addSubtask(task.id, title: newTitle) != nil else { return }
        newTitle = ""
        addFocused = true
    }
}

/// Accepts dragged subtasks ("subtask:<uuid>"); ignores tasks and projects.
private struct SubtaskDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let perform: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = SubtaskRow.draggedId(text) else { return }
            DispatchQueue.main.async { perform(id) }
        }
        return true
    }
}

/// Drag handle, checkbox, title (click to edit), Convert to task and remove ×.
private struct SubtaskRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem
    let subtask: Subtask

    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    static let dragPrefix = "subtask:"

    static func draggedId(_ text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(dragPrefix) else { return nil }
        return UUID(uuidString: String(trimmed.dropFirst(dragPrefix.count)))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Focus.text3)
                .frame(width: 14, height: 30)
                .contentShape(Rectangle())
                .opacity(hovering ? 1 : 0)
                .onDrag { NSItemProvider(object: (Self.dragPrefix + subtask.id.uuidString) as NSString) }
                .help("Drag to reorder")
                .accessibilityHidden(true)

            Button { store.toggleSubtask(task.id, subtask.id) } label: {
                ChecklistBox(checked: subtask.isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isDone ? "Mark subtask as not done" : "Mark subtask as done")

            if renaming {
                TextField("Subtask", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Focus.body)
                    .foregroundColor(Focus.text)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand { renaming = false }
                    .onChange(of: fieldFocused) { if !$0 { commit() } }
                    .onAppear { DispatchQueue.main.async { fieldFocused = true } }
            } else {
                Text(subtask.title)
                    .font(Focus.body)
                    .foregroundColor(subtask.isDone ? Focus.text3 : Focus.text)
                    .strikethrough(subtask.isDone, color: Focus.text3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = subtask.title
                        renaming = true
                    }
                    .focusPointerCursor()
                    .help("Click to edit")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Edit") {
                        draft = subtask.title
                        renaming = true
                    }
            }

            Button { model.convertSubtask(subtask.id, of: task.id, store: store) } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Focus.text3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Convert to task")
            .accessibilityLabel("Convert \(subtask.title) to a task")

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Focus.text3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.6)
            .help("Remove subtask")
            .accessibilityLabel("Remove subtask \(subtask.title)")
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(hovering ? Focus.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit") {
                draft = subtask.title
                renaming = true
            }
            Button("Convert to task") { model.convertSubtask(subtask.id, of: task.id, store: store) }
            Divider()
            Button("Remove subtask", action: remove)
        }
    }

    /// Removes at once; the toast offers Undo
    private func remove() {
        let before = store.lastUndoId
        store.removeSubtask(task.id, subtask.id)
        guard store.lastUndoId != before else { return }
        model.showUndoToast("Subtask removed", store: store)
    }

    private func commit() {
        guard renaming else { return }
        store.renameSubtask(task.id, subtask.id, to: draft)
        renaming = false
    }
}
