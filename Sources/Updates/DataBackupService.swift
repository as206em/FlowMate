import Foundation

/// Copies FlowMate's data (workspace, settings, project icons) into
/// <data folder>/Backups/<label>-<time>/ and puts a copy back on request.
///
/// Used before an update installs and from Settings › Updates. Logs and earlier backups are
/// never part of a backup. Every operation is synchronous and takes a plain folder, so tests can
/// run it on a scratch directory.
struct DataBackupService {
    struct Backup: Identifiable, Equatable {
        let url: URL
        let created: Date
        let sizeBytes: Int64
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    enum BackupError: LocalizedError {
        case nothingToBackUp
        case notABackup(URL)

        var errorDescription: String? {
            switch self {
            case .nothingToBackUp: return "There's no data to back up yet."
            case .notABackup(let url): return "\(url.lastPathComponent) isn't a FlowMate backup."
            }
        }
    }

    static let folderName = "Backups"
    /// Top-level items that are not data worth backing up
    private static let excluded: Set<String> = [folderName, "logs"]

    let dataDirectory: URL
    var backupsDirectory: URL { dataDirectory.appendingPathComponent(Self.folderName, isDirectory: true) }
    private var fileManager: FileManager { .default }

    init(dataDirectory: URL = AppDataLocation.directory) {
        self.dataDirectory = dataDirectory
    }

    /// Makes a new backup. `label` is usually the version being replaced ("1.1.0").
    @discardableResult
    func createBackup(label: String, now: Date = Date()) throws -> Backup {
        let items = try dataItems()
        guard !items.isEmpty else { throw BackupError.nothingToBackUp }

        let target = uniqueFolder(named: "\(Self.sanitized(label))-\(Self.stamp(now))")
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        do {
            for item in items {
                try fileManager.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
            }
        } catch {
            try? fileManager.removeItem(at: target)   // never leave half a backup that looks complete
            throw error
        }
        return Backup(url: target, created: now, sizeBytes: Self.size(of: target))
    }

    /// Existing backups, newest first.
    func backups() -> [Backup] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
        return urls.compactMap { url -> Backup? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return Backup(url: url, created: created, sizeBytes: Self.size(of: url))
        }
        .sorted { $0.created > $1.created }
    }

    /// Deletes all but the newest `keeping` backups.
    func prune(keeping: Int) {
        for old in backups().dropFirst(max(keeping, 1)) {
            try? fileManager.removeItem(at: old.url)
        }
    }

    /// Replaces the current data with a backup. The data as it is now is backed up first
    /// ("before-restore"), so a restore can itself be undone. FlowMate should be restarted after.
    func restore(_ backup: Backup, now: Date = Date()) throws {
        guard backup.url.deletingLastPathComponent().standardizedFileURL == backupsDirectory.standardizedFileURL,
              fileManager.fileExists(atPath: backup.url.appendingPathComponent("workspace.json").path)
                || fileManager.fileExists(atPath: backup.url.appendingPathComponent("config.json").path)
        else { throw BackupError.notABackup(backup.url) }

        _ = try? createBackup(label: "before-restore", now: now)
        for item in try dataItems() { try fileManager.removeItem(at: item) }
        for item in try fileManager.contentsOfDirectory(at: backup.url, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(at: item, to: dataDirectory.appendingPathComponent(item.lastPathComponent))
        }
    }

    // MARK: - Helpers

    private func dataItems() throws -> [URL] {
        guard fileManager.fileExists(atPath: dataDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)
            .filter { !Self.excluded.contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix(".") }
    }

    private func uniqueFolder(named name: String) -> URL {
        var url = backupsDirectory.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fileManager.fileExists(atPath: url.path) {
            url = backupsDirectory.appendingPathComponent("\(name)-\(n)", isDirectory: true)
            n += 1
        }
        return url
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    private static func sanitized(_ label: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return String(label.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private static func size(of url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
