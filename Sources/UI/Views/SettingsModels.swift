import Foundation

// MARK: - Settings Models
struct SettingsSidebarItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let tag: SettingsTab
    
    init(title: String, icon: String, tag: SettingsTab) {
        self.title = title
        self.icon = icon
        self.tag = tag
    }
    
    static func == (lhs: SettingsSidebarItem, rhs: SettingsSidebarItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SettingsTab: Hashable {
    case general
    case proofreading
    case aiProviders
    case maintenance
    
    var displayName: String {
        switch self {
        case .general:
            return "General"
        case .proofreading:
            return "Proofreading"
        case .aiProviders:
            return "AI Providers"
        case .maintenance:
            return "Maintenance"
        }
    }
    
    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .proofreading:
            return "doc.text.magnifyingglass"
        case .aiProviders:
            return "cpu"
        case .maintenance:
            return "wrench.and.screwdriver"
        }
    }
}
