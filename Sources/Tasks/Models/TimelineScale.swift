import Foundation

/// The Milestones tab shows rows or the roadmap timeline.
enum MilestonesLayout: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case list, timeline

    static var fallback: MilestonesLayout { .list }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .timeline: return "Timeline"
        }
    }
}

/// How much time the timeline fits in its visible width.
enum TimelineZoom: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case month, quarter

    static var fallback: TimelineZoom { .quarter }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Month"
        case .quarter: return "Quarter"
        }
    }

    /// Days the visible width shows: about five weeks, or the default 14-week window.
    var visibleDays: Int {
        switch self {
        case .month: return 35
        case .quarter: return TimelineScale.defaultDaysBefore + TimelineScale.defaultDaysAfter
        }
    }

    /// Never squeeze a day below this, so diamonds stay apart and draggable.
    var minimumPointsPerDay: CGFloat {
        switch self {
        case .month: return 22
        case .quarter: return 8
        }
    }
}

/// Maps days to x positions on the roadmap timeline and back. Day `i` (0-based from `start`)
/// spans `i * pointsPerDay ..< (i + 1) * pointsPerDay`; a milestone sits at the middle of its day.
struct TimelineScale: Equatable {
    /// The axis covers at least two weeks back and twelve weeks ahead.
    static let defaultDaysBefore = 14
    static let defaultDaysAfter = 84
    /// Room left around the earliest and latest dates the axis must show.
    static let margin = 7

    /// Midnight of the first day
    let start: Date
    let dayCount: Int
    let pointsPerDay: CGFloat
    let calendar: Calendar

    init(start: Date, dayCount: Int, pointsPerDay: CGFloat, calendar: Calendar = .current) {
        self.start = calendar.startOfDay(for: start)
        self.dayCount = max(1, dayCount)
        self.pointsPerDay = max(1, pointsPerDay)
        self.calendar = calendar
    }

    /// The axis for `dates` (milestone due dates, project target dates, sprint ends): from two weeks
    /// ago to twelve weeks ahead, widened to show every date with a week to spare, and starting on
    /// the first day of a week so week lines fall on the grid.
    static func fitting(_ dates: [Date], now: Date, zoom: TimelineZoom, visibleWidth: CGFloat,
                        calendar: Calendar = .current) -> TimelineScale {
        let today = calendar.startOfDay(for: now)
        var first = calendar.date(byAdding: .day, value: -defaultDaysBefore, to: today) ?? today
        var last = calendar.date(byAdding: .day, value: defaultDaysAfter, to: today) ?? today
        for date in dates {
            let day = calendar.startOfDay(for: date)
            if let before = calendar.date(byAdding: .day, value: -margin, to: day), before < first { first = before }
            if let after = calendar.date(byAdding: .day, value: margin, to: day), after > last { last = after }
        }
        first = calendar.dateInterval(of: .weekOfYear, for: first)?.start ?? first
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        return TimelineScale(start: first, dayCount: days,
                             pointsPerDay: pointsPerDay(zoom: zoom, visibleWidth: visibleWidth), calendar: calendar)
    }

    /// The day width that fits the zoom's days in the visible width.
    static func pointsPerDay(zoom: TimelineZoom, visibleWidth: CGFloat) -> CGFloat {
        max(zoom.minimumPointsPerDay, (visibleWidth / CGFloat(zoom.visibleDays)).rounded(.down))
    }

    var width: CGFloat { CGFloat(dayCount) * pointsPerDay }
    var end: Date { calendar.date(byAdding: .day, value: dayCount, to: start) ?? start }

    /// Days from the start to the date's day (negative before the axis).
    func dayIndex(of date: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// The middle of the date's day: where a milestone's diamond sits.
    func x(for date: Date) -> CGFloat {
        (CGFloat(dayIndex(of: date)) + 0.5) * pointsPerDay
    }

    /// The left edge of the date's day: where a day line (today, a sprint boundary) is drawn.
    func lineX(for date: Date) -> CGFloat {
        CGFloat(dayIndex(of: date)) * pointsPerDay
    }

    /// Midnight of the day under `x`.
    func date(atX x: CGFloat) -> Date {
        let index = Int((x / pointsPerDay).rounded(.down))
        return calendar.date(byAdding: .day, value: index, to: start) ?? start
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// Whole days a drag of `translation` points moves a diamond (snapped to the nearest day).
    func dayOffset(forTranslation translation: CGFloat) -> Int {
        Int((translation / pointsPerDay).rounded())
    }

    /// Where a diamond lands when dragged: the original date moved by whole days, keeping its time.
    func draggedDate(from original: Date, translation: CGFloat) -> Date {
        calendar.date(byAdding: .day, value: dayOffset(forTranslation: translation), to: original) ?? original
    }

    /// The first day of each week on the axis (week lines and labels).
    var weekStarts: [Date] {
        var result: [Date] = []
        var day = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        while day < end {
            if day >= start { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 7, to: day) else { break }
            day = next
        }
        return result
    }

    /// The first day of each month on the axis, plus the axis start (month labels).
    var monthStarts: [Date] {
        var result = [start]
        var month = calendar.dateInterval(of: .month, for: start)?.end ?? end
        while month < end {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }
}
