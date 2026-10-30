import SwiftUI

// The list's column layout: a sticky header and rows that share one set of column widths,
// so every value sits at the same x on every row.
//
//   TaskTable(showProject:, sort:) { groups of TaskRow }
//
// TaskTable measures the width, picks the columns that fit (TaskColumnLayout), pins the
// header and hands the layout to the rows through the environment. Rows lay out their cells
// with `TaskColumnCells`, the header with `TaskColumnHeaderRow`; both use the same widths.

/// One column of the task list, left to right.
enum TaskColumn: String, CaseIterable, Identifiable, Sendable {
    case status, project, title, milestone, sprint, due, priority, time, timer

    var id: String { rawValue }

    /// Header label; empty for the icon-only columns.
    var title: String {
        switch self {
        case .status, .timer: return ""
        case .project: return "Project"
        case .title: return "Title"
        case .milestone: return "Milestone"
        case .sprint: return "Sprint"
        case .due: return "Due"
        case .priority: return "Priority"
        case .time: return "Expected"
        }
    }

    /// Fixed width, or nil for the flexible title column.
    var width: CGFloat? {
        switch self {
        case .status: return 20
        case .project: return 130
        case .title: return nil
        case .milestone: return 130
        case .sprint: return 92
        case .due: return 88
        case .priority: return 76
        case .time: return 76
        case .timer: return 32
        }
    }

    var alignment: Alignment {
        switch self {
        case .time: return .trailing
        case .status, .timer: return .center
        default: return .leading
        }
    }

    /// What clicking the header sorts by; nil for columns that don't sort.
    var sortKey: TaskSortKey? {
        switch self {
        case .status, .timer: return nil
        case .project: return .project
        case .title: return .title
        case .milestone: return .milestone
        case .sprint: return .sprint
        case .due: return .due
        case .priority: return .priority
        case .time: return .expected
        }
    }
}

/// The columns a table shows at its current width.
struct TaskColumnLayout: Equatable, Sendable {
    /// Same as FocusRow, so header and rows line up
    static let spacing: CGFloat = 12
    static let leadingPadding: CGFloat = 14
    static let trailingPadding: CGFloat = 10
    /// The title keeps at least this much room; other columns drop out to make it.
    static let minTitleWidth: CGFloat = 200
    /// Dropped first when the table is narrow
    static let dropOrder: [TaskColumn] = [.sprint, .milestone, .project, .priority]

    var columns: [TaskColumn]

    static let standard = TaskColumnLayout(columns: TaskColumn.allCases)

    func contains(_ column: TaskColumn) -> Bool { columns.contains(column) }

    /// Width taken by everything but the title
    var fixedWidth: CGFloat {
        let widths = columns.compactMap(\.width).reduce(0, +)
        let gaps = CGFloat(max(columns.count - 1, 0)) * Self.spacing
        return widths + gaps + Self.leadingPadding + Self.trailingPadding
    }

    /// The layout for a table: Project only in All projects, minus `excluding`,
    /// then narrow columns dropped (sprint, milestone, project, priority) until the title fits.
    static func make(showProject: Bool, excluding: Set<TaskColumn> = [], width: CGFloat) -> TaskColumnLayout {
        var layout = TaskColumnLayout(columns: TaskColumn.allCases.filter { column in
            if column == .project && !showProject { return false }
            return !excluding.contains(column)
        })
        for column in dropOrder where layout.fixedWidth + minTitleWidth > width {
            layout.columns.removeAll { $0 == column }
        }
        return layout
    }
}

private struct TaskColumnLayoutKey: EnvironmentKey {
    static let defaultValue: TaskColumnLayout? = nil
}

extension EnvironmentValues {
    /// Set by TaskTable. Rows outside a table (nil) use their compact layout.
    var taskColumnLayout: TaskColumnLayout? {
        get { self[TaskColumnLayoutKey.self] }
        set { self[TaskColumnLayoutKey.self] = newValue }
    }
}

/// Lays out one cell per column at the column's width. Put it inside an HStack with
/// `TaskColumnLayout.spacing` (FocusRow already is one).
struct TaskColumnCells<Cell: View>: View {
    let layout: TaskColumnLayout
    @ViewBuilder let cell: (TaskColumn) -> Cell

    var body: some View {
        ForEach(layout.columns) { column in
            if let width = column.width {
                cell(column).frame(width: width, alignment: column.alignment)
            } else {
                cell(column)
                    .frame(maxWidth: .infinity, alignment: column.alignment)
                    .layoutPriority(1)
            }
        }
    }
}

/// The header row: one label per column. With `sort`, labels that can sort are clickable.
struct TaskColumnHeaderRow: View {
    let layout: TaskColumnLayout
    var sort: Binding<TaskSort>?

    var body: some View {
        HStack(spacing: TaskColumnLayout.spacing) {
            TaskColumnCells(layout: layout) { column in
                header(column)
            }
        }
        .padding(.leading, TaskColumnLayout.leadingPadding)
        .padding(.trailing, TaskColumnLayout.trailingPadding)
        .frame(height: 30)
    }

    @ViewBuilder
    private func header(_ column: TaskColumn) -> some View {
        if column.title.isEmpty {
            Color.clear.frame(height: 1)
        } else if let sort, let key = column.sortKey {
            FocusColumnHeader(
                title: column.title,
                alignment: column.alignment,
                sortAscending: sort.wrappedValue.key == key ? sort.wrappedValue.ascending : nil
            ) {
                withAnimation(Focus.hoverAnimation) { sort.wrappedValue = sort.wrappedValue.toggled(key) }
            }
        } else {
            FocusColumnHeader(title: column.title, alignment: column.alignment)
        }
    }
}

/// A table of task rows with a sticky column header. Measures its width, picks the columns
/// and shares them with every TaskRow inside through the environment.
struct TaskTable<Content: View>: View {
    let showProject: Bool
    var excluding: Set<TaskColumn> = []
    /// Clickable headers sort by this; nil for tables in manual (drag) order.
    var sort: Binding<TaskSort>?
    /// Optional line above the header, e.g. a hint. It scrolls away; the header stays.
    var caption: String = ""
    @ViewBuilder let content: () -> Content

    @State private var width: CGFloat = 0

    var body: some View {
        let layout = TaskColumnLayout.make(
            showProject: showProject,
            excluding: excluding,
            width: width > 0 ? width : 1000
        )
        VStack(alignment: .leading, spacing: 0) {
            if !caption.isEmpty {
                Text(caption)
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .padding(.top, -8)
                    .padding(.bottom, 10)
            }
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    content()
                        .padding(.top, 6)
                } header: {
                    TaskColumnHeaderRow(layout: layout, sort: sort)
                        .background(Focus.canvas)
                        .overlay(alignment: .bottom) { FocusDivider() }
                }
            }
        }
        .environment(\.taskColumnLayout, layout)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TaskTableWidthKey.self, value: proxy.size.width)
        })
        .onPreferenceChange(TaskTableWidthKey.self) { width = $0 }
    }
}

private struct TaskTableWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// "–" for an empty cell
struct TaskEmptyCell: View {
    var body: some View {
        Text("–")
            .font(Focus.meta)
            .foregroundColor(Focus.text3)
            .accessibilityLabel("None")
    }
}
