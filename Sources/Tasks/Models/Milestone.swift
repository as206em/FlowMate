import Foundation

struct Milestone: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var projectId: UUID
    var name: String
    var dueDate: Date?
    /// Optional start: the milestone then shows as a bar from here to the due date on the timeline
    var startDate: Date?
    /// Markdown description
    var notes: String
    /// Set by "Mark complete"
    var completedAt: Date?
    /// Its diamond and chips. 0 (`Milestone.unsetColor`) until one is given: files from before
    /// schema 8 and hand-built milestones get one from `Workspace.assignMilestoneColors()`.
    var colorHex: UInt32

    static let unsetColor: UInt32 = 0

    init(id: UUID = UUID(), projectId: UUID, name: String, dueDate: Date? = nil,
         startDate: Date? = nil, notes: String = "", completedAt: Date? = nil, colorHex: UInt32 = Milestone.unsetColor) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.dueDate = dueDate
        self.startDate = startDate
        self.notes = notes
        self.completedAt = completedAt
        self.colorHex = colorHex
    }

    var isCompleted: Bool { completedAt != nil }

    /// The palette milestones take their colors from (the project tile palette).
    static var palette: [UInt32] { Focus.projectPalette }

    /// Palette colors closer than this to the project's color (CIE76 ΔE in Lab) read as the same
    /// color next to its tile, so milestones don't take them. 25 stays under the palette's closest
    /// pair (green and teal, ~28) while catching a custom red next to coral (~14).
    static let minimumDistanceFromProject = 25.0

    /// The color for a project's next milestone: the palette color its milestones use least,
    /// leaving out colors that look like the project's own (by perceptual distance, so a custom
    /// project color near a palette color counts too) so a card's tile and milestone chip differ.
    /// Ties go to palette order, so a project's milestones walk through the palette.
    static func nextColor(projectColor: UInt32?, used: [UInt32]) -> UInt32 {
        var choices = palette
        if let projectColor {
            choices = palette.filter { ColorDistance.deltaE(projectColor, $0) >= minimumDistanceFromProject }
            if choices.isEmpty {
                // Nothing far enough (can't happen with the stock palette): the farthest one
                choices = palette.max { ColorDistance.deltaE(projectColor, $0) < ColorDistance.deltaE(projectColor, $1) }.map { [$0] } ?? []
            }
        }
        guard !choices.isEmpty else { return palette.first ?? 0x4EA1F5 }
        var counts: [UInt32: Int] = [:]
        for hex in used { counts[hex, default: 0] += 1 }
        let fewest = choices.map { counts[$0] ?? 0 }.min() ?? 0
        return choices.first { (counts[$0] ?? 0) == fewest } ?? choices[0]
    }

    private enum CodingKeys: String, CodingKey { case id, projectId, name, dueDate, startDate, notes, completedAt, colorHex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        name = c.decode(.name, or: "Untitled milestone")
        dueDate = c.decodeOptional(.dueDate)
        startDate = c.decodeOptional(.startDate)
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

/// How different two colors look: CIE76 ΔE between their CIELAB values (sRGB, D65). Around 2 is
/// barely visible; 25+ reads as a different color.
enum ColorDistance {
    static func deltaE(_ a: UInt32, _ b: UInt32) -> Double {
        let la = lab(a), lb = lab(b)
        return ((la.0 - lb.0) * (la.0 - lb.0) + (la.1 - lb.1) * (la.1 - lb.1) + (la.2 - lb.2) * (la.2 - lb.2)).squareRoot()
    }

    static func lab(_ hex: UInt32) -> (Double, Double, Double) {
        func linear(_ c: UInt32) -> Double {
            let v = Double(c & 0xFF) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(hex >> 16), g = linear(hex >> 8), b = linear(hex)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}
