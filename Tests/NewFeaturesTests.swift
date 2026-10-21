import XCTest
@testable import FlowMate

@MainActor
final class NewFeaturesTests: XCTestCase {
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-features-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: configURL)
        super.tearDown()
    }

    // MARK: - API key storage

    func testAPIKeyIsNotWrittenToConfigFile() throws {
        let store = InMemorySecretStore()
        let manager = ConfigurationManager(configURL: configURL, secretStore: store)
        manager.updateProvidersConfig { $0.openai.apiKey = "sk-secret-123" }

        let fileContents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(fileContents.contains("sk-secret-123"))
        XCTAssertEqual(store.secret(for: "openai-api-key"), "sk-secret-123")
        XCTAssertEqual(manager.config.providers.openai.apiKey, "sk-secret-123")

        // A new instance reads the key back from the store
        let reloaded = ConfigurationManager(configURL: configURL, secretStore: store)
        XCTAssertEqual(reloaded.config.providers.openai.apiKey, "sk-secret-123")
    }

    func testKeyInOldConfigFileIsMovedToStore() throws {
        // Write a config file the way older versions did, with the key inside
        let store = InMemorySecretStore()
        let writer = ConfigurationManager(configURL: configURL, secretStore: InMemorySecretStore())
        writer.saveConfiguration()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        var providers = try XCTUnwrap(json["providers"] as? [String: Any])
        var openai = try XCTUnwrap(providers["openai"] as? [String: Any])
        openai["apiKey"] = "sk-old-key"
        providers["openai"] = openai
        json["providers"] = providers
        try JSONSerialization.data(withJSONObject: json).write(to: configURL)
        XCTAssertTrue(try String(contentsOf: configURL, encoding: .utf8).contains("sk-old-key"))

        let manager = ConfigurationManager(configURL: configURL, secretStore: store)
        XCTAssertEqual(manager.config.providers.openai.apiKey, "sk-old-key")
        XCTAssertEqual(store.secret(for: "openai-api-key"), "sk-old-key")
        let migrated = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(migrated.contains("sk-old-key"))
    }

    func testDeleteConfigurationRemovesStoredKey() {
        let store = InMemorySecretStore()
        let manager = ConfigurationManager(configURL: configURL, secretStore: store)
        manager.updateProvidersConfig { $0.openai.apiKey = "sk-delete-me" }
        manager.deleteConfiguration()
        XCTAssertNil(store.secret(for: "openai-api-key"))
    }

    func testDefaultPromptIsUsedForNewConfig() {
        let manager = ConfigurationManager(configURL: configURL)
        XCTAssertEqual(manager.config.proofreading.defaultPrompt, ConfigurationManager.defaultPrompt)
    }

    // MARK: - General settings

    func testAppearanceAndHistorySettingsPersist() {
        let manager = ConfigurationManager(configURL: configURL)
        let appState = AppState(configurationManager: manager, statusManager: StatusManager())

        appState.updateAppearance("dark")
        appState.updateMaxHistoryItems(150) // clamped to 100
        XCTAssertEqual(manager.getAppSettings().theme, "dark")
        XCTAssertEqual(appState.maxHistoryItems, 100)
        XCTAssertEqual(manager.getAppSettings().maxHistoryItems, 100)

        appState.updateAppearance("system")
        appState.updateMaxHistoryItems(-3) // clamped to 0
        XCTAssertEqual(appState.maxHistoryItems, 0)
    }

    func testHistoryPreviewIsShortSingleLine() {
        let item = ProofreadingHistoryItem(date: Date(), original: "a", corrected: String(repeating: "word ", count: 30) + "\nsecond line")
        XCTAssertFalse(item.preview.contains("\n"))
        XCTAssertTrue(item.preview.hasSuffix("…"))
        XCTAssertLessThanOrEqual(item.preview.count, 51)
    }

    func testSwitchingProviderClearsOldModels() {
        let manager = ConfigurationManager(configURL: configURL)
        let appState = AppState(configurationManager: manager, statusManager: StatusManager())
        appState.availableModels = ["gemma3:4b"]
        appState.setProvider(.openai)
        XCTAssertTrue(appState.availableModels.isEmpty)
        XCTAssertEqual(appState.connectionState, .checking)
    }

    // MARK: - Status icon

    func testDisconnectedIdleStateShowsAfterTimeout() async {
        let statusManager = StatusManager()
        statusManager.setIdleState(.disconnected)
        XCTAssertEqual(statusManager.currentIcon, StatusState.disconnected.iconName)

        statusManager.updateStatus(state: .success, priority: .proofreading, timeout: 0.1)
        XCTAssertEqual(statusManager.state, .success)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(statusManager.state, .disconnected)

        statusManager.setIdleState(.idle)
        XCTAssertEqual(statusManager.currentIcon, StatusState.idle.iconName)
    }

    func testIdleStateDoesNotOverrideActiveProofreading() {
        let statusManager = StatusManager()
        statusManager.updateStatus(state: .processing, priority: .proofreading)
        statusManager.setIdleState(.disconnected)
        XCTAssertEqual(statusManager.state, .processing)
    }

    // MARK: - Shortcut labels

    func testShortcutDisplayString() {
        XCTAssertEqual(KeyboardShortcutManager.displayString(for: "command+."), "⌘.")
        XCTAssertEqual(KeyboardShortcutManager.displayString(for: "command+shift+p"), "⇧⌘P")
        XCTAssertEqual(KeyboardShortcutManager.displayString(for: "ctrl+alt+space"), "⌃⌥Space")
    }
}
