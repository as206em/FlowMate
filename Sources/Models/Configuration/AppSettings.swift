import Foundation
import SwiftUI

struct AppSettings: Codable {
    /// Appearance: "system", "light" or "dark"
    var theme: String
    /// How many recent proofreading results to keep in memory (0 = off)
    var maxHistoryItems: Int
    var customSettings: [String: String] // For extensibility
    /// Global shortcut that opens the floating New task box from any app ("" = off)
    var quickAddShortcut: String
    /// Task notifications: the morning summary, reminders and the timer prompts
    var notifications: NotificationSettings

    static let defaultQuickAddShortcut = "control+option+n"

    init(theme: String = "system", maxHistoryItems: Int = 50, customSettings: [String: String] = [:],
         quickAddShortcut: String = AppSettings.defaultQuickAddShortcut,
         notifications: NotificationSettings = NotificationSettings()) {
        self.theme = theme
        self.maxHistoryItems = maxHistoryItems
        self.customSettings = customSettings
        self.quickAddShortcut = quickAddShortcut
        self.notifications = notifications
    }
}
