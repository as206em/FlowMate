import Foundation

/// The active sprint of a project. Each project picks a length of 1–4 weeks (2 by default);
/// the next sprint is implied and starts the day after this one ends.
struct SprintState: Codable, Equatable, Sendable {
    static let defaultLengthWeeks = 2
    /// Lengths a project can choose, in weeks
    static let lengthChoices = Array(1...4)
    static let goalPlaceholder = "Set a goal for this sprint"

    var number: Int
    var startDate: Date
    var goal: String
    /// 1–4 weeks
    var lengthWeeks: Int

    init(number: Int = 1, startDate: Date, goal: String = "", lengthWeeks: Int = SprintState.defaultLengthWeeks) {
        self.number = number
        self.startDate = startDate
        self.goal = goal
        self.lengthWeeks = Self.clampedLength(lengthWeeks)
    }

    static func clampedLength(_ weeks: Int) -> Int { min(max(weeks, 1), 4) }

    var lengthInDays: Int { lengthWeeks * 7 }
    /// "2 weeks"
    var lengthLabel: String { Self.lengthLabel(lengthWeeks) }
    static func lengthLabel(_ weeks: Int) -> String { weeks == 1 ? "1 week" : "\(weeks) weeks" }

    /// Last day of the active sprint (start + length − 1 day)
    var endDate: Date { Self.day(startDate, adding: lengthInDays - 1) }
    var nextStartDate: Date { Self.day(startDate, adding: lengthInDays) }
    var nextEndDate: Date { Self.day(startDate, adding: lengthInDays * 2 - 1) }

    /// "Sprint 14"
    var name: String { "Sprint \(number)" }
    /// "Sprint 15"
    var nextName: String { "Sprint \(number + 1)" }
    /// "Oct 26 – Nov 8"
    var dateRange: String { Self.rangeString(startDate, endDate) }
    /// "Nov 9 – Nov 22"
    var nextDateRange: String { Self.rangeString(nextStartDate, nextEndDate) }
    /// The goal, or the placeholder when empty
    var displayGoal: String {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.goalPlaceholder : trimmed
    }

    static func day(_ date: Date, adding days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    static func rangeString(_ start: Date, _ end: Date) -> String {
        "\(shortDate(start)) – \(shortDate(end))"
    }

    /// "Oct 26"
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Start of the current week (Monday) at midnight, used for new projects
    static func defaultStart(for now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) } ?? Calendar.current.startOfDay(for: now)
    }

    private enum CodingKeys: String, CodingKey { case number, startDate, goal, lengthWeeks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = max(1, c.decode(.number, or: 1))
        startDate = c.decode(.startDate, or: SprintState.defaultStart())
        goal = c.decode(.goal, or: "")
        lengthWeeks = Self.clampedLength(c.decode(.lengthWeeks, or: SprintState.defaultLengthWeeks))
    }
}

/// A completed sprint, kept for the "Past sprints" history.
struct PastSprint: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var number: Int
    var startDate: Date
    /// The day it was completed
    var endDate: Date
    var goal: String
    /// Every task that was in the sprint when it was completed, done or not
    var taskIds: [UUID]
    /// The ones that were done
    var doneTaskIds: [UUID]
    var completedAt: Date
    /// Expected minutes of every task in the sprint when it closed (canceled ones left out)
    var plannedMinutes: Int
    /// Expected minutes of the done tasks: what the sprint delivered, the velocity
    var doneMinutes: Int
    /// Seconds tracked on the project during the sprint's dates (from the time log)
    var trackedSeconds: TimeInterval
    /// The project's capacity for the whole sprint (weekly hours × weeks) when it closed; nil when
    /// the project had none
    var capacityHours: Double?
    /// The numbers were worked out afterwards (schema 10 migration) from the tasks as they are now,
    /// so expected times may have changed since. Shown with a "≈".
    var isApproximate: Bool

    init(id: UUID = UUID(), number: Int, startDate: Date, endDate: Date, goal: String = "",
         taskIds: [UUID] = [], doneTaskIds: [UUID] = [], completedAt: Date,
         plannedMinutes: Int = 0, doneMinutes: Int = 0, trackedSeconds: TimeInterval = 0,
         capacityHours: Double? = nil, isApproximate: Bool = false) {
        self.id = id
        self.number = number
        self.startDate = startDate
        self.endDate = endDate
        self.goal = goal
        self.taskIds = taskIds
        self.doneTaskIds = doneTaskIds
        self.completedAt = completedAt
        self.plannedMinutes = max(0, plannedMinutes)
        self.doneMinutes = max(0, doneMinutes)
        self.trackedSeconds = max(0, trackedSeconds)
        self.capacityHours = capacityHours.flatMap { $0 > 0 ? $0 : nil }
        self.isApproximate = isApproximate
    }

    /// "Sprint 3"
    var name: String { "Sprint \(number)" }
    /// "Oct 12 – Oct 25"
    var dateRange: String { SprintState.rangeString(startDate, endDate) }
    /// "8 of 10 done"
    var doneLabel: String { "\(doneTaskIds.count) of \(taskIds.count) done" }
    /// "18h planned · 21h tracked" ("≈18h planned" when worked out afterwards)
    var hoursLabel: String {
        let mark = isApproximate ? "≈" : ""
        let tracked = Int((trackedSeconds / 60).rounded())
        return "\(mark)\(Focus.durationString(minutes: plannedMinutes)) planned · \(Focus.durationString(minutes: tracked)) tracked"
    }
    /// "Oct 12 – Oct 25 · 8 of 10 done"
    var summary: String { "\(dateRange) · \(doneLabel)" }
    /// "8 of 10 done · 18h planned · 21h tracked · Oct 12 – Oct 25"
    var statsSummary: String { "\(doneLabel) · \(hoursLabel) · \(dateRange)" }
    /// The past sprint's group header hint, after the header's own task count:
    /// "8 done · 18h planned · 21h tracked · Oct 12 – Oct 25"
    var headerHint: String { "\(doneTaskIds.count) done · \(hoursLabel) · \(dateRange)" }

    private enum CodingKeys: String, CodingKey {
        case id, number, startDate, endDate, goal, taskIds, doneTaskIds, completedAt
        case plannedMinutes, doneMinutes, trackedSeconds, capacityHours, isApproximate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decode(.id, or: UUID())
        number = max(1, c.decode(.number, or: 1))
        completedAt = c.decode(.completedAt, or: Date())
        startDate = c.decode(.startDate, or: completedAt)
        endDate = c.decode(.endDate, or: completedAt)
        goal = c.decode(.goal, or: "")
        taskIds = c.decode(.taskIds, or: [])
        doneTaskIds = c.decode(.doneTaskIds, or: [])
        // Schema 9 and older stored no numbers: Workspace.migrated works them out (approximately)
        plannedMinutes = max(0, c.decode(.plannedMinutes, or: 0))
        doneMinutes = max(0, c.decode(.doneMinutes, or: 0))
        trackedSeconds = max(0, c.decode(.trackedSeconds, or: 0))
        capacityHours = (c.decodeOptional(.capacityHours) as Double?).flatMap { $0 > 0 ? $0 : nil }
        isApproximate = c.decode(.isApproximate, or: false)
    }
}

/// A project's icon in place of the letter tile: an emoji, or an SF Symbol drawn in the project color.
enum ProjectIcon: Codable, Equatable, Hashable, Sendable {
    case emoji(String)
    case symbol(String)

    /// An emoji icon from typed text: its first character, when that's an emoji. nil otherwise.
    static func emoji(from text: String) -> ProjectIcon? {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0xFF) })
        else { return nil }
        return .emoji(String(first))
    }

    private enum CodingKeys: String, CodingKey { case emoji, symbol }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value: String = c.decodeOptional(.emoji), !value.isEmpty {
            self = .emoji(value)
        } else if let value: String = c.decodeOptional(.symbol), !value.isEmpty {
            self = .symbol(value)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty project icon"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .emoji(value): try c.encode(value, forKey: .emoji)
        case let .symbol(value): try c.encode(value, forKey: .symbol)
        }
    }
}

/// The view a project opens on when it has one set (Project.defaultView).
enum ProjectView: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case board, list, sprints, milestones

    static var fallback: ProjectView { .board }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: return "Board"
        case .list: return "List"
        case .sprints: return "Sprints"
        case .milestones: return "Milestones"
        }
    }
}

struct Project: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    /// 0xRRGGBB, normally one of Focus.projectPalette
    var colorHex: UInt32
    var sprint: SprintState
    var createdAt: Date
    /// Markdown description
    var notes: String
    var targetDate: Date?
    /// Set while the project is archived: hidden from the sidebar list, pickers and the menu bar.
    var archivedAt: Date?
    /// Completed sprints, oldest first
    var pastSprints: [PastSprint]
    /// The workflow, in board order. Always has a Not started and a Done status (WorkflowRules).
    var statuses: [WorkflowStatus]
    /// Hours a week you put into this project; nil when not set. Sprint planning compares the plan
    /// with it (× the sprint's weeks) and milestone health uses it (÷ 5 working days).
    var weeklyCapacityHours: Double?
    /// The project is planned in sprints (the default). Off: no Sprints tab, Board shows every open
    /// task, and nothing mentions sprints (TaskStore+Capacity.swift).
    var usesSprints: Bool
    /// The view the project opens on; nil opens on the one used last.
    var defaultView: ProjectView?
    /// Expected time of a new task; nil uses TaskItem.defaultExpectedMinutes.
    var defaultExpectedMinutes: Int?
    /// Where a new task goes when nothing else picks a sprint (active, next or backlog).
    var defaultSprintSlot: SprintSlot
    /// Shown in place of the letter tile; nil keeps the letter.
    var icon: ProjectIcon?

    init(id: UUID = UUID(), name: String, colorHex: UInt32, sprint: SprintState, createdAt: Date = Date(),
         notes: String = "", targetDate: Date? = nil, archivedAt: Date? = nil, pastSprints: [PastSprint] = [],
         statuses: [WorkflowStatus] = WorkflowPreset.simple.statuses, weeklyCapacityHours: Double? = nil,
         usesSprints: Bool = true, defaultView: ProjectView? = nil, defaultExpectedMinutes: Int? = nil,
         defaultSprintSlot: SprintSlot = .active, icon: ProjectIcon? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sprint = sprint
        self.createdAt = createdAt
        self.notes = notes
        self.targetDate = targetDate
        self.archivedAt = archivedAt
        self.pastSprints = pastSprints
        self.statuses = WorkflowRules.repaired(statuses)
        self.weeklyCapacityHours = Self.cleanCapacity(weeklyCapacityHours)
        self.usesSprints = usesSprints
        self.defaultView = defaultView
        self.defaultExpectedMinutes = Self.cleanExpected(defaultExpectedMinutes)
        self.defaultSprintSlot = Self.cleanSlot(defaultSprintSlot)
        self.icon = icon
    }

    var isArchived: Bool { archivedAt != nil }

    /// Capacity hours a week: positive and at most a week's hours, or nil.
    static func cleanCapacity(_ hours: Double?) -> Double? {
        guard let hours, hours.isFinite, hours > 0 else { return nil }
        return min(hours, 168)
    }

    static func cleanExpected(_ minutes: Int?) -> Int? {
        guard let minutes, minutes > 0 else { return nil }
        return min(minutes, 100 * 60)
    }

    /// Only a plannable slot can be a default (a past sprint can't take new tasks).
    static func cleanSlot(_ slot: SprintSlot) -> SprintSlot { slot == .closed ? .active : slot }

    /// The project's capacity for one whole sprint (weekly × weeks), or nil without a capacity.
    var sprintCapacityHours: Double? { weeklyCapacityHours.map { $0 * Double(sprint.lengthWeeks) } }

    /// Expected minutes a new task starts with.
    var newTaskExpectedMinutes: Int { defaultExpectedMinutes ?? TaskItem.defaultExpectedMinutes }

    /// The slot a new task gets when nothing else chooses: the default, or active without sprints.
    var newTaskSlot: SprintSlot { usesSprints ? defaultSprintSlot : .active }

    /// First letter for the project tile
    var initial: String { name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex, sprint, createdAt, notes, targetDate, archivedAt, pastSprints, statuses
        case weeklyCapacityHours, usesSprints, defaultView, defaultExpectedMinutes, defaultSprintSlot, icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = c.decode(.name, or: "Untitled project")
        colorHex = c.decode(.colorHex, or: 0x64748B)
        sprint = c.decode(.sprint, or: SprintState(startDate: SprintState.defaultStart()))
        createdAt = c.decode(.createdAt, or: Date())
        notes = c.decode(.notes, or: "")
        targetDate = c.decodeOptional(.targetDate)
        archivedAt = c.decodeOptional(.archivedAt)
        pastSprints = c.decodeLossyArray(.pastSprints)
        // Older files have no workflow: the Simple one (To do, In progress, Done)
        statuses = WorkflowRules.repaired(c.decodeLossyArray(.statuses))
        // Schema 9 and older: no capacity, sprints on, no defaults, the letter tile
        weeklyCapacityHours = Self.cleanCapacity(c.decodeOptional(.weeklyCapacityHours))
        usesSprints = c.decode(.usesSprints, or: true)
        defaultView = c.decodeOptional(.defaultView)
        defaultExpectedMinutes = Self.cleanExpected(c.decodeOptional(.defaultExpectedMinutes))
        defaultSprintSlot = Self.cleanSlot(c.decode(.defaultSprintSlot, or: .active))
        icon = c.decodeOptional(.icon)
    }
}
