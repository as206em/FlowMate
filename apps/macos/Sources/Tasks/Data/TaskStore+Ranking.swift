import Foundation

// Task types, the sprint's Make / Reach mix, and Next best: one ranked list of what to pick next
// across every project.
//
// Types: workspace-wide kinds of task (Build, Customers, Sales, Marketing, Ops by default), each in
// a bucket (Make or Reach) with an impact. A task has at most one; a project can give new tasks one.
//
// Mix: the expected time of a sprint slot's typed tasks per bucket, against the sprint's Reach
// target ("Make 14h · Reach 3h, target 50% Reach"). A bucket more than 10 points behind its share
// is "behind": the header turns amber and Next best gives that bucket's tasks +5.
//
// Score, 0–100: impact × 10 × effort factor, + its priority's points, + 5 when the task's bucket is
// behind, + its nudge.
//   impact  the task's own, else its project's (5 when none), averaged with
//           its type's impact when it has a type
//   effort  of the time left (expected − tracked): 1.0 up to 30m, 0.9 up to 1h, 0.8 up to 2h,
//           0.7 up to 4h, 0.6 beyond
//   priority High +20, Medium 0, Low −20: how urgent you said it is, on top of how valuable it is
//           (impact). One priority step weighs about two impact steps, so a High task of impact 5
//           ties a Medium task of impact 7, and a Medium one of impact 5 beats a Low one of impact 6.
//   nudge   Send up / Send down: the nth press in a row moves 5, 10, then 15 points; the other
//           direction takes back the last step. Send to top pins the task above every score for
//           the day. Back to normal clears both. Closing the task or the sprint clears them too.
//
// Candidates are the open current work of active projects (the active sprint, or every open task
// of a project without sprints), leaving out what Today already shows (running, overdue, due today,
// pinned to Today). Keep warm: a project untouched for longer than its cadence (from its impact:
// daily at 9–10, every 3 days at 6–8, weekly at 3–5, every two weeks at 1–2) gets its best small
// task listed under the ranking even when it doesn't rank, at most two a day.

/// The pure rules behind the score and the cadence, so they can be tested without a store.
enum ImpactRules {
    /// Points a bucket that is behind the mix target adds
    static let behindBoost = 5
    /// A bucket this many points under its share is behind
    static let behindMargin = 10
    /// Steps of a run of Send up / Send down presses
    static let nudgeSteps = [5, 10, 15]
    /// Keep warm rows at most
    static let keepWarmLimit = 2
    /// A Keep warm task should be small: this many minutes left or fewer when the project has one
    static let keepWarmMinutes = 30

    /// Points a priority adds to the score: High +20, Medium 0, Low −20.
    static func priorityPoints(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 20
        case .medium: return 0
        case .low: return -20
        }
    }

    /// The effort factor for `minutes` of work left.
    static func effortFactor(minutesLeft minutes: Int) -> Double {
        switch minutes {
        case ...30: return 1.0
        case ...60: return 0.9
        case ...120: return 0.8
        case ...240: return 0.7
        default: return 0.6
        }
    }

    /// The inherited impact averaged with the type's (rounded half up), or the inherited one alone.
    static func impact(inherited: Int, typeImpact: Int?) -> Int {
        guard let typeImpact else { return ImpactScale.clamped(inherited) }
        return ImpactScale.clamped(Int((Double(inherited + typeImpact) / 2).rounded(.toNearestOrAwayFromZero)))
    }

    /// impact × 10 × effort, rounded.
    static func base(impact: Int, minutesLeft: Int) -> Int {
        Int((Double(ImpactScale.clamped(impact) * 10) * effortFactor(minutesLeft: minutesLeft)).rounded())
    }

    static func score(base: Int, priority: Int = 0, boost: Int, nudge: Int) -> Int {
        min(100, max(0, base + priority + boost + nudge))
    }

    /// The size of the nth press in a row (1-based): 5, 10, then 15 for every press after.
    static func step(_ press: Int) -> Int { nudgeSteps[min(max(press, 1), nudgeSteps.count) - 1] }

    /// Applies one press: `up` true for Send up. Returns the new nudge and run. Pressing against a
    /// run takes back that run's last step; pressing with it (or from nothing) adds the next step.
    static func press(up: Bool, nudge: Int, run: Int) -> (nudge: Int, run: Int) {
        let direction = up ? 1 : -1
        if run * direction < 0 {
            // Against the run: undo its last step
            let last = step(abs(run))
            return (nudge + direction * last, run + direction)
        }
        let next = abs(run) + 1
        return (max(-100, min(100, nudge + direction * step(next))), run + direction)
    }

    /// Days a project may go untouched before Keep warm lists it, by its impact.
    static func cadenceDays(impact: Int) -> Int {
        switch impact {
        case 9...: return 1
        case 6...8: return 3
        case 3...5: return 7
        default: return 14
        }
    }
}

/// The planned time of a sprint slot per bucket, against the target.
struct SprintMix: Equatable, Sendable {
    let makeMinutes: Int
    let reachMinutes: Int
    /// Tasks without a type (not part of the mix)
    let untypedMinutes: Int
    /// Reach share the sprint aims for, in %; nil without a target
    let targetPercent: Int?

    var typedMinutes: Int { makeMinutes + reachMinutes }
    var hasTypedWork: Bool { typedMinutes > 0 }

    /// Reach's share of the typed time, 0–100; nil with nothing typed.
    var reachPercent: Int? {
        guard typedMinutes > 0 else { return nil }
        return Int((Double(reachMinutes) / Double(typedMinutes) * 100).rounded())
    }

    /// The bucket more than `ImpactRules.behindMargin` points under its share of the target, if any.
    var behind: TypeBucket? {
        guard let target = targetPercent, let reach = reachPercent else { return nil }
        if reach < target - ImpactRules.behindMargin { return .reach }
        if reach > target + ImpactRules.behindMargin { return .make }
        return nil
    }

    /// "Make 14h · Reach 3h"
    var label: String {
        "Make \(Focus.durationString(minutes: makeMinutes)) · Reach \(Focus.durationString(minutes: reachMinutes))"
    }

    /// "Reach 18% · target 50%", "Reach 18%", or nil with nothing typed
    var shareLabel: String? {
        guard let reach = reachPercent else { return nil }
        return targetPercent.map { "Reach \(reach)% · target \($0)%" } ?? "Reach \(reach)%"
    }

    /// The warning, when a bucket is behind: "Reach is light", "Make is light"
    var warning: String? { behind.map { "\($0.title) is light" } }
}

/// Why a task scores what it does, for the row's explanation.
struct NextBestScore: Equatable, Sendable {
    let impact: Int
    /// Where the impact came from: "task", "project" (and the type, when averaged)
    let impactSource: String
    let typeName: String?
    let minutesLeft: Int
    let base: Int
    /// The task's priority and the points it adds (High +20, Medium 0, Low −20)
    var priority: TaskPriority = .medium
    var priorityPoints: Int = 0
    /// Points for the bucket being behind the mix target
    let boost: Int
    let nudge: Int
    let score: Int
    let pinnedTop: Bool

    /// "Impact 8 (project + Sales) · 30m left · high priority +20 · behind on mix +5 · sent up +15"
    var reason: String {
        var parts = ["Impact \(impact) (\(impactSource))", "\(Focus.durationString(minutes: minutesLeft)) left"]
        if priorityPoints != 0 { parts.append("\(priority.title.lowercased()) priority \(priorityPoints > 0 ? "+" : "")\(priorityPoints)") }
        if boost > 0 { parts.append("behind on mix +\(boost)") }
        if nudge != 0 { parts.append(nudge > 0 ? "sent up +\(nudge)" : "sent down \(nudge)") }
        if pinnedTop { parts.insert("Sent to top", at: 0) }
        return parts.joined(separator: " · ")
    }
}

/// One row of Next best.
struct NextBestItem: Identifiable, Equatable, Sendable {
    let task: TaskItem
    let score: NextBestScore
    /// Listed by Keep warm: "Untouched 6 days · every 3 days"
    let keepWarm: String?

    var id: UUID { task.id }
}

struct NextBestList: Equatable, Sendable {
    /// Ranked: pinned to top first (newest pin first), then by score
    let ranked: [NextBestItem]
    /// Projects past their cadence, each with its best small task (not among `ranked`'s first `shown`)
    let keepWarm: [NextBestItem]
}

// MARK: - Types

extension TaskStore {
    var taskTypes: [TaskType] { workspace.taskTypes }

    func taskType(_ id: UUID?) -> TaskType? {
        guard let id else { return nil }
        return workspace.taskTypes.first { $0.id == id }
    }

    func taskType(of task: TaskItem) -> TaskType? { taskType(task.typeId) }

    /// How many tasks have each type (archived projects included).
    func typeUsage() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for task in workspace.tasks { if let id = task.typeId { counts[id, default: 0] += 1 } }
        return counts
    }

    /// The type a `^name` word means: the same name ignoring case, spaces and punctuation, else the
    /// one type whose name starts with it.
    func matchTaskType(_ query: String) -> TaskType? {
        let q = Self.matchKey(query)
        guard !q.isEmpty else { return nil }
        if let exact = taskTypes.first(where: { Self.matchKey($0.name) == q }) { return exact }
        let prefixed = taskTypes.filter { Self.matchKey($0.name).hasPrefix(q) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    /// Adds a type. A blank name, or one that exists (ignoring case), returns nil.
    @discardableResult
    func addTaskType(_ name: String, bucket: TypeBucket = .make, impact: Int = ImpactScale.neutral) -> UUID? {
        let name = TaskType.cleanName(name)
        guard !name.isEmpty, !workspace.taskTypes.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
        let type = TaskType(name: name, bucket: bucket, impact: impact,
                            colorHex: TaskLabel.nextColor(used: workspace.taskTypes.map(\.colorHex)))
        mutate("Add type") { $0.taskTypes.append(type) }
        return type.id
    }

    /// Renames a type; a blank name or one another type has is refused.
    @discardableResult
    func renameTaskType(_ id: UUID, to name: String) -> Bool {
        let name = TaskType.cleanName(name)
        guard !name.isEmpty, taskType(id) != nil,
              !workspace.taskTypes.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) else { return false }
        changeType(id, "Rename type") { $0.name = name }
        return true
    }

    func setTypeBucket(_ id: UUID, _ bucket: TypeBucket) { changeType(id, "Change type bucket") { $0.bucket = bucket } }

    func setTypeImpact(_ id: UUID, _ impact: Int) { changeType(id, "Change type impact") { $0.impact = ImpactScale.clamped(impact) } }

    func setTypeColor(_ id: UUID, _ colorHex: UInt32) { changeType(id, "Change type color") { $0.colorHex = colorHex } }

    /// Deletes a type: its tasks become untyped and projects stop giving it. One undo step.
    func deleteTaskType(_ id: UUID) {
        mutate("Delete type") { ws in
            ws.taskTypes.removeAll { $0.id == id }
            // normalizeTypes clears the references
        }
    }

    private func changeType(_ id: UUID, _ action: String, _ change: (inout TaskType) -> Void) {
        mutate(action) { ws in
            guard let i = ws.taskTypes.firstIndex(where: { $0.id == id }) else { return }
            change(&ws.taskTypes[i])
        }
    }

    /// Sets the type of tasks (nil: untyped). One undo step.
    func setType(_ ids: [UUID], _ typeId: UUID?) {
        guard typeId == nil || taskType(typeId) != nil else { return }
        undoGroup("Change type") {
            for id in existing(ids) { updateTask(id, action: "Change type") { $0.typeId = typeId } }
        }
    }

    func setProjectDefaultType(_ projectId: UUID, _ typeId: UUID?) {
        mutate("Change default type") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].defaultTypeId = typeId
        }
    }
}

// MARK: - Impact

extension TaskStore {
    func setProjectImpact(_ projectId: UUID, _ impact: Int?) {
        mutate("Change impact") { ws in
            guard let i = ws.projects.firstIndex(where: { $0.id == projectId }) else { return }
            ws.projects[i].impact = ImpactScale.cleaned(impact)
        }
    }

    /// The task's own impact; nil goes back to inheriting.
    func setTaskImpact(_ ids: [UUID], _ impact: Int?) {
        undoGroup("Change impact") {
            for id in existing(ids) { updateTask(id, action: "Change impact") { $0.impact = ImpactScale.cleaned(impact) } }
        }
    }

    /// The impact a task inherits when it has none of its own: its
    /// project's, else 5. With where it came from.
    func inheritedImpact(_ task: TaskItem) -> (value: Int, source: String) {
        if let value = project(task.projectId)?.impact { return (value, "project") }
        return (ImpactScale.neutral, "default")
    }

    /// The task's impact before its type: its own, else the inherited one.
    func ownOrInheritedImpact(_ task: TaskItem) -> (value: Int, source: String) {
        task.impact.map { ($0, "task") } ?? inheritedImpact(task)
    }
}

// MARK: - Mix

extension TaskStore {
    /// The Make / Reach split of a sprint slot's planned time (canceled tasks left out).
    func sprintMix(scope: TaskScope = .all, slot: SprintSlot = .active, ahead: Int = 1) -> SprintMix {
        let tasks = (slot == .next ? sprintTasks(ahead: ahead, in: scope) : sprintTasks(slot: slot, in: scope)).filter { !$0.isCanceled }
        return mix(of: tasks)
    }

    /// The split of the given tasks' expected time.
    func mix(of tasks: [TaskItem]) -> SprintMix {
        let buckets = Dictionary(taskTypes.map { ($0.id, $0.bucket) }, uniquingKeysWith: { a, _ in a })
        var make = 0, reach = 0, untyped = 0
        for task in tasks {
            switch task.typeId.flatMap({ buckets[$0] }) {
            case .make?: make += task.expectedMinutes
            case .reach?: reach += task.expectedMinutes
            case nil: untyped += task.expectedMinutes
            }
        }
        return SprintMix(makeMinutes: make, reachMinutes: reach, untypedMinutes: untyped, targetPercent: sprint.reachTargetPercent)
    }

    /// The Make / Reach split of the time actually tracked in `range` (this week on Today and the
    /// Overview), against the sprint's Reach target. Untracked or untyped work is left out.
    func trackedMix(in range: DateInterval, now: Date = Date()) -> SprintMix {
        let buckets = Dictionary(taskTypes.map { ($0.id, $0.bucket) }, uniquingKeysWith: { a, _ in a })
        let byTask = trackedSecondsByTask(.all, in: range, now: now)
        var make = 0.0, reach = 0.0, untyped = 0.0
        for (id, seconds) in byTask {
            switch task(id)?.typeId.flatMap({ buckets[$0] }) {
            case .make?: make += seconds
            case .reach?: reach += seconds
            case nil: untyped += seconds
            }
        }
        func minutes(_ s: Double) -> Int { Int((s / 60).rounded()) }
        return SprintMix(makeMinutes: minutes(make), reachMinutes: minutes(reach), untypedMinutes: minutes(untyped),
                         targetPercent: sprint.reachTargetPercent)
    }

    /// The share of typed time meant for Reach work; nil turns the target off.
    func setReachTarget(_ percent: Int?) {
        mutate("Change mix target") { $0.sprint.reachTargetPercent = SprintState.cleanTarget(percent) }
    }
}

// MARK: - Next best

extension TaskStore {
    /// The score of one task (the mix of the active sprint decides the boost).
    func nextBestScore(_ task: TaskItem, behind: TypeBucket? = nil, now: Date = Date(), calendar: Calendar = .current) -> NextBestScore {
        let own = ownOrInheritedImpact(task)
        let type = taskType(of: task)
        let impact = ImpactRules.impact(inherited: own.value, typeImpact: type?.impact)
        let left = max(0, task.expectedMinutes - Int(elapsed(task, now: now) / 60))
        let base = ImpactRules.base(impact: impact, minutesLeft: left)
        let boost = type != nil && type?.bucket == behind ? ImpactRules.behindBoost : 0
        let priority = ImpactRules.priorityPoints(task.priority)
        return NextBestScore(
            impact: impact,
            impactSource: type.map { "\(own.source) + \($0.name)" } ?? own.source,
            typeName: type?.name,
            minutesLeft: left,
            base: base,
            priority: task.priority,
            priorityPoints: priority,
            boost: boost,
            nudge: task.nudge,
            score: ImpactRules.score(base: base, priority: priority, boost: boost, nudge: task.nudge),
            pinnedTop: isPinnedTop(task, now: now, calendar: calendar)
        )
    }

    /// Sent to the top today (a pin from an earlier day has expired).
    func isPinnedTop(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let day = task.topPinnedAt else { return false }
        return calendar.isDate(day, inSameDayAs: now)
    }

    /// Tasks Next best can rank: open current work of active projects, minus what Today lists.
    func nextBestCandidates(now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let active = Set(projects.map(\.id))
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let running = Set(workspace.runningTimers.keys)
        return workspace.tasks.filter { task in
            guard active.contains(task.projectId), !task.isClosed, isCurrentWork(task) else { return false }
            if running.contains(task.id) || task.isPinned { return false }
            if let due = task.dueDate, due < tomorrow { return false }
            return true
        }
    }

    /// The ranked list and the Keep warm rows. `shown` is how many ranked rows are on screen, so
    /// Keep warm skips projects already visible.
    func nextBest(shown: Int = 5, now: Date = Date(), calendar: Calendar = .current) -> NextBestList {
        let behind = sprintMix().behind
        let candidates = nextBestCandidates(now: now, calendar: calendar)
        let items = candidates.map { NextBestItem(task: $0, score: nextBestScore($0, behind: behind, now: now, calendar: calendar), keepWarm: nil) }
        let ranked = items.sorted { a, b in
            if a.score.pinnedTop != b.score.pinnedTop { return a.score.pinnedTop }
            if a.score.pinnedTop, let x = a.task.topPinnedAt, let y = b.task.topPinnedAt, x != y { return x > y }
            if a.score.score != b.score.score { return a.score.score > b.score.score }
            if a.task.priority.rank != b.task.priority.rank { return a.task.priority.rank > b.task.priority.rank }
            switch (a.task.dueDate, b.task.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.task.sortIndex < b.task.sortIndex
            }
        }
        let visible = Set(ranked.prefix(shown).map(\.task.projectId))
        var warm: [(item: NextBestItem, overdue: Double)] = []
        let byProject = Dictionary(grouping: ranked, by: \.task.projectId)
        for project in projects where !visible.contains(project.id) {
            guard let tasks = byProject[project.id], !tasks.isEmpty else { continue }
            let cadence = ImpactRules.cadenceDays(impact: project.impact ?? ImpactScale.neutral)
            let last = calendar.startOfDay(for: lastActivity(projectId: project.id, now: now))
            let days = calendar.dateComponents([.day], from: last, to: calendar.startOfDay(for: now)).day ?? 0
            guard days > cadence else { continue }
            // Its best small task; its best task when none is small
            let pick = tasks.first { $0.score.minutesLeft <= ImpactRules.keepWarmMinutes } ?? tasks[0]
            let note = "\(project.name) untouched \(days) days · every \(cadence == 1 ? "day" : "\(cadence) days")"
            warm.append((NextBestItem(task: pick.task, score: pick.score, keepWarm: note), Double(days) / Double(cadence)))
        }
        let keepWarm = warm.sorted { $0.overdue > $1.overdue }.prefix(ImpactRules.keepWarmLimit).map(\.item)
        return NextBestList(ranked: ranked, keepWarm: Array(keepWarm))
    }

    /// Fill to capacity: moves backlog tasks of `scope` into the active sprint, best score first,
    /// while they fit what's left of the capacity. The mix is rechecked after every pick, so a
    /// light bucket's tasks keep their boost until it catches up. Returns the moved tasks, in pick
    /// order. Nothing moves without a capacity. One undo step.
    @discardableResult
    func fillSprintToCapacity(scope: TaskScope = .all, now: Date = Date(), calendar: Calendar = .current) -> [UUID] {
        let picked = fillPicks(scope: scope, now: now, calendar: calendar)
        guard !picked.isEmpty else { return [] }
        undoGroup("Fill to capacity") { setSprintSlot(picked, .active) }
        return picked
    }

    /// The backlog tasks Fill sprint would move, in pick order, without moving them (the Sprints
    /// view lists them as suggestions). Empty without a capacity or when nothing fits.
    func fillPicks(scope: TaskScope = .all, now: Date = Date(), calendar: Calendar = .current) -> [UUID] {
        guard let capacity = sprintCapacityMinutes(in: scope) else { return [] }
        var planned = slotLoad(scope: scope, slot: .active, now: now).plannedMinutes
        var active = sprintTasks(slot: .active, in: scope).filter { !$0.isCanceled }
        var pool = sprintTasks(slot: .backlog, in: scope).filter { !$0.isClosed && usesSprints($0.projectId) }
        var picked: [UUID] = []
        while planned < capacity {
            let behind = mix(of: active).behind
            let fitting = pool.filter { planned + $0.expectedMinutes <= capacity }
            guard let best = fitting.max(by: { a, b in
                let x = nextBestScore(a, behind: behind, now: now, calendar: calendar)
                let y = nextBestScore(b, behind: behind, now: now, calendar: calendar)
                if x.pinnedTop != y.pinnedTop { return y.pinnedTop }
                if x.score != y.score { return x.score < y.score }
                return a.sortIndex > b.sortIndex
            }) else { break }
            picked.append(best.id)
            planned += best.expectedMinutes
            active.append(best)
            pool.removeAll { $0.id == best.id }
        }
        return picked
    }

    /// Orders a sprint slot's tasks by score, highest first (closed ones keep their place at the
    /// end), reusing their own sort positions. One undo step.
    func sortByScore(scope: TaskScope = .all, slot: SprintSlot, ahead: Int = 1, now: Date = Date()) {
        let tasks = slot == .next ? sprintTasks(ahead: ahead, in: scope) : sprintTasks(slot: slot, in: scope)
        let behind = sprintMix().behind
        let scored = tasks.map { ($0, $0.isClosed ? -1 : nextBestScore($0, behind: behind, now: now).score) }
        let ordered = scored.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.sortIndex < b.0.sortIndex }.map(\.0.id)
        let slots = tasks.map(\.sortIndex).sorted()
        mutate("Sort by score") { ws in
            for (id, index) in zip(ordered, slots) {
                guard let i = ws.tasks.firstIndex(where: { $0.id == id }) else { continue }
                ws.tasks[i].sortIndex = index
            }
        }
    }

    /// Send up (`up`) or Send down: the nth press in a row moves 5, 10, then 15 points.
    func sendNextBest(_ id: UUID, up: Bool) {
        updateTask(id, action: up ? "Send up" : "Send down") { task in
            let result = ImpactRules.press(up: up, nudge: task.nudge, run: task.nudgeRun)
            task.nudge = result.nudge
            task.nudgeRun = result.run
        }
    }

    /// Puts the task first in Next best for today.
    func sendToTop(_ id: UUID, now: Date = Date(), calendar: Calendar = .current) {
        updateTask(id, now: now, action: "Send to top") { $0.topPinnedAt = calendar.startOfDay(for: now) }
    }

    /// Back to normal: no nudge and no pin, the computed score again.
    func resetNextBest(_ id: UUID) {
        updateTask(id, action: "Back to normal") { task in
            task.nudge = 0
            task.nudgeRun = 0
            task.topPinnedAt = nil
        }
    }
}
