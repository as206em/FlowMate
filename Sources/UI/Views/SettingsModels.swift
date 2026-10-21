import Foundation

// MARK: - Settings sections
enum SettingsTab: Hashable, CaseIterable {
    case general
    case proofreading
    case aiProviders
    case maintenance

    var displayName: String {
        switch self {
        case .general: return "General"
        case .proofreading: return "Proofreading"
        case .aiProviders: return "AI providers"
        case .maintenance: return "Maintenance"
        }
    }

    /// SF Symbol name
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .proofreading: return "pencil.line"
        case .aiProviders: return "cpu"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
}
