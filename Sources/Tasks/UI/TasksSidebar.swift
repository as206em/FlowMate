import SwiftUI

/// 240pt sidebar: app tile, Today, All projects, the saved views, the project list (drag to reorder; the arrow lists a
/// project's milestones), "New project", the Archived section and the running timers.
struct TasksSidebar: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var newProjectName = ""
    @State private var renamingId: UUID?
    @State private var pendingDelete: Project?
    @FocusState private var newProjectFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the window's traffic lights
            Color.clear.frame(height: 30)

            HStack(spacing: 9) {
                FocusAppTile()
                Text("FlowMate").font(.system(size: 14, weight: .semibold)).foregroundColor(Focus.text)
                Spacer(minLength: 0)
                FocusIconButton(systemName: "questionmark", label: "Keyboard shortcuts (⌘/)", size: 24) {
                    model.showingShortcuts.toggle()
                }
                .popover(isPresented: $model.showingShortcuts, arrowEdge: .trailing) {
                    TasksShortcutsHelp()
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 2)
            .padding(.bottom, 14)

            FocusSidebarItem(selected: model.sidebarSelection == .today, focused: model.sidebarCursor == .today, action: { model.select(.today) }) {
                Image(systemName: "sun.max")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text("Today").frame(maxWidth: .infinity, alignment: .leading)
                let count = store.todayCount()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundColor(store.dueCounts().overdue > 0 ? Focus.risk : Focus.text3)
                }
            }
            .help("Overdue, due today and pinned tasks across projects, with today's timers and time")
            .onDrop(of: [.plainText], delegate: SidebarTodayDrop(store: store, model: model))
            .overlay {
                if model.dropTarget == SidebarTodayDrop.key {
                    RoundedRectangle(cornerRadius: Focus.radiusControl)
                        .strokeBorder(Focus.text3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }

            FocusSidebarItem(selected: model.sidebarSelection == .all, focused: model.sidebarCursor == .all, action: { model.select(.all) }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text("All projects").frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        SidebarViewsSection()

                        FocusCaption(text: "Projects")
                            .padding(.horizontal, 8)
                            .padding(.top, 18)
                            .padding(.bottom, 6)

                        ForEach(store.projects) { project in
                            projectRow(project)
                                .id(SidebarItem.project(project.id))
                                .onDrag {
                                    model.draggingTaskId = nil
                                    return NSItemProvider(object: SidebarProjectDrop.payload(project.id) as NSString)
                                }
                                .onDrop(of: [.plainText], delegate: SidebarProjectDrop(target: project.id, store: store, model: model))
                                .overlay(alignment: .top) {
                                    if model.dropTarget == SidebarProjectDrop.key(project.id) {
                                        if model.draggingTaskId != nil {
                                            // A task: it moves into this project
                                            RoundedRectangle(cornerRadius: Focus.radiusControl)
                                                .strokeBorder(Focus.text3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                        } else {
                                            // A project: it goes above this one
                                            Rectangle().fill(Focus.text3).frame(height: 2).offset(y: -2)
                                        }
                                    }
                                }
                            if model.isProjectExpanded(project.id) {
                                SidebarMilestones(project: project)
                            }
                        }
                        newProjectField
                            .onDrop(of: [.plainText], delegate: SidebarProjectDrop(target: nil, store: store, model: model))
                            .overlay(alignment: .top) {
                                if model.dropTarget == SidebarProjectDrop.key(nil) {
                                    Rectangle().fill(Focus.text3).frame(height: 2).offset(y: -2)
                                }
                            }
                        archivedSection
                    }
                }
                // ⌘0 and ⌥⌘↑/↓ move a keyboard cursor through the sidebar: keep it on screen
                .onChange(of: model.sidebarCursor) { cursor in
                    guard let cursor, cursor != .today, cursor != .all else { return }
                    withAnimation(Focus.hoverAnimation) { proxy.scrollTo(cursor) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            RunningTimersPanel()
        }
        .padding(.top, 14)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: Focus.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Focus.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Focus.hairline).frame(width: 1) }
        .projectDeleteAlert($pendingDelete)
    }

    /// "Archived" with a disclosure arrow; archived projects keep their data and can be opened.
    @ViewBuilder
    private var archivedSection: some View {
        let archived = store.archivedProjects
        if !archived.isEmpty {
            Button {
                withAnimation(Focus.hoverAnimation) { model.showingArchived.toggle() }
            } label: {
                HStack(spacing: 6) {
                    FocusCaption(text: "Archived")
                    Text("\(archived.count)").font(Focus.caption.monospacedDigit()).foregroundColor(Focus.text3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Focus.text3)
                        .rotationEffect(.degrees(model.showingArchived ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archived projects")
            .accessibilityValue(model.showingArchived ? "Expanded" : "Collapsed")
            if model.showingArchived {
                ForEach(archived) { project in
                    FocusSidebarItem(selected: model.sidebarSelection == .project(project.id), focused: model.sidebarCursor == .project(project.id), action: { model.clickSidebarProject(project.id) }) {
                        FocusProjectTile(project: project)
                            .opacity(0.6)
                        Text(project.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(Focus.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(SidebarItem.project(project.id))
                    .contextMenu {
                        Button("Project settings…") { model.openProject(project.id) }
                        Button("Unarchive") { model.unarchiveProject(project.id, store: store) }
                        Divider()
                        Button("Delete project…") { pendingDelete = project }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        if renamingId == project.id {
            ProjectRenameField(project: project) { renamingId = nil }
        } else {
            FocusSidebarItem(selected: model.sidebarSelection == .project(project.id), focused: model.sidebarCursor == .project(project.id), action: { model.clickSidebarProject(project.id) }) {
                FocusProjectTile(project: project)
                Text(project.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if store.isProjectRunning(project.id) {
                    FocusLiveDot()
                }
                Text("\(store.openCount(project.id))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(Focus.text3)
                // Room for the disclosure arrow drawn on top
                Color.clear.frame(width: 14, height: 1)
            }
            .overlay(alignment: .trailing) {
                SidebarDisclosure(
                    expanded: model.isProjectExpanded(project.id),
                    label: "Milestones of \(project.name)"
                ) {
                    withAnimation(Focus.hoverAnimation) { model.toggleProjectExpanded(project.id) }
                }
                .padding(.trailing, 4)
            }
            .help(model.scope == .project(project.id) ? "Click again for project settings" : project.name)
            .contextMenu {
                Button("Project settings…") { model.openProject(project.id) }
                Button("Rename") { renamingId = project.id }
                Menu("Color") {
                    ForEach(Focus.projectPalette, id: \.self) { hex in
                        Button {
                            store.setProjectColor(project.id, colorHex: hex)
                        } label: {
                            if hex == project.colorHex {
                                Label(Focus.colorName(hex), systemImage: "checkmark")
                            } else {
                                Text(Focus.colorName(hex))
                            }
                        }
                    }
                }
                Button(model.isProjectExpanded(project.id) ? "Hide milestones" : "Show milestones") {
                    model.toggleProjectExpanded(project.id)
                }
                Divider()
                Button("Archive project") { model.archiveProject(project.id, store: store) }
                Button("Delete project…") { pendingDelete = project }
            }
        }
    }

    private var newProjectField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Focus.text3)
                .frame(width: 18)
            TextField("New project", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($newProjectFocused)
                .onExitCommand { newProjectFocused = false }
                .onSubmit {
                    // ↵ adds and says so (Open shows it); ⇧↵ adds, shows it and opens its panel
                    let open = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                    guard model.addProject(newProjectName, open: open, store: store) != nil else { return }
                    newProjectName = ""
                    if open {
                        newProjectFocused = false
                    } else {
                        DispatchQueue.main.async { newProjectFocused = true }
                    }
                }
                .accessibilityLabel("New project name")
                .accessibilityHint("Return adds it. Shift-Return adds it and opens its settings.")
            if newProjectFocused, !newProjectName.isEmpty {
                FocusKey(text: "⇧↵ open")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Focus.radiusControl)
                .strokeBorder(newProjectFocused ? Focus.lineStrong : .clear, lineWidth: 1)
        )
        .onAppear(perform: takeFocusRequest)
        .onChange(of: model.focusRequest) { _ in takeFocusRequest() }
    }

    /// ⇧⌘N
    private func takeFocusRequest() {
        guard model.focusRequest?.field == .newProject else { return }
        model.focusRequest = nil
        DispatchQueue.main.async { newProjectFocused = true }
    }

}

/// The small arrow on a sidebar project row that shows or hides its milestones.
private struct SidebarDisclosure: View {
    let expanded: Bool
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(hovering ? Focus.text : Focus.text3)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 16, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Focus.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(expanded ? "Hide milestones" : "Show milestones")
        .accessibilityLabel(label)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

/// A project's milestones under its sidebar row: diamond in its color, name and "done/total".
/// A click shows the milestone's page (again for its panel); the last row adds one.
private struct SidebarMilestones: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    var body: some View {
        let milestones = store.milestones(of: project.id)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(milestones) { milestone in
                let onScreen = model.activeViewId == nil && model.scope.milestoneId == milestone.id
                SidebarMilestoneRow(milestone: milestone,
                                    selected: onScreen || model.dropTarget == SidebarMilestoneDrop.key(milestone.id),
                                    focused: model.sidebarCursor == .milestone(milestone.id, projectId: project.id)) {
                    model.clickSidebarMilestone(milestone.id, store: store)
                }
                .id(SidebarItem.milestone(milestone.id, projectId: project.id))
                .help(onScreen ? "Click again for milestone details" : milestone.name)
                .onDrop(of: [.plainText], delegate: SidebarMilestoneDrop(milestone: milestone, store: store, model: model))
                .contextMenu {
                    Button("Show tasks") { model.showMilestone(milestone.id, store: store) }
                    Button("Milestone details…") { model.openMilestone(milestone.id) }
                    Menu("Color") {
                        ForEach(Milestone.palette, id: \.self) { hex in
                            Button {
                                store.setMilestoneColor(milestone.id, colorHex: hex)
                            } label: {
                                if hex == milestone.colorHex {
                                    Label(Focus.colorName(hex), systemImage: "checkmark")
                                } else {
                                    Text(Focus.colorName(hex))
                                }
                            }
                        }
                    }
                    if milestone.isCompleted {
                        Button("Reopen") { store.reopenMilestone(milestone.id) }
                    } else {
                        Button("Mark complete") {
                            store.completeMilestone(milestone.id)
                            model.showUndoToast("Milestone completed", store: store)
                        }
                    }
                }
            }
            SidebarNewMilestoneField(project: project)
        }
        .padding(.bottom, 4)
    }
}

/// "Add milestone" under a project's milestones. ↵ adds it (with an Open toast), ⇧↵ adds it and
/// shows its page.
private struct SidebarNewMilestoneField: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let project: Project

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Focus.text3)
                .frame(width: 16)
            TextField("Add milestone", text: $name)
                .textFieldStyle(.plain)
                .font(Focus.meta)
                .focused($focused)
                .onExitCommand { name = ""; focused = false }
                .onSubmit {
                    let open = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                    guard model.addMilestone(name, projectId: project.id, open: open, store: store) != nil else { return }
                    name = ""
                    if !open { DispatchQueue.main.async { focused = true } }
                }
                .accessibilityLabel("New milestone in \(project.name)")
                .accessibilityHint("Return adds it. Shift-Return adds it and shows its page.")
        }
        .onAppear(perform: takeFocusRequest)
        .onChange(of: model.focusRequest) { _ in takeFocusRequest() }
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(focused ? Focus.lineStrong : .clear, lineWidth: 1))
    }
}

extension SidebarNewMilestoneField {
    /// The palette's "New milestone in Atlas"
    fileprivate func takeFocusRequest() {
        guard model.focusRequest?.field == .newMilestone(project.id) else { return }
        model.focusRequest = nil
        DispatchQueue.main.async { focused = true }
    }
}

private struct SidebarMilestoneRow: View {
    @EnvironmentObject private var store: TaskStore
    let milestone: Milestone
    let selected: Bool
    var focused = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let progress = store.milestoneProgress(milestone.id)
        Button(action: action) {
            HStack(spacing: 8) {
                MilestoneIcon(milestone, size: 10)
                Text(milestone.name)
                    .font(Focus.meta)
                    .foregroundColor(milestone.isCompleted ? Focus.text3 : (hovering || selected ? Focus.text : Focus.text2))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(progress.short)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundColor(store.isOverdue(milestone) ? Focus.risk : Focus.text3)
            }
            .padding(.leading, 26)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(selected ? Focus.raised : (hovering ? Focus.hover : .clear)))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(focused ? Focus.text3 : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(progress.label)
        .accessibilityLabel("\(milestone.name), \(progress.label)")
    }
}

/// Drag a project row onto another to place it there (or onto New project to move it last).
/// The payload is "project:<uuid>" so task drop targets ignore it, and this ignores tasks.
private struct SidebarProjectDrop: DropDelegate {
    let target: UUID?
    let store: TaskStore
    let model: TasksViewModel

    static let prefix = "project:"
    static func payload(_ id: UUID) -> String { prefix + id.uuidString }
    static func key(_ id: UUID?) -> String { "sidebar-project-\(id?.uuidString ?? "end")" }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }

    func dropEntered(info: DropInfo) { model.dropTarget = Self.key(target) }

    func dropExited(info: DropInfo) {
        if model.dropTarget == Self.key(target) { model.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.dropTarget = nil
        model.draggingTaskId = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let target = target
        let store = store
        let model = model
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if text.hasPrefix(Self.prefix) {
                guard let id = UUID(uuidString: String(text.dropFirst(Self.prefix.count))) else { return }
                DispatchQueue.main.async { store.moveProject(id, before: target) }
            } else if let taskId = UUID(uuidString: text), let target {
                // A task dropped on a project moves it there (status, time and timer go with it)
                DispatchQueue.main.async {
                    guard let task = store.task(taskId), task.projectId != target,
                          let name = store.project(target)?.name else { return }
                    store.moveTask(taskId, to: .project(target), reorder: false)
                    model.showUndoToast("Moved to \(name)", store: store)
                }
            }
        }
        return true
    }
}

/// The sidebar's Today row as a drop target: a task dropped on it is pinned to Today.
private struct SidebarTodayDrop: DropDelegate {
    let store: TaskStore
    let model: TasksViewModel

    static let key = "sidebar-today"

    func validateDrop(info: DropInfo) -> Bool {
        model.draggingTaskId != nil && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) { model.dropTarget = Self.key }

    func dropExited(info: DropInfo) {
        if model.dropTarget == Self.key { model.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.dropTarget = nil
        let id = model.draggingTaskId
        model.draggingTaskId = nil
        guard let id, let task = store.task(id), !task.isClosed, !store.isInFocus(task) else { return false }
        model.toggleToday([id], store: store)
        return true
    }
}

/// A sidebar milestone row as a drop target: a task dropped on it joins that milestone
/// (moving to the milestone's project if needed). One undo step, with a toast.
private struct SidebarMilestoneDrop: DropDelegate {
    let milestone: Milestone
    let store: TaskStore
    let model: TasksViewModel

    static func key(_ id: UUID) -> String { "sidebar-milestone-\(id.uuidString)" }

    func validateDrop(info: DropInfo) -> Bool {
        // Only task drags (project drags clear draggingTaskId when they start)
        model.draggingTaskId != nil && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) { model.dropTarget = Self.key(milestone.id) }

    func dropExited(info: DropInfo) {
        if model.dropTarget == Self.key(milestone.id) { model.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.dropTarget = nil
        model.draggingTaskId = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let milestone = milestone
        let store = store
        let model = model
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let taskId = UUID(uuidString: text) else { return }
            DispatchQueue.main.async {
                guard let task = store.task(taskId), task.milestoneId != milestone.id else { return }
                store.moveTask(taskId, to: .milestone(milestone.id), reorder: false)
                model.showUndoToast("Added to \(milestone.name)", store: store)
            }
        }
        return true
    }
}

/// Inline rename for a project row. Enter saves, Esc cancels.
private struct ProjectRenameField: View {
    @EnvironmentObject private var store: TaskStore
    let project: Project
    let done: () -> Void

    @State private var name = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            FocusProjectTile(name: name.isEmpty ? project.name : name, colorHex: project.colorHex, icon: project.icon)
            TextField("Project name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .focused($focused)
                .onSubmit { finish(save: true) }
                .onExitCommand { finish(save: false) }
                .onChange(of: focused) { isFocused in if !isFocused { finish(save: true) } }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.lineStrong, lineWidth: 1))
        .onAppear {
            name = project.name
            DispatchQueue.main.async { focused = true }
        }
    }

    private func finish(save: Bool) {
        guard !finished else { return }
        finished = true
        if save { store.renameProject(project.id, to: name) }
        done()
    }
}

/// "2 running" panel at the bottom of the sidebar, one line per running timer.
private struct RunningTimersPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        let running = store.runningTasks
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(running.count) running".uppercased())
                        .font(Focus.caption)
                        .tracking(0.5)
                        .foregroundColor(Focus.liveText)
                    Spacer()
                    Button("Pause all") { store.pauseAllTimers() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

                ForEach(running) { task in
                    HStack(spacing: 6) {
                        TaskTimerButton(task: task)
                        VStack(alignment: .leading, spacing: 1) {
                            TaskTitleButton(task: task, font: .system(size: 12.5, weight: .medium)) { model.openTask(task.id) }
                            if let project = store.project(of: task) {
                                Text(project.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(Focus.text3)
                                    .lineLimit(1)
                            }
                        }
                        LiveTime { now in
                            Text(Focus.clockString(store.elapsed(task, now: now)))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundColor(Focus.liveText)
                        }
                        .padding(.trailing, 4)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .focusPanel()
            .padding(.top, 8)
        }
    }
}
