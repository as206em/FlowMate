import Foundation

// The portfolio: one summary per active project for All projects › Overview ("which project is
// slipping?"), and the milestone forecasts the roadmap timeline draws. The rules are pure
// functions (PortfolioRules) so they can be tested without a store; the store only gathers inputs.

/// Where a milestone stands against its due date.
enum MilestoneHealth: Equatable, Sendable {
    /// Marked complete, or every task done
    case complete
    /// No due date, or enough working time left for the remaining hours
    case onTrack
    /// The remaining expected hours don't fit in the working time left before the due date
    case atRisk
    /// Past its due date with work left
    case overdue

    /// Drawn with a `risk` outline / tag
    var needsAttention: Bool { self == .atRisk || self == .overdue }

    /// "At risk", "Overdue"; nil when there's nothing to flag
    var label: String? {
        switch self {
        case .atRisk: return "At risk"
        case .overdue: return "Overdue"
        case .complete, .onTrack: return nil
        }
    }
}

/// A milestone's progress, remaining work and health, as of `now`.
struct MilestoneForecast: Equatable, Sendable {
    let milestoneId: UUID
    let progress: MilestoneProgress
    /// Σ over open tasks of max(0, expected − tracked), in hours
    let remainingHours: Double
    /// Working days from today through the due day (nil without a due date)
    let workingDaysLeft: Int?
    /// The hours that fit in those days at the project's pace
    let hoursAvailable: Double?
    let health: MilestoneHealth

    /// "12h left", "45m left", "Nothing left"
    var remainingLabel: String {
        let minutes = Int((remainingHours * 60).rounded())
        return minutes <= 0 ? "Nothing left" : Focus.durationString(minutes: minutes) + " left"
    }
}

/// Where a project's active sprint is today.
struct SprintDay: Equatable, Sendable {
    /// 1-based day of the sprint; 0 or less before it starts, above `length` after its last day
    let day: Int
    let length: Int

    var hasStarted: Bool { day >= 1 }
    var isOver: Bool { day > length }
}

/// The Overview's sort toggle.
enum PortfolioSort: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case attention, name, activity

    static var fallback: PortfolioSort { .attention }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: return "Attention"
        case .name: return "Name"
        case .activity: return "Recent activity"
        }
    }
}

/// One project card of the Overview.
struct ProjectOverview: Identifiable, Equatable, Sendable {
    let project: Project
    let sprintDay: SprintDay
    /// Active-sprint tasks done / planned (canceled ones left out); without sprints, every task not
    /// closed with a past sprint
    let sprintDone: Int
    let sprintPlanned: Int
    /// Open tasks of the project (the "No sprints · 12 open" line)
    var openCount = 0
    /// Seconds tracked on the project during the active sprint's dates, and this week
    let trackedInSprint: TimeInterval
    let trackedThisWeek: TimeInterval
    let overdueCount: Int
    /// Open tasks in a Started status
    let inProgressCount: Int
    /// The first open milestone by due date (dated before undated), with its forecast
    let nextMilestone: Milestone?
    let nextMilestoneForecast: MilestoneForecast?
    /// Latest task update, time entry or running timer (the project's creation when it has none)
    let lastActivity: Date
    /// Whole days since `lastActivity`
    let untouchedDays: Int
    /// The task the play button starts (TaskStore.nextTaskToStart)
    let nextTaskId: UUID?
    let isRunning: Bool

    var id: UUID { project.id }
    var isStale: Bool { untouchedDays >= PortfolioRules.staleAfterDays }

    /// Higher needs attention sooner (see PortfolioRules.attentionLevel).
    var attentionLevel: Int {
        PortfolioRules.attentionLevel(milestoneHealth: nextMilestoneForecast?.health, overdueTasks: overdueCount,
                                      untouchedDays: untouchedDays)
    }

    /// "Sprint 14 · day 9 of 14", "Sprint 14 · starts Nov 2", "Sprint 14 · ended Oct 28";
    /// "No sprints · 12 open" for a project without sprints
    var sprintLine: String {
        guard project.usesSprints else { return "No sprints · \(openCount) open" }
        return PortfolioRules.sprintLine(project.sprint, day: sprintDay)
    }
}

enum PortfolioRules {
    /// Hours a solo project gets per working day when it has no capacity of its own.
    static let defaultDailyHours: Double = 4
    /// Working days in a week, to turn a weekly capacity into a daily one.
    static let workingDaysPerWeek: Double = 5
    /// "Untouched N days" turns amber from this many days.
    static let staleAfterDays = 7

    // MARK: - Milestone health

    /// Working days (Monday–Friday) from today through the due day, both included; 0 once the due
    /// day has passed. A milestone due today still has today.
    static func workingDaysLeft(until due: Date, now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        guard dueDay >= today else { return 0 }
        var count = 0
        var day = today
        while day <= dueDay {
            if !calendar.isDateInWeekend(day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// Hours of work a project gets per working day: its weekly capacity ÷ 5, or 4h without one.
    static func dailyHours(weeklyCapacityHours: Double?) -> Double {
        guard let weekly = weeklyCapacityHours, weekly > 0 else { return defaultDailyHours }
        return weekly / workingDaysPerWeek
    }

    /// A milestone's health:
    /// - **complete** when marked complete, or it has tasks and all of them are done;
    /// - **overdue** when its due day is before today and work is left;
    /// - **at risk** when the remaining expected hours (expected − tracked of open tasks) exceed
    ///   the working days left until the due day × the daily hours (weekly capacity ÷ 5, or 4h when
    ///   the project has no capacity);
    /// - **on track** otherwise, and always without a due date.
    static func milestoneHealth(dueDate: Date?, isCompleted: Bool, progress: MilestoneProgress, remainingHours: Double,
                                weeklyCapacityHours: Double? = nil, now: Date, calendar: Calendar = .current) -> MilestoneHealth {
        if isCompleted || (progress.total > 0 && progress.done == progress.total) { return .complete }
        guard let due = dueDate else { return .onTrack }
        let workLeft = progress.done < progress.total || remainingHours > 0
        if due < calendar.startOfDay(for: now) { return workLeft ? .overdue : .onTrack }
        let available = Double(workingDaysLeft(until: due, now: now, calendar: calendar)) * dailyHours(weeklyCapacityHours: weeklyCapacityHours)
        return remainingHours > available + 0.0001 ? .atRisk : .onTrack
    }

    /// Remaining hours of a set of tasks: for each open (not done or canceled) task, its expected
    /// time minus what's tracked on it, never below zero.
    static func remainingHours(_ tasks: [(expectedMinutes: Int, trackedSeconds: TimeInterval, isClosed: Bool)]) -> Double {
        tasks.reduce(0) { sum, t in
            t.isClosed ? sum : sum + max(0, Double(t.expectedMinutes) * 60 - t.trackedSeconds) / 3600
        }
    }

    // MARK: - Sprint

    /// Which day of the sprint `now` falls on (day 1 is the start date).
    static func sprintDay(_ sprint: SprintState, now: Date, calendar: Calendar = .current) -> SprintDay {
        let start = calendar.startOfDay(for: sprint.startDate)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return SprintDay(day: days + 1, length: sprint.lengthInDays)
    }

    static func sprintLine(_ sprint: SprintState, day: SprintDay) -> String {
        if !day.hasStarted { return "\(sprint.name) · starts \(SprintState.shortDate(sprint.startDate))" }
        if day.isOver { return "\(sprint.name) · ended \(SprintState.shortDate(sprint.endDate))" }
        return "\(sprint.name) · day \(day.day) of \(day.length)"
    }

    // MARK: - Activity

    /// The latest of the dates (task updates, time entry ends, now for a running timer), or
    /// `fallback` (the project's creation) when there are none or all are older.
    static func lastActivity(_ dates: [Date], fallback: Date) -> Date {
        max(dates.max() ?? fallback, fallback)
    }

    /// Whole calendar days from the activity's day to today (0 today, 1 yesterday).
    static func untouchedDays(since activity: Date, now: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: activity), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// "Active today", "Active yesterday", "Untouched 12 days"
    static func activityLabel(untouchedDays days: Int) -> String {
        switch days {
        case 0: return "Active today"
        case 1: return "Active yesterday"
        default: return "Untouched \(days) days"
        }
    }

    // MARK: - Attention

    /// How urgently a project needs a look: 4 an overdue milestone, 3 a milestone at risk,
    /// 2 overdue tasks, 1 untouched for `staleAfterDays` or more, 0 fine.
    static func attentionLevel(milestoneHealth: MilestoneHealth?, overdueTasks: Int, untouchedDays: Int) -> Int {
        if milestoneHealth == .overdue { return 4 }
        if milestoneHealth == .atRisk { return 3 }
        if overdueTasks > 0 { return 2 }
        if untouchedDays >= staleAfterDays { return 1 }
        return 0
    }

    /// The Overview's order. Attention: the level, then more overdue tasks, then longer untouched,
    /// then the sidebar order. Name: A–Z. Recent activity: the most recently touched first.
    /// `cards` come in sidebar order; ties keep it.
    static func sorted(_ cards: [ProjectOverview], by sort: PortfolioSort) -> [ProjectOverview] {
        let indexed = Array(cards.enumerated())
        let ordered: [(offset: Int, element: ProjectOverview)]
        switch sort {
        case .attention:
            ordered = indexed.sorted { a, b in
                let x = a.element, y = b.element
                if x.attentionLevel != y.attentionLevel { return x.attentionLevel > y.attentionLevel }
                if x.overdueCount != y.overdueCount { return x.overdueCount > y.overdueCount }
                if x.untouchedDays != y.untouchedDays { return x.untouchedDays > y.untouchedDays }
                return a.offset < b.offset
            }
        case .name:
            ordered = indexed.sorted { a, b in
                let c = a.element.project.name.localizedCaseInsensitiveCompare(b.element.project.name)
                return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
            }
        case .activity:
            ordered = indexed.sorted { a, b in
                a.element.lastActivity == b.element.lastActivity ? a.offset < b.offset : a.element.lastActivity > b.element.lastActivity
            }
        }
        return ordered.map(\.element)
    }

    /// The calendar week containing `now`.
    static func weekInterval(_ now: Date, calendar: Calendar = .current) -> DateInterval {
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) { return week }
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, duration: 7 * 86_400)
    }
}

// MARK: - Store queries

extension TaskStore {
    /// The project's capacity in hours a week (Project.weeklyCapacityHours), used for milestone
    /// health; nil works at the default pace (4h a working day).
    func weeklyCapacityHours(_ projectId: UUID) -> Double? { project(projectId)?.weeklyCapacityHours }

    /// Progress, remaining hours and health of a milestone as of `now`.
    func milestoneForecast(_ milestoneId: UUID, now: Date = Date(), calendar: Calendar = .current) -> MilestoneForecast? {
        guard let milestone = milestone(milestoneId) else { return nil }
        let tasks = workspace.tasks.filter { $0.milestoneId == milestoneId }
        let progress = milestoneProgress(milestoneId)
        let remaining = PortfolioRules.remainingHours(tasks.map { ($0.expectedMinutes, elapsed($0, now: now), $0.isClosed) })
        let capacity = weeklyCapacityHours(milestone.projectId)
        let days = milestone.dueDate.map { PortfolioRules.workingDaysLeft(until: $0, now: now, calendar: calendar) }
        let health = PortfolioRules.milestoneHealth(dueDate: milestone.dueDate, isCompleted: milestone.isCompleted,
                                                    progress: progress, remainingHours: remaining,
                                                    weeklyCapacityHours: capacity, now: now, calendar: calendar)
        return MilestoneForecast(milestoneId: milestoneId, progress: progress, remainingHours: remaining,
                                 workingDaysLeft: days,
                                 hoursAvailable: days.map { Double($0) * PortfolioRules.dailyHours(weeklyCapacityHours: capacity) },
                                 health: health)
    }

    /// The project's next open milestone: the earliest due, then undated ones (Milestones order).
    func nextMilestone(of projectId: UUID) -> Milestone? {
        milestones(of: projectId).first { !$0.isCompleted }
    }

    /// When anything last happened in the project (task edits, time tracked, a running timer).
    func lastActivity(projectId: UUID, now: Date = Date()) -> Date {
        let tasks = workspace.tasks.filter { $0.projectId == projectId }
        let ids = Set(tasks.map(\.id))
        var dates = tasks.map(\.updatedAt)
        dates += workspace.timeEntries.filter { ids.contains($0.taskId) }.map(\.end)
        if workspace.runningTimers.keys.contains(where: ids.contains) { dates.append(now) }
        let created = project(projectId)?.createdAt ?? now
        return min(now, PortfolioRules.lastActivity(dates, fallback: created))
    }

    /// The Overview card of one project.
    func projectOverview(_ projectId: UUID, now: Date = Date(), calendar: Calendar = .current) -> ProjectOverview? {
        guard let project = project(projectId) else { return nil }
        let tasks = workspace.tasks.filter { $0.projectId == projectId }
        let sprint = tasks.filter { isCurrentWork($0) && !$0.isCanceled }
        let next = nextMilestone(of: projectId)
        let activity = lastActivity(projectId: projectId, now: now)
        let sprintRange = Self.days(project.sprint.startDate, through: project.sprint.endDate, calendar: calendar)
        return ProjectOverview(
            project: project,
            sprintDay: PortfolioRules.sprintDay(project.sprint, now: now, calendar: calendar),
            sprintDone: sprint.filter(\.isDone).count,
            sprintPlanned: sprint.count,
            openCount: tasks.filter { !$0.isClosed }.count,
            trackedInSprint: trackedSeconds(.project(projectId), in: sprintRange, now: now),
            trackedThisWeek: trackedSeconds(.project(projectId), in: PortfolioRules.weekInterval(now, calendar: calendar), now: now),
            overdueCount: tasks.filter { isOverdue($0, now: now) }.count,
            inProgressCount: tasks.filter { $0.statusCategory == .started && $0.sprintSlot != .closed }.count,
            nextMilestone: next,
            nextMilestoneForecast: next.flatMap { milestoneForecast($0.id, now: now, calendar: calendar) },
            lastActivity: activity,
            untouchedDays: PortfolioRules.untouchedDays(since: activity, now: now, calendar: calendar),
            nextTaskId: nextTaskToStart(projectId: projectId)?.id,
            isRunning: isProjectRunning(projectId)
        )
    }

    /// Every active (not archived) project's card, in the chosen order.
    func portfolio(sortedBy sort: PortfolioSort, now: Date = Date(), calendar: Calendar = .current) -> [ProjectOverview] {
        PortfolioRules.sorted(projects.compactMap { projectOverview($0.id, now: now, calendar: calendar) }, by: sort)
    }

    /// Moves a milestone's due date by whole days (a timeline drag), keeping its time of day.
    /// One undo step; nothing happens for 0 days or a milestone without a date.
    @discardableResult
    func shiftMilestoneDue(_ id: UUID, byDays days: Int, calendar: Calendar = .current) -> Date? {
        guard days != 0, let milestone = milestone(id), let due = milestone.dueDate,
              var moved = calendar.date(byAdding: .day, value: days, to: due) else { return nil }
        // With a start date this resizes the bar: the due date never goes before the start
        if let start = milestone.startDate, moved < start { moved = start }
        guard moved != due else { return nil }
        setMilestoneDates(id, start: milestone.startDate, due: moved)
        return moved
    }

    /// Sets start and due together (one undo step). A start on or after the due date is dropped.
    func setMilestoneDates(_ id: UUID, start: Date?, due: Date?, calendar: Calendar = .current) {
        mutate("Change milestone dates") { ws in
            guard let i = ws.milestones.firstIndex(where: { $0.id == id }) else { return }
            ws.milestones[i].dueDate = due
            if let start, let due, calendar.startOfDay(for: start) < calendar.startOfDay(for: due) {
                ws.milestones[i].startDate = calendar.startOfDay(for: start)
            } else {
                ws.milestones[i].startDate = nil
            }
        }
    }

    /// Moves a milestone's whole bar (start and due) by whole days. Returns the new due date.
    @discardableResult
    func shiftMilestone(_ id: UUID, byDays days: Int, calendar: Calendar = .current) -> Date? {
        guard days != 0, let milestone = milestone(id), let due = milestone.dueDate,
              let newDue = calendar.date(byAdding: .day, value: days, to: due) else { return nil }
        let newStart = milestone.startDate.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        setMilestoneDates(id, start: newStart, due: newDue)
        return newDue
    }

    /// A milestone from the timeline's No date tray dropped on a day: it's due then. Returns its
    /// name, or nil when the milestone is gone or already has that date.
    @discardableResult
    func placeMilestone(_ id: UUID, on day: Date, calendar: Calendar = .current) -> String? {
        guard let milestone = milestone(id) else { return nil }
        let date = calendar.startOfDay(for: day)
        guard milestone.dueDate.map({ !calendar.isDate($0, inSameDayAs: date) }) ?? true else { return nil }
        setMilestoneDue(id, to: date)
        return milestone.name
    }
}
