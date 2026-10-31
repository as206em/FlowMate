import AppKit
import Combine
import Foundation
import UserNotifications

// Task notifications: the morning summary, due and milestone reminders, and the long-run and
// sleep prompts in Notification Center. NotificationPlanner decides what should be there; this
// service keeps Notification Center in step with it (debounced after every change, at midnight
// and on wake) and runs the notifications' buttons.

/// Whether FlowMate may post notifications.
enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
    /// Not running as the FlowMate app bundle (swift run, tests): there's no Notification Center
    case unavailable
}

/// Notification Center, behind a protocol so tests can stand in for it.
@MainActor
protocol NotificationCenterClient: AnyObject {
    func authorization() async -> NotificationAuthorization
    /// Asks the user (only the first time macOS lets it). True when allowed.
    func requestAuthorization() async -> Bool
    /// FlowMate's scheduled notifications: identifier → signature
    func pending() async -> [String: String]
    /// FlowMate's notifications already shown
    func delivered() async -> Set<String>
    func add(_ notification: PlannedNotification) async
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
    func registerCategories()
}

/// The buttons on FlowMate's notifications.
enum NotificationAction {
    static let keepGoing = "flowmate.keep-going"
    static let pause = "flowmate.pause"
    static let keepAway = "flowmate.away-keep"
    static let discardAway = "flowmate.away-discard"
}

/// UNUserNotificationCenter. Only made inside the app bundle: it traps without one.
@MainActor
final class UserNotificationClient: NotificationCenterClient {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func authorization() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pending() async -> [String: String] {
        let requests = await center.pendingNotificationRequests()
        return Dictionary(requests.filter { $0.identifier.hasPrefix(NotificationPlanner.idPrefix) }.map {
            ($0.identifier, $0.content.userInfo["signature"] as? String ?? "")
        }, uniquingKeysWith: { a, _ in a })
    }

    func delivered() async -> Set<String> {
        let shown = await center.deliveredNotifications()
        return Set(shown.map(\.request.identifier).filter { $0.hasPrefix(NotificationPlanner.idPrefix) })
    }

    func add(_ notification: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.categoryIdentifier = notification.kind.categoryId
        content.threadIdentifier = notification.kind.rawValue
        content.sound = notification.kind == .morning || notification.kind == .due ? .default : nil
        var info: [String: String] = [
            "signature": notification.signature,
            "kind": notification.kind.rawValue,
            "target": notification.target.stringValue,
        ]
        if let taskId = notification.taskId { info["taskId"] = taskId.uuidString }
        content.userInfo = info
        var trigger: UNNotificationTrigger?
        if let fire = notification.fireDate {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            Logger.shared.error("Couldn't schedule notification \(notification.id)", error: error)
        }
    }

    func removePending(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeDelivered(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func registerCategories() {
        let longRun = UNNotificationCategory(
            identifier: NotificationPlanner.longRunCategory,
            actions: [
                UNNotificationAction(identifier: NotificationAction.keepGoing, title: "Keep going"),
                UNNotificationAction(identifier: NotificationAction.pause, title: "Pause"),
            ],
            intentIdentifiers: []
        )
        let away = UNNotificationCategory(
            identifier: NotificationPlanner.awayCategory,
            actions: [
                UNNotificationAction(identifier: NotificationAction.keepAway, title: "Keep"),
                UNNotificationAction(identifier: NotificationAction.discardAway, title: "Discard sleep time"),
            ],
            intentIdentifiers: []
        )
        let plain = UNNotificationCategory(identifier: NotificationPlanner.plainCategory, actions: [], intentIdentifiers: [])
        center.setNotificationCategories([longRun, away, plain])
    }
}

/// Outside the app bundle: nothing to post to.
@MainActor
final class UnavailableNotificationClient: NotificationCenterClient {
    func authorization() async -> NotificationAuthorization { .unavailable }
    func requestAuthorization() async -> Bool { false }
    func pending() async -> [String: String] { [:] }
    func delivered() async -> Set<String> { [] }
    func add(_ notification: PlannedNotification) async {}
    func removePending(_ ids: [String]) {}
    func removeDelivered(_ ids: [String]) {}
    func registerCategories() {}
}

@MainActor
final class TaskNotifications: ObservableObject {
    static let shared = TaskNotifications(
        client: UserNotificationClient.isAvailable ? UserNotificationClient() : UnavailableNotificationClient()
    )

    /// Settings › Notifications (saved in config.json by AppState)
    @Published var settings = NotificationSettings() {
        didSet { if settings != oldValue { scheduleSoon() } }
    }
    @Published private(set) var authorization: NotificationAuthorization = .notDetermined

    let client: NotificationCenterClient
    /// Waits this long after a change before rescheduling, so typing or a burst of edits is one pass
    var debounce: TimeInterval = 1
    var clock: () -> Date = Date.init
    private weak var store: TaskStore?
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var pendingPass: Task<Void, Never>?
    /// Immediate notifications sent this run (each only once)
    private(set) var posted: Set<String> = []

    init(client: NotificationCenterClient) {
        self.client = client
    }

    /// Follows the store from launch: every change reschedules (debounced), and so do a new day
    /// and waking from sleep.
    func start(store: TaskStore) {
        guard self.store == nil else { return }
        self.store = store
        client.registerCategories()
        // The sleep prompt (preferences.pendingAway) is part of the workspace
        store.$workspace.map { _ in () }
            .sink { [weak self] in self?.scheduleSoon() }
            .store(in: &subscriptions)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        scheduleSoon()
    }

    /// Reschedules after `debounce`; a newer call replaces a waiting one.
    func scheduleSoon() {
        pendingPass?.cancel()
        let delay = debounce
        pendingPass = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    /// Brings Notification Center in step with the plan now. Without permission (or with every
    /// notification off) FlowMate's pending ones are removed.
    func reschedule() async {
        authorization = await client.authorization()
        guard authorization != .unavailable else { return }
        let now = clock()
        var plan: [PlannedNotification] = []
        if authorization == .authorized, let store, store.isLoaded {
            plan = NotificationPlanner.plan(store.notificationInput(now: now), settings: settings, now: now)
        }
        let changes = NotificationPlanner.diff(pending: await client.pending(), delivered: await client.delivered(),
                                               plan: plan, posted: posted, now: now)
        guard !changes.isEmpty else { return }
        client.removePending(changes.removePending)
        client.removeDelivered(changes.removeDelivered)
        for notification in changes.add {
            await client.add(notification)
            if notification.fireDate == nil { posted.insert(notification.id) }
        }
        // Forget sent prompts that are over, so a new one with the same id could be sent again
        posted = posted.filter { id in plan.contains { $0.id == id } }
    }

    func refreshAuthorization() async {
        authorization = await client.authorization()
    }

    /// Turning a notification on: asks macOS the first time. Returns the state after.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> NotificationAuthorization {
        authorization = await client.authorization()
        if authorization == .notDetermined {
            _ = await client.requestAuthorization()
            authorization = await client.authorization()
        }
        scheduleSoon()
        return authorization
    }

    /// System Settings › Notifications, at FlowMate when it can.
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Responses

    /// Long-run and sleep prompts stay quiet while FlowMate is in front (its own prompt shows).
    static func presentsWhileActive(kind: String?) -> Bool {
        guard let kind = kind.flatMap(PlannedNotification.Kind.init(rawValue:)) else { return true }
        return !kind.onlyWhenInBackground
    }

    /// A click on a notification or one of its buttons. Returns what to open, if anything.
    @discardableResult
    func handle(action: String, userInfo: [AnyHashable: Any], store: TaskStore? = nil) -> NotificationTarget? {
        let store = store ?? self.store ?? .shared
        let taskId = (userInfo["taskId"] as? String).flatMap(UUID.init(uuidString:))
        switch action {
        case NotificationAction.keepGoing:
            if let taskId { store.keepRunning(taskId) }
            return nil
        case NotificationAction.pause:
            if let taskId { store.pauseTimer(taskId) }
            return nil
        case NotificationAction.keepAway:
            store.keepAwayTime()
            return nil
        case NotificationAction.discardAway:
            store.discardAwayTime()
            return nil
        case UNNotificationDismissActionIdentifier:
            return nil
        default:
            return (userInfo["target"] as? String).flatMap(NotificationTarget.init(stringValue:))
        }
    }

    /// Opens the main window on a notification's target.
    func open(_ target: NotificationTarget, store: TaskStore? = nil) {
        let store = store ?? self.store ?? .shared
        let model = TasksWindow.viewModel
        switch target {
        case .today:
            model.select(.today)
            TasksWindow.show(store: store)
        case let .task(id):
            TasksWindow.show(store: store, openTask: id)
        case let .milestone(id):
            model.showMilestone(id, store: store)
            TasksWindow.show(store: store)
        }
    }
}
