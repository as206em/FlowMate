import Foundation

/// A saved view ("smart list") in the sidebar's Views section: a scope (All projects, a project or
/// a milestone's page), Board or List, and the filters, sort and grouping to show it with.
/// Clicking it shows exactly that; changing the filters afterwards marks it Modified until you
/// Update it or Revert.
struct SavedView: Identifiable, Codable, Equatable, Sendable {
    /// The two layouts a view can open on (the ones with a filter bar).
    enum Layout: String, CaseIterable, Sendable, TolerantStringEnum {
        case board, list
        static var fallback: Layout { .list }

        var title: String { self == .board ? "Board" : "List" }
    }

    /// Icons offered in the Save view sheet (SF Symbols).
    static let icons: [String] = [
        "line.3.horizontal.decrease.circle", "star", "flag", "bolt", "flame", "exclamationmark.triangle",
        "calendar", "clock", "tray", "tag", "person", "bookmark",
    ]
    static let defaultIcon = "line.3.horizontal.decrease.circle"
    static let maxNameLength = 60

    var id: UUID
    var name: String
    /// An SF Symbol; nil shows the default filter icon
    var icon: String?
    /// The scope as TaskScope.storageKey ("all", a project id, "milestone-<id>@<project>")
    var scopeKey: String
    var layout: Layout
    /// Filter, sort and grouping (the search text included)
    var options: TaskViewOptions

    init(id: UUID = UUID(), name: String, icon: String? = nil, scope: TaskScope, layout: Layout = .list,
         options: TaskViewOptions = .standard) {
        self.id = id
        self.name = name
        self.icon = icon
        self.scopeKey = (scope == .today ? TaskScope.all : scope).storageKey
        self.layout = layout
        self.options = options
    }

    /// The scope it shows. Today has no filters, so it's never one (All projects instead).
    var scope: TaskScope {
        get {
            guard let scope = TaskScope(storageKey: scopeKey), scope != .today else { return .all }
            return scope
        }
        set { scopeKey = (newValue == .today ? TaskScope.all : newValue).storageKey }
    }

    var iconName: String { icon ?? Self.defaultIcon }

    static func cleanName(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maxNameLength))
    }

    private enum CodingKeys: String, CodingKey { case id, name, icon, scope, layout, options }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let stored = Self.cleanName(c.decode(.name, or: ""))
        name = stored.isEmpty ? "View" : stored
        icon = c.decodeOptional(.icon)
        let key: String = c.decode(.scope, or: "all")
        scopeKey = TaskScope(storageKey: key).map { $0 == .today ? "all" : $0.storageKey } ?? "all"
        layout = c.decode(.layout, or: .list)
        options = c.decode(.options, or: .standard)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(scopeKey, forKey: .scope)
        try c.encode(layout, forKey: .layout)
        try c.encode(options, forKey: .options)
    }
}

/// A view to suggest while there are none: shown in the empty Views section, created only when
/// clicked.
struct SavedViewSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let icon: String
    let options: TaskViewOptions

    /// High priority tasks that are still open, and what's due this week, across every project.
    static let starters: [SavedViewSuggestion] = {
        var high = TaskViewOptions()
        high.filter.priorities = [.high]
        high.filter.categories = [.notStarted, .started]
        var week = TaskViewOptions()
        week.filter.due = [.overdue, .thisWeek]
        week.filter.categories = [.notStarted, .started]
        week.sort = TaskSort(key: .due)
        return [
            SavedViewSuggestion(id: "high", name: "High priority", icon: "flag", options: high),
            SavedViewSuggestion(id: "week", name: "Due this week", icon: "calendar", options: week),
        ]
    }()
}
