import AppKit
import SwiftUI

// Notices for the main window and the menu: data problems, the first-launch sample data and the
// "Create your first project" empty state.

/// Reveals the data file in Finder (or its folder when the file isn't there).
@MainActor
enum DataFileReveal {
    static func reveal(_ url: URL?) {
        guard let url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

/// "Couldn't save your tasks · Retry · Show file", or what happened when the file couldn't be read.
/// A failed save stays until a save works; load notices can be dismissed.
struct PersistenceBanner: View {
    @EnvironmentObject private var store: TaskStore
    var compact = false

    var body: some View {
        if let issue = store.persistenceIssue {
            FocusBanner(
                tone: .risk,
                systemImage: "exclamationmark.triangle.fill",
                title: issue.title,
                message: compact ? nil : issue.message,
                primaryTitle: retryTitle(issue),
                primaryAction: { Task { await store.retryPersistence() } },
                secondaryTitle: issue.fileURL == nil ? nil : "Show file",
                secondaryAction: { DataFileReveal.reveal(issue.fileURL) },
                dismiss: issue.kind == .saveFailed ? nil : { store.dismissPersistenceIssue() }
            )
            .help(issue.detail)
        }
    }

    private func retryTitle(_ issue: PersistenceIssue) -> String? {
        switch issue.kind {
        case .saveFailed: return "Retry"
        case .loadFailed: return store.savesBlocked ? "Retry" : nil
        case .recoveredFromBackup: return nil
        }
    }
}

/// First launch: "This is sample data" with Clear sample data (undoable) and Keep it.
struct SampleDataBanner: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        if store.isLoaded, store.showsSampleDataBanner {
            FocusBanner(
                systemImage: "sparkles",
                title: "You're looking at sample data",
                message: "“\(store.sampleProjects.map(\.name).joined(separator: "”, “"))” shows how projects, sprints and timers work. Clear it when you're ready to start.",
                primaryTitle: "Clear sample data",
                primaryAction: { model.clearSampleData(store) },
                secondaryTitle: "Keep it",
                secondaryAction: { store.keepSampleData() }
            )
        }
    }
}

/// No projects at all: name the first one right here.
struct FirstProjectEmptyState: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let archived = store.archivedProjects.count
        FocusEmptyState(
            systemImage: "folder.badge.plus",
            title: "Create your first project",
            message: archived > 0
                ? "Every project is archived. Start a new one, or unarchive one from the sidebar."
                : "A project holds its tasks, milestones and sprints. Name one to start; you can add tasks right after.",
            secondaryTitle: archived > 0 ? "Show archived (\(archived))" : nil,
            secondaryAction: { model.showingArchived = true }
        ) {
            HStack(spacing: 8) {
                TextField("Project name, e.g. Website", text: $name)
                    .focusField(focused: focused)
                    .focused($focused)
                    .frame(width: 280)
                    .onSubmit(create)
                    .accessibilityLabel("New project name")
                Button("Create project", action: create)
                    .buttonStyle(.focus(.primary))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        .focusPanel()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func create() {
        guard let id = store.addProject(name: name) else { return }
        name = ""
        model.select(.project(id))
        model.startNewTask(store)
    }
}

/// A List or Board with nothing to show: says why (no tasks yet, filters hide them, the sprint is
/// empty) and offers the step that fixes it.
struct TasksEmptyStateView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let reason: TasksViewModel.EmptyReason
    var board = false

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
            .focusPanel()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        let project = model.scope.projectId.flatMap { store.project($0) }
        let milestone = model.scope.milestoneId.flatMap { store.milestone($0) }
        switch reason {
        case .noTasks:
            let hidden = board ? 0 : model.hiddenClosedCount(store)
            FocusEmptyState(
                systemImage: "checklist",
                title: (milestone?.name ?? project?.name).map { "No tasks in \($0) yet" } ?? "No tasks yet",
                message: hidden > 0
                    ? "\(TaskStore.taskCount(hidden)) from past sprints are hidden. Add a new task with the field above, or show the past ones."
                    : "Add one with the New task field above. Tokens like !high, due:fri and ~90m set the details as you type.",
                actionTitle: "New task",
                action: { model.startNewTask(store) },
                secondaryTitle: hidden > 0 ? "Show past sprints" : nil,
                secondaryAction: { model.filter.sprintSlots.insert(.closed) }
            )
        case .noMatches:
            let query = model.filter.trimmedQuery
            let chips = model.filter.chipCount
            FocusEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No tasks match",
                message: matchMessage(query: query, chips: chips),
                actionTitle: "Clear filters",
                action: { model.filter = TaskFilter() },
                secondaryTitle: !query.isEmpty && chips > 0 ? "Clear search only" : nil,
                secondaryAction: { model.filter.query = "" }
            )
        case let .sprintEmpty(waiting):
            let waitingText = waiting > 0
                ? " \(TaskStore.taskCount(waiting)) \(waiting == 1 ? "waits" : "wait") in Next and Backlog."
                : ""
            if let project {
                FocusEmptyState(
                    systemImage: "rectangle.split.3x1",
                    title: "Nothing in \(store.sprintName()) yet",
                    message: "The board shows the active sprint." + waitingText + " Plan tasks into it in Sprints, or add a new one.",
                    actionTitle: "Plan in Sprints",
                    action: { model.tab = .sprints },
                    secondaryTitle: "New task",
                    secondaryAction: { model.startNewTask(store) }
                )
            } else {
                FocusEmptyState(
                    systemImage: "rectangle.split.3x1",
                    title: "No tasks in any active sprint",
                    message: "The board shows the active sprint." + waitingText + " List shows every task.",
                    actionTitle: "Open List",
                    action: { model.tab = .list },
                    secondaryTitle: "New task",
                    secondaryAction: { model.startNewTask(store) }
                )
            }
        }
    }

    private func matchMessage(query: String, chips: Int) -> String {
        var parts: [String] = []
        if !query.isEmpty { parts.append("the search “\(query)”") }
        if chips > 0 { parts.append(chips == 1 ? "1 filter" : "\(chips) filters") }
        let hiding = parts.joined(separator: " and ")
        return "Tasks exist here, but \(hiding) \(parts.count > 1 || chips > 1 ? "hide" : "hides") all of them."
    }
}
