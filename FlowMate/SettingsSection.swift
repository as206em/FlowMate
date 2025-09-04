import SwiftUI

enum SettingsSection: CaseIterable, Identifiable {
    case settings
    case models
    case shortcuts
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .settings:
            return "Settings"
        case .models:
            return "Models"
        case .shortcuts:
            return "Shortcuts"
        }
    }
    
    var systemImage: String {
        switch self {
        case .settings:
            return "gear"
        case .models:
            return "cpu"
        case .shortcuts:
            return "keyboard"
        }
    }
}
