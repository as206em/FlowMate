import AppKit
import Combine
import SwiftUI

// The task list's engine: a real NSTableView with recycled rows.
//
// SwiftUI stacks keep every row they have built, and each task row carries popovers, hover
// trackers, gestures and a context menu. With a hundred tasks that is thousands of live views
// that every scroll event has to hit-test and every store change has to diff. NSTableView only
// keeps the rows on screen (plus a few spares) and reuses them while scrolling, so the cost
// stays flat however many tasks there are. Each row's content is still the SwiftUI TaskRow.
//
//   TaskTable (TaskColumns.swift)  → sticky column header + NativeTaskTable
//   TaskListView / SprintPlanView  → build the [TaskTableRow] items

// MARK: - Items

/// Where a row sits inside its group's panel (the rounded raised box around a group's tasks).
enum PanelPosition: Equatable {
    case only, first, middle, last

    var hasTopEdge: Bool { self == .only || self == .first }
    var hasBottomEdge: Bool { self == .only || self == .last }
}

struct GroupHeaderInfo: Equatable {
    let key: String
    let title: String
    let hint: String
    let colorHex: UInt32?
    /// Status groups: the status icon (and its color; nil for a category's signal color)
    var statusKind: FocusStatusKind? = nil
    var statusColorHex: UInt32? = nil
    let count: Int
    let open: Bool
    /// Space above the header, between groups
    let gap: CGFloat
}

struct TaskRowInfo: Equatable {
    let task: TaskItem
    let group: String
    let position: PanelPosition
    let showProject: Bool
    let display: RowDisplay
}

/// One line of the table, top to bottom.
enum TaskTableRow: Equatable, Identifiable {
    case spacer(id: String, height: CGFloat)
    case sectionTitle(String)
    case groupHeader(GroupHeaderInfo)
    case task(TaskRowInfo)
    case empty(group: String, text: String)
    case composer(group: String, preset: TaskGroupValue, isDefault: Bool, title: String)

    var id: String {
        switch self {
        case let .spacer(id, _): return "s-" + id
        case let .sectionTitle(text): return "st-" + text
        case let .groupHeader(info): return "h-" + info.key
        case let .task(info): return "t-\(info.group)-\(info.task.id.uuidString)"
        case let .empty(group, _): return "e-" + group
        case let .composer(group, _, _, _): return "c-" + group
        }
    }

    /// The group this row belongs to, for drops
    var group: String? {
        switch self {
        case let .groupHeader(info): return info.key
        case let .task(info): return info.group
        case let .empty(group, _): return group
        case let .composer(group, _, _, _): return group
        case .spacer, .sectionTitle: return nil
        }
    }

    /// Rows whose height is the content's own (measured), not a constant
    var measuresHeight: Bool {
        switch self {
        case .spacer, .task: return false
        default: return true
        }
    }

    /// Height used until the content has been measured
    var estimatedHeight: CGFloat {
        switch self {
        case let .spacer(_, height): return height
        case .task(let info): return Focus.rowHeight + (info.position.hasTopEdge ? 0 : 1)
        case let .groupHeader(info): return info.gap + 32
        case .sectionTitle: return 50
        case .empty: return 52
        case .composer: return 44
        }
    }
}

/// Builds the rows of a table group by group.
struct TaskTableBuilder {
    private(set) var rows: [TaskTableRow] = []
    private(set) var drops: [String: TaskGroupDrop] = [:]

    mutating func spacer(_ id: String, _ height: CGFloat) {
        rows.append(.spacer(id: id, height: height))
    }

    mutating func sectionTitle(_ text: String) {
        rows.append(.sectionTitle(text))
    }

    mutating func group(
        key: String,
        title: String,
        hint: String = "",
        colorHex: UInt32? = nil,
        statusKind: FocusStatusKind? = nil,
        statusColorHex: UInt32? = nil,
        tasks: [TaskItem],
        emptyText: String,
        showProject: Bool,
        drop: TaskGroupDrop?,
        composerIsDefault: Bool = false,
        composerOnTop: Bool = false,
        open: Bool,
        gap: CGFloat,
        display: (TaskItem) -> RowDisplay
    ) {
        rows.append(.groupHeader(GroupHeaderInfo(
            key: key, title: title, hint: hint, colorHex: colorHex, statusKind: statusKind,
            statusColorHex: statusColorHex, count: tasks.count, open: open, gap: gap
        )))
        if let drop { drops[key] = drop }
        guard open else { return }
        let composer = drop.map {
            TaskTableRow.composer(group: key, preset: TaskGroupSection.preset($0), isDefault: composerIsDefault, title: title)
        }
        // ⌘N pins the composer above the group's tasks, so it's on screen however long the group is
        if composerOnTop, let composer { rows.append(composer) }
        if tasks.isEmpty {
            rows.append(.empty(group: key, text: emptyText))
        }
        for (index, task) in tasks.enumerated() {
            let position: PanelPosition
            switch (index == 0, index == tasks.count - 1) {
            case (true, true): position = .only
            case (true, false): position = .first
            case (false, true): position = .last
            default: position = .middle
            }
            rows.append(.task(TaskRowInfo(task: task, group: key, position: position, showProject: showProject, display: display(task))))
        }
        if !composerOnTop, let composer { rows.append(composer) }
    }
}

// MARK: - Row content (SwiftUI)

/// The rounded outline of a group's panel, cut into per-row pieces: sides on every row, the top
/// edge on the first and the bottom edge on the last.
private struct PanelEdge: Shape {
    let position: PanelPosition

    func path(in rect: CGRect) -> Path {
        let r = Focus.radiusPanel
        let box = rect.insetBy(dx: 0.5, dy: 0.5)
        let (minX, maxX, minY, maxY) = (box.minX, box.maxX, box.minY, box.maxY)
        let top = position.hasTopEdge
        let bottom = position.hasBottomEdge
        var p = Path()
        p.move(to: CGPoint(x: minX, y: bottom ? maxY - r : maxY))
        if top {
            p.addLine(to: CGPoint(x: minX, y: minY + r))
            p.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
            p.addLine(to: CGPoint(x: maxX - r, y: minY))
            p.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
        } else {
            p.addLine(to: CGPoint(x: minX, y: minY))
            p.move(to: CGPoint(x: maxX, y: minY))
        }
        if bottom {
            p.addLine(to: CGPoint(x: maxX, y: maxY - r))
            p.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - r, y: maxY), radius: r)
            p.addLine(to: CGPoint(x: minX + r, y: maxY))
            p.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - r), radius: r)
        } else {
            p.addLine(to: CGPoint(x: maxX, y: maxY))
        }
        return p
    }
}

private extension View {
    /// Draws this row as a slice of its group's panel.
    func panelSlice(_ position: PanelPosition) -> some View {
        let r = Focus.radiusPanel
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: position.hasTopEdge ? r : 0,
            bottomLeadingRadius: position.hasBottomEdge ? r : 0,
            bottomTrailingRadius: position.hasBottomEdge ? r : 0,
            topTrailingRadius: position.hasTopEdge ? r : 0
        )
        return self
            .background(Focus.raised)
            .overlay(alignment: .top) {
                if !position.hasTopEdge { FocusDivider() }
            }
            .clipShape(shape)
            .overlay(PanelEdge(position: position).stroke(Focus.hairline, lineWidth: 1))
    }
}

/// What one table row shows.
struct TaskTableCell: View {
    let row: TaskTableRow
    /// Rows that size to their content report their height here (the composer grows when it opens)
    var onHeight: ((CGFloat) -> Void)?

    static let sidePadding: CGFloat = 28

    var body: some View {
        content
            .padding(.horizontal, Self.sidePadding)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CellHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(CellHeightKey.self) { onHeight?($0) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch row {
        case .spacer:
            Color.clear
        case let .sectionTitle(text):
            FocusCaption(text: text).padding(.horizontal, 4).padding(.top, 32)
        case let .groupHeader(info):
            GroupHeaderRow(info: info)
        case .task:
            // Task rows are drawn by TaskRowNSView, not hosted
            Color.clear
        case let .empty(_, text):
            Text(text)
                .font(Focus.body)
                .foregroundColor(Focus.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .panelSlice(.only)
        case let .composer(group, preset, isDefault, title):
            TaskComposer(key: TasksViewModel.listComposerKey(group), preset: preset, isDefault: isDefault, groupName: title)
                .environment(\.composerReservesMenuSpace, true)
                .padding(.top, 6)
        }
    }
}

private struct CellHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct GroupHeaderRow: View {
    @EnvironmentObject private var model: TasksViewModel
    let info: GroupHeaderInfo

    var body: some View {
        Button {
            model.toggleGroup(info.key)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Focus.text3)
                    .rotationEffect(.degrees(info.open ? 90 : 0))
                    .frame(width: 10)
                if let colorHex = info.colorHex {
                    FocusProjectTile(name: info.title, colorHex: colorHex)
                }
                if let kind = info.statusKind {
                    FocusStatusIcon(kind: kind, color: info.statusColorHex.map { Color(hex: $0) }, size: 15)
                }
                Text(info.title).font(Focus.groupTitle).foregroundColor(Focus.text).lineLimit(1)
                Text("\(info.count)").font(Focus.row.monospacedDigit()).foregroundColor(Focus.text3)
                if !info.hint.isEmpty {
                    Text(info.hint).font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4 + info.gap)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(info.open ? "Expanded" : "Collapsed")
    }
}

// MARK: - AppKit views

/// Hosts one row's SwiftUI content (group headers, empty text, the composer).
final class RowHostingView: NSHostingView<AnyView> {}

final class RowCell: NSView {
    let hosting: RowHostingView

    override init(frame: NSRect) {
        hosting = RowHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: frame)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Never takes keyboard focus: arrow keys belong to the app's own shortcuts and text fields.
final class TaskNSTableView: NSTableView {
    /// Pointer moved, left or the table scrolled: the coordinator re-picks the hovered row
    var onPointerChange: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) { onPointerChange?() }
    override func mouseEntered(with event: NSEvent) { onPointerChange?() }
    override func mouseExited(with event: NSEvent) { onPointerChange?() }
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
}

// MARK: - Representable

struct NativeTaskTable: NSViewRepresentable {
    let rows: [TaskTableRow]
    let drops: [String: TaskGroupDrop]
    let layout: TaskColumnLayout
    let store: TaskStore
    let model: TasksViewModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TaskNSTableView()
        table.headerView = nil
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.allowsColumnSelection = false
        table.allowsEmptySelection = true
        table.rowSizeStyle = .custom
        table.usesAutomaticRowHeights = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false

        let coordinator = context.coordinator
        coordinator.table = table
        table.onPointerChange = { [weak coordinator] in coordinator?.updateHover() }
        scroll.contentView.postsBoundsChangedNotifications = true
        coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.updateHover() }
        }
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.update(rows: rows, drops: drops, layout: layout, store: store, model: model)
        return scroll
    }

    /// The table takes whatever room it is given. Without this SwiftUI asks the scroll view for its
    /// fittingSize on every layout pass, and AppKit builds a constraint engine over every row view.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 600)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(rows: rows, drops: drops, layout: layout, store: store, model: model)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSDraggingSource {
        weak var table: NSTableView?
        private(set) var rows: [TaskTableRow] = []
        private var drops: [String: TaskGroupDrop] = [:]
        private var layout = TaskColumnLayout.standard
        private var store: TaskStore?
        private var model: TasksViewModel?
        private var indexById: [String: Int] = [:]
        private var headerIndexByGroup: [String: Int] = [:]
        /// Measured heights of rows that size to their content, by row id
        private var measured: [String: CGFloat] = [:]
        private var revealedTaskId: UUID?
        private var revealedFlashId: UUID?
        private var handledFocusRequest: UUID?
        private var tickerSubscription: AnyCancellable?
        private let controller = TaskRowController()
        nonisolated(unsafe) var scrollObserver: NSObjectProtocol?
        private weak var hoveredView: TaskRowNSView?

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        /// Highlights the task row under the pointer, and only that one.
        func updateHover() {
            guard let table, let window = table.window, window.isKeyWindow || window.isMainWindow else {
                setHovered(nil)
                return
            }
            let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            var target: TaskRowNSView?
            if table.visibleRect.contains(point) {
                let row = table.row(at: point)
                if row >= 0 { target = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskRowNSView }
            }
            setHovered(target)
        }

        private func setHovered(_ view: TaskRowNSView?) {
            guard view !== hoveredView else { return }
            hoveredView?.hovered = false
            view?.hovered = true
            hoveredView = view
        }

        // MARK: Updates

        func update(rows newRows: [TaskTableRow], drops: [String: TaskGroupDrop], layout: TaskColumnLayout,
                    store: TaskStore, model: TasksViewModel) {
            if self.store !== store {
                tickerSubscription = store.ticker.$now.sink { [weak self] _ in self?.tick() }
            }
            self.store = store
            self.model = model
            controller.store = store
            controller.model = model
            self.drops = drops
            let old = rows
            let layoutChanged = layout != self.layout
            self.layout = layout
            rows = newRows
            indexById = Dictionary(newRows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            headerIndexByGroup = [:]
            for (index, row) in newRows.enumerated() {
                if case let .groupHeader(info) = row { headerIndexByGroup[info.key] = index }
            }
            guard let table else { return }

            if old.map(\.id) != newRows.map(\.id) {
                measured = measured.filter { indexById[$0.key] != nil }
                table.reloadData()
            } else {
                var heightChanged = IndexSet()
                for index in newRows.indices where old[index] != newRows[index] || layoutChanged {
                    if let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? RowCell {
                        configure(cell, row: newRows[index], index: index)
                    } else if let view = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? TaskRowNSView,
                              case let .task(info) = newRows[index] {
                        configure(view, info: info)
                    }
                    if newRows[index].measuresHeight, old[index] != newRows[index] { heightChanged.insert(index) }
                }
                if !heightChanged.isEmpty { table.noteHeightOfRows(withIndexesChanged: heightChanged) }
            }
            revealSelectionIfNeeded(model: model)
            DispatchQueue.main.async { [weak self] in self?.updateHover() }
        }

        /// Keeps the keyboard selection on screen, and brings ⌘N's composer into view.
        private func revealSelectionIfNeeded(model: TasksViewModel) {
            guard let table else { return }
            if let id = model.selectedTaskId, id != revealedTaskId, !model.isPanelOpen,
               let index = rows.firstIndex(where: { if case let .task(info) = $0 { return info.task.id == id } else { return false } }) {
                table.scrollRowToVisible(index)
            }
            revealedTaskId = model.selectedTaskId

            if let request = model.focusRequest, request.field == .newTask, request.id != handledFocusRequest,
               let index = rows.firstIndex(where: { if case .composer(_, _, true, _) = $0 { return true } else { return false } }) {
                handledFocusRequest = request.id
                table.scrollRowToVisible(index)
                // Pinned under its group's header: show the header too (once the composer has its height)
                if index > 0, case .groupHeader = rows[index - 1] {
                    let reveal: @MainActor @Sendable () -> Void = { [weak table] in
                        guard let table, let clip = table.enclosingScrollView?.contentView else { return }
                        let header = table.rect(ofRow: index - 1)
                        guard header.minY < clip.bounds.minY else { return }
                        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, header.minY)))
                        table.enclosingScrollView?.reflectScrolledClipView(clip)
                    }
                    reveal()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: reveal)
                }
            } else if model.focusRequest == nil {
                handledFocusRequest = nil
            }

            // A task just added from the composer at the top
            if let id = model.flashTaskId, id != revealedFlashId,
               let index = rows.firstIndex(where: { if case let .task(info) = $0 { return info.task.id == id } else { return false } }) {
                table.scrollRowToVisible(index)
            }
            revealedFlashId = model.flashTaskId
        }

        // MARK: Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return 0 }
            let item = rows[row]
            if item.measuresHeight, let height = measured[item.id] { return height }
            return item.estimatedHeight
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            if case let .task(info) = rows[row] {
                let id = NSUserInterfaceItemIdentifier("task")
                let view = (tableView.makeView(withIdentifier: id, owner: nil) as? TaskRowNSView) ?? {
                    let view = TaskRowNSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: Focus.rowHeight))
                    view.identifier = id
                    return view
                }()
                configure(view, info: info)
                return view
            }
            let id = NSUserInterfaceItemIdentifier("row")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? RowCell) ?? {
                let cell = RowCell(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 44))
                cell.identifier = id
                return cell
            }()
            configure(cell, row: rows[row], index: row)
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("rowView")
            if let view = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableRowView { return view }
            let view = NSTableRowView()
            view.identifier = id
            view.isEmphasized = false
            return view
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        /// A composer row scrolled away and was recycled: its view (and what was typed) is gone,
        /// so it must not stay the active composer.
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            guard rows.indices.contains(row), case let .composer(group, _, _, _) = rows[row] else { return }
            let key = TasksViewModel.listComposerKey(group)
            DispatchQueue.main.async { [weak self] in
                guard let model = self?.model, model.activeComposer == key else { return }
                // Still on screen after a reload: keep it
                if let index = self?.indexById["c-" + group],
                   self?.table?.view(atColumn: 0, row: index, makeIfNecessary: false) != nil { return }
                model.activeComposer = nil
            }
        }

        private func configure(_ cell: RowCell, row: TaskTableRow, index: Int) {
            guard let store, let model else { return }
            let rowId = row.id
            let cellView = TaskTableCell(row: row, onHeight: row.measuresHeight ? { [weak self] height in
                self?.record(height: height, rowId: rowId)
            } : nil)
            cell.hosting.sizingOptions = []
            cell.hosting.rootView = AnyView(
                cellView
                    .environmentObject(store)
                    .environmentObject(model)
                    .environment(\.taskColumnLayout, layout)
                    .id(rowId)
            )
        }

        private var hoverUpdatePending = false

        /// New rows appear under a still pointer while scrolling: pick the hovered row once they're in.
        private func scheduleHoverUpdate() {
            guard !hoverUpdatePending else { return }
            hoverUpdatePending = true
            DispatchQueue.main.async { [weak self] in
                self?.hoverUpdatePending = false
                self?.updateHover()
            }
        }

        private func configure(_ view: TaskRowNSView, info: TaskRowInfo) {
            if view === hoveredView { hoveredView = nil }
            view.reset()
            scheduleHoverUpdate()
            view.layout = layout
            view.info = info
            view.nowProvider = { [weak store] in store?.ticker.now ?? Date() }
            view.controller = controller
            view.onDragStart = { [weak model] id in model?.draggingTaskId = id }
            view.dragSource = drops[info.group] != nil ? self : nil
        }

        /// Running rows redraw once a second for their clock and ring.
        private func tick() {
            guard let table else { return }
            let visible = table.rows(in: table.visibleRect)
            for row in visible.location..<(visible.location + visible.length) {
                if let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskRowNSView, view.isRunning {
                    view.needsDisplay = true
                }
            }
        }

        /// Records a row's content height; the table re-lays out on the next turn of the run loop
        /// (never from inside SwiftUI's update or a delegate callback).
        private func record(height: CGFloat, rowId: String) {
            let height = ceil(height)
            guard height > 1, abs(height - (measured[rowId] ?? -1)) > 0.5 else { return }
            measured[rowId] = height
            DispatchQueue.main.async { [weak self] in
                guard let self, let table = self.table, let index = self.indexById[rowId] else { return }
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
                NSAnimationContext.endGrouping()
            }
        }

        // MARK: Drag source

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            model?.draggingTaskId = nil
        }

        // MARK: Drop destination

        /// Where a drop proposed at (row, operation) lands: the group, the task to go before
        /// (nil appends) and how to show it (`row`/`operation` for the table's indicator).
        private struct Landing {
            let group: String
            let before: UUID?
            let row: Int
            let operation: NSTableView.DropOperation
        }

        private func landing(row proposed: Int, operation: NSTableView.DropOperation) -> Landing? {
            guard !rows.isEmpty else { return nil }
            func header(_ group: String) -> Landing? {
                headerIndexByGroup[group].map { Landing(group: group, before: nil, row: $0, operation: .on) }
            }
            // Below everything: append to the last group
            guard proposed < rows.count else {
                guard let group = rows.last(where: { $0.group != nil })?.group else { return nil }
                return header(group)
            }
            let target = rows[proposed]
            switch target {
            case let .task(info):
                guard reorders(info.group) else { return header(info.group) }
                return Landing(group: info.group, before: info.task.id, row: proposed, operation: .above)
            case let .groupHeader(info):
                if operation == .above, proposed > 0, let previous = rows[..<proposed].last(where: { $0.group != nil })?.group,
                   previous != info.key, drops[previous] != nil {
                    return header(previous)
                }
                return header(info.key)
            case let .empty(group, _), let .composer(group, _, _, _):
                return header(group)
            case .spacer, .sectionTitle:
                // Gap between groups: the group just above it
                guard let group = rows[..<proposed].last(where: { $0.group != nil })?.group else { return nil }
                return header(group)
            }
        }

        /// Whether a drop in the group can be placed before a given row
        private func reorders(_ group: String) -> Bool {
            switch drops[group] {
            case .slot?: return true
            case let .group(_, reorder)?: return reorder
            case nil: return false
            }
        }

        private func draggedTaskId(_ info: NSDraggingInfo) -> UUID? {
            info.draggingPasteboard.string(forType: .string)
                .flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard draggedTaskId(info) != nil,
                  let target = landing(row: row, operation: dropOperation),
                  drops[target.group] != nil else { return [] }
            tableView.setDropRow(target.row, dropOperation: target.operation)
            return .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard let id = draggedTaskId(info), let store,
                  let target = landing(row: row, operation: dropOperation),
                  let drop = drops[target.group] else { return false }
            model?.draggingTaskId = nil
            guard id != target.before else { return false }
            TaskGroupSection.perform(drop, id: id, before: target.before, store: store)
            return true
        }
    }
}

// MARK: - Composer menu space

private struct ComposerReservesMenuSpaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside the native table a row can't paint outside its own bounds, so the composer makes
    /// room for its suggestion menu instead of letting it hang over the rows below.
    var composerReservesMenuSpace: Bool {
        get { self[ComposerReservesMenuSpaceKey.self] }
        set { self[ComposerReservesMenuSpaceKey.self] = newValue }
    }
}
