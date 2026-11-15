import AppKit

extension TaskStore {
    /// Moves `currentDay` to the day of `now`. Returns true when the day changed, which
    /// republishes the store so date-based views rebuild. `force` republishes on the same day
    /// too (the system clock or time zone changed, so times within the day may have moved).
    @discardableResult
    func refreshDay(now: Date = Date(), calendar: Calendar = .current, force: Bool = false) -> Bool {
        let day = calendar.startOfDay(for: now)
        if day != currentDay {
            currentDay = day
            return true
        }
        if force { objectWillChange.send() }
        return false
    }
}

/// Tells the store when the clock has moved in a way views can't notice on their own: views
/// rebuild only when data changes, so without this a list built yesterday stays as it was
/// (yesterday's done tasks still in Today focus) until something is edited.
///
/// Checks at midnight, after waking from sleep, when the app comes to the front or the menu
/// opens, and when the system clock or time zone changes.
@MainActor
final class DayClock {
    static let shared = DayClock()

    private weak var store: TaskStore?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var midnightTimer: Timer?

    func start(store: TaskStore) {
        guard tokens.isEmpty else { return }
        self.store = store
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(center, .NSCalendarDayChanged) { $0.check() }
        observe(center, NSApplication.didBecomeActiveNotification) { $0.check() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.check() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.check() }
        observe(center, .NSSystemClockDidChange) { $0.check(force: true) }
        observe(center, .NSSystemTimeZoneDidChange) { $0.check(force: true) }
        check()
    }

    /// Brings the store to today and sets the next midnight check.
    func check(force: Bool = false) {
        store?.refreshDay(force: force)
        scheduleMidnight()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (DayClock) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        tokens.append((center, token))
    }

    /// A timer for just after the next midnight, in case NSCalendarDayChanged doesn't arrive.
    /// (Timers don't fire during sleep; the wake check covers that.)
    private func scheduleMidnight(calendar: Calendar = .current) {
        midnightTimer?.invalidate()
        let now = Date()
        guard let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 1),
                                           matchingPolicy: .nextTime) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
