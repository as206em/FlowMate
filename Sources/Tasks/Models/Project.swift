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

    init(id: UUID = UUID(), number: Int, startDate: Date, endDate: Date, goal: String = "",
         taskIds: [UUID] = [], doneTaskIds: [UUID] = [], completedAt: Date) {
        self.id = id
        self.number = number
        self.startDate = startDate
        self.endDate = endDate
        self.goal = goal
        self.taskIds = taskIds
        self.doneTaskIds = doneTaskIds
        self.completedAt = completedAt
    }

    /// "Sprint 3"
    var name: String { "Sprint \(number)" }
    /// "Oct 12 – Oct 25"
    var dateRange: String { SprintState.rangeString(startDate, endDate) }
    /// "8 of 10 done"
    var doneLabel: String { "\(doneTaskIds.count) of \(taskIds.count) done" }
    /// "Oct 12 – Oct 25 · 8 of 10 done"
    var summary: String { "\(dateRange) · \(doneLabel)" }

    private enum CodingKeys: String, CodingKey { case id, number, startDate, endDate, goal, taskIds, doneTaskIds, completedAt }

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

    init(id: UUID = UUID(), name: String, colorHex: UInt32, sprint: SprintState, createdAt: Date = Date(),
         notes: String = "", targetDate: Date? = nil, archivedAt: Date? = nil, pastSprints: [PastSprint] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sprint = sprint
        self.createdAt = createdAt
        self.notes = notes
        self.targetDate = targetDate
        self.archivedAt = archivedAt
        self.pastSprints = pastSprints
    }

    var isArchived: Bool { archivedAt != nil }

    /// First letter for the project tile
    var initial: String { name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex, sprint, createdAt, notes, targetDate, archivedAt, pastSprints
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
    }
}
