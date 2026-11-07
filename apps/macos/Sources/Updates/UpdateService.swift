import Foundation
import AppKit
import Sparkle

/// Sparkle 2 wrapper: checks the appcast, installs updates, and backs up the data first.
///
/// Updates only work in the packaged app with a feed URL and a public EdDSA key in its Info.plist
/// (build-app.sh writes both). Under `swift run` or in tests `isAvailable` is false and nothing
/// starts, so Sparkle never complains about a missing bundle.
@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateService()

    private enum Keys {
        static let backupBeforeUpdate = "updates.backupBeforeUpdate"
        static let backupsToKeep = "updates.backupsToKeep"
    }

    @Published private(set) var lastBackup: DataBackupService.Backup?
    @Published private(set) var lastBackupError: String?
    @Published private(set) var backups: [DataBackupService.Backup] = []

    private var controller: SPUStandardUpdaterController?

    /// True when this build can update itself.
    var isAvailable: Bool { controller != nil }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    var backupBeforeUpdate: Bool {
        get { UserDefaults.standard.object(forKey: Keys.backupBeforeUpdate) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.backupBeforeUpdate); objectWillChange.send() }
    }

    var backupsToKeep: Int {
        get { max(UserDefaults.standard.object(forKey: Keys.backupsToKeep) as? Int ?? 5, 1) }
        set { UserDefaults.standard.set(max(newValue, 1), forKey: Keys.backupsToKeep); objectWillChange.send() }
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue; objectWillChange.send() }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    /// Starts Sparkle (once, at launch). Only in the released app: an update from the release feed
    /// would turn a dev build into the production app, on the production data. Not for a test
    /// copy running on other data either.
    func start() {
        guard controller == nil, AppChannel.current == .production, Self.canUpdate,
              AppDataLocation.override == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        refreshBackups()
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: - Backups

    func refreshBackups() {
        backups = DataBackupService().backups()
    }

    /// Flushes unsaved task changes, then copies the data into Backups/.
    @discardableResult
    func backUpNow(label: String? = nil) -> Bool {
        TaskStore.shared.flushBlocking()
        do {
            let service = DataBackupService()
            lastBackup = try service.createBackup(label: label ?? currentVersionLabel)
            lastBackupError = nil
            service.prune(keeping: backupsToKeep)
            refreshBackups()
            Logger.shared.info("Backed up data to \(lastBackup?.url.path ?? "?")")
            return true
        } catch {
            lastBackupError = error.localizedDescription
            Logger.shared.error("Backup failed", error: error)
            return false
        }
    }

    /// Puts a backup back and relaunches FlowMate on it.
    func restore(_ backup: DataBackupService.Backup) {
        do {
            TaskStore.shared.flushBlocking()
            try DataBackupService().restore(backup)
            Logger.shared.warning("Restored data from \(backup.url.path) - restarting")
            Self.relaunch()
        } catch {
            lastBackupError = error.localizedDescription
            Logger.shared.error("Restore failed", error: error)
        }
    }

    private var currentVersionLabel: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    // MARK: - SPUUpdaterDelegate

    /// Runs after the update is downloaded and verified, just before it replaces the app.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            guard backupBeforeUpdate else { return }
            // Name the backup after the version being replaced, so a rollback is easy to find
            backUpNow(label: "\(currentVersionLabel)-before-\(item.displayVersionString)")
        }
    }

    // MARK: - Packaging checks

    private static var canUpdate: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        let info = Bundle.main.infoDictionary
        let feed = info?["SUFeedURL"] as? String ?? ""
        let key = info?["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }

    private static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                          "flowmate-restart", String(pid), Bundle.main.bundleURL.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
