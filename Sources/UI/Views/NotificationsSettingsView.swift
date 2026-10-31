import SwiftUI

// MARK: - Notifications settings: apply right away

/// Settings › Notifications: the morning summary, due and milestone reminders, and the timer
/// prompts in Notification Center. Turning one on asks macOS for permission the first time; when
/// notifications are off for FlowMate in System Settings, a banner says so and opens it.
struct NotificationsSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var notifications = TaskNotifications.shared
    /// The long-run interval lives with the task data (Settings › General › Timers)
    @ObservedObject private var tasks = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let settings = appState.notificationSettings
        FocusSettingsPage(
            title: "Notifications",
            subtitle: "What FlowMate tells you in Notification Center. Changes apply right away."
        ) {
            permissionBanner(settings)

            FocusSection(
                title: "Today",
                subtitle: "Click a notification to open Today, the task or the milestone."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    toggle("Morning summary", hint: "“3 due today, 1 overdue”. Not sent on days with nothing due.",
                           isOn: settings.morningSummary) { value in update { $0.morningSummary = value } }
                    toggle("Due today reminders", hint: "One per task due that day, at the same time.",
                           isOn: settings.dueReminders) { value in update { $0.dueReminders = value } }
                    FocusLabeled(label: "Send them at", hint: "The morning summary, the due reminders and the milestone reminders arrive then.") {
                        FocusTabs(
                            options: NotificationSettings.morningChoices.map { (value: $0, label: NotificationSettings.timeLabel($0)) },
                            selection: Binding(
                                get: { settings.morningMinutes },
                                set: { minutes in update { $0.morningMinutes = minutes } }
                            )
                        )
                        .fixedSize()
                    }
                    .opacity(settings.morningSummary || settings.dueReminders || settings.milestoneReminders ? 1 : 0.55)
                    toggle("Milestone due in 2 days", hint: "“Marketing is due in 2 days · 4 of 9 done”.",
                           isOn: settings.milestoneReminders) { value in update { $0.milestoneReminders = value } }
                }
            }

            FocusSection(
                title: "Timers",
                subtitle: "Only while FlowMate isn't the app in front; otherwise its own prompt shows. Neither ever stops a timer by itself."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    toggle("“Still working on it?”", hint: longRunHint, isOn: settings.longRunAlerts) { value in
                        update { $0.longRunAlerts = value }
                    }
                    toggle("Timers ran while the Mac slept", hint: "With Keep and Discard sleep time, after more than 5 minutes of sleep or screen lock.",
                           isOn: settings.sleepAlerts) { value in update { $0.sleepAlerts = value } }
                }
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.focus())
        }
        .task { await notifications.refreshAuthorization() }
    }

    private var longRunHint: String {
        let minutes = tasks.preferences.longRunPromptMinutes
        guard minutes > 0 else { return "The prompt is set to Never in General › Timers, so nothing is sent." }
        return "After \(Focus.durationString(minutes: minutes)) without a break (General › Timers), with Keep going and Pause."
    }

    @ViewBuilder
    private func permissionBanner(_ settings: NotificationSettings) -> some View {
        switch notifications.authorization {
        case .denied:
            FocusBanner(
                tone: .risk,
                systemImage: "bell.slash",
                title: "Notifications are off for FlowMate",
                message: "macOS isn't showing FlowMate's notifications. Turn them on in System Settings › Notifications › FlowMate.",
                primaryTitle: "Open System Settings",
                primaryAction: { notifications.openSystemSettings() }
            )
        case .notDetermined where settings.anyOn:
            FocusBanner(
                systemImage: "bell.badge",
                title: "Allow notifications",
                message: "macOS asks once. Until then nothing reaches Notification Center.",
                primaryTitle: "Allow…",
                primaryAction: { Task { await notifications.requestAuthorizationIfNeeded() } }
            )
        case .unavailable:
            FocusBanner(
                systemImage: "info.circle",
                title: "Notifications need the FlowMate app",
                message: "This copy runs outside an app bundle. Build FlowMate.app with build-app.sh to get notifications."
            )
        case .authorized, .notDetermined:
            EmptyView()
        }
    }

    private func toggle(_ title: String, hint: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Focus.control).foregroundColor(Focus.text)
                Text(hint).font(.system(size: 12)).foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.focus)
        .frame(maxWidth: 520, alignment: .leading)
    }

    /// Saves the change; turning something on asks for permission the first time.
    private func update(_ change: (inout NotificationSettings) -> Void) {
        let before = appState.notificationSettings
        appState.updateNotificationSettings(change)
        let after = appState.notificationSettings
        let turnedOn = (after.morningSummary && !before.morningSummary) || (after.dueReminders && !before.dueReminders)
            || (after.milestoneReminders && !before.milestoneReminders) || (after.longRunAlerts && !before.longRunAlerts)
            || (after.sleepAlerts && !before.sleepAlerts)
        if turnedOn { Task { await notifications.requestAuthorizationIfNeeded() } }
    }
}
