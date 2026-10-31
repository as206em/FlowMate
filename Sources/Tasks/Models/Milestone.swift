import Foundation

struct Milestone: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var projectId: UUID
    var name: String
    var dueDate: Date?
    /// Markdown description
    var notes: String
    /// Set by "Mark complete"
    var completedAt: Date?
    /// Its diamond and chips. 0 (`Milestone.unsetColor`) until one is given: files from before
    /// schema 8 and hand-built milestones get one from `Workspace.assignMilestoneColors()`.
    var colorHex: UInt32

    static let unsetColor: UInt32 = 0

    init(id: UUID = UUID(), projectId: UUID, name: String, dueDate: Date? = nil,
         notes: String = "", completedAt: Date? = nil, colorHex: UInt32 = Milestone.unsetColor) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.dueDate = dueDate
        self.notes = notes
        self.completedAt = completedAt
        self.colorHex = colorHex
    }

    var isCompleted: Bool { completedAt != nil }

    /// The palette milestones take their colors from (the project tile palette).
    static var palette: [UInt32] { Focus.projectPalette }

    /// The color for a project's next milestone: the palette color its milestones use least,
    /// leaving out the project's own color so a card's tile and milestone chip differ. Ties go to
    /// palette order, so a project's milestones walk through the palette.
    static func nextColor(projectColor: UInt32?, used: [UInt32]) -> UInt32 {
        let choices = palette.filter { $0 != projectColor }
        guard !choices.isEmpty else { return palette.first ?? 0x4EA1F5 }
        var counts: [UInt32: Int] = [:]
        for hex in used { counts[hex, default: 0] += 1 }
        let fewest = choices.map { counts[$0] ?? 0 }.min() ?? 0
        return choices.first { (counts[$0] ?? 0) == fewest } ?? choices[0]
    }

    private enum CodingKeys: String, CodingKey { case id, projectId, name, dueDate, notes, completedAt, colorHex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        name = c.decode(.name, or: "Untitled milestone")
        dueDate = c.decodeOptional(.dueDate)
        notes = c.decode(.notes, or: "")
        completedAt = c.decodeOptional(.completedAt)
        // Before schema 8: none stored; migration picks one
        colorHex = c.decode(.colorHex, or: Milestone.unsetColor)
    }
}

/// Done / total task counts for a milestone
struct MilestoneProgress: Equatable, Sendable {
    var done: Int
    var total: Int

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    /// "3/7"
    var short: String { "\(done)/\(total)" }
    /// "3 of 7 tasks done"
    var label: String { "\(done) of \(total) tasks done" }
}
