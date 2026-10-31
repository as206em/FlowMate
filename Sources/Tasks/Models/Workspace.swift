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
    static let currentSchemaVersion = 7

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

    init(
        schemaVersion: Int = Workspace.currentSchemaVersion,
        projects: [Project] = [],
        milestones: [Milestone] = [],
        tasks: [TaskItem] = [],
        runningTimers: [UUID: Date] = [:],
        timeEntries: [TimeEntry] = [],
        preferences: WorkspacePreferences = WorkspacePreferences()
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.milestones = milestones
        self.tasks = tasks
        self.runningTimers = runningTimers
        self.timeEntries = timeEntries
        self.preferences = preferences
    }

    static let empty = Workspace()

    /// Upgrades older stored data to the current schema and drops dangling references.
    func migrated(now: Date = Date()) -> Workspace {
        var ws = self
        if ws.schemaVersion < 2 {
            // The new fields decode to their defaults (no description, not archived, 2-week sprints,
            // no history). Version 1 sprints were always two weeks long; keep that explicitly.
            for i in ws.projects.indices { ws.projects[i].sprint.lengthWeeks = SprintState.defaultLengthWeeks }
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
        ws.normalizeStatuses()
        ws.normalizeCompletion()
        ws.reconcileTrackedTime(now: now)
        return ws
    }

    // Running timers are stored as {"<uuid>": "<date>"} so the JSON stays readable.
    private enum CodingKeys: String, CodingKey { case schemaVersion, projects, milestones, tasks, runningTimers, timeEntries, preferences }

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
    }
}

/// Settings stored with the workspace. Every field is optional on disk.
struct WorkspacePreferences: Codable, Equatable, Sendable {
    /// "Still working on X?" choices, in minutes (0 = never ask)
    static let longRunChoices = [0, 60, 120, 180, 240, 360]
    static let defaultLongRunMinutes = 180

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

    init(lastProjectId: UUID? = nil, showsMenuBarClock: Bool = false,
         longRunPromptMinutes: Int = WorkspacePreferences.defaultLongRunMinutes,
         sampleProjectIds: [UUID] = [], longRunKeptAt: [UUID: Date] = [:]) {
        self.lastProjectId = lastProjectId
        self.showsMenuBarClock = showsMenuBarClock
        self.longRunPromptMinutes = max(0, longRunPromptMinutes)
        self.sampleProjectIds = sampleProjectIds
        self.longRunKeptAt = longRunKeptAt
    }

    private enum CodingKeys: String, CodingKey {
        case lastProjectId, showsMenuBarClock, longRunPromptMinutes, sampleProjectIds, longRunKeptAt
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(lastProjectId, forKey: .lastProjectId)
        try c.encode(showsMenuBarClock, forKey: .showsMenuBarClock)
        try c.encode(longRunPromptMinutes, forKey: .longRunPromptMinutes)
        try c.encode(sampleProjectIds, forKey: .sampleProjectIds)
        let kept = Dictionary(longRunKeptAt.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { a, _ in a })
        try c.encode(kept, forKey: .longRunKeptAt)
    }

    private struct LossyDate: Decodable {
        let date: Date?
        init(from decoder: Decoder) throws {
            // Through a container, so the decoder's date strategy (ISO 8601) applies
            date = try? decoder.singleValueContainer().decode(Date.self)
        }
    }
}
