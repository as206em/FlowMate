import SwiftUI

/// The keyboard shortcuts popover (⌘/ or the ? button in the sidebar).
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

    static let sections: [Section] = [
        Section(title: "Create and find", shortcuts: [
            Shortcut(label: "New task", keys: ["⌘", "N"]),
            Shortcut(label: "New project", keys: ["⇧", "⌘", "N"]),
            Shortcut(label: "Search", keys: ["⌘", "F"]),
            Shortcut(label: "Board, List, Sprints, Milestones", keys: ["⌘", "1–4"]),
            Shortcut(label: "Previous or next in the sidebar", keys: ["⌥", "⌘", "↑↓"]),
        ]),
        Section(title: "Selection", shortcuts: [
            Shortcut(label: "Move up or down", keys: ["↑", "↓"]),
            Shortcut(label: "Open task", keys: ["↵"]),
            Shortcut(label: "Start or pause timer", keys: ["Space"]),
            Shortcut(label: "Add to the selection", keys: ["⌘", "Click"]),
            Shortcut(label: "Select a range", keys: ["⇧", "Click"]),
            Shortcut(label: "Grow the selection", keys: ["⇧", "↑↓"]),
            Shortcut(label: "Select all", keys: ["⌘", "A"]),
            Shortcut(label: "Previous or next task in the panel", keys: ["⌘", "[ ]"]),
            Shortcut(label: "Close panel or clear selection", keys: ["esc"]),
        ]),
        Section(title: "Edit", shortcuts: [
            Shortcut(label: "Delete task", keys: ["⌘", "⌫"]),
            Shortcut(label: "Duplicate task", keys: ["⌘", "D"]),
            Shortcut(label: "Add to Today or remove", keys: ["⌘", "T"]),
            Shortcut(label: "Undo", keys: ["⌘", "Z"]),
            Shortcut(label: "Redo", keys: ["⇧", "⌘", "Z"]),
            Shortcut(label: "Rename in the list", keys: ["Double-click"]),
        ]),
        Section(title: "New task", shortcuts: [
            Shortcut(label: "Add and open", keys: ["⇧", "↵"]),
            Shortcut(label: "New project or milestone: add and open", keys: ["⇧", "↵"]),
            Shortcut(label: "Expected time", keys: ["2h", "90m"]),
            Shortcut(label: "Sprint", keys: ["#next", "#backlog"]),
            Shortcut(label: "Milestone", keys: ["@beta"]),
            Shortcut(label: "Priority", keys: ["!high", "!low"]),
            Shortcut(label: "Due date", keys: ["due:fri", "tomorrow"]),
            Shortcut(label: "Every option", keys: ["/"]),
        ]),
        Section(title: "Menu bar", shortcuts: [
            Shortcut(label: "Move through tasks in progress", keys: ["↑", "↓"]),
            Shortcut(label: "Start or pause the timer", keys: ["Space"]),
            Shortcut(label: "Open in FlowMate", keys: ["↵"]),
            Shortcut(label: "Show or hide a project's tasks", keys: ["→", "←"]),
            Shortcut(label: "Add the search text as a task", keys: ["⌘", "↵"]),
        ]),
        Section(title: "Help", shortcuts: [
            Shortcut(label: "Show these shortcuts", keys: ["⌘", "/"]),
        ]),
    ]

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 340)
        .frame(height: 560)
        .background(Focus.raised)
        .focusLight()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard shortcuts").font(Focus.header).foregroundColor(Focus.text)
            if let quickAdd = QuickAddPanel.shortcutKeys {
                VStack(alignment: .leading, spacing: 2) {
                    FocusCaption(text: "Anywhere").padding(.bottom, 4)
                    FocusShortcutRow(label: "New task box over any app", keys: quickAdd)
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
            Text("Shortcuts that edit tasks wait while you're typing in a field. With several tasks selected, ⌘⌫ and ⌘D act on all of them.")
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
    }
}
