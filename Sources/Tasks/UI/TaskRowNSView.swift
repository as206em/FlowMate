import AppKit
import SwiftUI

// A task row drawn straight into an NSView, no SwiftUI inside.
//
// Profiling showed the SwiftUI TaskRow (9 cells, each with tooltips, hover regions, gestures,
// accessibility and popover anchors) costing ~12 ms to build, which is what made fast scrolling
// drop frames. This view draws the same row with a handful of CoreGraphics / NSString calls and
// is cheap to recycle. Interactions are added back one at a time (see the stage notes below).
//
//   look, hover, keyboard selection, running tint, drag to regroup
//   clicks, popover editors, rename, context menu and tooltips live in TaskRowController

/// What a row shows beyond the task itself: values looked up in the store when the table's rows
/// are built, so the row view never touches the store while drawing.
struct RowDisplay: Equatable {
    var projectName: String?
    var projectColorHex: UInt32?
    var milestoneName: String?
    var sprintLabel: String
    var dueLabel: String?
    var dueIsRisk: Bool
    /// When the task's timer was started; nil when it isn't running
    var runningSince: Date?
    /// The keyboard / multi-selection highlight
    var selected: Bool
}

final class TaskRowNSView: NSView, NSViewToolTipOwner, NSTextFieldDelegate {
    var info: TaskRowInfo? {
        didSet { if info != oldValue { needsDisplay = true } }
    }
    var layout = TaskColumnLayout.standard {
        didSet {
            guard layout != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// The time shown on running rows; the table redraws them once a second
    var nowProvider: () -> Date = { Date() }
    weak var controller: TaskRowController?
    var onDragStart: ((UUID) -> Void)?
    /// nil: this row can't be dragged
    weak var dragSource: NSDraggingSource?

    /// Set by the table, which tracks the pointer for all rows at once (a row can't rely on
    /// mouseExited: rows scroll out from under a still pointer without getting one)
    var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }
    private var mouseDownEvent: NSEvent?
    private var dragStarted = false

    var isRunning: Bool { info?.display.runningSince != nil }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layerContentsRedrawPolicy = .duringViewResize
        // One tooltip area for the whole row; the text is picked by pointer position on demand
        addToolTip(NSRect(x: 0, y: 0, width: 10_000, height: 200), owner: self, userData: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Look

    private enum Style {
        static let title = NSFont.systemFont(ofSize: 13.5)
        static let titleRunning = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        static let meta = NSFont.systemFont(ofSize: 12.5)
        static let tag = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let count = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        static let time = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        static let timeLive = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)

        static let raised = NSColor(Focus.raised)
        static let hover = NSColor(Focus.hover)
        static let selected = NSColor(Focus.selected)
        static let liveSoft = NSColor(Focus.liveSoft)
        static let live = NSColor(Focus.live)
        static let liveText = NSColor(Focus.liveText)
        static let text = NSColor(Focus.text)
        static let text2 = NSColor(Focus.text2)
        static let text3 = NSColor(Focus.text3)
        static let hairline = NSColor(Focus.hairline)
        static let risk = NSColor(Focus.risk)
        static let done = NSColor(Focus.done)
        static let progress = NSColor(Focus.progress)
        static let ringTrack = NSColor(Focus.ringTrack)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let info else { return }
        let display = info.display
        let task = info.task
        let inner = NSRect(x: TaskTableCell.sidePadding, y: 0,
                           width: bounds.width - TaskTableCell.sidePadding * 2, height: bounds.height)
        let top = info.position.hasTopEdge
        let bottom = info.position.hasBottomEdge

        NSGraphicsContext.saveGraphicsState()
        Self.panelPath(inner, top: top, bottom: bottom).addClip()
        Style.raised.setFill()
        inner.fill()
        if display.runningSince != nil {
            Style.liveSoft.setFill()
            inner.fill()
        } else if display.selected {
            Style.selected.setFill()
            inner.fill()
        } else if hovered {
            Style.hover.setFill()
            inner.fill()
        }
        if display.selected {
            Style.text2.setFill()
            NSRect(x: inner.minX, y: 0, width: 2, height: inner.height).fill()
        }
        if !top {
            Style.hairline.setFill()
            NSRect(x: inner.minX, y: 0, width: inner.width, height: 1).fill()
        }

        drawColumns(task: task, display: display, in: inner)
        NSGraphicsContext.restoreGraphicsState()

        Style.hairline.setStroke()
        let edge = Self.edgePath(inner.insetBy(dx: 0.5, dy: 0.5), top: top, bottom: bottom)
        edge.lineWidth = 1
        edge.stroke()
    }

    /// Each visible column with its cell rectangle, left to right
    private func columnRects() -> [(column: TaskColumn, rect: NSRect)] {
        let inner = NSRect(x: TaskTableCell.sidePadding, y: 0,
                           width: bounds.width - TaskTableCell.sidePadding * 2, height: bounds.height)
        let titleWidth = max(TaskColumnLayout.minTitleWidth, inner.width - layout.fixedWidth)
        var x = inner.minX + TaskColumnLayout.leadingPadding
        var rects: [(TaskColumn, NSRect)] = []
        for column in layout.columns {
            let width = column.width ?? titleWidth
            rects.append((column, NSRect(x: x, y: 0, width: width, height: bounds.height)))
            x += width + TaskColumnLayout.spacing
        }
        return rects
    }

    /// The row is as wide as the table but only draws inside the side padding.
    private func isInsidePanel(_ point: NSPoint) -> Bool {
        point.x >= TaskTableCell.sidePadding && point.x <= bounds.width - TaskTableCell.sidePadding
    }

    /// The column under a point (the gap between two columns counts toward both)
    private func column(at point: NSPoint) -> (column: TaskColumn, rect: NSRect)? {
        let half = TaskColumnLayout.spacing / 2
        return columnRects().first { point.x >= $0.rect.minX - half && point.x < $0.rect.maxX + half }
    }

    private func drawColumns(task: TaskItem, display: RowDisplay, in inner: NSRect) {
        for (column, cell) in columnRects() {
            switch column {
            case .status: drawStatus(task.status, in: cell)
            case .project: drawProject(display, in: cell)
            case .title: if !isRenaming { drawTitle(task, display, in: cell) }
            case .milestone: drawMeta(display.milestoneName, in: cell)
            case .sprint: drawMeta(display.sprintLabel, in: cell)
            case .due: drawDue(task, display, in: cell)
            case .priority: drawPriority(task.priority, in: cell)
            case .time: drawTime(task, display, in: cell)
            case .timer: drawTimer(task, display, in: cell)
            }
        }
    }

    // MARK: Cells

    private static var projectColors: [UInt32: NSColor] = [:]
    private static var priorityColors: [FocusPriorityLevel: NSColor] = [:]

    private static func projectColor(_ hex: UInt32) -> NSColor {
        if let color = projectColors[hex] { return color }
        let color = NSColor(Color(hex: hex))
        projectColors[hex] = color
        return color
    }

    private static func priorityColor(_ level: FocusPriorityLevel) -> NSColor {
        if let color = priorityColors[level] { return color }
        let color = NSColor(level.tint.icon)
        priorityColors[level] = color
        return color
    }

    private func drawText(_ string: String, font: NSFont, color: NSColor, in rect: NSRect,
                          align: NSTextAlignment = .left, strikethrough: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = align
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        if strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = color
        }
        let lineHeight = ceil(font.ascender - font.descender)
        let target = NSRect(x: rect.minX, y: rect.midY - lineHeight / 2, width: rect.width, height: lineHeight)
        (string as NSString).draw(with: target, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    private func textWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private func drawEmpty(in cell: NSRect) {
        drawText("–", font: Style.meta, color: Style.text3, in: cell)
    }

    private func drawMeta(_ text: String?, in cell: NSRect) {
        guard let text, !text.isEmpty else { return drawEmpty(in: cell) }
        drawText(text, font: Style.meta, color: Style.text3, in: cell)
    }

    private func drawStatus(_ status: TaskStatus, in cell: NSRect) {
        let size: CGFloat = 16
        let rect = NSRect(x: cell.midX - size / 2, y: cell.midY - size / 2, width: size, height: size)
        let line = size * 0.14
        switch status {
        case .todo:
            Style.text3.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: line / 2, dy: line / 2))
            ring.lineWidth = line
            ring.stroke()
        case .inProgress:
            Style.progress.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: line / 2, dy: line / 2))
            ring.lineWidth = line
            ring.stroke()
            let disc = rect.insetBy(dx: size * 0.25, dy: size * 0.25)
            let center = NSPoint(x: disc.midX, y: disc.midY)
            let half = NSBezierPath()
            half.move(to: NSPoint(x: center.x, y: disc.minY))
            half.appendArc(withCenter: center, radius: disc.width / 2, startAngle: -90, endAngle: 90, clockwise: false)
            half.close()
            Style.progress.setFill()
            half.fill()
        case .done:
            Style.done.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.minX + size * 0.28, y: rect.minY + size * 0.53))
            check.line(to: NSPoint(x: rect.minX + size * 0.44, y: rect.minY + size * 0.69))
            check.line(to: NSPoint(x: rect.minX + size * 0.74, y: rect.minY + size * 0.34))
            check.lineWidth = 1.6
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        }
    }

    private func drawProject(_ display: RowDisplay, in cell: NSRect) {
        guard let name = display.projectName, let hex = display.projectColorHex else { return drawEmpty(in: cell) }
        let size: CGFloat = 18
        let tile = NSRect(x: cell.minX, y: cell.midY - size / 2, width: size, height: size)
        let color = Self.projectColor(hex)
        color.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: tile, xRadius: size * 0.28, yRadius: size * 0.28).fill()
        let letter = String(name.prefix(1)).uppercased()
        drawText(letter, font: .systemFont(ofSize: size * 0.56, weight: .bold), color: color, in: tile, align: .center)
        let textX = tile.maxX + 7
        drawText(name, font: Style.meta, color: Style.text3,
                 in: NSRect(x: textX, y: cell.minY, width: max(0, cell.maxX - textX), height: cell.height))
    }

    private func drawTitle(_ task: TaskItem, _ display: RowDisplay, in cell: NSRect) {
        var titleWidth = cell.width
        if let summary = task.subtaskSummary {
            let countWidth = 13 + textWidth(summary, font: Style.count)
            titleWidth = max(0, cell.width - countWidth - 10)
            let titleDrawn = min(textWidth(task.title, font: Style.title), titleWidth)
            let countX = cell.minX + titleDrawn + 10
            drawSubtaskCount(summary, at: NSPoint(x: countX, y: cell.midY))
        }
        let running = display.runningSince != nil
        drawText(task.title,
                 font: running ? Style.titleRunning : Style.title,
                 color: task.isDone ? Style.text3 : Style.text,
                 in: NSRect(x: cell.minX, y: cell.minY, width: titleWidth, height: cell.height),
                 strikethrough: task.isDone)
    }

    private func drawSubtaskCount(_ summary: String, at origin: NSPoint) {
        let check = NSBezierPath()
        check.move(to: NSPoint(x: origin.x + 1, y: origin.y + 0.5))
        check.line(to: NSPoint(x: origin.x + 3.8, y: origin.y + 3.4))
        check.line(to: NSPoint(x: origin.x + 8.5, y: origin.y - 3))
        check.lineWidth = 1.5
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        Style.text3.setStroke()
        check.stroke()
        drawText(summary, font: Style.count, color: Style.text3,
                 in: NSRect(x: origin.x + 13, y: origin.y - 12, width: textWidth(summary, font: Style.count) + 2, height: 24))
    }

    private func drawDue(_ task: TaskItem, _ display: RowDisplay, in cell: NSRect) {
        guard let label = display.dueLabel else { return drawEmpty(in: cell) }
        if task.isDone {
            return drawText(label, font: Style.meta, color: Style.text3, in: cell)
        }
        let width = min(cell.width, textWidth(label, font: Style.tag) + 14)
        let tag = NSRect(x: cell.minX, y: cell.midY - Focus.tagHeight / 2, width: width, height: Focus.tagHeight)
        let color = display.dueIsRisk ? Style.risk : Style.text2
        (display.dueIsRisk ? Style.risk : Style.hairline).setStroke()
        let outline = NSBezierPath(roundedRect: tag.insetBy(dx: 0.5, dy: 0.5), xRadius: Focus.radiusTag, yRadius: Focus.radiusTag)
        outline.lineWidth = 1
        outline.stroke()
        drawText(label, font: Style.tag, color: color, in: tag.insetBy(dx: 7, dy: 0))
    }

    private func drawPriority(_ priority: TaskPriority, in cell: NSRect) {
        let level = priority.focusLevel
        let color = Self.priorityColor(level)
        let heights: [CGFloat] = [5, 8, 12]
        let boxBottom = cell.midY + 6
        for index in 0..<3 {
            let bar = NSRect(x: cell.minX + CGFloat(index) * 5, y: boxBottom - heights[index], width: 3, height: heights[index])
            color.withAlphaComponent(index < level.bars ? 1 : 0.25).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        }
        let textX = cell.minX + 15 + 7
        drawText(priority.title, font: Style.meta, color: Style.text3,
                 in: NSRect(x: textX, y: cell.minY, width: max(0, cell.maxX - textX), height: cell.height))
    }

    private func elapsed(_ task: TaskItem, _ display: RowDisplay) -> TimeInterval {
        let running = display.runningSince.map { max(0, nowProvider().timeIntervalSince($0)) } ?? 0
        return task.spentSeconds + running
    }

    private func drawTime(_ task: TaskItem, _ display: RowDisplay, in cell: NSRect) {
        if display.runningSince != nil {
            drawText(Focus.clockString(elapsed(task, display)), font: Style.timeLive, color: Style.liveText, in: cell, align: .right)
        } else {
            drawText(Focus.durationString(minutes: task.expectedMinutes), font: Style.time, color: Style.text3, in: cell, align: .right)
        }
    }

    private func drawTimer(_ task: TaskItem, _ display: RowDisplay, in cell: NSRect) {
        guard !task.isDone else { return }
        let running = display.runningSince != nil
        let size: CGFloat = 32
        let box = NSRect(x: cell.midX - size / 2, y: cell.midY - size / 2, width: size, height: size)
        let progress = elapsed(task, display) / Double(max(1, task.expectedMinutes) * 60)
        let over = progress > 1 && !running
        let line: CGFloat = 2.5
        let ringRect = box.insetBy(dx: size * 0.094 + line / 2, dy: size * 0.094 + line / 2)
        (over ? Style.risk : Style.ringTrack).setStroke()
        let track = NSBezierPath(ovalIn: ringRect)
        track.lineWidth = line
        track.stroke()
        if !over, progress > 0 {
            let arc = NSBezierPath()
            let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
            arc.appendArc(withCenter: center, radius: ringRect.width / 2, startAngle: -90,
                          endAngle: -90 + 360 * min(1, progress), clockwise: false)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            (running ? Style.live : Style.text2).setStroke()
            arc.stroke()
        }
        let glyph = size * 0.32
        let glyphColor = running ? Style.live : Style.text2
        glyphColor.setFill()
        if running {
            let barWidth = glyph * 0.32
            let gap = glyph * 0.26
            let left = NSRect(x: box.midX - gap / 2 - barWidth, y: box.midY - glyph / 2, width: barWidth, height: glyph)
            let right = NSRect(x: box.midX + gap / 2, y: box.midY - glyph / 2, width: barWidth, height: glyph)
            NSBezierPath(roundedRect: left, xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: right, xRadius: 0.8, yRadius: 0.8).fill()
        } else {
            let offset = size * 0.03
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: box.midX - glyph * 0.38 + offset, y: box.midY - glyph / 2))
            triangle.line(to: NSPoint(x: box.midX + glyph * 0.5 + offset, y: box.midY))
            triangle.line(to: NSPoint(x: box.midX - glyph * 0.38 + offset, y: box.midY + glyph / 2))
            triangle.close()
            triangle.fill()
        }
    }

    // MARK: Panel shape

    /// The rounded outline of a group's panel, as far as this row is part of it
    private static func panelPath(_ rect: NSRect, top: Bool, bottom: Bool) -> NSBezierPath {
        let r = Focus.radiusPanel
        let (x0, x1, y0, y1) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x0 + (top ? r : 0), y: y0))
        p.line(to: NSPoint(x: x1 - (top ? r : 0), y: y0))
        if top { p.appendArc(from: NSPoint(x: x1, y: y0), to: NSPoint(x: x1, y: y0 + r), radius: r) }
        p.line(to: NSPoint(x: x1, y: y1 - (bottom ? r : 0)))
        if bottom { p.appendArc(from: NSPoint(x: x1, y: y1), to: NSPoint(x: x1 - r, y: y1), radius: r) }
        p.line(to: NSPoint(x: x0 + (bottom ? r : 0), y: y1))
        if bottom { p.appendArc(from: NSPoint(x: x0, y: y1), to: NSPoint(x: x0, y: y1 - r), radius: r) }
        p.line(to: NSPoint(x: x0, y: y0 + (top ? r : 0)))
        if top { p.appendArc(from: NSPoint(x: x0, y: y0), to: NSPoint(x: x0 + r, y: y0), radius: r) }
        p.close()
        return p
    }

    /// The hairline border: both sides on every row, the top on the first, the bottom on the last
    private static func edgePath(_ rect: NSRect, top: Bool, bottom: Bool) -> NSBezierPath {
        let r = Focus.radiusPanel
        let (x0, x1, y0, y1) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x0, y: bottom ? y1 - r : y1))
        if top {
            p.line(to: NSPoint(x: x0, y: y0 + r))
            p.appendArc(from: NSPoint(x: x0, y: y0), to: NSPoint(x: x0 + r, y: y0), radius: r)
            p.line(to: NSPoint(x: x1 - r, y: y0))
            p.appendArc(from: NSPoint(x: x1, y: y0), to: NSPoint(x: x1, y: y0 + r), radius: r)
        } else {
            p.line(to: NSPoint(x: x0, y: y0))
            p.move(to: NSPoint(x: x1, y: y0))
        }
        if bottom {
            p.line(to: NSPoint(x: x1, y: y1 - r))
            p.appendArc(from: NSPoint(x: x1, y: y1), to: NSPoint(x: x1 - r, y: y1), radius: r)
            p.line(to: NSPoint(x: x0 + r, y: y1))
            p.appendArc(from: NSPoint(x: x0, y: y1), to: NSPoint(x: x0, y: y1 - r), radius: r)
        } else {
            p.line(to: NSPoint(x: x1, y: y1))
        }
        return p
    }

    // MARK: Mouse

    /// Called when the table hands this view to another row
    func reset() {
        if renameField != nil { endRename(save: true) }
        hovered = false
        mouseDownEvent = nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let info, let down = mouseDownEvent, !dragStarted, let source = dragSource, !isRenaming else { return }
        let distance = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
        guard distance > 5 else { return }
        dragStarted = true
        onDragStart?(info.task.id)
        let item = NSDraggingItem(pasteboardWriter: info.task.id.uuidString as NSString)
        item.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [item], event: down, source: source)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !dragStarted, !isRenaming, let info else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard isInsidePanel(point) else { return }
        let hit = column(at: point)
        controller?.click(task: info.task.id, column: hit?.column, rect: hit?.rect ?? bounds, in: self,
                          clickCount: event.clickCount, modifiers: event.modifierFlags,
                          rename: { [weak self] in self?.beginRename() })
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let info, !isRenaming, isInsidePanel(convert(event.locationInWindow, from: nil)) else { return nil }
        return controller?.makeMenu(task: info.task.id, rename: { [weak self] in self?.beginRename() })
    }

    override func resetCursorRects() {
        guard !isRenaming, let rect = columnRects().first(where: { $0.column == .title })?.rect else { return }
        addCursorRect(rect, cursor: .pointingHand)
    }

    // MARK: Tooltips

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let info, let hit = column(at: point) else { return "" }
        let task = info.task
        switch hit.column {
        case .status: return "\(task.status.title). Click for \(task.status.next.title.lowercased()), right-click for all"
        case .title: return "Click to open, double-click to rename"
        case .project: return info.display.projectName ?? ""
        case .milestone: return "Change milestone"
        case .sprint: return task.sprintSlot == .closed ? info.display.sprintLabel : "Change sprint"
        case .due: return "Change due date"
        case .priority: return "Change priority"
        case .time: return "Change time spent or expected time"
        case .timer: return task.isDone ? "" : (info.display.runningSince != nil ? "Pause timer" : "Start timer")
        }
    }

    // MARK: Rename in place

    private var renameField: NSTextField?
    private var isRenaming: Bool { renameField != nil }

    func beginRename() {
        guard renameField == nil, let info, let rect = columnRects().first(where: { $0.column == .title })?.rect else { return }
        let field = NSTextField(string: info.task.title)
        field.font = Style.title
        field.textColor = Style.text
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = Style.raised
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.wantsLayer = true
        field.layer?.cornerRadius = Focus.radiusTag
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor(Focus.lineStrong).cgColor
        field.frame = NSRect(x: rect.minX - 8, y: rect.midY - 14, width: rect.width + 8, height: 28)
        field.delegate = self
        addSubview(field)
        renameField = field
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    private func endRename(save: Bool) {
        guard let field = renameField, let info else { return }
        renameField = nil
        let text = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        if save, text.trimmingCharacters(in: .whitespacesAndNewlines) != info.task.title {
            controller?.rename(info.task.id, to: text)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Return and clicking elsewhere both save; Esc is handled below
        endRename(save: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endRename(save: false)
            return true
        }
        return false
    }

    private func snapshot() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: Accessibility (answered on demand, so it costs nothing while scrolling)

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }

    override func accessibilityLabel() -> String? {
        guard let task = info?.task else { return nil }
        return "\(task.title), \(task.status.title), \(task.priority.title) priority"
    }

    override func accessibilityPerformPress() -> Bool {
        guard let info, let store = controller?.store, let model = controller?.model else { return false }
        model.clickTitle(info.task.id, store: store, modifiers: [])
        return true
    }
}
