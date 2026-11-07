import XCTest
@testable import FlowMate

/// Two Macs syncing through a real FlowMate API. Skipped unless a server is given:
///   FLOWMATE_LIVE_API_URL=http://localhost:8080 FLOWMATE_LIVE_API_TOKEN=fm_… swift test --filter CloudSyncLiveTests
/// Use a fresh user (services/api CLI: create-user): the test writes to that user's workspace.
final class CloudSyncLiveTests: XCTestCase {
    private var root: URL!
    private var serverURL = ""
    private var token = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["FLOWMATE_LIVE_API_URL"], let token = env["FLOWMATE_LIVE_API_TOKEN"] else {
            throw XCTSkip("Set FLOWMATE_LIVE_API_URL and FLOWMATE_LIVE_API_TOKEN to run against a server")
        }
        serverURL = url
        self.token = token
        root = FileManager.default.temporaryDirectory.appendingPathComponent("flowmate-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// A Mac with its own data folder and sync turned on
    private func mac(_ name: String) throws -> SyncingWorkspaceRepository {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var state = CloudSyncState()
        state.settings = CloudSyncSettings(enabled: true, serverURL: serverURL, deviceName: name)
        try JSONEncoder().encode(state).write(to: dir.appendingPathComponent("sync-state.json"))
        let token = self.token
        return SyncingWorkspaceRepository(
            local: LocalJSONWorkspaceRepository(fileURL: dir.appendingPathComponent("workspace.json")),
            tokenProvider: { token },
            pushDelay: 0.05,
            launchTimeout: 10
        )
    }

    private func waitForPush(_ repo: SyncingWorkspaceRepository) async {
        for _ in 0..<100 {
            let status = await repo.currentStatus()
            if status.localDirty != true || status.state.conflict != nil { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testTwoMacsSyncAndConflict() async throws {
        let me = try await mac("A").testConnection(serverURL: serverURL, token: token)
        XCTAssertFalse(me.workspaces.isEmpty)

        // Mac A starts with data and pushes it (force, so a rerun on the same user starts clean)
        let a = try mac("A")
        var ws = Workspace.sample(now: Date())
        ws.projects[0].name = "From A"
        _ = try await a.load()
        try await a.save(ws)
        await waitForPush(a)
        if await a.currentStatus().state.conflict != nil { try await a.keepThisMacCopy() }

        // Mac B is new: it takes the cloud copy at launch
        let b = try mac("B")
        let onB = try await b.load()
        XCTAssertEqual(onB?.projects[0].name, "From A")

        // B edits and pushes; A has no changes, so its next launch pulls B's edit
        var edited = try XCTUnwrap(onB)
        edited.projects[0].name = "Edited on B"
        try await b.save(edited)
        await waitForPush(b)
        // Mac A relaunches (same data folder)
        let aAgain = SyncingWorkspaceRepository(
            local: LocalJSONWorkspaceRepository(fileURL: root.appendingPathComponent("A/workspace.json")),
            tokenProvider: { [token] in token },
            pushDelay: 0.05,
            launchTimeout: 10
        )
        let onA = try await aAgain.load()
        XCTAssertEqual(onA?.projects[0].name, "Edited on B")

        // Both edit without syncing in between: the second push is a conflict, nothing lost
        var fromA = try XCTUnwrap(onA)
        fromA.projects[0].name = "A again"
        var fromB = edited
        fromB.projects[0].name = "B again"
        try await b.save(fromB)
        await waitForPush(b)
        try await aAgain.save(fromA)
        await waitForPush(aAgain)
        let conflict = await aAgain.currentStatus().state.conflict
        XCTAssertNotNil(conflict)

        // A takes the cloud copy: B's edit wins on A
        let resolved = try await aAgain.useCloudCopy()
        XCTAssertEqual(resolved.projects[0].name, "B again")
        let after = await aAgain.currentStatus().state.conflict
        XCTAssertNil(after)
    }
}
