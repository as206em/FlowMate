import SwiftUI
import Combine
import AppKit
import ApplicationServices
import ServiceManagement

/// Whether the active AI provider can be reached
enum ConnectionState: Equatable {
    case checking
    case connected(modelCount: Int)
    case failed(String)
}

/// One finished proofreading run, kept in memory for the "Recent" menu
struct ProofreadingHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let original: String
    let corrected: String

    /// Short single-line label for menus
    var preview: String {
        let singleLine = corrected.components(separatedBy: .newlines).joined(separator: " ")
        return singleLine.count > 50 ? String(singleLine.prefix(50)) + "…" : singleLine
    }
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var currentPrompt: String = ""
    @Published var availableModels: [String] = []
    @Published var isProcessing: Bool = false
    @Published var correctedText: String = ""
    @Published var originalText: String = ""
    /// Set when the last proofreading run failed; the dialog shows it with a Retry button
    @Published var proofreadingError: String?
    @Published var ollamaURL: String = ""
    @Published var openAIURL: String = ""
    @Published var openAIAPIKey: String = ""
    @Published var keyboardShortcut: String = ""
    /// Set when the typed shortcut can't be used; the last valid shortcut stays active.
    @Published var shortcutError: String?
    @Published var showDiffByDefault: Bool = true
    @Published var showDialog: Bool = true
    @Published var proofreadingProvider: AIProvider = .ollama
    @Published var proofreadingModel: String = ""
    @Published var aiService: AIService!
    @Published private(set) var connectionState: ConnectionState = .checking
    @Published private(set) var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    @Published private(set) var history: [ProofreadingHistoryItem] = []
    @Published private(set) var appearance: String = "system"
    @Published private(set) var maxHistoryItems: Int = 50
    @Published private(set) var launchAtLogin: Bool = false
    @Published var launchAtLoginError: String?

    // Backward compatibility computed properties
    var currentModel: String {
        get { proofreadingModel }
        set { proofreadingModel = newValue }
    }

    var currentProvider: AIProvider {
        get { proofreadingProvider }
        set { proofreadingProvider = newValue }
    }

    /// True when the provider is reachable but the selected model isn't installed/available
    var isSelectedModelMissing: Bool {
        if case .connected = connectionState {
            return !availableModels.isEmpty && !availableModels.contains(proofreadingModel)
        }
        return false
    }

    /// Models for the pickers: the available ones, plus the selected one if it's missing,
    /// so a picker always has a matching entry and never shows blank
    var modelChoices: [String] {
        var models = availableModels
        if !proofreadingModel.isEmpty && !models.contains(proofreadingModel) {
            models.insert(proofreadingModel, at: 0)
        }
        return models
    }

    /// True when the dialog's result can be pasted back into the app it came from
    var canReplace: Bool { replaceTargetApp != nil }

    // MARK: - Dependencies
    let configurationManager: ConfigurationManager
    private let statusManager: StatusManager

    // Service dependencies
    private let keyboardShortcutManager: KeyboardShortcutManagerProtocol
    private let clipboardService: ClipboardServiceProtocol
    private let promptBuilder: PromptBuilderProtocol
    private let proofreadingService: ProofreadingServiceProtocol

    /// The app the dialog's text came from (nil when proofreading the clipboard)
    private var replaceTargetApp: NSRunningApplication?
    private var proofreadingTask: Task<Void, Never>?
    private var connectionCheckID = 0
    /// After a failed check, when to try again (nil while connected). The wait doubles up to 10 minutes.
    private var nextConnectionRetry: Date?
    private var connectionRetryDelay: TimeInterval = 30
    private var monitorTask: Task<Void, Never>?

    private static let dialogWindowID = "proofreading-dialog"
    private static let settingsWindowID = "settings"

    init(
        configurationManager: ConfigurationManager? = nil,
        statusManager: StatusManager,
        keyboardShortcutManager: KeyboardShortcutManagerProtocol? = nil,
        clipboardService: ClipboardServiceProtocol? = nil,
        promptBuilder: PromptBuilderProtocol? = nil,
        proofreadingService: ProofreadingServiceProtocol? = nil
    ) {
        // Initialize dependencies
        self.configurationManager = configurationManager ?? ConfigurationManager()
        self.statusManager = statusManager
        self.keyboardShortcutManager = keyboardShortcutManager ?? KeyboardShortcutManager()
        self.clipboardService = clipboardService ?? ClipboardService()
        self.promptBuilder = promptBuilder ?? PromptBuilder()
        self.proofreadingService = proofreadingService ?? ProofreadingService()

        Logger.shared.info("AppState: Initializing")

        // Load configuration and initialize services
        loadConfiguration()
        updateAIService()
        setupKeyboardShortcut()
        checkConnection()
        refreshLaunchAtLogin()
        applyAppearance()
        startBackgroundMonitoring()

        Logger.shared.info("AppState: Initialized - Provider: \(proofreadingProvider.rawValue), Model: \(proofreadingModel)")
    }

    deinit {
        keyboardShortcutManager.removeShortcut()
        monitorTask?.cancel()
    }

    // MARK: - Configuration Management

    private func loadConfiguration() {
        let config = configurationManager.config

        // Proofreading settings
        proofreadingProvider = AIProvider(rawValue: config.proofreading.selectedProvider) ?? .ollama
        proofreadingModel = config.proofreading.selectedModel
        currentPrompt = config.proofreading.defaultPrompt
        keyboardShortcut = config.proofreading.keyboardShortcut
        showDiffByDefault = config.proofreading.showDiffByDefault
        showDialog = config.proofreading.showDialog

        // Provider settings
        ollamaURL = config.providers.ollama.url
        openAIURL = config.providers.openai.url
        openAIAPIKey = config.providers.openai.apiKey ?? ""

        // App settings
        appearance = config.app.theme
        maxHistoryItems = config.app.maxHistoryItems
    }

    private func updateAIService() {
        let configuration = AIConfiguration(
            ollamaURL: ollamaURL,
            openAIURL: openAIURL,
            openAIAPIKey: openAIAPIKey
        )

        aiService = AIServiceFactory.createService(
            for: proofreadingProvider,
            configuration: configuration
        )
    }

    // MARK: - Provider Management

    func setProvider(_ provider: AIProvider) {
        Logger.shared.info("AppState: Switching provider to \(provider.rawValue)")
        proofreadingProvider = provider

        configurationManager.updateProofreadingConfig { config in
            config.selectedProvider = provider.rawValue
        }

        // The old provider's models don't apply any more
        availableModels = []
        updateAIService()
        checkConnection()
    }

    @discardableResult
    private func setupKeyboardShortcut(_ shortcut: String? = nil) -> Bool {
        let shortcut = shortcut ?? keyboardShortcut
        let isValid = keyboardShortcutManager.setupShortcut(shortcut) { [weak self] in
            self?.handleProofreadingShortcut()
        }
        shortcutError = isValid ? nil : "\"\(shortcut)\" isn't a valid shortcut. Use a modifier plus one key, e.g. command+shift+p."
        return isValid
    }

    /// Checks whether the active provider is reachable and refreshes the model list.
    /// - Parameter quiet: when true, keeps showing the current state while checking (used by the periodic refresh)
    func checkConnection(quiet: Bool = false) {
        connectionCheckID += 1
        let checkID = connectionCheckID
        let service = aiService!
        let provider = proofreadingProvider
        if !quiet {
            connectionState = .checking
        }

        Task {
            if !quiet {
                Logger.shared.debug("AppState: Checking connection for provider: \(provider)")
            }
            do {
                let models = try await service.listModels()
                // Ignore results from a check that was superseded (e.g. provider changed meanwhile)
                guard checkID == self.connectionCheckID else { return }
                if !quiet || self.connectionState != .connected(modelCount: models.count) {
                    Logger.shared.info("AppState: Connection successful, got \(models.count) models")
                }
                self.availableModels = models
                self.connectionState = .connected(modelCount: models.count)
                self.statusManager.setIdleState(.idle)
                self.nextConnectionRetry = nil
                self.connectionRetryDelay = 30
            } catch {
                guard checkID == self.connectionCheckID else { return }
                if !quiet || self.connectionState == .checking {
                    Logger.shared.error("AppState: Connection failed - \(error.localizedDescription)")
                }
                self.connectionState = .failed(error.localizedDescription)
                self.statusManager.setIdleState(.disconnected)
                // Try again later, waiting longer each time
                self.nextConnectionRetry = Date().addingTimeInterval(self.connectionRetryDelay)
                self.connectionRetryDelay = min(self.connectionRetryDelay * 2, 600)
            }
        }
    }

    /// Checks the Accessibility permission every few seconds, and retries a failed connection
    /// with a growing wait. A working connection isn't polled; proofreading errors re-check it.
    private func startBackgroundMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                guard let self else { return }
                self.refreshAccessibilityPermission()
                if let retryAt = self.nextConnectionRetry, Date() >= retryAt {
                    self.nextConnectionRetry = nil
                    self.checkConnection(quiet: true)
                }
            }
        }
    }

    // MARK: - Accessibility Permission

    /// FlowMate needs Accessibility access to see the global shortcut and to copy/paste in other apps.
    func refreshAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        guard trusted != hasAccessibilityPermission else { return }
        hasAccessibilityPermission = trusted
        Logger.shared.info("AppState: Accessibility permission \(trusted ? "granted" : "missing")")
        if trusted {
            // A global key monitor created before access was granted doesn't receive events
            setupKeyboardShortcut()
        }
    }

    /// Shows the system's "allow Accessibility access" prompt if access is missing.
    static func promptForAccessibilityAccess() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the system prompt and opens the Accessibility pane in System Settings.
    func requestAccessibilityPermission() {
        Self.promptForAccessibilityAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Settings Updates

    /// Updates the URL of the given provider (defaults to the active one).
    func updateProviderURL(_ url: String, for provider: AIProvider? = nil) {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider ?? proofreadingProvider {
        case .ollama:
            ollamaURL = url
            configurationManager.updateProvidersConfig { $0.ollama.url = url }
        case .openai:
            openAIURL = url
            configurationManager.updateProvidersConfig { $0.openai.url = url }
        }
        updateAIService()
        checkConnection()
    }

    /// Saves all provider settings at once, then refreshes the active service a single time.
    func updateProviderSettings(ollamaURL: String, openAIURL: String, openAIAPIKey: String) {
        let ollamaURL = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let openAIURL = openAIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ollamaURL = ollamaURL
        self.openAIURL = openAIURL
        self.openAIAPIKey = openAIAPIKey
        configurationManager.updateProvidersConfig {
            $0.ollama.url = ollamaURL
            $0.openai.url = openAIURL
            $0.openai.apiKey = openAIAPIKey
        }
        updateAIService()
        checkConnection()
    }

    func updateKeyboardShortcut(_ shortcut: String) {
        // Only apply and save shortcuts that work. An invalid one sets shortcutError and the
        // current shortcut stays as it is, so the menu never shows a shortcut that isn't active.
        if setupKeyboardShortcut(shortcut) {
            keyboardShortcut = shortcut
            configurationManager.updateProofreadingConfig { $0.keyboardShortcut = shortcut }
        }
    }

    func updateCurrentPrompt(_ prompt: String) {
        currentPrompt = prompt
        configurationManager.updateProofreadingConfig { $0.defaultPrompt = prompt }
    }

    func updateCurrentModel(_ model: String) {
        proofreadingModel = model
        configurationManager.updateProofreadingConfig { $0.selectedModel = model }
    }

    func updateShowDiffByDefault(_ showDiff: Bool) {
        showDiffByDefault = showDiff
        configurationManager.updateProofreadingConfig { $0.showDiffByDefault = showDiff }
    }

    func updateShowDialog(_ showDialog: Bool) {
        self.showDialog = showDialog
        configurationManager.updateProofreadingConfig { $0.showDialog = showDialog }
    }

    func updateOpenAIAPIKey(_ apiKey: String) {
        openAIAPIKey = apiKey
        configurationManager.updateProvidersConfig { $0.openai.apiKey = apiKey }
        // Rebuild the service so the new key is used right away.
        updateAIService()
        if proofreadingProvider == .openai {
            checkConnection()
        }
    }

    // MARK: - General Settings

    /// "system", "light" or "dark"
    func updateAppearance(_ appearance: String) {
        self.appearance = appearance
        configurationManager.updateAppSettings { $0.theme = appearance }
        applyAppearance()
    }

    private func applyAppearance() {
        switch appearance {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: NSApplication.shared.appearance = nil
        }
    }

    /// How many recent results to keep in memory (0 turns history off)
    func updateMaxHistoryItems(_ count: Int) {
        let count = max(0, min(count, 100))
        maxHistoryItems = count
        configurationManager.updateAppSettings { $0.maxHistoryItems = count }
        if history.count > count {
            history = Array(history.prefix(count))
        }
    }

    func clearHistory() {
        history = []
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Logger.shared.info("AppState: Launch at login \(enabled ? "enabled" : "disabled")")
        } catch {
            Logger.shared.error("AppState: Failed to change launch at login", error: error)
            launchAtLoginError = "Couldn't change this: \(error.localizedDescription). Make sure FlowMate is running from the Applications folder."
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Proofreading Workflow

    func handleProofreadingShortcut() {
        guard !isProcessing else {
            Logger.shared.info("AppState: Ignoring shortcut - proofreading already in progress")
            return
        }

        // Remember the app the text comes from, so the result can go back there
        let sourceApp = NSWorkspace.shared.frontmostApplication

        // Get currently selected text
        guard let selectedText = clipboardService.getSelectedText() else {
            Logger.shared.warning("AppState: No text selected for proofreading")
            statusManager.updateStatus(
                state: .failure,
                priority: .proofreading,
                timeout: 3.0
            )
            return
        }

        Logger.shared.info("AppState: Starting proofreading - Text length: \(selectedText.count) characters")

        if showDialog {
            startDialogProofreading(text: selectedText, sourceApp: sourceApp)
        } else {
            startInlineProofreading(text: selectedText, sourceApp: sourceApp)
        }
    }

    /// Proofreads whatever text is on the clipboard and shows the result in the dialog.
    func proofreadClipboard() {
        guard !isProcessing else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.warning("AppState: Clipboard has no text to proofread")
            statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 3.0)
            return
        }
        startDialogProofreading(text: text, sourceApp: nil)
    }

    /// Runs the last text again (used by the dialog's Retry button).
    func retryProofreading() {
        guard !isProcessing, !originalText.isEmpty else { return }
        startDialogProofreading(text: originalText, sourceApp: replaceTargetApp)
    }

    /// Stops a running proofreading request and closes the dialog.
    func cancelProofreading() {
        proofreadingTask?.cancel()
        proofreadingTask = nil
        isProcessing = false
        statusManager.updateStatus(state: .idle, priority: .proofreading, timeout: 0.1)
        closeProofreadingDialog()
        Logger.shared.info("AppState: Proofreading cancelled by user")
    }

    /// Opens a past result in the dialog.
    func showHistoryItem(_ item: ProofreadingHistoryItem) {
        guard !isProcessing else { return }
        originalText = item.original
        correctedText = item.corrected
        proofreadingError = nil
        replaceTargetApp = nil
        showProofreadingDialog(nil)
    }

    private func startDialogProofreading(text: String, sourceApp: NSRunningApplication?) {
        originalText = text
        correctedText = ""
        proofreadingError = nil
        replaceTargetApp = sourceApp
        isProcessing = true
        statusManager.updateStatus(state: .processing, priority: .proofreading)
        showProofreadingDialog(nil)

        proofreadingTask = Task {
            let result = await runProofreading(text)
            guard !Task.isCancelled else { return }
            isProcessing = false

            switch result {
            case .success(let corrected):
                correctedText = corrected
                addToHistory(original: text, corrected: corrected)
                statusManager.updateStatus(state: .success, priority: .proofreading, timeout: 3.0)
            case .failure(let error):
                proofreadingError = error.localizedDescription
                statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 5.0)
                checkConnection(quiet: true) // the provider may have gone away
            }
        }
    }

    private func startInlineProofreading(text: String, sourceApp: NSRunningApplication?) {
        originalText = text
        isProcessing = true
        statusManager.updateStatus(state: .processing, priority: .proofreading)

        proofreadingTask = Task {
            let result = await runProofreading(text)
            guard !Task.isCancelled else { return }
            isProcessing = false

            switch result {
            case .success(let corrected):
                correctedText = corrected
                addToHistory(original: text, corrected: corrected)

                // If the user moved to another app while waiting, don't paste into the wrong place.
                // Leave the corrected text on the clipboard instead.
                let currentApp = NSWorkspace.shared.frontmostApplication
                guard sourceApp == nil || currentApp?.processIdentifier == sourceApp?.processIdentifier else {
                    clipboardService.copyToClipboard(corrected)
                    Logger.shared.warning("AppState: Focus moved to another app - corrected text left on clipboard instead of pasting")
                    statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 5.0)
                    return
                }

                await paste(corrected)
                statusManager.updateStatus(state: .success, priority: .proofreading, timeout: 2.0)
                Logger.shared.info("AppState: Text replaced successfully")

            case .failure(let error):
                correctedText = "Error: \(error.localizedDescription)"
                statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 5.0)
                checkConnection(quiet: true) // the provider may have gone away
                Logger.shared.error("AppState: Proofreading failed - \(error.localizedDescription)")
            }
        }
    }

    private func runProofreading(_ text: String) async -> ProofreadingResult {
        await proofreadingService.proofread(
            text: text,
            model: proofreadingModel,
            prompt: currentPrompt,
            aiService: aiService,
            promptBuilder: promptBuilder,
            maxRetries: 3
        )
    }

    private func addToHistory(original: String, corrected: String) {
        guard maxHistoryItems > 0 else { return }
        history.insert(ProofreadingHistoryItem(date: Date(), original: original, corrected: corrected), at: 0)
        if history.count > maxHistoryItems {
            history.removeLast(history.count - maxHistoryItems)
        }
    }

    /// Closes the dialog, switches back to the source app and pastes the (possibly edited) result
    /// over the still-selected original text.
    func replaceInSourceApp() {
        guard let targetApp = replaceTargetApp, !correctedText.isEmpty else { return }
        let text = correctedText
        closeProofreadingDialog()
        if #available(macOS 14.0, *) {
            targetApp.activate()
        } else {
            targetApp.activate(options: [])
        }

        Task {
            // Wait until the source app is in front again
            for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != targetApp.processIdentifier {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
                clipboardService.copyToClipboard(text)
                Logger.shared.warning("AppState: Couldn't return to \(targetApp.localizedName ?? "source app") - corrected text left on clipboard")
                statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 5.0)
                return
            }
            // Give the app a moment to restore focus to its text field
            try? await Task.sleep(nanoseconds: 150_000_000)
            await paste(text)
            statusManager.updateStatus(state: .success, priority: .proofreading, timeout: 2.0)
            Logger.shared.info("AppState: Replaced text in \(targetApp.localizedName ?? "source app")")
        }
    }

    /// Copies the dialog's (possibly edited) result to the clipboard.
    func copyResult() {
        clipboardService.copyToClipboard(correctedText)
    }

    /// Pastes text into the frontmost app, then puts the user's previous clipboard back.
    private func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        // Save everything on the clipboard (images, files, rich text), not just plain text
        let previousClipboard = pasteboard.snapshot()

        clipboardService.copyToClipboard(text)
        // Small delay to ensure clipboard is updated
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let changeCountAfterCopy = pasteboard.changeCount

        clipboardService.pasteFromClipboard()

        // Give the target app time to read the clipboard before restoring it.
        // Slow apps (Electron, browsers) can take several hundred milliseconds.
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s

        // Restore the previous clipboard only if nothing else changed it meanwhile
        if pasteboard.changeCount == changeCountAfterCopy {
            pasteboard.restore(previousClipboard)
        }
    }

    // MARK: - Window Management

    @objc func showProofreadingDialog(_ sender: Any?) {
        WindowManager.shared.showWindow(
            id: Self.dialogWindowID,
            title: "Proofreading Results",
            content: { ProofreadingDialog().environmentObject(self) },
            size: NSSize(width: 800, height: 500)
        )
    }

    func closeProofreadingDialog() {
        WindowManager.shared.closeWindow(id: Self.dialogWindowID)
    }

    @objc func showSettings(_ sender: Any?) {
        WindowManager.shared.showWindow(
            id: Self.settingsWindowID,
            title: "FlowMate Settings",
            content: { SettingsView().environmentObject(self) },
            size: NSSize(width: 880, height: 640)
        )
    }
}
