import Foundation

// What task notifications to schedule, as a pure function of a snapshot of the data, the settings
// and the time: NotificationPlanner.plan. TaskNotifications (the service) compares the plan with
// what Notification Center already holds (NotificationPlanner.diff) and only adds and removes
// the difference, so rescheduling after every change never duplicates a notification.
//
// Identifiers are stable: the same reminder for the same day always has the same id, and its
// signature (title, body, time) tells when the scheduled copy is out of date.

/// Where a click on a notification goes.
enum NotificationTarget: Equatable, Sendable {
    case today
    case task(UUID)
    case milestone(UUID)

    var stringValue: String {
        switch self {
        case .today: return "today"
        case let .task(id): return "task:\(id.uuidString)"
        case let .milestone(id): return "milestone:\(id.uuidString)"
        }
    }

    init?(stringValue: String) {
        if stringValue == "today" { self = .today; return }
        let parts = stringValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "task": self = .task(id)
        case "milestone": self = .milestone(id)
        default: return nil
        }
    }
}

/// One notification FlowMate wants in Notification Center.
struct PlannedNotification: Equatable, Sendable {
    enum Kind: String, Sendable {
        case morning, due, milestone, longRun, away

        /// The actions offered with it (registered as UNNotificationCategory)
        var categoryId: String {
            switch self {
            case .longRun: return NotificationPlanner.longRunCategory
            case .away: return NotificationPlanner.awayCategory
            case .morning, .due, .milestone: return NotificationPlanner.plainCategory
            }
        }

        /// Prompts FlowMate also shows in its own window and menu: they stay out of the way
        /// while FlowMate is the frontmost app.
        var onlyWhenInBackground: Bool { self == .longRun || self == .away }
    }

    let id: String
    let kind: Kind
    let title: String
    let body: String
    /// When it fires; nil delivers it right away
    let fireDate: Date?
    let target: NotificationTarget
    /// The running task of a long-run prompt (Keep going and Pause act on it)
    var taskId: UUID?

    /// Changes whenever what the user would see changes
    var signature: String {
        "\(title)|\(body)|\(fireDate.map { String(Int($0.timeIntervalSince1970)) } ?? "now")"
    }
}

/// What to change in Notification Center (NotificationPlanner.diff).
struct NotificationChanges: Equatable, Sendable {
    var removePending: [String] = []
    var removeDelivered: [String] = []
    var add: [PlannedNotification] = []

    var isEmpty: Bool { removePending.isEmpty && removeDelivered.isEmpty && add.isEmpty }
}

/// The data the planner reads, taken from the store.
struct NotificationPlanInput: Equatable, Sendable {
    struct DueTask: Equatable, Sendable {
        let id: UUID
        let title: String
        let projectName: String
        let dueDate: Date
    }

    struct DueMilestone: Equatable, Sendable {
        let id: UUID
        let name: String
        let projectName: String
        let dueDate: Date
        let done: Int
        let total: Int
    }

    struct RunningTimer: Equatable, Sendable {
        let taskId: UUID
        let title: String
        /// When the prompt's interval started: the session start, or the last Keep
        let since: Date
    }

    struct Away: Equatable, Sendable {
        let ids: [UUID]
        let duration: TimeInterval
        let slept: Bool
        let taskTitles: [String]
    }

    /// Open tasks with a due date (archived projects left out)
    var dueTasks: [DueTask] = []
    /// Open milestones with a due date
    var milestones: [DueMilestone] = []
    var running: [RunningTimer] = []
    /// "Still working?" interval; nil when the prompt is off
    var longRunThreshold: TimeInterval?
    /// Sleep or lock waiting for Keep or Discard
    var away: Away?
}

enum NotificationPlanner {
    static let plainCategory = "flowmate.task"
    static let longRunCategory = "flowmate.longrun"
    static let awayCategory = "flowmate.away"
    /// Every identifier starts with this, so FlowMate never touches anything else
    static let idPrefix = "flowmate."

    /// Days ahead the morning summary and due reminders are planned (today and tomorrow; the
    /// plan is redone every day and after every change)
    static let dayHorizon = 2
    /// Milestone reminders this far ahead
    static let milestoneHorizonDays = 30
    /// How many tasks get their own due reminder on one day; the rest share one
    static let dueReminderLimit = 4
    /// Milestone reminders come this many days before the due date
    static let milestoneLeadDays = 2

    static func plan(_ input: NotificationPlanInput, settings: NotificationSettings, now: Date,
                     calendar: Calendar = .current) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        let today = calendar.startOfDay(for: now)
        func morning(of day: Date) -> Date {
            calendar.date(byAdding: .minute, value: settings.morningMinutes, to: day) ?? day
        }

        for offset in 0..<dayHorizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let fire = morning(of: day)
            guard fire > now, let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let dueThatDay = input.dueTasks.filter { $0.dueDate >= day && $0.dueDate < next }
                .sorted { $0.dueDate == $1.dueDate ? $0.title < $1.title : $0.dueDate < $1.dueDate }
            let overdueThen = input.dueTasks.filter { $0.dueDate < day }.count
            let key = dayKey(day, calendar: calendar)

            if settings.morningSummary, !dueThatDay.isEmpty || overdueThen > 0 {
                result.append(PlannedNotification(
                    id: idPrefix + "morning-\(key)", kind: .morning, title: "Today",
                    body: summaryLine(dueToday: dueThatDay.count, overdue: overdueThen),
                    fireDate: fire, target: .today
                ))
            }
            if settings.dueReminders, !dueThatDay.isEmpty {
                let own = dueThatDay.count > dueReminderLimit ? Array(dueThatDay.prefix(dueReminderLimit - 1)) : dueThatDay
                for task in own {
                    result.append(PlannedNotification(
                        id: idPrefix + "due-\(task.id.uuidString)-\(key)", kind: .due, title: task.title,
                        body: "Due today · \(task.projectName)", fireDate: fire, target: .task(task.id)
                    ))
                }
                if own.count < dueThatDay.count {
                    let more = dueThatDay.count - own.count
                    result.append(PlannedNotification(
                        id: idPrefix + "due-more-\(key)", kind: .due, title: "\(more) more due today",
                        body: dueThatDay.dropFirst(own.count).map(\.title).joined(separator: ", "),
                        fireDate: fire, target: .today
                    ))
                }
            }
        }

        if settings.milestoneReminders, let horizon = calendar.date(byAdding: .day, value: milestoneHorizonDays, to: today) {
            for milestone in input.milestones where milestone.total == 0 || milestone.done < milestone.total {
                let dueDay = calendar.startOfDay(for: milestone.dueDate)
                guard let remindDay = calendar.date(byAdding: .day, value: -milestoneLeadDays, to: dueDay) else { continue }
                let fire = morning(of: remindDay)
                guard fire > now, remindDay <= horizon else { continue }
                let progress = milestone.total == 0 ? "No tasks yet" : "\(milestone.done) of \(milestone.total) done"
                result.append(PlannedNotification(
                    id: idPrefix + "milestone-\(milestone.id.uuidString)-\(dayKey(dueDay, calendar: calendar))",
                    kind: .milestone, title: "\(milestone.name) is due in \(milestoneLeadDays) days",
                    body: "\(progress) · \(milestone.projectName)", fireDate: fire, target: .milestone(milestone.id)
                ))
            }
        }

        if settings.longRunAlerts, let threshold = input.longRunThreshold {
            for timer in input.running {
                // Kept in the plan after it fires, so the shown notification stays while the timer
                // runs; one already past when planned (a relaunch) isn't sent: the window and the menu ask
                let fire = timer.since.addingTimeInterval(threshold)
                result.append(PlannedNotification(
                    id: idPrefix + "longrun-\(timer.taskId.uuidString)-\(Int(timer.since.timeIntervalSince1970))",
                    kind: .longRun, title: "Still working on \(timer.title)?",
                    body: "Running for \(estimate(threshold)) without a break.",
                    fireDate: fire, target: .task(timer.taskId), taskId: timer.taskId
                ))
            }
        }

        if settings.sleepAlerts, let away = input.away, !away.ids.isEmpty {
            let what = away.slept ? "slept" : "was locked"
            let tasks = away.taskTitles.first.map { away.taskTitles.count == 1 ? $0 : "\($0) and \(away.taskTitles.count - 1) more" } ?? ""
            result.append(PlannedNotification(
                id: idPrefix + "away-" + away.ids.map(\.uuidString).joined(separator: "-"),
                kind: .away,
                title: "\(away.taskTitles.count == 1 ? "A timer" : "Timers") ran while your Mac \(what) \(clockLength(away.duration))",
                body: "\(tasks) kept counting. Keep it, or discard the \(away.slept ? "sleep" : "away") time.",
                fireDate: nil, target: .today
            ))
        }
        return result
    }

    /// "3 due today, 1 overdue", "1 due today", "2 overdue"
    static func summaryLine(dueToday: Int, overdue: Int) -> String {
        var parts: [String] = []
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        if overdue > 0 { parts.append("\(overdue) overdue") }
        return parts.isEmpty ? "Nothing due today" : parts.joined(separator: ", ")
    }

    /// What to change in Notification Center to match `plan`.
    /// - `pending`: FlowMate's scheduled notifications (id → signature). Unwanted and out-of-date
    ///   ones are removed; new and changed ones whose time is still ahead are added.
    /// - `delivered`: FlowMate's notifications already shown. Only prompts (long-run, sleep) that no
    ///   longer apply are taken back; a morning summary or a reminder stays until you clear it.
    /// - `posted`: immediate notifications already sent this run, so they're sent once.
    static func diff(pending: [String: String], delivered: Set<String>, plan: [PlannedNotification],
                     posted: Set<String> = [], now: Date) -> NotificationChanges {
        let wanted = Dictionary(plan.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let removePending = pending.filter { id, signature in
            guard id.hasPrefix(idPrefix) else { return false }
            guard let planned = wanted[id] else { return true }
            return planned.signature != signature
        }.keys.sorted()
        let removeDelivered = delivered.filter { id in
            id.hasPrefix(idPrefix) && isPrompt(id) && wanted[id] == nil
        }.sorted()
        let add = plan.filter { planned in
            guard let fire = planned.fireDate else {
                return !delivered.contains(planned.id) && !posted.contains(planned.id) && pending[planned.id] == nil
            }
            return fire > now && pending[planned.id] != planned.signature
        }
        return NotificationChanges(removePending: removePending, removeDelivered: removeDelivered, add: add)
    }

    /// Long-run and sleep prompts, which go away once answered or no longer true.
    static func isPrompt(_ id: String) -> Bool {
        id.hasPrefix(idPrefix + "longrun-") || id.hasPrefix(idPrefix + "away-")
    }

    /// "3h", "2h 30m", "45m"
    static func estimate(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "2h 05m", "45m" (as the sleep prompt says it)
    static func clockLength(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : String(format: "%dh %02dm", h, m)
    }

    /// "2026-10-31"
    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension TaskStore {
    /// The planner's view of the data now.
    func notificationInput(now: Date = Date()) -> NotificationPlanInput {
        let archived = Set(archivedProjects.map(\.id))
        let names = Dictionary(workspace.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var input = NotificationPlanInput()
        input.dueTasks = workspace.tasks.compactMap { task in
            guard !task.isClosed, !archived.contains(task.projectId), let due = task.dueDate else { return nil }
            return .init(id: task.id, title: task.title, projectName: names[task.projectId] ?? "", dueDate: due)
        }
        input.milestones = workspace.milestones.compactMap { milestone in
            guard !milestone.isCompleted, !archived.contains(milestone.projectId), let due = milestone.dueDate else { return nil }
            let progress = milestoneProgress(milestone.id)
            return .init(id: milestone.id, name: milestone.name, projectName: names[milestone.projectId] ?? "",
                         dueDate: due, done: progress.done, total: progress.total)
        }
        input.running = runningTasks.compactMap { task in
            guard let started = startedAt(task.id) else { return nil }
            return .init(taskId: task.id, title: task.title, since: max(started, longRunAcknowledged[task.id] ?? started))
        }
        input.longRunThreshold = longRunThreshold
        if !awayGaps.isEmpty {
            input.away = .init(ids: awayGaps.map(\.id), duration: awayDuration,
                               slept: awayGaps.contains { $0.kind == .sleep }, taskTitles: awayTasks.map(\.title))
        }
        return input
    }
}
