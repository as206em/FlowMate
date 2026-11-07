import XCTest
@testable import FlowMate

/// Answers the cloud client's requests in tests. One handler for all requests, set per test.
final class CloudStubProtocol: URLProtocol {
    struct Recorded {
        var method: String
        var path: String
        var body: Data?
        var authorization: String?
    }

    static var handler: ((URLRequest, Data?) throws -> (Int, Data))?
    private static let lock = NSLock()
    private static var _requests: [Recorded] = []
    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); _requests = []; lock.unlock()
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.lock.lock()
        Self._requests.append(Recorded(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            body: body,
            authorization: request.value(forHTTPHeaderField: "Authorization")
        ))
        Self.lock.unlock()
        do {
            guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
            let (status, data) = try handler(request, body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class CloudSyncTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL { dir.appendingPathComponent("workspace.json") }
    private var stateURL: URL { dir.appendingPathComponent("sync-state.json") }
    private let workspaceId = "11111111-2222-3333-4444-555555555555"
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudSyncTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CloudStubProtocol.reset()
    }

    override func tearDown() {
        CloudStubProtocol.reset()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: - Helpers

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeRepository(token: String? = "fm_test", launchTimeout: TimeInterval = 4) -> SyncingWorkspaceRepository {
        SyncingWorkspaceRepository(
            local: LocalJSONWorkspaceRepository(fileURL: fileURL),
            stateURL: stateURL,
            tokenProvider: { token },
            session: session,
            pushDelay: 0.05,
            launchTimeout: launchTimeout
        )
    }

    /// A workspace whose first project has this name, so variants differ
    private func workspace(_ name: String) -> Workspace {
        var ws = Workspace.sample(now: t0)
        ws.projects[0].name = name
        return ws
    }

    private func writeLocal(_ ws: Workspace) async throws {
        try await LocalJSONWorkspaceRepository(fileURL: fileURL).save(ws)
    }

    private func readLocal() async throws -> Workspace? {
        try await LocalJSONWorkspaceRepository(fileURL: fileURL).load()
    }

    /// Sync turned on for the stub server; optionally already synced at `version` with `syncedWith`.
    private func writeState(version: Int = 0, syncedWith: Workspace? = nil) throws {
        var state = CloudSyncState()
        state.settings = CloudSyncSettings(enabled: true, serverURL: "https://sync.test", deviceName: "Test Mac")
        if version > 0 {
            state.syncedServerURL = "https://sync.test"
            state.workspaceId = workspaceId
            state.lastSyncedVersion = version
            state.lastSyncedHash = syncedWith.flatMap(WorkspaceHash.of)
        }
        try state.write(to: stateURL)
    }

    private func readState() -> CloudSyncState? { CloudSyncState.read(from: stateURL) }

    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    private var meBody: Data {
        json(["user": ["id": "u1", "email": "me@example.com", "displayName": "Me"],
              "workspaces": [["id": workspaceId, "name": "Personal", "role": "owner", "snapshotVersion": NSNull()]]])
    }

    private func snapshotBody(_ ws: Workspace, version: Int, device: String = "Other Mac") -> Data {
        let data = try! LocalJSONWorkspaceRepository.makeEncoder().encode(ws)
        let object = try! JSONSerialization.jsonObject(with: data)
        return json(["version": version, "schemaVersion": ws.schemaVersion, "updatedAt": "2026-11-07T10:00:00.000Z",
                     "updatedByDevice": device, "data": object])
    }

    private func pushes() -> [CloudStubProtocol.Recorded] {
        CloudStubProtocol.requests.filter { $0.method == "PUT" }
    }

    private func bodyObject(_ recorded: CloudStubProtocol.Recorded) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: recorded.body ?? Data())) as? [String: Any] ?? [:]
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// A simple server: /v1/me, the snapshot (nil = 404) and PUT that bumps the version or 409s.
    private final class FakeServer {
        var snapshot: (version: Int, body: Data)?
        var conflictOnPut = false
        var lastPut: [String: Any]?

        func handle(_ request: URLRequest, _ body: Data?, me: Data, render: (Data, Int) -> Data) -> (Int, Data) {
            let path = request.url?.path ?? ""
            if path == "/v1/me" { return (200, me) }
            if request.httpMethod == "GET" {
                guard let snapshot else { return (404, Data(#"{"error":"no_snapshot"}"#.utf8)) }
                return (200, snapshot.body)
            }
            let object = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] ?? [:]
            lastPut = object
            let base = (object["baseVersion"] as? Int) ?? -1
            let force = (object["force"] as? Bool) ?? false
            let current = snapshot?.version ?? 0
            if conflictOnPut || (!force && base != current) {
                return (409, Data(#"{"error":"version_conflict","currentVersion":\#(current),"updatedAt":"2026-11-07T10:00:00Z","updatedByDevice":"Other Mac"}"#.utf8))
            }
            let next = current + 1
            let data = try! JSONSerialization.data(withJSONObject: object["data"] ?? [:])
            snapshot = (next, render(data, next))
            return (200, Data(#"{"version":\#(next),"updatedAt":"2026-11-07T10:00:00Z"}"#.utf8))
        }
    }

    private func install(_ server: FakeServer) {
        let me = meBody
        CloudStubProtocol.handler = { request, body in
            server.handle(request, body, me: me) { data, version in
                let object = try! JSONSerialization.jsonObject(with: data)
                return try! JSONSerialization.data(withJSONObject: [
                    "version": version, "schemaVersion": Workspace.currentSchemaVersion,
                    "updatedAt": "2026-11-07T10:00:00Z", "updatedByDevice": "Test Mac", "data": object
                ])
            }
        }
    }

    // MARK: - Sync off

    func testSyncOffIsPlainLocalStorage() async throws {
        let repo = makeRepository()
        let missing = try await repo.load()
        XCTAssertNil(missing)
        let ws = workspace("Alpha")
        try await repo.save(ws)
        let loaded = try await repo.load()
        let onDisk = try await readLocal()
        XCTAssertEqual(loaded, onDisk)
        XCTAssertEqual(loaded?.projects[0].name, "Alpha")
        XCTAssertTrue(CloudStubProtocol.requests.isEmpty, "No network with sync off")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path), "No sync file until sync is set up")
        XCTAssertEqual(repo.location, fileURL)
    }

    func testSyncOnWithoutTokenStaysLocal() async throws {
        try writeState()
        try await writeLocal(workspace("Alpha"))
        let repo = makeRepository(token: nil)
        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "Alpha")
        XCTAssertTrue(CloudStubProtocol.requests.isEmpty)
    }

    // MARK: - Push

    func testFirstLaunchPushesWhenCloudIsEmptyThenPushesSaves() async throws {
        try writeState()
        try await writeLocal(workspace("Alpha"))
        let server = FakeServer()
        install(server)
        let repo = makeRepository()

        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "Alpha")
        XCTAssertEqual(pushes().count, 1)
        XCTAssertEqual(bodyObject(pushes()[0])["baseVersion"] as? Int, 0)
        XCTAssertEqual(bodyObject(pushes()[0])["deviceName"] as? String, "Test Mac")
        XCTAssertEqual(pushes()[0].authorization, "Bearer fm_test")
        XCTAssertEqual(readState()?.lastSyncedVersion, 1)
        XCTAssertEqual(readState()?.workspaceId, workspaceId)

        // A save is pushed a moment later, on top of version 1
        try await repo.save(workspace("Beta"))
        await waitUntil { self.pushes().count == 2 }
        XCTAssertEqual(pushes().count, 2)
        XCTAssertEqual(bodyObject(pushes()[1])["baseVersion"] as? Int, 1)
        let pushed = bodyObject(pushes()[1])["data"] as? [String: Any]
        XCTAssertEqual(((pushed?["projects"] as? [[String: Any]])?.first)?["name"] as? String, "Beta")
        await waitUntil { self.readState()?.lastSyncedVersion == 2 }
        XCTAssertEqual(readState()?.lastSyncedVersion, 2)
        let status = await repo.currentStatus()
        XCTAssertEqual(status.localDirty, false)
        XCTAssertNil(status.state.conflict)
    }

    func testSaveWithoutChangesDoesNotPush() async throws {
        let ws = workspace("Alpha")
        try writeState(version: 3, syncedWith: ws)
        try await writeLocal(ws)
        let server = FakeServer()
        server.snapshot = (3, snapshotBody(ws, version: 3))
        install(server)
        let repo = makeRepository()
        _ = try await repo.load()
        try await repo.save(ws)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(pushes().isEmpty)
    }

    // MARK: - Conflicts

    func testPushConflictKeepsBothSides() async throws {
        let ws = workspace("Alpha")
        try writeState(version: 1, syncedWith: ws)
        try await writeLocal(ws)
        let server = FakeServer()
        server.snapshot = (1, snapshotBody(ws, version: 1))
        install(server)
        let repo = makeRepository()
        _ = try await repo.load()

        // Another device pushes version 2 meanwhile
        server.snapshot = (2, snapshotBody(workspace("Other"), version: 2))
        try await repo.save(workspace("Mine"))
        await waitUntil { self.readState()?.conflict != nil }

        XCTAssertEqual(readState()?.conflict?.cloudVersion, 2)
        XCTAssertEqual(readState()?.conflict?.updatedByDevice, "Other Mac")
        XCTAssertEqual(readState()?.lastSyncedVersion, 1)
        let localName = try await readLocal()?.projects[0].name
        XCTAssertEqual(localName, "Mine", "The local save is kept")
        XCTAssertEqual(server.snapshot?.version, 2, "The cloud copy isn't overwritten")

        // Further saves wait for the user's choice
        let before = pushes().count
        try await repo.save(workspace("Mine again"))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(pushes().count, before)
    }

    func testLaunchWithBothSidesChangedIsAConflict() async throws {
        let synced = workspace("Synced")
        try writeState(version: 1, syncedWith: synced)
        try await writeLocal(workspace("Local edit"))
        let server = FakeServer()
        server.snapshot = (2, snapshotBody(workspace("Cloud edit"), version: 2))
        install(server)
        let repo = makeRepository()

        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "Local edit")
        XCTAssertEqual(readState()?.conflict?.cloudVersion, 2)
        XCTAssertTrue(pushes().isEmpty)
        let localName = try await readLocal()?.projects[0].name
        XCTAssertEqual(localName, "Local edit")
    }

    func testFirstSyncWithDataOnBothSidesIsAConflict() async throws {
        try writeState()
        try await writeLocal(workspace("This Mac"))
        let server = FakeServer()
        server.snapshot = (5, snapshotBody(workspace("Cloud"), version: 5))
        install(server)
        let repo = makeRepository()

        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "This Mac")
        XCTAssertEqual(readState()?.conflict?.cloudVersion, 5)
        XCTAssertTrue(pushes().isEmpty, "A non-empty cloud copy is never silently overwritten")
    }

    func testKeepThisMacCopyForcePushes() async throws {
        let synced = workspace("Synced")
        try writeState(version: 1, syncedWith: synced)
        try await writeLocal(workspace("Local edit"))
        let server = FakeServer()
        server.snapshot = (2, snapshotBody(workspace("Cloud edit"), version: 2))
        install(server)
        let repo = makeRepository()
        _ = try await repo.load()
        XCTAssertNotNil(readState()?.conflict)

        try await repo.keepThisMacCopy()
        XCTAssertEqual(server.lastPut?["force"] as? Bool, true)
        XCTAssertNil(readState()?.conflict)
        XCTAssertEqual(readState()?.lastSyncedVersion, 3)
        let cloud = try XCTUnwrap(server.snapshot)
        let cloudWorkspace = try CloudSnapshot.decode(cloud.body).workspace()
        XCTAssertEqual(cloudWorkspace.projects[0].name, "Local edit")
    }

    func testUseCloudCopyReplacesLocalAndKeepsTheOldFile() async throws {
        let synced = workspace("Synced")
        try writeState(version: 1, syncedWith: synced)
        try await writeLocal(workspace("Local edit"))
        let server = FakeServer()
        server.snapshot = (2, snapshotBody(workspace("Cloud edit"), version: 2))
        install(server)
        let repo = makeRepository()
        _ = try await repo.load()

        let cloud = try await repo.useCloudCopy()
        XCTAssertEqual(cloud.projects[0].name, "Cloud edit")
        let localName = try await readLocal()?.projects[0].name
        XCTAssertEqual(localName, "Cloud edit")
        XCTAssertNil(readState()?.conflict)
        XCTAssertEqual(readState()?.lastSyncedVersion, 2)
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("before-cloud") }
        XCTAssertEqual(kept.count, 1)
    }

    // MARK: - Pull

    func testLaunchPullsNewerCloudCopyWhenLocalIsUnchanged() async throws {
        let synced = workspace("Synced")
        try writeState(version: 1, syncedWith: synced)
        try await writeLocal(synced)
        let server = FakeServer()
        server.snapshot = (4, snapshotBody(workspace("From iPad"), version: 4))
        install(server)
        let repo = makeRepository()

        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "From iPad")
        let localName = try await readLocal()?.projects[0].name
        XCTAssertEqual(localName, "From iPad", "Saved locally too")
        XCTAssertEqual(readState()?.lastSyncedVersion, 4)
        XCTAssertNil(readState()?.conflict)
        XCTAssertTrue(pushes().isEmpty)
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("before-cloud") }
        XCTAssertEqual(kept.count, 1, "The replaced file is kept")
    }

    func testNewMacWithNoDataTakesTheCloudCopy() async throws {
        try writeState()
        let server = FakeServer()
        server.snapshot = (7, snapshotBody(workspace("Cloud"), version: 7))
        install(server)
        let repo = makeRepository()

        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "Cloud")
        XCTAssertEqual(readState()?.lastSyncedVersion, 7)
    }

    func testTaskStoreLoadShowsThePulledCopy() async throws {
        let synced = workspace("Synced")
        try writeState(version: 1, syncedWith: synced)
        try await writeLocal(synced)
        let server = FakeServer()
        server.snapshot = (2, snapshotBody(workspace("Pulled"), version: 2))
        install(server)
        let store = await TaskStore(repository: makeRepository(), saveDelay: 0)
        await store.load()
        let name = await store.workspace.projects[0].name
        XCTAssertEqual(name, "Pulled")
    }

    // MARK: - Offline

    func testOfflineLaunchUsesLocalData() async throws {
        let synced = workspace("Synced")
        try writeState(version: 1, syncedWith: synced)
        try await writeLocal(workspace("Local edit"))
        CloudStubProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }
        let repo = makeRepository()

        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "Local edit")
        let status = await repo.currentStatus()
        XCTAssertTrue(status.isOffline)
        XCTAssertEqual(status.localDirty, true)
        XCTAssertNil(status.state.conflict)
        XCTAssertEqual(readState()?.lastSyncedVersion, 1)

        // Back online: Sync now pushes the change on top of version 1
        let server = FakeServer()
        server.snapshot = (1, snapshotBody(synced, version: 1))
        install(server)
        let replaced = await repo.syncNow()
        XCTAssertNil(replaced)
        XCTAssertEqual(server.lastPut?["baseVersion"] as? Int, 1)
        XCTAssertEqual(readState()?.lastSyncedVersion, 2)
        let after = await repo.currentStatus()
        XCTAssertFalse(after.isOffline)
        XCTAssertEqual(after.localDirty, false)
    }

    func testSlowServerDoesNotHoldUpLaunch() async throws {
        try writeState(version: 1, syncedWith: workspace("Synced"))
        try await writeLocal(workspace("Local"))
        CloudStubProtocol.handler = { _, _ in
            Thread.sleep(forTimeInterval: 2)
            throw URLError(.timedOut)
        }
        let repo = makeRepository(launchTimeout: 0.2)
        let start = Date()
        let loaded = try await repo.load()
        XCTAssertEqual(loaded?.projects[0].name, "Local")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    // MARK: - Client

    func testErrorsMapFromStatusCodes() {
        XCTAssertEqual(CloudSyncError.from(status: 401, body: Data()), .unauthorized)
        XCTAssertEqual(CloudSyncError.from(status: 404, body: Data(#"{"error":"no_snapshot"}"#.utf8)), .noSnapshot)
        XCTAssertEqual(CloudSyncError.from(status: 404, body: Data(#"{"error":"not_found"}"#.utf8)), .notFound)
        XCTAssertEqual(CloudSyncError.from(status: 404, body: Data("404 page not found".utf8)), .notAPI)
        XCTAssertEqual(CloudSyncError.from(status: 413, body: Data()), .tooLarge)
        if case let .conflict(conflict) = CloudSyncError.from(status: 409, body: Data(#"{"error":"version_conflict","currentVersion":9,"updatedByDevice":"iPad"}"#.utf8)) {
            XCTAssertEqual(conflict.cloudVersion, 9)
            XCTAssertEqual(conflict.updatedByDevice, "iPad")
        } else {
            XCTFail("Expected a conflict")
        }
    }

    func testBaseURLNormalization() {
        XCTAssertEqual(CloudSyncClient.baseURL(from: " https://api.example.com/ ")?.absoluteString, "https://api.example.com")
        XCTAssertNil(CloudSyncClient.baseURL(from: "api.example.com"))
        XCTAssertNil(CloudSyncClient.baseURL(from: ""))
        XCTAssertNil(CloudSyncClient.baseURL(from: "ftp://x.com"))
    }

    func testPushBodyCarriesTheWorkspaceBytesUnchanged() throws {
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(workspace("Alpha"))
        let body = CloudSyncClient.pushBody(workspaceJSON: data, schemaVersion: 14, baseVersion: 3, deviceName: "Asem's \"Mac\"", force: false)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["baseVersion"] as? Int, 3)
        XCTAssertEqual(object["deviceName"] as? String, "Asem's \"Mac\"")
        XCTAssertEqual(object["force"] as? Bool, false)
        XCTAssertTrue(body.range(of: data) != nil)
    }

    func testTestConnectionReadsMe() async throws {
        install(FakeServer())
        let me = try await makeRepository().testConnection(serverURL: "https://sync.test/", token: "fm_abc")
        XCTAssertEqual(me.user.displayName, "Me")
        XCTAssertEqual(me.primaryWorkspace?.name, "Personal")
        XCTAssertEqual(CloudStubProtocol.requests.last?.authorization, "Bearer fm_abc")
    }
}
