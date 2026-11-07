import Foundation

// MARK: - Settings sections
enum SettingsTab: Hashable, CaseIterable {
    case general
    case cloudSync
    case notifications
    case proofreading
    case dictation
    case aiProviders
    case updates
    case maintenance

    var displayName: String {
        switch self {
        case .general: return "General"
        case .cloudSync: return "Cloud sync"
        case .notifications: return "Notifications"
        case .proofreading: return "Proofreading"
        case .dictation: return "Dictation"
        case .aiProviders: return "AI providers"
        case .updates: return "Updates"
        case .maintenance: return "Maintenance"
        }
    }

    /// SF Symbol name
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .cloudSync: return "icloud"
        case .notifications: return "bell"
        case .proofreading: return "pencil.line"
        case .dictation: return "mic"
        case .aiProviders: return "cpu"
        case .updates: return "arrow.down.circle"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
}
