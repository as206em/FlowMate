import Foundation

// MARK: - Settings sections
enum SettingsTab: Hashable, CaseIterable {
    case general
    case notifications
    case proofreading
    case aiProviders
    case updates
    case maintenance

    var displayName: String {
        switch self {
        case .general: return "General"
        case .notifications: return "Notifications"
        case .proofreading: return "Proofreading"
        case .aiProviders: return "AI providers"
        case .updates: return "Updates"
        case .maintenance: return "Maintenance"
        }
    }

    /// SF Symbol name
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .notifications: return "bell"
        case .proofreading: return "pencil.line"
        case .aiProviders: return "cpu"
        case .updates: return "arrow.down.circle"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
}
