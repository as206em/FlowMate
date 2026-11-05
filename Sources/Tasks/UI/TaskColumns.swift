import SwiftUI

// The list's column layout: a sticky header and rows that share one set of column widths,
// so every value sits at the same x on every row.
//
//   TaskTable(showProject:, sort:, rows:, drops:)
//
// TaskTable measures the width, picks the columns that fit (TaskColumnLayout) and hands the
// layout to the rows through the environment. Rows lay out their cells with `TaskColumnCells`;
// each group's header band puts its labels at the same widths (GroupHeaderRow).

/// One column of the task list, left to right.
enum TaskColumn: String, CaseIterable, Identifiable, Sendable {
    case status, project, title, milestone, labels, sprint, due, priority, score, time, timer

    var id: String { rawValue }

    /// Header label; empty for the icon-only columns.
    var title: String {
        switch self {
        case .status, .timer: return ""
        case .project: return "Project"
        case .title: return "Title"
        case .milestone: return "Milestone"
        case .labels: return "Labels"
        case .sprint: return "Sprint"
        case .due: return "Due"
        case .priority: return "Priority"
        case .score: return "Score"
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
        case .labels: return 112
        case .sprint: return 92
        case .due: return 88
        case .priority: return 76
        case .score: return 48
        case .time: return 76
        case .timer: return 32
        }
    }

    var alignment: Alignment {
        switch self {
        case .time: return .trailing
        case .status, .timer, .score: return .center
        default: return .leading
        }
    }

    /// What clicking the header sorts by; nil for columns that don't sort.
    var sortKey: TaskSortKey? {
        switch self {
        case .status, .timer, .labels, .score: return nil
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
    /// (Score, where shown, is what the Sprints view plans by: it goes last)
    static let dropOrder: [TaskColumn] = [.sprint, .labels, .milestone, .project, .priority, .score]
    /// Shown only where a table asks for them (`including`)
    static let optIn: Set<TaskColumn> = [.score]

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
    /// then narrow columns dropped (sprint, labels, milestone, project, priority) until the title fits.
    static func make(showProject: Bool, excluding: Set<TaskColumn> = [], including: Set<TaskColumn> = [],
                     width: CGFloat) -> TaskColumnLayout {
        var layout = TaskColumnLayout(columns: TaskColumn.allCases.filter { column in
            if column == .project && !showProject { return false }
            if optIn.contains(column) && !including.contains(column) { return false }
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

/// A table of task rows; each group's header band carries the column labels (GroupHeaderRow). Measures its width, picks the columns
/// and shares them with every TaskRow inside through the environment. The rows live in a native
/// NSTableView (NativeTaskTable.swift) that only keeps the visible ones.
struct TaskTable: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let showProject: Bool
    var excluding: Set<TaskColumn> = []
    /// Opt-in columns to show (the Sprints view's Score)
    var including: Set<TaskColumn> = []
    /// Optional line above the header, e.g. a hint.
    var caption: String = ""
    let rows: [TaskTableRow]
    let drops: [String: TaskGroupDrop]
    /// Groups whose rows drag without taking drops (Today's sections, onto My focus)
    var draggable: Set<String> = []

    var body: some View {
        let topPadding: CGFloat = 16
        GeometryReader { proxy in
            let layout = TaskColumnLayout.make(
                showProject: showProject,
                excluding: excluding,
                including: including,
                width: max(proxy.size.width - TaskTableCell.sidePadding * 2, 1)
            )
            VStack(alignment: .leading, spacing: 0) {
                if !caption.isEmpty {
                    Text(caption)
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                        .padding(.horizontal, TaskTableCell.sidePadding)
                        .padding(.top, topPadding)
                        .padding(.bottom, 10)
                }
                Color.clear.frame(height: caption.isEmpty ? topPadding : 0)
                NativeTaskTable(rows: rows, drops: drops, draggable: draggable, layout: layout, store: store, model: model)
            }
        }
    }
}
