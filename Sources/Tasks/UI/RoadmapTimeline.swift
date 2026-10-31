import SwiftUI

/// The Milestones tab's Timeline: a horizontal time axis with one lane per project (sticky on the
/// left), milestones as diamonds at their due dates filled by progress, faint lines for each
/// project's target date and current sprint, and a Today line. Hover a diamond for its numbers,
/// click it for its page, drag it sideways to move its due date (snaps to days, one undo step).
/// Milestones without a date wait in the No date tray underneath.
struct RoadmapTimeline: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    static let laneHeight: CGFloat = 56
    static let axisHeight: CGFloat = 44
    static let laneColumnWidth: CGFloat = 200
    /// The canvas is never shorter than this, so a tooltip has room under a single lane.
    static let minCanvasHeight: CGFloat = 236
    static let tooltipWidth: CGFloat = 236

    @State private var hovered: UUID?
    @State private var dragging: UUID?

    /// The projects drawn: the one on screen, or every active project in sidebar order.
    private var lanes: [Project] {
        if let id = model.scope.projectId { return store.project(id).map { [$0] } ?? [] }
        return store.projects
    }

    var body: some View {
        let lanes = lanes
        let milestones = lanes.flatMap { store.milestones(of: $0.id) }
        let undated = milestones.filter { $0.dueDate == nil }
        let canvasHeight = max(Self.minCanvasHeight, Self.axisHeight + CGFloat(lanes.count) * Self.laneHeight)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                laneColumn(lanes, height: canvasHeight)
                Rectangle().fill(Focus.hairline).frame(width: 1)
                GeometryReader { geo in
                    let now = Date()
                    let scale = TimelineScale.fitting(axisDates(lanes, milestones), now: now, zoom: model.timelineZoom,
                                                      visibleWidth: geo.size.width)
                    canvas(lanes, scale: scale, now: now, height: canvasHeight)
                }
            }
            .frame(height: canvasHeight)
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
            .focusPanel()
            if !undated.isEmpty { noDateTray(undated) }
        }
    }

    /// Dates the axis must show: due dates, target dates and the current sprints.
    private func axisDates(_ lanes: [Project], _ milestones: [Milestone]) -> [Date] {
        milestones.compactMap(\.dueDate) + lanes.compactMap(\.targetDate) + lanes.flatMap { [$0.sprint.startDate, $0.sprint.nextStartDate] }
    }

    // MARK: - Lanes (sticky column)

    private func laneColumn(_ lanes: [Project], height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                FocusCaption(text: lanes.count == 1 ? "Project" : "Projects")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.axisHeight)
            .overlay(alignment: .bottom) { FocusDivider() }
            ForEach(lanes) { project in
                LaneHeader(project: project, count: store.milestones(of: project.id).filter { !$0.isCompleted }.count)
                    .frame(height: Self.laneHeight)
                    .overlay(alignment: .bottom) { FocusDivider() }
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.laneColumnWidth, height: height, alignment: .top)
        .background(Focus.raised)
    }

    // MARK: - Canvas

    private func canvas(_ lanes: [Project], scale: TimelineScale, now: Date, height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    TimelineGrid(scale: scale, lanes: lanes, now: now, axisHeight: Self.axisHeight, laneHeight: Self.laneHeight)
                        .frame(width: scale.width, height: height)
                    TimelineAxis(scale: scale, now: now)
                        .frame(width: scale.width, height: Self.axisHeight)
                    VStack(spacing: 0) {
                        ForEach(lanes) { project in
                            lane(project, scale: scale, now: now)
                                .frame(width: scale.width, height: Self.laneHeight)
                                .zIndex(laneHolds(hovered ?? dragging, project) ? 1 : 0)
                        }
                    }
                    .padding(.top, Self.axisHeight)
                    tooltipLayer(lanes, scale: scale, now: now, height: height)
                    // Where the axis opens: two weeks before today
                    HStack(spacing: 0) {
                        Color.clear.frame(width: max(0, scale.lineX(for: Calendar.current.date(
                            byAdding: .day, value: -TimelineScale.defaultDaysBefore, to: now) ?? now)), height: 1)
                        Color.clear.frame(width: 1, height: 1).id(scrollAnchor)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: scale.width, height: height, alignment: .topLeading)
                .coordinateSpace(name: Self.space)
            }
            .onAppear { scrollToStart(proxy) }
            .onChange(of: model.timelineZoom) { _ in scrollToStart(proxy) }
            .onReceive(NotificationCenter.default.publisher(for: Self.scrollToTodayNotification)) { _ in scrollToStart(proxy) }
        }
    }

    static let space = "roadmap-timeline"
    private let scrollAnchor = "timeline-start"
    /// Posted by the toolbar's Today button.
    static let scrollToTodayNotification = Notification.Name("FlowMate.timelineScrollToToday")

    private func scrollToStart(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async { proxy.scrollTo(scrollAnchor, anchor: .leading) }
    }

    private func laneHolds(_ milestoneId: UUID?, _ project: Project) -> Bool {
        milestoneId.flatMap { store.milestone($0) }?.projectId == project.id
    }

    private func lane(_ project: Project, scale: TimelineScale, now: Date) -> some View {
        let dated = store.milestones(of: project.id)
            .compactMap { m in m.dueDate.map { (milestone: m, x: scale.x(for: $0)) } }
            .sorted { $0.x < $1.x }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dated.enumerated()), id: \.element.milestone.id) { index, item in
                let nextX = index + 1 < dated.count ? dated[index + 1].x : scale.width
                TimelineDiamond(
                    milestone: item.milestone,
                    forecast: store.milestoneForecast(item.milestone.id, now: now),
                    scale: scale,
                    labelWidth: max(0, nextX - item.x - 22),
                    hovered: $hovered,
                    dragging: $dragging
                )
                .position(x: item.x, y: Self.laneHeight / 2)
            }
        }
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltipLayer(_ lanes: [Project], scale: TimelineScale, now: Date, height: CGFloat) -> some View {
        if dragging == nil, let id = hovered, let milestone = store.milestone(id), let due = milestone.dueDate,
           let laneIndex = lanes.firstIndex(where: { $0.id == milestone.projectId }),
           let forecast = store.milestoneForecast(id, now: now) {
            let laneTop = Self.axisHeight + CGFloat(laneIndex) * Self.laneHeight
            let below = laneTop + Self.laneHeight - 6
            let tooltipHeight: CGFloat = 126
            let fitsBelow = below + tooltipHeight <= height
            let x = min(max(8, scale.x(for: due) - 18), scale.width - Self.tooltipWidth - 8)
            TimelineTooltip(milestone: milestone, forecast: forecast, now: now)
                .frame(width: Self.tooltipWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: x, y: fitsBelow ? below : max(0, laneTop - tooltipHeight + 6))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - No date

    private func noDateTray(_ undated: [Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FocusCaption(text: "No date")
                Text("Give these a due date to place them on the timeline")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
            }
            FlowRow(spacing: 8) {
                ForEach(undated) { milestone in
                    NoDateChip(milestone: milestone, showProject: model.scope.projectId == nil)
                }
            }
        }
    }
}

// MARK: - Lane header

private struct LaneHeader: View {
    @EnvironmentObject private var model: TasksViewModel
    let project: Project
    let count: Int

    @State private var hovering = false

    var body: some View {
        Button { model.select(.project(project.id)) } label: {
            HStack(spacing: 9) {
                FocusProjectTile(project: project)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(Focus.rowStrong).foregroundColor(Focus.text).lineLimit(1)
                    Text(count == 0 ? "No open milestones" : "\(count) open")
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .background(hovering ? Focus.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help("Show \(project.name)")
    }
}

// MARK: - Grid and axis

/// Week lines, each lane's sprint boundaries and target date, lane separators and the Today line.
private struct TimelineGrid: View {
    let scale: TimelineScale
    let lanes: [Project]
    let now: Date
    let axisHeight: CGFloat
    let laneHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            // Weekends, very faint
            if scale.pointsPerDay >= 12 {
                for index in 0..<scale.dayCount {
                    guard let day = scale.calendar.date(byAdding: .day, value: index, to: scale.start),
                          scale.calendar.isDateInWeekend(day) else { continue }
                    let rect = CGRect(x: CGFloat(index) * scale.pointsPerDay, y: axisHeight,
                                      width: scale.pointsPerDay, height: size.height - axisHeight)
                    context.fill(Path(rect), with: .color(Focus.sidebar.opacity(0.6)))
                }
            }
            // Week lines
            for week in scale.weekStarts {
                let x = scale.lineX(for: week)
                context.stroke(line(x, from: axisHeight, to: size.height), with: .color(Focus.hairline), lineWidth: 1)
            }
            for (index, project) in lanes.enumerated() {
                let top = axisHeight + CGFloat(index) * laneHeight
                let bottom = top + laneHeight
                // Current sprint: a faint band with dashed edges
                let start = scale.lineX(for: project.sprint.startDate)
                let end = scale.lineX(for: project.sprint.nextStartDate)
                context.fill(Path(CGRect(x: start, y: top + 1, width: max(0, end - start), height: laneHeight - 2)),
                             with: .color(Color(hex: project.colorHex).opacity(0.05)))
                let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
                for x in [start, end] {
                    context.stroke(line(x, from: top + 4, to: bottom - 4), with: .color(Focus.text3.opacity(0.45)), style: dash)
                }
                // Target date: a solid line in the project's color
                if let target = project.targetDate {
                    let x = scale.x(for: target)
                    context.stroke(line(x, from: top + 4, to: bottom - 4), with: .color(Color(hex: project.colorHex).opacity(0.7)), lineWidth: 1.5)
                    var flag = Path()
                    flag.move(to: CGPoint(x: x, y: top + 4))
                    flag.addLine(to: CGPoint(x: x + 7, y: top + 7.5))
                    flag.addLine(to: CGPoint(x: x, y: top + 11))
                    flag.closeSubpath()
                    context.fill(flag, with: .color(Color(hex: project.colorHex).opacity(0.7)))
                }
                context.stroke(line(0, from: bottom, to: bottom, toX: size.width), with: .color(Focus.hairline), lineWidth: 1)
            }
            // Today
            let today = scale.x(for: now)
            context.stroke(line(today, from: axisHeight - 6, to: size.height), with: .color(Focus.text2.opacity(0.75)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }

    private func line(_ x: CGFloat, from top: CGFloat, to bottom: CGFloat, toX: CGFloat? = nil) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: toX ?? x, y: bottom))
        return path
    }
}

/// Month names on top, the first day of each week under them, and the Today label.
private struct TimelineAxis: View {
    let scale: TimelineScale
    let now: Date

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var body: some View {
        let todayX = scale.x(for: now)
        ZStack(alignment: .topLeading) {
            ForEach(scale.monthStarts, id: \.self) { month in
                Text(Self.monthFormatter.string(from: month))
                    .font(Focus.caption)
                    .foregroundColor(Focus.text2)
                    .fixedSize()
                    .offset(x: scale.lineX(for: month) + 8, y: 7)
            }
            if scale.pointsPerDay * 7 >= 34 {
                // Leave room for the Today label
                ForEach(scale.weekStarts.filter { abs(scale.lineX(for: $0) + 10 - todayX) > 34 }, id: \.self) { week in
                    Text(String(scale.calendar.component(.day, from: week)))
                        .font(Focus.meta.monospacedDigit())
                        .foregroundColor(Focus.text3)
                        .fixedSize()
                        .offset(x: scale.lineX(for: week) + 5, y: 24)
                }
            }
            Text("Today")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(Focus.raised)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Capsule().fill(Focus.text2))
                .fixedSize()
                .offset(x: todayX - 20, y: 23)
        }
        .frame(width: scale.width, height: RoadmapTimeline.axisHeight, alignment: .topLeading)
        .background(Focus.raised.opacity(0.92))
        .overlay(alignment: .bottom) { FocusDivider() }
        .accessibilityHidden(true)
    }
}

// MARK: - Diamond

/// A rotated square filled from the bottom by progress, in the milestone's color: a `risk`
/// outline when overdue or at risk, a check when complete. Click opens the milestone's page;
/// dragging sideways moves its due date by whole days.
private struct TimelineDiamond: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestone: Milestone
    let forecast: MilestoneForecast?
    let scale: TimelineScale
    let labelWidth: CGFloat
    @Binding var hovered: UUID?
    @Binding var dragging: UUID?

    @State private var translation: CGFloat = 0

    static let size: CGFloat = 18

    var body: some View {
        let offsetDays = scale.dayOffset(forTranslation: translation)
        let shift = CGFloat(offsetDays) * scale.pointsPerDay
        let isDragging = dragging == milestone.id
        ZStack {
            DiamondGlyph(milestone: milestone, forecast: forecast, highlighted: hovered == milestone.id || isDragging)
                .frame(width: Self.size, height: Self.size)
            if labelWidth >= 36, !isDragging {
                Text(milestone.name)
                    .font(Focus.meta)
                    .foregroundColor(milestone.isCompleted ? Focus.text3 : Focus.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: min(labelWidth, 170), alignment: .leading)
                    .offset(x: Self.size / 2 + 6 + min(labelWidth, 170) / 2)
                    .allowsHitTesting(false)
            }
            if isDragging, let due = milestone.dueDate {
                Text(dragLabel(scale.draggedDate(from: due, translation: translation), days: offsetDays))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(Focus.text)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(Focus.raised))
                    .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(Focus.lineStrong, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .fixedSize()
                    .offset(y: -24)
            }
        }
        .frame(width: Self.size + 6, height: Self.size + 6)
        .contentShape(Rectangle())
        .offset(x: shift)
        .onHover { inside in
            if inside { hovered = milestone.id } else if hovered == milestone.id { hovered = nil }
        }
        .onTapGesture { model.showMilestone(milestone.id, store: store) }
        .gesture(dragGesture)
        .focusPointerCursor()
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the milestone")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.showMilestone(milestone.id, store: store) }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(byDays: 1)
            case .decrement: move(byDays: -1)
            @unknown default: break
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(RoadmapTimeline.space))
            .onChanged { value in
                guard milestone.dueDate != nil else { return }
                if dragging != milestone.id { dragging = milestone.id }
                translation = value.translation.width
            }
            .onEnded { value in
                let days = scale.dayOffset(forTranslation: value.translation.width)
                translation = 0
                dragging = nil
                move(byDays: days)
            }
    }

    private func move(byDays days: Int) {
        guard let moved = store.shiftMilestoneDue(milestone.id, byDays: days) else { return }
        model.showUndoToast("\(milestone.name) moved to \(SprintState.shortDate(moved))", store: store)
    }

    /// "Nov 18 · +3d"
    private func dragLabel(_ date: Date, days: Int) -> String {
        let shift = days == 0 ? "" : " · \(days > 0 ? "+" : "−")\(abs(days))d"
        return SprintState.shortDate(date) + shift
    }

    private var accessibilityText: String {
        var text = "\(milestone.name), due \(milestone.dueDate.map(SprintState.shortDate) ?? "no date")"
        if let forecast { text += ", \(forecast.progress.label)" }
        if let label = forecast?.health.label { text += ", \(label)" }
        return text
    }
}

/// The diamond drawing shared by the timeline and the No date tray.
private struct DiamondGlyph: View {
    let milestone: Milestone
    let forecast: MilestoneForecast?
    var highlighted = false

    var body: some View {
        let color = Color(hex: milestone.colorHex == Milestone.unsetColor ? 0x64748B : milestone.colorHex)
        let fraction = milestone.isCompleted ? 1 : (forecast?.progress.fraction ?? 0)
        let risky = forecast?.health.needsAttention ?? false
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                Diamond().fill(Focus.raised)
                Diamond().fill(color.opacity(0.16))
                // Progress fills from the bottom
                Diamond().fill(color)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: side * CGFloat(max(0, min(1, fraction))))
                    }
                Diamond().stroke(risky ? Focus.risk : color, lineWidth: risky ? 2 : 1.5)
                if milestone.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.42, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(highlighted ? 1.15 : 1)
            .shadow(color: highlighted ? .black.opacity(0.18) : .clear, radius: 3, y: 1)
            .animation(Focus.hoverAnimation, value: highlighted)
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tooltip

/// Name, due date and health, "N of M done" and the hours left.
private struct TimelineTooltip: View {
    @EnvironmentObject private var store: TaskStore
    let milestone: Milestone
    let forecast: MilestoneForecast
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MilestoneIcon(milestone, size: 11)
                Text(milestone.name).font(Focus.groupTitle).foregroundColor(Focus.text).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(milestone.dueDate.map { "Due " + TaskDates.dueLabel($0, now: now) } ?? "No date")
                    .font(Focus.meta)
                    .foregroundColor(forecast.health.needsAttention ? Focus.risk : Focus.text2)
                if let label = forecast.health.label {
                    FocusTag(text: label, systemImage: "exclamationmark.triangle", risk: true)
                } else if forecast.health == .complete {
                    FocusTag(text: "Completed", systemImage: "checkmark")
                }
            }
            HStack(spacing: 8) {
                FocusProgressBar(fraction: forecast.progress.fraction).frame(width: 70)
                Text("\(forecast.progress.done) of \(forecast.progress.total) done")
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text2)
            }
            Text(hoursLine)
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .focusMenuSurface()
    }

    private var hoursLine: String {
        var line = forecast.remainingLabel
        if forecast.health == .atRisk, let available = forecast.hoursAvailable {
            line += " · \(Focus.durationString(minutes: Int(available * 60))) of working time left"
        }
        return line + " · drag to move"
    }
}

// MARK: - No date chip

private struct NoDateChip: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let milestone: Milestone
    let showProject: Bool

    @State private var hovering = false

    var body: some View {
        Button { model.showMilestone(milestone.id, store: store) } label: {
            HStack(spacing: 7) {
                if showProject, let project = store.project(milestone.projectId) {
                    FocusProjectTile(project: project, size: 16)
                }
                MilestoneIcon(milestone, size: 11)
                Text(milestone.name).font(Focus.control).foregroundColor(Focus.text2).lineLimit(1)
                let progress = store.milestoneProgress(milestone.id)
                Text(progress.short).font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 9)
            .frame(height: Focus.controlHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help("Show \(milestone.name). Set a due date from its page or right-click.")
        .contextMenu {
            ForEach(DuePreset.allCases) { preset in
                Button("Due \(preset.title.lowercased())") { store.setMilestoneDue(milestone.id, to: preset.date()) }
            }
        }
    }
}
