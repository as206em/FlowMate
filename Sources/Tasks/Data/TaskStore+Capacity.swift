import Foundation

// Sprint capacity and velocity, projects without sprints, and the per-project settings
// (capacity, sprints on or off, default view, defaults for new tasks, icon).
//
// The sprint is one for the whole workspace (Workspace.sprint); projects take part in it.
// Capacity: the weekly hours of the projects in view, added up × the sprint's weeks, is what one
// sprint can hold. The Sprints view compares each slot's expected time with it ("11h of 20h"),
// amber from 90% and red past 100%. Velocity: the expected time of the tasks done in a sprint, kept on each PastSprint;
// "recent velocity" is the average of the last three sprints.
//
// Without sprints (Project.usesSprints off) a project's tasks keep their slot but nothing shows
// it: every open task is current work (Board, Up next, the menu bar, the play button, Overview).
// New tasks go to the active slot. Turning sprints back on puts the work in flight (started,
// running or pinned to Today) in the active sprint and the other open tasks in the backlog to be
// planned; done and canceled tasks stay where they are.

/// How a sprint's plan compares with its capacity.
enum CapacityLevel: Equatable, Sendable {
    /// Below 90%, or no capacity set
    case under
    /// 90% to 100%
    case near
    /// Above 100%
    case over
}

/// One slot of the Sprints view in numbers.
struct SprintSlotLoad: Equatable, Sendable {
    /// Tasks in the slot (canceled ones left out)
    let count: Int
    /// Their expected minutes
    let plannedMinutes: Int
    /// What one sprint can hold, in minutes (weekly capacity × weeks); nil without a capacity.
    /// Always nil for the backlog.
    let capacityMinutes: Int?
    /// Active only: Σ over open tasks of max(0, expected − tracked), in minutes
    let remainingMinutes: Int?

    var level: CapacityLevel { SprintPlanRules.level(plannedMinutes: plannedMinutes, capacityMinutes: capacityMinutes) }

    /// "7 tasks · 11h", "7 tasks · 11h of 20h", "7 tasks · 11h of 20h · 5h left"
    var label: String {
        var parts = [count == 1 ? "1 task" : "\(count) tasks"]
        let planned = Focus.durationString(minutes: plannedMinutes)
        parts.append(capacityMinutes.map { "\(planned) of \(Focus.durationString(minutes: $0))" } ?? planned)
        if let remainingMinutes, count > 0 { parts.append("\(Focus.durationString(minutes: remainingMinutes)) left") }
        return parts.joined(separator: " · ")
    }
}

/// A past sprint's bar in the velocity chart.
struct VelocityPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let number: Int
    let doneHours: Double
    let plannedHours: Double
    let capacityHours: Double?
    let isApproximate: Bool

    /// "S14", the chart's axis label
    var shortName: String { "S\(number)" }
}

enum SprintPlanRules {
    /// The plan turns amber from this share of the capacity.
    static let nearShare = 0.9
    /// How many recent sprints "recent velocity" averages.
    static let velocityWindow = 3
    /// How many past sprints the velocity chart shows.
    static let chartWindow = 6

    static func level(plannedMinutes: Int, capacityMinutes: Int?) -> CapacityLevel {
        guard let capacity = capacityMinutes, capacity > 0 else { return .under }
        if plannedMinutes > capacity { return .over }
        if Double(plannedMinutes) >= Double(capacity) * nearShare { return .near }
        return .under
    }

    /// Average done minutes of the last `velocityWindow` sprints (oldest first in `doneMinutes`);
    /// nil without any.
    static func velocity(doneMinutes: [Int]) -> Int? {
        let recent = doneMinutes.suffix(velocityWindow)
        guard !recent.isEmpty else { return nil }
        return Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
    }

    /// Minutes of a whole sprint at `weeklyHours`.
    static func capacityMinutes(weeklyHours: Double?, weeks: Int) -> Int? {
        guard let weeklyHours, weeklyHours > 0 else { return nil }
        return Int((weeklyHours * Double(weeks) * 60).rounded())
    }

    /// "20h", "7.5h"
    static func hoursText(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }
}

// MARK: - Queries

extension TaskStore {
    /// The project is planned in sprints (unknown projects count as yes).
    func usesSprints(_ projectId: UUID) -> Bool { project(projectId)?.usesSprints ?? true }

    /// A task that is current work: in the active sprint, or for a project without sprints any task
    /// not closed with a past sprint.
    func isCurrentWork(_ task: TaskItem) -> Bool {
        usesSprints(task.projectId) ? task.sprintSlot == .active : task.sprintSlot != .closed
    }

    /// What one sprint can hold, in minutes, for the projects in `scope`: their weekly capacities
    /// added up × the sprint's weeks. Projects without a capacity or outside sprints add nothing;
    /// nil when none has one.
    func sprintCapacityMinutes(in scope: TaskScope = .all) -> Int? {
        let hours = sprintProjects(in: scope).compactMap(\.weeklyCapacityHours).reduce(0, +)
        return SprintPlanRules.capacityMinutes(weeklyHours: hours, weeks: sprint.lengthWeeks)
    }

    /// The projects in `scope` that take part in sprints (archived ones only when asked for).
    private func sprintProjects(in scope: TaskScope) -> [Project] {
        if let id = scope.projectId { return allProjects.filter { $0.id == id && $0.usesSprints } }
        return projects.filter(\.usesSprints)
    }

    /// The numbers of one Sprints view slot (live: the store changes as tasks are dragged).
    func slotLoad(scope: TaskScope = .all, slot: SprintSlot, ahead: Int = 1, now: Date = Date()) -> SprintSlotLoad {
        let sprintTasks = slot == .next ? sprintTasks(ahead: ahead, in: scope) : sprintTasks(slot: slot, in: scope)
        let tasks = sprintTasks.filter { !$0.isCanceled }
        let planned = tasks.reduce(0) { $0 + $1.expectedMinutes }
        let capacity = slot == .backlog ? nil : sprintCapacityMinutes(in: scope)
        var remaining: Int?
        if slot == .active {
            let open = tasks.filter { !$0.isClosed }
            remaining = Int((PortfolioRules.remainingHours(open.map { ($0.expectedMinutes, elapsed($0, now: now), false) }) * 60).rounded())
        }
        return SprintSlotLoad(count: tasks.count, plannedMinutes: planned, capacityMinutes: capacity, remainingMinutes: remaining)
    }

    /// The Board's sprint line: "Planned 11h of 20h · tracked 6h" (no "of" without a capacity).
    func sprintPlanLine(scope: TaskScope = .all, now: Date = Date()) -> (text: String, level: CapacityLevel) {
        let load = slotLoad(scope: scope, slot: .active, now: now)
        let planned = Focus.durationString(minutes: load.plannedMinutes)
        let tracked = Int((trackedInSprint(projectId: scope.projectId, now: now) / 60).rounded())
        let plan = load.capacityMinutes.map { "Planned \(planned) of \(Focus.durationString(minutes: $0))" } ?? "Planned \(planned)"
        return ("\(plan) · tracked \(Focus.durationString(minutes: tracked))", load.level)
    }

    /// The last `limit` past sprints as chart points, oldest first.
    func velocityHistory(limit: Int = SprintPlanRules.chartWindow) -> [VelocityPoint] {
        workspace.pastSprints.suffix(limit).map {
            VelocityPoint(id: $0.id, number: $0.number, doneHours: Double($0.doneMinutes) / 60,
                          plannedHours: Double($0.plannedMinutes) / 60, capacityHours: $0.capacityHours,
                          isApproximate: $0.isApproximate)
        }
    }

    /// Average done minutes of the recent sprints. `includingActive` counts the active sprint's
    /// done tasks as the newest sprint (the Complete sprint dialog, before it closes).
    func recentVelocityMinutes(includingActive: Bool = false) -> Int? {
        var done = workspace.pastSprints.map(\.doneMinutes)
        if includingActive {
            done.append(sprintTasks(slot: .active).filter(\.isDone).reduce(0) { $0 + $1.expectedMinutes })
        }
        return SprintPlanRules.velocity(doneMinutes: done)
    }

    /// Expected minutes the next sprint starts with once the active one completes: what's in Next,
    /// plus the unfinished active tasks when they carry over.
    func nextSprintPlanMinutes(unfinished: UnfinishedSprintTasks) -> Int {
        let next = sprintTasks(slot: .next).filter { !$0.isCanceled }
        var minutes = next.reduce(0) { $0 + $1.expectedMinutes }
        if unfinished == .moveToNextSprint {
            minutes += sprintTasks(slot: .active).filter { !$0.isClosed }.reduce(0) { $0 + $1.expectedMinutes }
        }
        return minutes
    }

    /// The numbers stored on a sprint as it completes: planned and done expected time of its
    /// tasks, the time tracked inside its dates, and the capacity for its length.
    func completionStats(now: Date = Date(), calendar: Calendar = .current)
        -> (planned: Int, done: Int, tracked: TimeInterval, capacity: Double?) {
        let active = sprintTasks(slot: .active)
        let planned = active.filter { !$0.isCanceled }.reduce(0) { $0 + $1.expectedMinutes }
        let done = active.filter(\.isDone).reduce(0) { $0 + $1.expectedMinutes }
        let sprint = self.sprint
        let end = max(sprint.startDate, calendar.startOfDay(for: now))
        let tracked = trackedSeconds(.all, in: Self.days(sprint.startDate, through: end, calendar: calendar), now: now)
        let weekly = sprintProjects(in: .all).compactMap(\.weeklyCapacityHours).reduce(0, +)
        return (planned, done, tracked, weekly > 0 ? weekly * Double(sprint.lengthWeeks) : nil)
    }
}

// MARK: - Settings

extension TaskStore {
    /// "Hours per week on this project"; nil or 0 clears it.
    func setWeeklyCapacity(_ projectId: UUID, hours: Double?) {
        mutate("Change capacity", coalesce: "capacity-\(projectId)") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].weeklyCapacityHours = Project.cleanCapacity(hours)
        }
    }

    /// Takes the project out of the sprint or back in. Off changes no task. On puts the work in
    /// flight active (a Started status, a running timer or pinned to Today) and every other open
    /// task in the backlog; done and canceled tasks stay. One undo step.
    func setUsesSprints(_ projectId: UUID, _ on: Bool, now: Date = Date()) {
        guard let project = project(projectId), project.usesSprints != on else { return }
        let running = Set(workspace.runningTimers.keys)
        mutate(on ? "Turn on sprints" : "Turn off sprints") { ws in
            guard let p = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[p].usesSprints = on
            guard on else { return }
            for i in ws.tasks.indices where ws.tasks[i].projectId == projectId {
                let task = ws.tasks[i]
                guard task.sprintSlot != .closed, !task.isClosed else { continue }
                let inFlight = task.statusCategory == .started || running.contains(task.id) || task.focusDate != nil
                let slot: SprintSlot = inFlight ? .active : .backlog
                if task.sprintSlot != slot {
                    ws.tasks[i].sprintSlot = slot
                    ws.tasks[i].updatedAt = now
                }
            }
        }
    }

    func setDefaultView(_ projectId: UUID, _ view: ProjectView?) {
        mutate("Change default view") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].defaultView = view
        }
    }

    /// Expected time new tasks of the project start with; nil goes back to 1h.
    func setDefaultExpectedMinutes(_ projectId: UUID, _ minutes: Int?) {
        mutate("Change default expected time") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].defaultExpectedMinutes = Project.cleanExpected(minutes)
        }
    }

    /// The sprint new tasks go to when nothing else picks one.
    func setDefaultSprintSlot(_ projectId: UUID, _ slot: SprintSlot) {
        mutate("Change default sprint") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].defaultSprintSlot = Project.cleanSlot(slot)
        }
    }

    /// An emoji or SF Symbol in place of the letter tile; nil brings the letter back.
    func setProjectIcon(_ projectId: UUID, _ icon: ProjectIcon?) {
        mutate("Change icon") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].icon = icon
        }
    }
}
