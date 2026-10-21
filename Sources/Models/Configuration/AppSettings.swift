import Foundation
import SwiftUI

struct AppSettings: Codable {
    /// Appearance: "system", "light" or "dark"
    var theme: String
    /// How many recent proofreading results to keep in memory (0 = off)
    var maxHistoryItems: Int
    var customSettings: [String: String] // For extensibility

    init(theme: String = "system", maxHistoryItems: Int = 50, customSettings: [String: String] = [:]) {
        self.theme = theme
        self.maxHistoryItems = maxHistoryItems
        self.customSettings = customSettings
    }
}
