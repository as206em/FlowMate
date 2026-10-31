import AppKit
import Foundation

// Sleep and screen lock. Timers keep counting while the Mac sleeps or sits locked (they store when
// they started). When that lasted a while, a quiet prompt asks: "Timers ran while your Mac slept
// 2h 05m · Keep · Discard sleep time". Discard takes the away time out of those timers' sessions.

/// A stretch the Mac was asleep or locked while timers ran.
struct AwayGap: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case sleep, locked }

    let id: UUID
    let start: Date
    let end: Date
    let kind: Kind
    /// Timers that ran through it
    let taskIds: [UUID]

    init(id: UUID = UUID(), start: Date, end: Date, kind: Kind, taskIds: [UUID]) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.taskIds = taskIds
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// Follows sleep, wake, lock and unlock and says when an away stretch is over. Away starts at
/// sleep or lock, whichever comes first; it ends at wake, or at unlock when the screen was locked
/// (a Mac that wakes to the lock screen isn't back until you unlock it).
struct AwayTracker: Equatable, Sendable {
    private(set) var start: Date?
    private(set) var slept = false
    private(set) var locked = false

    mutating func willSleep(at time: Date) {
        if start == nil { start = time }
        slept = true
    }

    /// The finished stretch, if wake ends it.
    mutating func didWake(at time: Date) -> (start: Date, end: Date, kind: AwayGap.Kind)? {
        guard !locked else { return nil }
        return finish(at: time)
    }

    mutating func screenLocked(at time: Date) {
        if start == nil { start = time }
        locked = true
    }

    mutating func screenUnlocked(at time: Date) -> (start: Date, end: Date, kind: AwayGap.Kind)? {
        locked = false
        return finish(at: time)
    }

    private mutating func finish(at time: Date) -> (start: Date, end: Date, kind: AwayGap.Kind)? {
        defer { start = nil; slept = false }
        guard let start, time > start else { return nil }
        return (start, time, slept ? .sleep : .locked)
    }
}

extension TaskStore {
    /// Away stretches shorter than this don't ask (a quick lock, a short nap).
    static let awayPromptThreshold: TimeInterval = 5 * 60

    func systemWillSleep(at time: Date = Date()) { away.willSleep(at: time) }
    func systemDidWake(at time: Date = Date()) { record(away.didWake(at: time)) }
    func screenDidLock(at time: Date = Date()) { away.screenLocked(at: time) }
    func screenDidUnlock(at time: Date = Date()) { record(away.screenUnlocked(at: time)) }

    /// Remembers a finished away stretch when timers that started before it still run and it
    /// lasted long enough to ask about.
    private func record(_ stretch: (start: Date, end: Date, kind: AwayGap.Kind)?) {
        guard let stretch, stretch.end.timeIntervalSince(stretch.start) >= Self.awayPromptThreshold else { return }
        let ids = runningTasks.map(\.id).filter { (startedAt($0) ?? .distantFuture) < stretch.start }
        guard !ids.isEmpty else { return }
        awayGaps.append(AwayGap(start: stretch.start, end: stretch.end, kind: stretch.kind, taskIds: ids))
    }

    /// Total away time waiting for an answer.
    var awayDuration: TimeInterval { awayGaps.reduce(0) { $0 + $1.duration } }

    /// The tasks the prompt names, in timer order, without repeats.
    var awayTasks: [TaskItem] {
        var seen = Set<UUID>()
        return awayGaps.flatMap(\.taskIds).filter { seen.insert($0).inserted }.compactMap { task($0) }
    }

    /// "Keep": the time counts as tracked.
    func keepAwayTime() {
        awayGaps.removeAll()
    }

    /// "Discard sleep time": each timer that ran through the gap loses it. A running session is
    /// split (an entry ending when the Mac went to sleep, the timer going on from wake); a session
    /// already stopped since is cut the same way. One undo step.
    func discardAwayTime() {
        let gaps = awayGaps
        awayGaps.removeAll()
        guard !gaps.isEmpty else { return }
        let kind = gaps.contains { $0.kind == .sleep } ? "sleep" : "away"
        mutate("Discard \(kind) time") { ws in
            for gap in gaps {
                for id in gap.taskIds where ws.tasks.contains(where: { $0.id == id }) {
                    ws.removeTrackedTime(id, in: gap.interval)
                }
            }
        }
    }
}

/// Watches NSWorkspace sleep/wake and the screen lock for the app's task store.
@MainActor
final class SystemAwayMonitor {
    static let shared = SystemAwayMonitor()
    private var tokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    func start(store: TaskStore) {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.systemWillSleep() }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.systemDidWake() }
        })
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.screenDidLock() }
        })
        distributedTokens.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.screenDidUnlock() }
        })
    }
}
