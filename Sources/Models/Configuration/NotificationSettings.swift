import Foundation

/// Which task notifications FlowMate sends (Settings › Notifications). Stored in config.json with
/// the other app settings; settings missing from an older file get these defaults.
///
/// The morning summary and the reminders are off until you turn them on. "Still working on X?"
/// and the sleep prompt are on, but they only reach Notification Center once you've allowed
/// notifications, and only while FlowMate isn't the frontmost app (its own prompts show then).
struct NotificationSettings: Codable, Equatable, Sendable {
    /// "3 due today, 1 overdue" at `morningMinutes`
    var morningSummary: Bool
    /// When the morning summary and the due reminders arrive, in minutes after midnight
    var morningMinutes: Int
    /// One notification per task due that day, at the morning time
    var dueReminders: Bool
    /// "Marketing is due in 2 days · 4 of 9 done", at the morning time two days before
    var milestoneReminders: Bool
    /// "Still working on X?" with Keep going and Pause
    var longRunAlerts: Bool
    /// "Timers ran while your Mac slept 2h 05m" with Keep and Discard sleep time
    var sleepAlerts: Bool

    static let defaultMorningMinutes = 9 * 60
    /// The choices offered for the morning time
    static let morningChoices = [7 * 60, 8 * 60, 8 * 60 + 30, 9 * 60, 9 * 60 + 30, 10 * 60]

    init(morningSummary: Bool = false, morningMinutes: Int = NotificationSettings.defaultMorningMinutes,
         dueReminders: Bool = false, milestoneReminders: Bool = false,
         longRunAlerts: Bool = true, sleepAlerts: Bool = true) {
        self.morningSummary = morningSummary
        self.morningMinutes = min(max(0, morningMinutes), 24 * 60 - 1)
        self.dueReminders = dueReminders
        self.milestoneReminders = milestoneReminders
        self.longRunAlerts = longRunAlerts
        self.sleepAlerts = sleepAlerts
    }

    /// Any notification that's on
    var anyOn: Bool { morningSummary || dueReminders || milestoneReminders || longRunAlerts || sleepAlerts }

    /// "9:00", "8:30"
    static func timeLabel(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
