import SwiftUI
import AppKit

/// The dropdown that opens from the menu bar icon, in Focus (docs/design/reference/FocusMenu.dc.html):
/// search / quick add, the tasks in progress, the proofreading tools and a footer.
struct StatusMenuView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: TaskStore
    @ObservedObject private var menu = MenuState.shared

    @State private var query = ""
    /// Keyboard highlight in the search results; ↵ activates it
    @State private var highlight: MenuSearchItem?
    @State private var scrollHeight: CGFloat = 0
    /// The proofreading tools folded to one line, so the tasks get the room (kept across launches)
    @AppStorage(StatusMenuView.proofreadingCollapsedKey) private var proofreadingCollapsed = false

    static let proofreadingCollapsedKey = "FlowMate.menuProofreadingCollapsed"

    var body: some View {
        VStack(spacing: 0) {
            header
            MenuSearchField(
                query: $query,
                target: target,
                setTarget: { store.rememberProject($0) },
                hint: keyHint,
                submit: submit,
                handleKey: handleKey
            )
            if let added = menu.added {
                addedNote(added)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if store.persistenceIssue?.kind == .saveFailed {
                            FocusNotice(text: "Couldn't save your tasks. Changes are kept while FlowMate runs.", actionTitle: "Retry") {
                                Task { await store.retryPersistence() }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        }
                        if isSearching {
                            MenuSearchResults(
                                query: query,
                                results: searchResults,
                                highlight: currentHighlight,
                                target: target,
                                setTarget: { store.rememberProject($0) },
                                activate: activate
                            )
                        } else {
                            MenuInProgressSection()
                        }
                        FocusDivider()
                        proofreading
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    })
                }
                .frame(height: min(max(scrollHeight, 1), maxScrollHeight))
                .onPreferenceChange(ContentHeightKey.self) { height in
                    scrollHeight = height
                    // The menu bar window doesn't shrink on its own when rows go away (a timer
                    // paused), which left blank space above and below the content
                    DispatchQueue.main.async { MenuBarPanel.fitToContent() }
                }
                .onChange(of: menu.highlight) { item in
                    guard let item else { return }
                    withAnimation(Focus.hoverAnimation) { proxy.scrollTo(item) }
                }
            }

            footer
        }
        .frame(width: Focus.menuWidth)
        .background(Focus.canvas)
        .focusLight()
        // New text, new results: ↵ goes back to the first match
        .onChange(of: query) { _ in
            highlight = nil
            menu.highlight = nil
        }
        .onAppear { menu.highlight = nil }
    }

    // MARK: - Tasks

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Where new tasks go: the last project used (shown inside the field; click it to change)
    private var target: Project? { store.menuQuickAddTarget }

    private var searchResults: MenuSearchResultsModel {
        store.menuSearchResults(query, canAdd: target != nil)
    }

    /// The highlight, or the first result when the user hasn't moved it (or it left the list)
    private var currentHighlight: MenuSearchItem? {
        searchResults.validated(highlight)
    }

    private var browse: MenuBrowseModel {
        store.menuBrowseItems()
    }

    /// The browse highlight while it's still on screen
    private var browseHighlight: MenuRowItem? { browse.validated(menu.highlight) }

    /// What the keys do right now, inside the field
    private var keyHint: String? {
        if isSearching {
            guard let current = currentHighlight else { return target == nil ? nil : "⌘↵ add" }
            return current == .add ? "↵ add" : "↵ open"
        }
        return browseHighlight == nil ? nil : "␣ timer"
    }

    /// The menu's keys. Searching: ↑/↓ move through results, ↵ opens, ⌘↵ adds. Field empty:
    /// ↑/↓ move through the tasks in progress; Space starts or pauses; ↵ opens; Esc clears the highlight.
    private func handleKey(_ key: MenuKey) -> Bool {
        if isSearching {
            switch key {
            case .up: highlight = searchResults.moving(currentHighlight, by: -1)
            case .down: highlight = searchResults.moving(currentHighlight, by: 1)
            case let .returnKey(command): submit(command: command)
            case .escape:
                query = ""
            default: return false
            }
            return true
        }
        let current = browseHighlight
        switch key {
        case .up, .down:
            menu.highlight = browse.moving(current, by: key == .up ? -1 : 1)
            return true
        case .space:
            guard let current else { return false }
            store.toggleTimer(current.taskId)
            return true
        case .returnKey:
            guard let current else { return false }
            MenuNavigation.openTask(current.taskId)
            return true
        case .left, .right:
            return false
        case .escape:
            guard current != nil else { return false }
            menu.highlight = nil
            return true
        }
    }

    /// ↵ opens the highlighted result (or adds, when the Add row is highlighted); ⌘↵ always adds.
    private func submit(command: Bool) {
        guard isSearching else { return }
        if command {
            addTask()
        } else if let current = currentHighlight {
            activate(current)
        }
    }

    private func activate(_ item: MenuSearchItem) {
        switch item {
        case .add:
            addTask()
        case .project(let id):
            MenuNavigation.openProject(id)
        case .milestone(let id):
            MenuNavigation.openMilestone(id)
        case .task(let id):
            MenuNavigation.openTask(id)
        }
    }

    /// Adds with the New task tokens (!high @milestone due:fri ~90m) and remembers the project.
    private func addTask() {
        guard let target, let outcome = store.quickAddTask(query, projectId: target.id) else { return }
        query = ""
        highlight = nil
        let project = store.project(outcome.projectId)?.name ?? target.name
        menu.added = MenuState.AddedNote(
            message: (["Added to \(project)"] + outcome.applied).joined(separator: " · "),
            taskId: outcome.taskId
        )
    }

    /// "✓ Added to Atlas · High   Open", for a few seconds after adding
    private func addedNote(_ note: MenuState.AddedNote) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Focus.ok)
            Text(note.message)
                .font(.system(size: 12))
                .foregroundColor(Focus.text2)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Open") { MenuNavigation.openTask(note.taskId) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Focus.text)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Focus.sidebar)
        .overlay(alignment: .bottom) { FocusDivider() }
        .task(id: note.id) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if menu.added?.id == note.id { menu.added = nil }
        }
    }

    /// The scrolling middle stops growing before the panel runs off the screen
    private var maxScrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(260, screen - 190)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            FocusAppTile(size: 20)
            Text("FlowMate").font(.system(size: 14, weight: .semibold)).foregroundColor(Focus.text)
            Spacer(minLength: 8)
            connectionStatus
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) { FocusDivider() }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        let name = appState.proofreadingProvider.displayName
        switch appState.connectionState {
        case .checking:
            FocusStatusLabel(text: "Checking \(name)…", tone: .pending)
        case .connected:
            FocusStatusLabel(text: "\(name) ready", tone: .ok)
        case .failed(let message):
            FocusStatusLabel(text: "\(name) offline", tone: .risk).help(message)
        }
    }

    // MARK: - Proofreading

    /// The caption line; a click folds the tools to this one line or opens them again.
    private var proofreadingHeader: some View {
        Button {
            withAnimation(Focus.hoverAnimation) { proofreadingCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Focus.text3)
                    .rotationEffect(.degrees(proofreadingCollapsed ? 0 : 90))
                    .frame(width: 10)
                FocusCaption(text: "Proofreading")
                if proofreadingCollapsed, notice != nil {
                    // Something needs fixing: open the tools to see it
                    Circle().fill(Focus.risk).frame(width: 6, height: 6)
                }
                Spacer()
                Text("Select text, press")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                FocusKey(text: KeyboardShortcutManager.displayString(for: appState.keyboardShortcut))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(proofreadingCollapsed ? "Show the proofreading tools" : "Fold the proofreading tools to one line")
        .accessibilityLabel("Proofreading tools")
        .accessibilityValue(proofreadingCollapsed ? "Collapsed" : "Expanded")
    }

    private var proofreading: some View {
        VStack(alignment: .leading, spacing: 10) {
            proofreadingHeader
            if !proofreadingCollapsed {
                proofreadingTools
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, proofreadingCollapsed ? 12 : 14)
    }

    @ViewBuilder
    private var proofreadingTools: some View {
        if let notice = notice {
            notice
        }

        Button {
            MenuBarPanel.close()
            appState.proofreadClipboard()
        } label: {
            Label(appState.isProcessing ? "Proofreading…" : "Proofread clipboard", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.focus(fullWidth: true))
        .disabled(appState.isProcessing)

        HStack(spacing: 8) {
            FocusTabs(
                options: AIProvider.allCases.map { (value: $0, label: $0.displayName) },
                selection: Binding(
                    get: { appState.proofreadingProvider },
                    set: { appState.setProvider($0) }
                )
            )
            .fixedSize()
            .accessibilityLabel("Provider")

            if appState.modelChoices.isEmpty {
                Text("No models found")
                    .font(Focus.control)
                    .foregroundColor(Focus.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusField()
            } else {
                FocusPicker(
                    options: appState.modelChoices,
                    selection: Binding(
                        get: { appState.proofreadingModel },
                        set: { appState.updateCurrentModel($0) }
                    ),
                    title: { $0 }
                )
                .accessibilityLabel("Model")
            }
        }

        Toggle(isOn: Binding(
            get: { appState.showDialog },
            set: { appState.updateShowDialog($0) }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Review first").font(Focus.control).foregroundColor(Focus.text)
                Text("Off: replace right away").font(.system(size: 12)).foregroundColor(Focus.text3)
            }
        }
        .toggleStyle(.focus)

        if !appState.history.isEmpty {
            recent
        }
    }

    /// The one most important problem, if any, with a way to fix it
    private var notice: FocusNotice? {
        if !appState.hasAccessibilityPermission {
            return FocusNotice(
                text: "FlowMate needs Accessibility access to read and replace selected text.",
                actionTitle: "Allow",
                action: { appState.requestAccessibilityPermission() }
            )
        }
        if case .failed = appState.connectionState {
            return FocusNotice(
                text: "Can't reach \(appState.proofreadingProvider.displayName). Check that it's running.",
                actionTitle: "Retry",
                action: { appState.checkConnection() }
            )
        }
        if appState.isSelectedModelMissing {
            return FocusNotice(text: "Model “\(appState.proofreadingModel)” isn't installed. Pick another.")
        }
        return nil
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FocusCaption(text: "Recent")
                Spacer()
                Button("Clear") { appState.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
            }
            VStack(spacing: 0) {
                ForEach(Array(appState.history.prefix(3).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { FocusDivider() }
                    RecentResultRow(item: item) {
                        MenuBarPanel.close()
                        appState.showHistoryItem(item)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusCard))
            .focusPanel(radius: Focus.radiusCard)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            FooterButton(title: "Open FlowMate", key: "⌘O") { MenuNavigation.openApp() }
                .keyboardShortcut("o")
            FooterButton(title: "Settings", key: "⌘,") {
                MenuBarPanel.close()
                appState.showSettings(nil)
            }
            .keyboardShortcut(",")
            Spacer(minLength: 4)
            FooterButton(title: "Quit", key: "⌘Q") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(Focus.sidebar)
        .overlay(alignment: .top) { FocusDivider() }
    }
}

/// A recent proofreading result: one line of text and how long ago
private struct RecentResultRow: View {
    let item: ProofreadingHistoryItem
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(item.preview)
                    .font(.system(size: 12.5))
                    .foregroundColor(Focus.text2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(hovering ? Focus.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Ghost footer button with its shortcut hint
private struct FooterButton: View {
    let title: String
    let key: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(Focus.text2)
                FocusKey(text: key)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Helpers for the menu bar panel window
enum MenuBarPanel {
    /// Closes the panel, e.g. before opening another window
    static func close() {
        (window ?? NSApp.keyWindow)?.close()
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.className.contains("MenuBarExtra") && $0.isVisible }
    }

    /// Sizes the open panel to its content, keeping its top edge under the menu bar.
    @MainActor
    static func fitToContent() {
        guard let window, let content = window.contentView else { return }
        let size = content.fittingSize
        guard size.height > 0, abs(size.height - window.frame.height) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y = frame.maxY - size.height
        frame.size.height = size.height
        window.setFrame(frame, display: true)
    }
}
