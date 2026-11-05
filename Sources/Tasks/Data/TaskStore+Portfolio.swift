import Foundation

// The portfolio: one summary per active project for All projects › Overview ("which project is
// slipping?"). The rules are pure
// functions (PortfolioRules) so they can be tested without a store; the store only gathers inputs.

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
    /// The workspace's sprint, the same on every card
    let sprint: SprintState
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
        PortfolioRules.attentionLevel(overdueTasks: overdueCount, untouchedDays: untouchedDays)
    }

    /// "Sprint 14 · day 9 of 14", "Sprint 14 · starts Nov 2", "Sprint 14 · ended Oct 28";
    /// "No sprints · 12 open" for a project without sprints
    var sprintLine: String {
        guard project.usesSprints else { return "No sprints · \(openCount) open" }
        return PortfolioRules.sprintLine(sprint, day: sprintDay)
    }
}

enum PortfolioRules {
    /// "Untouched N days" turns amber from this many days.
    static let staleAfterDays = 7

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

    /// How urgently a project needs a look: 2 overdue tasks, 1 untouched for `staleAfterDays` or
    /// more, 0 fine.
    static func attentionLevel(overdueTasks: Int, untouchedDays: Int) -> Int {
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
        let sprintWork = tasks.filter { isCurrentWork($0) && !$0.isCanceled }
        let activity = lastActivity(projectId: projectId, now: now)
        let sprintRange = sprintInterval(calendar: calendar)
        return ProjectOverview(
            project: project,
            sprint: self.sprint,
            sprintDay: PortfolioRules.sprintDay(self.sprint, now: now, calendar: calendar),
            sprintDone: sprintWork.filter(\.isDone).count,
            sprintPlanned: sprintWork.count,
            openCount: tasks.filter { !$0.isClosed }.count,
            trackedInSprint: trackedSeconds(.project(projectId), in: sprintRange, now: now),
            trackedThisWeek: trackedSeconds(.project(projectId), in: PortfolioRules.weekInterval(now, calendar: calendar), now: now),
            overdueCount: tasks.filter { isOverdue($0, now: now) }.count,
            inProgressCount: tasks.filter { $0.statusCategory == .started && $0.sprintSlot != .closed }.count,
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
}
