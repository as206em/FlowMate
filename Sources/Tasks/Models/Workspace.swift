import Foundation

/// Everything the task feature stores, saved and loaded as one value by a WorkspaceRepository.
struct Workspace: Codable, Equatable, Sendable {
    /// Bump when the stored shape changes, and add a step to `migrated()`.
    /// 2: project description, target date, archive and past sprints; sprint length; milestone
    ///    description and completion; the sprint number on closed tasks.
    /// 3: preferences (last project used for new tasks, menu bar clock, the long-run prompt).
    /// 4: which projects are first-launch sample data (preferences.sampleProjectIds).
    /// 5: when you last answered Keep to "Still working on X?" (preferences.longRunKeptAt), so the
    ///    answer survives a relaunch.
    /// 6: statuses per project (Project.statuses, a custom workflow). Tasks store a status id and
    ///    its category instead of the fixed To do / In progress / Done; older files get the Simple
    ///    workflow, whose ids match the old values.
    /// 7: a time log (timeEntries: timer sessions, time added by hand) and TaskItem.completedAt.
    ///    Time tracked before becomes one `imported` entry per task, so totals don't change; tasks
    ///    already done or canceled get their last update as completion date.
    /// 8: a color per milestone (Milestone.colorHex). Older milestones get one by walking the
    ///    palette within each project, skipping the project's own color.
    /// 9: tasks pinned to Today (TaskItem.focusDate, focusIndex). Older tasks decode as not pinned.
    /// 10: sprint capacity and per-project settings (Project.weeklyCapacityHours, usesSprints,
    ///     defaultView, defaultExpectedMinutes, defaultSprintSlot, icon), and numbers on each past
    ///     sprint (planned, done and tracked time, capacity). Older projects decode with sprints on
    ///     and no settings; older past sprints get their numbers worked out from the tasks and the
    ///     time log as they are now, marked approximate (addPastSprintStats).
    /// 11: labels (Workspace.labels, TaskItem.labelIds) and saved views (Workspace.savedViews).
    ///     Older files decode with none of either; nothing to convert.
    /// 12: the waiting "Timers ran while your Mac slept" prompt (preferences.pendingAway), so it
    ///     survives a relaunch. Older files decode with none.
    /// 13 also holds the sprints planned ahead (Workspace.upcomingCount, upcomingGoals,
    ///     TaskItem.laterSprint); older files decode with just the next one.
    /// 13: one sprint for the whole workspace (Workspace.sprint, Workspace.pastSprints) instead of
    ///     one per project. The sprint with the highest number becomes the workspace's; every
    ///     project's past sprints are kept, oldest first. Tasks keep their slot.
    static let currentSchemaVersion = 13

    var schemaVersion: Int
    var projects: [Project]
    var milestones: [Milestone]
    var tasks: [TaskItem]
    /// Task id -> when its current timer session started. Several can run at once.
    var runningTimers: [UUID: Date]
    /// Every stretch of time tracked, of any task (see TimeEntry). Task.spentSeconds is their sum.
    var timeEntries: [TimeEntry]
    /// Small settings that travel with the data (the last project used, timer prompts).
    var preferences: WorkspacePreferences
    /// The active sprint. Every project that takes part (Project.usesSprints) shares it, so a sprint
    /// holds tasks of several projects.
    var sprint: SprintState
    /// Completed sprints, oldest first
    var pastSprints: [PastSprint]
    /// How many sprints are planned after the active one (at least 1: the next). Sprint N+k exists
    /// for k in 1...upcomingCount; tasks go into them with TaskItem.sprintSlot `next` and `laterSprint`.
    var upcomingCount: Int
    /// The active sprint's planned time over its days (see SprintScopePoint)
    var sprintScope: [SprintScopePoint]
    /// Goals of the upcoming sprints, by sprint number
    var upcomingGoals: [Int: String]
    /// Labels every project shares, in the order they were made (shown sorted by name)
    var labels: [TaskLabel]
    /// The sidebar's Views, in sidebar order
    var savedViews: [SavedView]

    init(
        schemaVersion: Int = Workspace.currentSchemaVersion,
        projects: [Project] = [],
        milestones: [Milestone] = [],
        tasks: [TaskItem] = [],
        runningTimers: [UUID: Date] = [:],
        timeEntries: [TimeEntry] = [],
        preferences: WorkspacePreferences = WorkspacePreferences(),
        sprint: SprintState = SprintState(startDate: SprintState.defaultStart()),
        pastSprints: [PastSprint] = [],
        upcomingCount: Int = 1,
        sprintScope: [SprintScopePoint] = [],
        upcomingGoals: [Int: String] = [:],
        labels: [TaskLabel] = [],
        savedViews: [SavedView] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.milestones = milestones
        self.tasks = tasks
        self.runningTimers = runningTimers
        self.timeEntries = timeEntries
        self.preferences = preferences
        self.sprint = sprint
        self.pastSprints = pastSprints
        self.upcomingCount = max(1, upcomingCount)
        self.sprintScope = sprintScope
        self.upcomingGoals = upcomingGoals
        self.labels = labels
        self.savedViews = savedViews
    }

    static let empty = Workspace()

    /// Upgrades older stored data to the current schema and drops dangling references.
    func migrated(now: Date = Date()) -> Workspace {
        var ws = self
        if ws.schemaVersion < 2 {
            // The new fields decode to their defaults (no description, not archived, 2-week sprints,
            // no history). Version 1 sprints were always two weeks long; keep that explicitly.
            for i in ws.projects.indices { ws.projects[i].legacySprint?.lengthWeeks = SprintState.defaultLengthWeeks }
        }
        // 3: preferences decode to their defaults (no last project, no menu bar clock, ask after 3h).
        if let last = ws.preferences.lastProjectId, !ws.projects.contains(where: { $0.id == last }) {
            ws.preferences.lastProjectId = nil
        }
        // 4: older files have no sample marker (decodes to none), so no "sample data" banner shows for them.
        ws.preferences.sampleProjectIds.removeAll { id in !ws.projects.contains(where: { $0.id == id }) }
        // 5: older files have no Keep answers (decodes to none). Answers only matter while that timer runs.
        ws.preferences.longRunKeptAt = ws.preferences.longRunKeptAt.filter { ws.runningTimers[$0.key] != nil }
        // 6: projects decode the Simple workflow and tasks their old status under the same id.
        // 7: no time entries yet: reconcileTrackedTime (below) turns each task's total into one
        //    imported entry; normalizeCompletion dates closed tasks by their last update.
        // 8: milestones decode without a color; assignMilestoneColors (below) gives each one.
        // 9: tasks decode with no focusDate (not pinned to Today); nothing to convert.
        // 10: past sprints get their numbers after the time log is reconciled (below).
        // 11: no labels or saved views yet (they decode as none); normalizeLabels drops dangling ids.
        // 12: no waiting sleep prompt (decodes to none). Below: prompts keep only tasks that exist.
        // 13: the per-project sprints become the workspace's (liftSprints, below).
        let addStats = ws.schemaVersion < 10
        let liftSprints = ws.schemaVersion < 13
        ws.schemaVersion = Workspace.currentSchemaVersion

        let projectIds = Set(ws.projects.map(\.id))
        ws.milestones.removeAll { !projectIds.contains($0.projectId) }
        ws.tasks.removeAll { !projectIds.contains($0.projectId) }
        let milestoneProject = Dictionary(ws.milestones.map { ($0.id, $0.projectId) }, uniquingKeysWith: { a, _ in a })
        for i in ws.tasks.indices {
            if let mid = ws.tasks[i].milestoneId, milestoneProject[mid] != ws.tasks[i].projectId {
                ws.tasks[i].milestoneId = nil
            }
        }
        let taskIds = Set(ws.tasks.map(\.id))
        ws.runningTimers = ws.runningTimers.filter { taskIds.contains($0.key) }
        ws.preferences.longRunKeptAt = ws.preferences.longRunKeptAt.filter { ws.runningTimers[$0.key] != nil }
        ws.normalizePreferences()
        ws.normalizeStatuses()
        ws.normalizeCompletion()
        ws.reconcileTrackedTime(now: now)
        ws.assignMilestoneColors()
        ws.normalizeLabels()
        if addStats { ws.addPastSprintStats() }
        if liftSprints { ws.liftProjectSprints() }
        return ws
    }

    /// Preferences only point at things that exist: the last project used, sample projects, Keep
    /// answers of timers still running, and a waiting sleep prompt (only the tasks that still
    /// exist; one left with none goes away).
    mutating func normalizePreferences() {
        if let last = preferences.lastProjectId, !projects.contains(where: { $0.id == last }) {
            preferences.lastProjectId = nil
        }
        if preferences.sampleProjectIds.contains(where: { id in !projects.contains { $0.id == id } }) {
            preferences.sampleProjectIds.removeAll { id in !projects.contains { $0.id == id } }
        }
        if preferences.longRunKeptAt.keys.contains(where: { runningTimers[$0] == nil }) {
            preferences.longRunKeptAt = preferences.longRunKeptAt.filter { runningTimers[$0.key] != nil }
        }
        guard !preferences.pendingAway.isEmpty else { return }
        let taskIds = Set(tasks.map(\.id))
        let gaps = preferences.pendingAway.compactMap { gap -> AwayGap? in
            let ids = gap.taskIds.filter { taskIds.contains($0) }
            return ids.isEmpty || gap.end <= gap.start ? nil
                : AwayGap(id: gap.id, start: gap.start, end: gap.end, kind: gap.kind, taskIds: ids)
        }
        if gaps != preferences.pendingAway { preferences.pendingAway = gaps }
    }

    /// Schema 13: the workspace gets one sprint. The project sprint furthest along (highest number,
    /// the first on a tie; projects without sprints count last) becomes the workspace's sprint, and
    /// every project's past sprints join one history, oldest first.
    mutating func liftProjectSprints() {
        let withSprint = projects.filter { $0.legacySprint != nil }
        let pick = withSprint.filter(\.usesSprints).max(by: { ($0.legacySprint?.number ?? 0) < ($1.legacySprint?.number ?? 0) })
            ?? withSprint.max(by: { ($0.legacySprint?.number ?? 0) < ($1.legacySprint?.number ?? 0) })
        if let sprint = pick?.legacySprint { self.sprint = sprint }
        pastSprints = projects.flatMap(\.legacyPastSprints).sorted { $0.completedAt < $1.completedAt }
        for i in projects.indices {
            projects[i].legacySprint = nil
            projects[i].legacyPastSprints = []
        }
    }

    /// Schema 10: numbers for past sprints closed before they were stored. Planned is the expected
    /// time of the sprint's tasks (canceled ones left out), done that of its done tasks, both as the
    /// tasks are now; tracked is the time log inside the sprint's dates for the project's tasks and
    /// the sprint's own. Capacity is unknown. All marked approximate.
    mutating func addPastSprintStats(calendar: Calendar = .current) {
        let tasksById = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in projects.indices where !projects[p].legacyPastSprints.isEmpty {
            let projectId = projects[p].id
            let projectTasks = Set(tasks.filter { $0.projectId == projectId }.map(\.id))
            for s in projects[p].legacyPastSprints.indices {
                var sprint = projects[p].legacyPastSprints[s]
                let planned = sprint.taskIds.compactMap { tasksById[$0] }.filter { !$0.isCanceled }
                sprint.plannedMinutes = planned.reduce(0) { $0 + $1.expectedMinutes }
                sprint.doneMinutes = sprint.doneTaskIds.compactMap { tasksById[$0] }.reduce(0) { $0 + $1.expectedMinutes }
                let ids = projectTasks.union(sprint.taskIds)
                let range = TaskStore.days(sprint.startDate, through: sprint.endDate, calendar: calendar)
                sprint.trackedSeconds = timeEntries.filter { ids.contains($0.taskId) }
                    .reduce(0) { $0 + TimeEntry.overlap($1.start, $1.end, range) }
                sprint.capacityHours = nil
                sprint.isApproximate = true
                projects[p].legacyPastSprints[s] = sprint
            }
        }
    }

    /// Gives every milestone without a color one: per project, in stored order, the palette color
    /// its milestones use least (never the project's own color while others are free).
    mutating func assignMilestoneColors() {
        guard milestones.contains(where: { $0.colorHex == Milestone.unsetColor }) else { return }
        let projectColors = Dictionary(projects.map { ($0.id, $0.colorHex) }, uniquingKeysWith: { a, _ in a })
        var used: [UUID: [UInt32]] = [:]
        for m in milestones where m.colorHex != Milestone.unsetColor { used[m.projectId, default: []].append(m.colorHex) }
        for i in milestones.indices where milestones[i].colorHex == Milestone.unsetColor {
            let projectId = milestones[i].projectId
            let hex = Milestone.nextColor(projectColor: projectColors[projectId], used: used[projectId] ?? [])
            milestones[i].colorHex = hex
            used[projectId, default: []].append(hex)
        }
    }

    /// Keeps labels and saved views consistent with the rest: one label per name (a duplicate's
    /// tasks move to the first), tasks only carry labels that exist (each once), and saved views
    /// whose project or milestone is gone are dropped. Filters inside views keep only existing labels
    /// and statuses.
    mutating func normalizeLabels() {
        if labels.isEmpty, savedViews.isEmpty, !tasks.contains(where: { !$0.labelIds.isEmpty }) { return }
        // Duplicate ids or names (hand-edited files): the first wins
        var seenIds = Set<UUID>()
        var byName: [String: UUID] = [:]
        var merged: [UUID: UUID] = [:]
        var kept: [TaskLabel] = []
        for label in labels {
            guard seenIds.insert(label.id).inserted else { continue }
            let key = label.name.lowercased()
            if let first = byName[key] {
                merged[label.id] = first
            } else {
                byName[key] = label.id
                kept.append(label)
            }
        }
        if kept != labels { labels = kept }
        let valid = Set(labels.map(\.id))
        for i in tasks.indices where !tasks[i].labelIds.isEmpty {
            var seen = Set<UUID>()
            let ids = tasks[i].labelIds.map { merged[$0] ?? $0 }.filter { valid.contains($0) && seen.insert($0).inserted }
            if ids != tasks[i].labelIds { tasks[i].labelIds = ids }
        }
        guard !savedViews.isEmpty else { return }
        let projectIds = Set(projects.map(\.id))
        let milestoneProjects = Dictionary(milestones.map { ($0.id, $0.projectId) }, uniquingKeysWith: { a, _ in a })
        let statusIds = Set(projects.flatMap { $0.statuses.map(\.id) })
        var viewIds = Set<UUID>()
        let views = savedViews.compactMap { view -> SavedView? in
            guard viewIds.insert(view.id).inserted else { return nil }
            switch view.scope {
            case .today, .all: break
            case let .project(id): if !projectIds.contains(id) { return nil }
            case let .milestone(id, projectId): if milestoneProjects[id] != projectId { return nil }
            }
            var view = view
            let labels = Set(view.options.filter.labels.map { merged[$0] ?? $0 }).intersection(valid)
            if labels != view.options.filter.labels { view.options.filter.labels = labels }
            // A status deleted from every workflow can't match anything: the view forgets it
            let statuses = view.options.filter.statuses.intersection(statusIds)
            if statuses != view.options.filter.statuses { view.options.filter.statuses = statuses }
            return view
        }
        if views != savedViews { savedViews = views }
    }

    // Running timers are stored as {"<uuid>": "<date>"} so the JSON stays readable.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projects, milestones, tasks, runningTimers, timeEntries, preferences, sprint, pastSprints, upcomingCount, sprintScope, upcomingGoals, labels, savedViews
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.decode(.schemaVersion, or: 1)
        projects = c.decodeLossyArray(.projects)
        milestones = c.decodeLossyArray(.milestones)
        tasks = c.decodeLossyArray(.tasks)
        let raw: [String: Date] = c.decode(.runningTimers, or: [:])
        runningTimers = Dictionary(raw.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
                                   uniquingKeysWith: { a, _ in a })
        timeEntries = c.decodeLossyArray(.timeEntries)
        preferences = c.decode(.preferences, or: WorkspacePreferences())
        // Schema 12 and older: the sprint lives on the projects; migrated() lifts it
        sprint = c.decode(.sprint, or: SprintState(startDate: SprintState.defaultStart()))
        pastSprints = c.decodeLossyArray(.pastSprints)
        upcomingCount = max(1, c.decode(.upcomingCount, or: 1))
        sprintScope = c.decodeLossyArray(.sprintScope)
        // Stored as {"<number>": "<goal>"}: JSON keys are strings
        let goals: [String: String] = c.decode(.upcomingGoals, or: [:])
        upcomingGoals = Dictionary(goals.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: { a, _ in a })
        // Schema 10 and older: no labels or views
        labels = c.decodeLossyArray(.labels)
        savedViews = c.decodeLossyArray(.savedViews)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(projects, forKey: .projects)
        try c.encode(milestones, forKey: .milestones)
        try c.encode(tasks, forKey: .tasks)
        let raw = Dictionary(runningTimers.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { a, _ in a })
        try c.encode(raw, forKey: .runningTimers)
        try c.encode(timeEntries, forKey: .timeEntries)
        try c.encode(preferences, forKey: .preferences)
        try c.encode(sprint, forKey: .sprint)
        try c.encode(pastSprints, forKey: .pastSprints)
        try c.encode(upcomingCount, forKey: .upcomingCount)
        try c.encode(sprintScope, forKey: .sprintScope)
        try c.encode(Dictionary(upcomingGoals.map { (String($0.key), $0.value) }, uniquingKeysWith: { a, _ in a }), forKey: .upcomingGoals)
        try c.encode(labels, forKey: .labels)
        try c.encode(savedViews, forKey: .savedViews)
    }
}

/// Settings stored with the workspace. Every field is optional on disk.
struct WorkspacePreferences: Codable, Equatable, Sendable {
    /// "Still working on X?" choices, in minutes (0 = never ask)
    static let longRunChoices = [0, 60, 120, 180, 240, 360]
    static let defaultLongRunMinutes = 180
    /// Minutes without a key press or mouse move before running timers stop (0 = never)
    static let idleStopChoices = [0, 5, 10, 15, 20, 30, 45, 60]
    static let defaultIdleStopMinutes = 15

    /// The project the last task was added to; New task fields in All projects start there.
    var lastProjectId: UUID?
    /// Show the running timer's clock next to the menu bar icon.
    var showsMenuBarClock: Bool
    /// After a timer runs this long without a break, a quiet prompt asks if you're still working (0 = off).
    var longRunPromptMinutes: Int
    /// Projects created as first-launch sample data. While any still exists, a banner offers
    /// "Clear sample data"; Keep empties the list.
    var sampleProjectIds: [UUID]
    /// Running task -> when you last answered Keep to "Still working on it?". The prompt waits a
    /// full interval from then. Entries go away when that timer stops.
    var longRunKeptAt: [UUID: Date]
    /// Sleep or lock stretches timers ran through, waiting for Keep or Discard sleep time.
    var pendingAway: [AwayGap]
    /// Timers stop when there was no key press or mouse move for this many minutes, and the idle
    /// minutes are not counted (0 = off).
    var idleStopMinutes: Int

    init(lastProjectId: UUID? = nil, showsMenuBarClock: Bool = false,
         longRunPromptMinutes: Int = WorkspacePreferences.defaultLongRunMinutes,
         sampleProjectIds: [UUID] = [], longRunKeptAt: [UUID: Date] = [:], pendingAway: [AwayGap] = [],
         idleStopMinutes: Int = WorkspacePreferences.defaultIdleStopMinutes) {
        self.lastProjectId = lastProjectId
        self.showsMenuBarClock = showsMenuBarClock
        self.longRunPromptMinutes = max(0, longRunPromptMinutes)
        self.sampleProjectIds = sampleProjectIds
        self.longRunKeptAt = longRunKeptAt
        self.pendingAway = pendingAway
        self.idleStopMinutes = max(0, idleStopMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case lastProjectId, showsMenuBarClock, longRunPromptMinutes, sampleProjectIds, longRunKeptAt, pendingAway, idleStopMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastProjectId = c.decodeOptional(.lastProjectId)
        showsMenuBarClock = c.decode(.showsMenuBarClock, or: false)
        longRunPromptMinutes = max(0, c.decode(.longRunPromptMinutes, or: WorkspacePreferences.defaultLongRunMinutes))
        sampleProjectIds = c.decodeLossyArray(.sampleProjectIds)
        // Stored as {"<uuid>": "<date>"}; a bad entry is dropped, not the whole file
        let kept: [String: LossyDate] = c.decode(.longRunKeptAt, or: [:])
        longRunKeptAt = Dictionary(kept.compactMap { key, value in
            guard let id = UUID(uuidString: key), let date = value.date else { return nil }
            return (id, date)
        }, uniquingKeysWith: { a, _ in a })
        // Schema 11 and older: no waiting sleep prompt
        pendingAway = c.decodeLossyArray(.pendingAway)
        idleStopMinutes = max(0, c.decode(.idleStopMinutes, or: WorkspacePreferences.defaultIdleStopMinutes))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(lastProjectId, forKey: .lastProjectId)
        try c.encode(showsMenuBarClock, forKey: .showsMenuBarClock)
        try c.encode(longRunPromptMinutes, forKey: .longRunPromptMinutes)
        try c.encode(sampleProjectIds, forKey: .sampleProjectIds)
        let kept = Dictionary(longRunKeptAt.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { a, _ in a })
        try c.encode(kept, forKey: .longRunKeptAt)
        try c.encode(pendingAway, forKey: .pendingAway)
        try c.encode(idleStopMinutes, forKey: .idleStopMinutes)
    }

    private struct LossyDate: Decodable {
        let date: Date?
        init(from decoder: Decoder) throws {
            // Through a container, so the decoder's date strategy (ISO 8601) applies
            date = try? decoder.singleValueContainer().decode(Date.self)
        }
    }
}
