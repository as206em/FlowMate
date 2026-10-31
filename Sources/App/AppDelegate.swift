import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app to allow windows to receive focus
        NSApp.setActivationPolicy(.accessory)

        // The shortcut and copy/paste need Accessibility access; ask once at launch if it's missing
        Task { @MainActor in
            AppState.promptForAccessibilityAccess()
            // Timers that run through sleep or a locked screen ask whether that time counts
            SystemAwayMonitor.shared.start(store: TaskStore.shared)
            // The morning summary, reminders and timer prompts in Notification Center
            if UserNotificationClient.isAvailable { UNUserNotificationCenter.current().delegate = self }
            TaskNotifications.shared.start(store: TaskStore.shared)
        }
    }

    // MARK: - Notifications

    /// Long-run and sleep prompts stay quiet while FlowMate is in front: its own prompt shows.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let kind = notification.request.content.userInfo["kind"] as? String
        // Delegate calls can come on another thread; NSApp is read on the main one
        Task { @MainActor in
            let show = !NSApp.isActive || TaskNotifications.presentsWhileActive(kind: kind)
            completionHandler(show ? [.banner, .list, .sound] : [])
        }
    }

    /// A click on a notification opens what it's about; its buttons (Keep going, Pause, Keep,
    /// Discard sleep time) act without opening anything.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let target = (info["target"] as? String) ?? ""
        let taskId = (info["taskId"] as? String) ?? ""
        Task { @MainActor in
            let service = TaskNotifications.shared
            if let open = service.handle(action: action, userInfo: ["target": target, "taskId": taskId]) {
                service.open(open)
            }
            service.scheduleSoon()
            completionHandler()
        }
    }

    /// Lets a pending task save finish before the app quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = MainActor.assumeIsolated { TaskStore.shared }
        // Always flush: it also waits for a save that is already writing (hasUnsavedChanges is false then)
        Task { @MainActor in
            await store.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Last chance if termination skipped the async flush above
        MainActor.assumeIsolated { TaskStore.shared.flushBlocking() }
    }
}
