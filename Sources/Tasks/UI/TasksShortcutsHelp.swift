import SwiftUI

/// The keyboard shortcuts popover (⌘/ or the ? button in the sidebar): every shortcut, grouped.
struct TasksShortcutsHelp: View {
    struct Shortcut: Identifiable {
        let label: String
        let keys: [String]
        var id: String { label }
    }

    struct Section: Identifiable {
        let title: String
        let shortcuts: [Shortcut]
        var id: String { title }
    }

    /// Global hotkeys set in Settings › General, as key caps; nil when off (AppState sets them).
    static var timerShortcutKeys: [String]?
    static var menuSearchShortcutKeys: [String]?

    static let sections: [Section] = [
        Section(title: "Jump and find", shortcuts: [
            Shortcut(label: "Jump anywhere, or run a command", keys: ["⌘", "K"]),
            Shortcut(label: "In the palette: commands only", keys: [">"]),
            Shortcut(label: "In the palette: open in a panel, stay here", keys: ["⇧", "↵"]),
            Shortcut(label: "Filter this view", keys: ["⌘", "F"]),
            Shortcut(label: "Board, List, Sprints, Milestones", keys: ["⌘", "1–4"]),
            Shortcut(label: "Previous or next in the sidebar (views too)", keys: ["⌥", "⌘", "↑↓"]),
            Shortcut(label: "Move to the sidebar", keys: ["⌘", "0"]),
            Shortcut(label: "Sidebar: show milestones, hide them", keys: ["→", "←"]),
            Shortcut(label: "Open or close the panel", keys: ["⌘", "I"]),
        ]),
        Section(title: "Create", shortcuts: [
            Shortcut(label: "New task", keys: ["⌘", "N"]),
            Shortcut(label: "New project", keys: ["⇧", "⌘", "N"]),
        ]),
        Section(title: "Selection", shortcuts: [
            Shortcut(label: "Move up or down (the panel follows)", keys: ["↑", "↓"]),
            Shortcut(label: "Open task", keys: ["↵"]),
            Shortcut(label: "Add to the selection", keys: ["⌘", "Click"]),
            Shortcut(label: "Select a range", keys: ["⇧", "Click"]),
            Shortcut(label: "Grow the selection", keys: ["⇧", "↑↓"]),
            Shortcut(label: "Select all", keys: ["⌘", "A"]),
            Shortcut(label: "Select none", keys: ["⇧", "⌘", "A"]),
            Shortcut(label: "Previous or next in the panel", keys: ["⌘", "[ ]"]),
            Shortcut(label: "Close panel or clear selection", keys: ["esc"]),
        ]),
        Section(title: "Edit the selection", shortcuts: [
            Shortcut(label: "Status", keys: ["S"]),
            Shortcut(label: "Priority", keys: ["P"]),
            Shortcut(label: "High, medium, low priority", keys: ["1", "2", "3"]),
            Shortcut(label: "Milestone", keys: ["M"]),
            Shortcut(label: "Sprint", keys: ["R"]),
            Shortcut(label: "Due date (type fri, nov 18…)", keys: ["D"]),
            Shortcut(label: "Expected time", keys: ["E"]),
            Shortcut(label: "Time spent (1h sets, +15m adds)", keys: ["T"]),
            Shortcut(label: "Labels (toggle several; type to create)", keys: ["L"]),
            Shortcut(label: "Move to project", keys: ["⇧", "M"]),
            Shortcut(label: "Done, or reopen", keys: ["X"]),
            Shortcut(label: "Move up or down in its group", keys: ["⌥", "↑↓"]),
            Shortcut(label: "Add to Today or remove", keys: ["⌘", "T"]),
            Shortcut(label: "Duplicate", keys: ["⌘", "D"]),
            Shortcut(label: "Delete", keys: ["⌘", "⌫"]),
            Shortcut(label: "Undo", keys: ["⌘", "Z"]),
            Shortcut(label: "Redo", keys: ["⇧", "⌘", "Z"]),
            Shortcut(label: "Rename in the list", keys: ["Double-click"]),
        ]),
        Section(title: "In a picker", shortcuts: [
            Shortcut(label: "Filter the choices", keys: ["Type"]),
            Shortcut(label: "Choose", keys: ["↑", "↓"]),
            Shortcut(label: "Set it", keys: ["↵"]),
            Shortcut(label: "Labels: toggle and stay open", keys: ["↵", "Space"]),
            Shortcut(label: "Close", keys: ["esc"]),
        ]),
        Section(title: "Timers", shortcuts: [
            Shortcut(label: "Start or pause", keys: ["Space"]),
            Shortcut(label: "Start, pausing every other timer", keys: ["⌥", "Space"]),
            Shortcut(label: "Same, on a play button", keys: ["⌥", "Click"]),
            Shortcut(label: "Pause all timers", keys: ["⇧", "Space"]),
        ]),
        Section(title: "New task (every New task box)", shortcuts: [
            Shortcut(label: "Add and open", keys: ["⇧", "↵"]),
            Shortcut(label: "New project or milestone: add and open", keys: ["⇧", "↵"]),
            Shortcut(label: "Expected time", keys: ["2h", "~90m"]),
            Shortcut(label: "Sprint", keys: ["#next", "#backlog"]),
            Shortcut(label: "Milestone", keys: ["@beta"]),
            Shortcut(label: "Priority", keys: ["!high", "!low"]),
            Shortcut(label: "Status", keys: ["*review"]),
            Shortcut(label: "Label (new names are created)", keys: ["%bug", "%\"needs review\""]),
            Shortcut(label: "Project", keys: ["+atlas"]),
            Shortcut(label: "Due date", keys: ["due:fri", "tomorrow"]),
            Shortcut(label: "Complete the word (menu bar, quick add)", keys: ["Tab"]),
            Shortcut(label: "Every option (in the list)", keys: ["/"]),
        ]),
        Section(title: "Menu bar", shortcuts: [
            Shortcut(label: "Move through the tasks", keys: ["↑", "↓"]),
            Shortcut(label: "Start or pause the timer", keys: ["Space"]),
            Shortcut(label: "Start, pausing every other timer", keys: ["⌥", "Space"]),
            Shortcut(label: "Timer of the first nine tasks", keys: ["⌘", "1–9"]),
            Shortcut(label: "Open in FlowMate", keys: ["↵"]),
            Shortcut(label: "Show or hide a project's tasks", keys: ["→", "←"]),
            Shortcut(label: "Add the search text as a task", keys: ["⌘", "↵"]),
        ]),
        Section(title: "Help", shortcuts: [
            Shortcut(label: "Show these shortcuts", keys: ["⌘", "/"]),
        ]),
    ]

    /// The global hotkeys that are on, for the "Anywhere" section
    static var anywhere: [Shortcut] {
        var rows: [Shortcut] = []
        if let keys = QuickAddPanel.shortcutKeys { rows.append(Shortcut(label: "New task box over any app", keys: keys)) }
        if let keys = timerShortcutKeys { rows.append(Shortcut(label: "Pause or resume the last timer", keys: keys)) }
        if let keys = menuSearchShortcutKeys { rows.append(Shortcut(label: "Menu bar search", keys: keys)) }
        return rows
    }

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 380)
        .frame(height: 600)
        .background(Focus.raised)
        .focusLight()
    }

    /// Every section, unscrolled
    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard shortcuts").font(Focus.header).foregroundColor(Focus.text)
            let anywhere = Self.anywhere
            if !anywhere.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    FocusCaption(text: "Anywhere").padding(.bottom, 4)
                    ForEach(anywhere) { shortcut in
                        FocusShortcutRow(label: shortcut.label, keys: shortcut.keys)
                    }
                }
            }
            ForEach(Self.sections) { section in
                VStack(alignment: .leading, spacing: 2) {
                    FocusCaption(text: section.title).padding(.bottom, 4)
                    ForEach(section.shortcuts) { shortcut in
                        FocusShortcutRow(label: shortcut.label, keys: shortcut.keys)
                    }
                }
            }
            Text("Single keys and shortcuts that edit tasks wait while you're typing in a field. With several tasks selected, they act on all of them. Turn on the global hotkeys in Settings › General.")
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
    }
}
