import Foundation

/// The two kinds of work a sprint balances: making the product, and reaching the people who use
/// or buy it (customers, sales, marketing). The Sprint plan compares their planned time with the
/// sprint's mix target, so a sprint that is all building shows it.
enum TypeBucket: String, CaseIterable, Identifiable, Sendable, TolerantStringEnum {
    case make, reach

    static var fallback: TypeBucket { .make }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .make: return "Make"
        case .reach: return "Reach"
        }
    }

    var help: String {
        switch self {
        case .make: return "Building and running the product"
        case .reach: return "Customers, sales and marketing: getting what you built to people"
        }
    }
}

/// A workspace-wide kind of task ("Build", "Customers", "Sales"), in one bucket, with an impact
/// (1–10) that every task of the type leans toward in the Next best ranking. Edited in the Types
/// sheet; each task has at most one.
struct TaskType: Identifiable, Codable, Equatable, Hashable, Sendable {
    static let maxNameLength = 30

    var id: UUID
    var name: String
    var bucket: TypeBucket
    /// 1–10
    var impact: Int
    var colorHex: UInt32

    init(id: UUID = UUID(), name: String, bucket: TypeBucket, impact: Int = ImpactScale.neutral, colorHex: UInt32 = TaskLabel.palette[0]) {
        self.id = id
        self.name = name
        self.bucket = bucket
        self.impact = ImpactScale.clamped(impact)
        self.colorHex = colorHex
    }

    /// The types a new workspace starts with (and older files get once). Fixed ids, so two fresh
    /// workspaces compare equal.
    static let defaults: [TaskType] = [
        TaskType(id: UUID(uuidString: "7A1E0000-0000-4000-8000-000000000001")!, name: "Build", bucket: .make, impact: 5, colorHex: 0x4EA1F5),
        TaskType(id: UUID(uuidString: "7A1E0000-0000-4000-8000-000000000002")!, name: "Customers", bucket: .reach, impact: 9, colorHex: 0x2FB67C),
        TaskType(id: UUID(uuidString: "7A1E0000-0000-4000-8000-000000000003")!, name: "Sales", bucket: .reach, impact: 9, colorHex: 0xE5A50A),
        TaskType(id: UUID(uuidString: "7A1E0000-0000-4000-8000-000000000004")!, name: "Marketing", bucket: .reach, impact: 8, colorHex: 0xE5604C),
        TaskType(id: UUID(uuidString: "7A1E0000-0000-4000-8000-000000000005")!, name: "Ops", bucket: .make, impact: 3, colorHex: 0x8E8E93),
    ]

    /// Trimmed, inner spaces squeezed, at most `maxNameLength` long; empty when nothing is left.
    static func cleanName(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maxNameLength))
    }

    private enum CodingKeys: String, CodingKey { case id, name, bucket, impact, colorHex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let stored = Self.cleanName(c.decode(.name, or: ""))
        name = stored.isEmpty ? "Type" : stored
        bucket = c.decode(.bucket, or: .make)
        impact = ImpactScale.clamped(c.decode(.impact, or: ImpactScale.neutral))
        colorHex = c.decode(.colorHex, or: TaskLabel.palette[0])
    }
}

/// Impact is a whole number from 1 (least valuable) to 10 (most) wherever it is set: a project, a
/// type or a task.
enum ImpactScale {
    static let range = 1...10
    /// What a project without an impact counts as
    static let neutral = 5
    static let choices = Array(range).reversed() as [Int]

    static func clamped(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }

    /// nil stays nil; anything else is clamped to 1–10.
    static func cleaned(_ value: Int?) -> Int? { value.map(clamped) }

    /// "9 · Very high", the picker's title for a value
    static func title(_ value: Int) -> String {
        switch value {
        case 9...: return "\(value) · Very high"
        case 7...8: return "\(value) · High"
        case 4...6: return "\(value) · Medium"
        case 2...3: return "\(value) · Low"
        default: return "\(value) · Very low"
        }
    }
}
