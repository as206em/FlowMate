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

    init(id: UUID = UUID(), projectId: UUID, name: String, dueDate: Date? = nil,
         notes: String = "", completedAt: Date? = nil) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.dueDate = dueDate
        self.notes = notes
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }

    private enum CodingKeys: String, CodingKey { case id, projectId, name, dueDate, notes, completedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        name = c.decode(.name, or: "Untitled milestone")
        dueDate = c.decodeOptional(.dueDate)
        notes = c.decode(.notes, or: "")
        completedAt = c.decodeOptional(.completedAt)
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
