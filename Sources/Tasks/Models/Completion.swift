import Foundation

/// How much of a set of tasks is done, by count and by expected time (canceled tasks aren't part
/// of the work). The hours figure is the main one: a 5h task weighs more than a 5-minute one.
struct Completion: Equatable, Sendable {
    var doneCount = 0
    var totalCount = 0
    var doneMinutes = 0
    var totalMinutes = 0

    init(doneCount: Int = 0, totalCount: Int = 0, doneMinutes: Int = 0, totalMinutes: Int = 0) {
        self.doneCount = doneCount
        self.totalCount = totalCount
        self.doneMinutes = doneMinutes
        self.totalMinutes = totalMinutes
    }

    init(_ tasks: [TaskItem]) {
        let work = tasks.filter { !$0.isCanceled }
        let done = work.filter(\.isDone)
        self.init(doneCount: done.count, totalCount: work.count,
                  doneMinutes: done.reduce(0) { $0 + $1.expectedMinutes }, totalMinutes: work.reduce(0) { $0 + $1.expectedMinutes })
    }

    /// 0…1 of the expected time (of the task count when no time is planned)
    var fraction: Double {
        if totalMinutes > 0 { return Double(doneMinutes) / Double(totalMinutes) }
        return totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
    }

    /// "62%"
    var percentText: String { "\(Int((fraction * 100).rounded()))%" }

    /// "14h of 23h · 8 of 12 tasks", "Nothing planned yet"
    var detail: String {
        guard totalCount > 0 else { return "No tasks yet" }
        return "\(Focus.durationString(minutes: doneMinutes)) of \(Focus.durationString(minutes: totalMinutes)) · "
            + "\(doneCount) of \(totalCount) \(totalCount == 1 ? "task" : "tasks")"
    }
}

/// The planned time of the active sprint on one day, logged when it changes so the sprint's chart
/// can show work added after the start. Only the active sprint's points are kept.
struct SprintScopePoint: Codable, Equatable, Sendable {
    var sprint: Int
    var day: Date
    var plannedMinutes: Int
}

/// The numbers behind the sprint's burnup chart: per day since the start, the time done and the
/// time planned, up to today; and the sprint's end for the ideal line.
struct SprintBurnup: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let doneHours: Double
        let plannedHours: Double
        var id: Date { date }
    }

    let days: [Day]
    let start: Date
    let end: Date
    let today: Date
    /// What the sprint plans now, in hours: where the ideal line ends
    let plannedHours: Double
    /// The ideal pace for `date`: a straight line from 0 at the start to the plan at the end
    func idealHours(on date: Date, calendar: Calendar = .current) -> Double {
        let total = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let elapsed = min(max(calendar.dateComponents([.day], from: start, to: date).day ?? 0, 0), total)
        return plannedHours * Double(elapsed + 1) / Double(total + 1)
    }

    /// Done now against the ideal pace for today, in hours (positive: ahead)
    var aheadHours: Double {
        guard let last = days.last else { return 0 }
        return last.doneHours - idealHours(on: today)
    }
}

extension Workspace {
    /// Keeps the sprint's scope log current: one point per day the planned time of the active
    /// sprint changed. Points of earlier sprints go.
    mutating func recordSprintScope(now: Date = Date(), calendar: Calendar = .current) {
        let participating = Set(projects.filter(\.usesSprints).map(\.id))
        let planned = tasks
            .filter { $0.sprintSlot == .active && !$0.isCanceled && participating.contains($0.projectId) }
            .reduce(0) { $0 + $1.expectedMinutes }
        let day = calendar.startOfDay(for: now)
        var log = sprintScope.filter { $0.sprint == sprint.number }
        if let last = log.last {
            guard last.plannedMinutes != planned else {
                if log != sprintScope { sprintScope = log }
                return
            }
            if calendar.isDate(last.day, inSameDayAs: day) {
                log[log.count - 1].plannedMinutes = planned
            } else {
                log.append(SprintScopePoint(sprint: sprint.number, day: day, plannedMinutes: planned))
            }
        } else {
            log.append(SprintScopePoint(sprint: sprint.number, day: day, plannedMinutes: planned))
        }
        sprintScope = log
    }
}
