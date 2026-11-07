import Foundation

/// A workspace-wide label (tag) a task can carry several of: "bug", "waiting", "client". Shared
/// by every project. Named TaskLabel because SwiftUI already has a `Label`.
struct TaskLabel: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// The colors labels pick from: the Focus project palette.
    static var palette: [UInt32] { Focus.projectPalette }
    static let maxNameLength = 40

    var id: UUID
    var name: String
    var colorHex: UInt32

    init(id: UUID = UUID(), name: String, colorHex: UInt32 = TaskLabel.palette[0]) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    /// A name as stored: trimmed, inner runs of spaces squeezed, at most `maxNameLength` long.
    /// Empty when nothing is left.
    static func cleanName(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(maxNameLength))
    }

    /// The palette color used least by `used` (the first one on a tie), for a new label.
    static func nextColor(used: [UInt32]) -> UInt32 {
        let counts = Dictionary(used.map { ($0, 1) }, uniquingKeysWith: +)
        return palette.min { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? palette[0]
    }

    private enum CodingKeys: String, CodingKey { case id, name, colorHex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let stored = Self.cleanName(c.decode(.name, or: ""))
        name = stored.isEmpty ? "Label" : stored
        colorHex = c.decode(.colorHex, or: TaskLabel.palette[0])
    }
}
