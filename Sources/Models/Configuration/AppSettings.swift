import Foundation
import SwiftUI

struct AppSettings: Codable {
    var theme: String
    var autoCheckUpdates: Bool
    var maxHistoryItems: Int
    var customSettings: [String: String] // For extensibility
    
    init(theme: String = "system", autoCheckUpdates: Bool = true, maxHistoryItems: Int = 50, customSettings: [String: String] = [:]) {
        self.theme = theme
        self.autoCheckUpdates = autoCheckUpdates
        self.maxHistoryItems = maxHistoryItems
        self.customSettings = customSettings
    }
}
