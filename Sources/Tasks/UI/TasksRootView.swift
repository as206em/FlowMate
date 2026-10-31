import SwiftUI

/// Root of the main window: sidebar, header and the current view, with the task side panel on top.
struct TasksRootView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        HStack(spacing: 0) {
            TasksSidebar()
            main
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Focus.canvas)
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onChange(of: store.workspace.projects.map(\.id)) { _ in
            // The selected or open project was deleted elsewhere (e.g. the menu bar)
            model.dropStaleIds(store)
        }
        .onChange(of: store.workspace.milestones.map(\.id)) { _ in model.dropStaleIds(store) }
        // The restored scope (last launch) may name a project that's gone
        .onAppear { if store.isLoaded { model.dropStaleIds(store) } }
        .onChange(of: store.isLoaded) { loaded in if loaded { model.dropStaleIds(store) } }
        .sheet(isPresented: Binding(
            get: { model.completingSprintProjectId != nil },
            set: { if !$0 { model.completingSprintProjectId = nil } }
        )) {
            if let id = model.completingSprintProjectId, let project = store.project(id) {
                CompleteSprintSheet(project: project)
                    .environmentObject(store)
                    .environmentObject(model)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.adjustingTimeTaskId != nil },
            set: { if !$0 { model.adjustingTimeTaskId = nil } }
        )) {
            if let id = model.adjustingTimeTaskId, let task = store.task(id) {
                AdjustTimeSheet(task: task)
                    .environmentObject(store)
                    .environmentObject(model)
            }
        }
        .onChange(of: store.workspace.tasks.map(\.id)) { _ in
            // A selected task was deleted (here, by undo or from the menu bar)
            model.pruneSelection(store)
        }
        .onChange(of: store.lastUndoId) { _ in
            // A newer step means the toast's Undo would revert something else: hide it
            if let toast = model.toast, toast.undoId != nil, toast.undoId != store.lastUndoId { model.dismissToast() }
        }
    }

    private var main: some View {
        VStack(spacing: 0) {
            TasksHeader()
            if model.showsFilterBar, !showsFirstProject {
                TaskFilterBar()
            }
            notices
            LongRunBanner()
            if usesNativeTable {
                // List and Sprints scroll inside their own native table (rows are recycled)
                nativeTableContent
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .padding(.top, model.showsFilterBar ? 16 : 24)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 72)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .onChange(of: model.selectedTaskId) { id in
                        // Keep the keyboard selection on screen
                        guard let id, !model.isPanelOpen else { return }
                        withAnimation(Focus.hoverAnimation) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if model.isMultiSelecting, !model.isPanelOpen {
                    TaskBulkBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 22)
            .animation(Focus.menuAnimation, value: model.isMultiSelecting)
        }
        .overlay { taskPanelLayer }
        // Above the side panel too: actions taken inside it (duplicate, convert a subtask) show their toast
        .overlay(alignment: .bottom) {
            toastLayer
                .padding(.bottom, 22 + (model.isMultiSelecting && !model.isPanelOpen ? Focus.actionBarHeight + 10 : 0))
                .animation(Focus.menuAnimation, value: model.isMultiSelecting)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = model.toast {
            let canUndo = toast.undoId != nil && toast.undoId == store.lastUndoId
            let canOpen = toast.openTaskId.map { store.task($0) != nil } ?? false
            FocusToast(
                message: toast.message,
                actionTitle: canUndo ? "Undo" : nil,
                actionKey: canUndo ? "⌘Z" : nil,
                action: { model.undoFromToast(store) },
                secondaryTitle: canOpen ? "Open" : nil,
                secondaryAction: { model.openFromToast() },
                dismiss: { model.dismissToast(toast.id) }
            )
            .id(toast.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                // Quietly goes away; hovering doesn't matter, ⌘Z still works after
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                model.dismissToast(toast.id)
            }
        }
    }

    /// Save/load problems and the first-launch sample data banner, under the filter bar.
    private var notices: some View {
        VStack(spacing: 8) {
            PersistenceBanner()
            SampleDataBanner()
        }
        .padding(.horizontal, 28)
        .padding(.top, store.persistenceIssue != nil || store.showsSampleDataBanner ? 12 : 0)
    }

    /// No projects at all (only All projects can be on screen): the "Create your first project" state.
    private var showsFirstProject: Bool {
        store.isLoaded && store.projects.isEmpty && model.scope.projectId == nil
    }

    /// List, and Sprints of a project: views drawn by the native table
    private var usesNativeTable: Bool {
        guard !showsFirstProject else { return false }
        switch model.effectiveTab {
        case .list: return true
        case .sprints: return model.scope.projectId.flatMap { store.project($0) } != nil
        case .board, .milestones: return false
        }
    }

    @ViewBuilder
    private var nativeTableContent: some View {
        if model.effectiveTab == .sprints, let project = model.scope.projectId.flatMap({ store.project($0) }) {
            VStack(alignment: .leading, spacing: 0) {
                SprintHeader(project: project)
                    .padding(.top, 24)
                    .padding(.horizontal, TaskTableCell.sidePadding)
                SprintPlanView(projectId: project.id)
            }
        } else {
            TaskListView()
        }
    }

    @ViewBuilder
    private var content: some View {
        if showsFirstProject {
            FirstProjectEmptyState()
        } else {
            scopeContent
        }
    }

    @ViewBuilder
    private var scopeContent: some View {
        let project = model.scope.projectId.flatMap { store.project($0) }
        VStack(alignment: .leading, spacing: 0) {
            if let project, model.effectiveTab == .board || model.effectiveTab == .sprints {
                SprintHeader(project: project)
            }
            switch model.effectiveTab {
            case .board:
                BoardView()
            case .list:
                TaskListView()
            case .sprints:
                if let project { SprintPlanView(projectId: project.id) }
            case .milestones:
                MilestonesView()
            }
        }
    }

    // MARK: - Side panel

    /// What the side panel shows: a task, a project or a milestone (whichever is open and still exists).
    private enum PanelContent: Equatable {
        case task(UUID), project(UUID), milestone(UUID)

        var id: String {
            switch self {
            case let .task(id): return "task-\(id)"
            case let .project(id): return "project-\(id)"
            case let .milestone(id): return "milestone-\(id)"
            }
        }
    }

    private var panelContent: PanelContent? {
        if let id = model.openTaskId, store.task(id) != nil { return .task(id) }
        switch model.openDetail {
        case let .project(id)? where store.project(id) != nil: return .project(id)
        case let .milestone(id)? where store.milestone(id) != nil: return .milestone(id)
        default: return nil
        }
    }

    /// Scrim plus the 860pt panel sliding in from the right. Task, project and milestone panels share
    /// it. Closes with ×, Esc or a click on the scrim.
    private var taskPanelLayer: some View {
        let content = panelContent
        return GeometryReader { geo in
            ZStack(alignment: .trailing) {
                if let content {
                    Focus.scrim
                        .contentShape(Rectangle())
                        .onTapGesture { model.closePanel() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                    panel(content)
                        .id(content.id)
                        .frame(width: min(Focus.taskPanelWidth, geo.size.width))
                        .frame(maxHeight: .infinity)
                        .background(Focus.canvas)
                        .overlay(alignment: .leading) { Rectangle().fill(Focus.lineStrong).frame(width: 1) }
                        .shadow(color: .black.opacity(0.12), radius: 24, x: -18)
                        .shadow(color: .black.opacity(0.04), radius: 4, x: -2)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    // Esc closes the panel
                    Button("Close panel") { model.closePanel() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
        }
        .allowsHitTesting(content != nil)
    }

    /// Panel content: TaskDetailPanel.swift, ProjectPanel.swift, MilestonePanel.swift.
    @ViewBuilder
    private func panel(_ content: PanelContent) -> some View {
        switch content {
        case let .task(id): TaskDetailPanel(taskId: id)
        case let .project(id): ProjectPanel(projectId: id)
        case let .milestone(id): MilestonePanel(milestoneId: id)
        }
    }
}
