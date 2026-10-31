import AppKit
import SwiftUI

/// ⌘K: a field over the window that finds any project, milestone or task, Today, and commands.
/// ↑/↓ move, ↵ goes (or runs), ⇧↵ opens the item's panel over the current view, ">" lists
/// commands only, Esc or a click outside closes. Results: TasksViewModel+Palette.
struct CommandPalette: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @FocusState private var focused: Bool

    static let width: CGFloat = 600

    var body: some View {
        let results = model.paletteResults(store)
        let items = results.items
        let current = results.validated(model.paletteHighlight)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Focus.text3)
                TextField("Jump to a project, milestone or task. Type > for commands", text: $model.paletteQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundColor(Focus.text)
                    .focused($focused)
                    .accessibilityLabel("Jump to or run")
                FocusKey(text: "esc")
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            FocusDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let caption = caption(isEmpty: items.isEmpty) {
                            FocusCaption(text: caption).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                        }
                        if items.isEmpty {
                            Text(model.paletteQuery.hasPrefix(">") ? "No command matches." : "Nothing matches. Try fewer letters, or > for commands.")
                                .font(Focus.meta)
                                .foregroundColor(Focus.text3)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                        }
                        ForEach(items, id: \.self) { item in
                            PaletteRow(item: item, highlighted: item == current) {
                                model.runPaletteItem(item, inPanel: NSEvent.modifierFlags.contains(.shift), store: store)
                            }
                            .id(item)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: model.paletteHighlight) { item in
                    if let item { proxy.scrollTo(item) }
                }
            }
            FocusDivider()
            HStack(spacing: 12) {
                hint("↑↓", "move")
                hint("↵", "go")
                hint("⇧↵", "open in panel")
                hint(">", "commands")
                Spacer(minLength: 8)
                Text("⌘F filters this view").font(.system(size: 11.5)).foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Focus.sidebar)
        }
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: Focus.radiusPanel).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusPanel).strokeBorder(Focus.lineStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
        .background(KeyDownMonitor(isActive: model.showingPalette) { handle($0) })
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func caption(isEmpty: Bool) -> String? {
        let query = model.paletteQuery.trimmingCharacters(in: .whitespaces)
        if query == ">" { return "Commands" }
        guard query.isEmpty else { return nil }
        return model.paletteRecents.contains(where: { model.paletteItem(forKey: $0, store: store) != nil }) ? "Recent" : "Jump to"
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            FocusKey(text: key)
            Text(label).font(.system(size: 11.5)).foregroundColor(Focus.text3)
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let key = ListKey(event) else { return false }
        switch key {
        case .up: model.movePaletteHighlight(-1, store: store)
        case .down: model.movePaletteHighlight(1, store: store)
        case let .returnKey(shift):
            guard let item = model.paletteCurrent(store) else { return true }
            model.runPaletteItem(item, inPanel: shift, store: store)
        case .escape: model.closePalette()
        case .tab: model.movePaletteHighlight(1, store: store)
        }
        return true
    }
}

/// One palette row: an icon, the name, where it lives, and the keys of a command.
private struct PaletteRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let item: MenuSearchItem
    let highlighted: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.frame(width: 20)
                Text(title)
                    .font(Focus.row)
                    .foregroundColor(isClosed ? Focus.text3 : Focus.text)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(Focus.text3).lineLimit(1)
                }
                Spacer(minLength: 8)
                if case let .command(command) = item {
                    HStack(spacing: 3) { ForEach(model.paletteKeys(command), id: \.self) { FocusKey(text: $0) } }
                } else if highlighted {
                    Text(kind).font(.system(size: 11.5)).foregroundColor(Focus.text3)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(highlighted ? Focus.selected : (hovering ? Focus.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(kind)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private var isClosed: Bool {
        if case let .task(id) = item { return store.task(id)?.isClosed ?? false }
        return false
    }

    private var title: String {
        switch item {
        case .add: return "Add"
        case .today: return "Today"
        case let .project(id): return store.project(id)?.name ?? ""
        case let .milestone(id): return store.milestone(id)?.name ?? ""
        case let .task(id): return store.task(id)?.title ?? ""
        case let .command(command): return model.paletteTitle(command, store: store)
        }
    }

    private var subtitle: String {
        switch item {
        case .today: return "Overdue, due today and pinned"
        case let .project(id): return store.project(id)?.isArchived == true ? "Archived" : "\(store.openCount(id)) open"
        case let .milestone(id): return store.milestone(id).flatMap { store.project($0.projectId)?.name } ?? ""
        case let .task(id): return store.task(id).flatMap { store.project($0.projectId)?.name } ?? ""
        case .add, .command: return ""
        }
    }

    private var kind: String {
        switch item {
        case .today, .project, .milestone: return "↵ go · ⇧↵ panel"
        case .task: return "↵ go · ⇧↵ open here"
        case .add, .command: return "Command"
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .today:
            Image(systemName: "sun.max").font(.system(size: 13, weight: .medium)).foregroundColor(Focus.text2)
        case let .project(id):
            if let project = store.project(id) { FocusProjectTile(project: project, size: 16) }
        case let .milestone(id):
            if let milestone = store.milestone(id) { MilestoneIcon(milestone, size: 12) }
        case let .task(id):
            if let task = store.task(id) { WorkflowStatusIcon(status: store.status(of: task), size: 14) }
        case .command, .add:
            Image(systemName: "chevron.right.2").font(.system(size: 10, weight: .bold)).foregroundColor(Focus.text3)
        }
    }
}

/// "Press ⌘K to jump anywhere": shown once, until it's closed or the palette is used.
struct PaletteHint: View {
    @EnvironmentObject private var model: TasksViewModel
    @AppStorage(TasksViewModel.paletteHintDismissedKey) private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Focus.text2)
                Text("Press").font(.system(size: 12.5)).foregroundColor(Focus.text2)
                HStack(spacing: 3) { FocusKey(text: "⌘"); FocusKey(text: "K") }
                Text("to jump anywhere or run a command. Single keys edit the selection: S status, P priority, D due…")
                    .font(.system(size: 12.5))
                    .foregroundColor(Focus.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Show shortcuts") { model.showingShortcuts = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Focus.text)
                FocusIconButton(systemName: "xmark", label: "Dismiss hint", size: 22) { dismissed = true }
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.sidebar))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.hairline, lineWidth: 1))
            .padding(.horizontal, 28)
            .padding(.top, 12)
        }
    }
}
