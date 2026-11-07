import XCTest
@testable import FlowMate

final class DataBackupServiceTests: XCTestCase {
    private var dir: URL!
    private var service: DataBackupService!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("flowmate-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try "tasks-v1".write(to: dir.appendingPathComponent("workspace.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "log".write(to: dir.appendingPathComponent("logs/a.log"), atomically: true, encoding: .utf8)
        service = DataBackupService(dataDirectory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testBackupCopiesDataButNotLogsOrBackups() throws {
        let first = try service.createBackup(label: "1.1.0")
        let second = try service.createBackup(label: "1.1.0")
        let names = try FileManager.default.contentsOfDirectory(atPath: second.url.path).sorted()
        XCTAssertEqual(names, ["config.json", "workspace.json"])
        XCTAssertNotEqual(first.url, second.url)
    }

    func testNothingToBackUpThrows() {
        let empty = DataBackupService(dataDirectory: dir.appendingPathComponent("missing"))
        XCTAssertThrowsError(try empty.createBackup(label: "x"))
    }

    func testPruneKeepsNewest() throws {
        for i in 0..<4 { _ = try service.createBackup(label: "v\(i)", now: Date(timeIntervalSince1970: Double(1_000 + i))) }
        service.prune(keeping: 2)
        XCTAssertEqual(service.backups().count, 2)
    }

    func testRestoreReplacesDataAndBacksUpCurrentFirst() throws {
        let backup = try service.createBackup(label: "1.0.0")
        try "tasks-v2".write(to: dir.appendingPathComponent("workspace.json"), atomically: true, encoding: .utf8)
        try service.restore(backup)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("workspace.json")), "tasks-v1")
        XCTAssertTrue(service.backups().contains { $0.name.hasPrefix("before-restore") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("logs/a.log").path))
    }

    func testRestoreRejectsFolderOutsideBackups() {
        let stray = DataBackupService.Backup(url: dir, created: Date(), sizeBytes: 0)
        XCTAssertThrowsError(try service.restore(stray))
    }
}
