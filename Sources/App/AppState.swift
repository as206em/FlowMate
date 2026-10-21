import SwiftUI
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var currentPrompt: String = ""
    @Published var availableModels: [String] = []
    @Published var isProcessing: Bool = false
    @Published var correctedText: String = ""
    @Published var originalText: String = ""
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
    
    // Backward compatibility computed properties
    var currentModel: String {
        get { proofreadingModel }
        set { proofreadingModel = newValue }
    }
    
    var currentProvider: AIProvider {
        get { proofreadingProvider }
        set { proofreadingProvider = newValue }
    }
    
    // MARK: - Dependencies
    let configurationManager: ConfigurationManager
    private let statusManager: StatusManager
    
    // Service dependencies
    private let keyboardShortcutManager: KeyboardShortcutManagerProtocol
    private let clipboardService: ClipboardServiceProtocol
    private let promptBuilder: PromptBuilderProtocol
    private let proofreadingService: ProofreadingServiceProtocol
    
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
        
        Logger.shared.info("AppState: Initialized - Provider: \(proofreadingProvider.rawValue), Model: \(proofreadingModel)")
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
        
        updateAIService()
        checkConnection()
    }
    
    deinit {
        keyboardShortcutManager.removeShortcut()
    }
    
    @discardableResult
    private func setupKeyboardShortcut() -> Bool {
        let isValid = keyboardShortcutManager.setupShortcut(keyboardShortcut) { [weak self] in
            self?.handleProofreadingShortcut()
        }
        shortcutError = isValid ? nil : "\"\(keyboardShortcut)\" isn't a valid shortcut. Use a modifier plus one key, e.g. command+shift+p."
        return isValid
    }
    
    func checkConnection() {
        Task {
            Logger.shared.info("AppState: Checking connection for provider: \(proofreadingProvider)")
            do {
                let models = try await aiService.listModels()
                await MainActor.run {
                    Logger.shared.info("AppState: Connection successful, got \(models.count) models")
                    self.availableModels = models
                }
            } catch {
                await MainActor.run {
                    Logger.shared.error("AppState: Connection failed - \(error.localizedDescription)")
                }
            }
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
        keyboardShortcut = shortcut
        // Only save shortcuts that work, so an invalid one never survives a restart.
        if setupKeyboardShortcut() {
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
    
    // MARK: - Proofreading Workflow
    
    func handleProofreadingShortcut() {
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
        
        // Store original text for comparison
        self.originalText = selectedText
        
        // Update status to processing
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        // Check if dialog should be shown or inline replacement
        if showDialog {
            // Show dialog mode - display results with loading state
            self.correctedText = ""
            self.isProcessing = true
            self.showProofreadingDialog(nil)
            
            // Perform proofreading using the service
            Task {
                let result = await proofreadingService.proofread(
                    text: selectedText,
                    model: proofreadingModel,
                    prompt: currentPrompt,
                    aiService: aiService,
                    promptBuilder: promptBuilder,
                    maxRetries: 3
                )
                
                await MainActor.run {
                    self.isProcessing = false
                    
                    switch result {
                    case .success(let correctedText):
                        self.correctedText = correctedText
                        
                        // Update status to success with 3 second timeout
                        self.statusManager.updateStatus(
                            state: .success,
                            priority: .proofreading,
                            timeout: 3.0
                        )
                        
                    case .failure(let error):
                        self.correctedText = "Error: \(error.localizedDescription)"
                        
                        // Update status to failure with 5 second timeout
                        self.statusManager.updateStatus(
                            state: .failure,
                            priority: .proofreading,
                            timeout: 5.0
                        )
                    }
                }
            }
        } else {
            // Inline replacement mode - no dialog
            // Remember the clipboard and the app the text came from
            let pasteboard = NSPasteboard.general
            let previousClipboard = pasteboard.string(forType: .string)
            let targetApp = NSWorkspace.shared.frontmostApplication

            Task {
                let result = await proofreadingService.proofread(
                    text: selectedText,
                    model: proofreadingModel,
                    prompt: currentPrompt,
                    aiService: aiService,
                    promptBuilder: promptBuilder,
                    maxRetries: 3
                )

                switch result {
                case .success(let correctedText):
                    self.correctedText = correctedText
                    self.clipboardService.copyToClipboard(correctedText)

                    // If the user moved to another app while waiting, don't paste into the wrong place.
                    // Leave the corrected text on the clipboard instead.
                    let currentApp = NSWorkspace.shared.frontmostApplication
                    guard targetApp == nil || currentApp?.processIdentifier == targetApp?.processIdentifier else {
                        Logger.shared.warning("AppState: Focus moved to another app - corrected text left on clipboard instead of pasting")
                        self.statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 5.0)
                        return
                    }

                    // Small delay to ensure clipboard is updated
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    let changeCountAfterCopy = pasteboard.changeCount

                    self.clipboardService.pasteFromClipboard()

                    // Give the target app time to read the clipboard before restoring it.
                    // Slow apps (Electron, browsers) can take several hundred milliseconds.
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s

                    // Restore the previous clipboard only if nothing else changed it meanwhile
                    if let previousClipboard = previousClipboard,
                       pasteboard.changeCount == changeCountAfterCopy,
                       previousClipboard != correctedText {
                        self.clipboardService.copyToClipboard(previousClipboard)
                    }

                    self.statusManager.updateStatus(state: .success, priority: .proofreading, timeout: 2.0)
                    Logger.shared.info("AppState: Text replaced successfully")

                case .failure(let error):
                    self.correctedText = "Error: \(error.localizedDescription)"

                    // Clipboard was not touched on failure, so nothing to restore
                    self.statusManager.updateStatus(state: .failure, priority: .proofreading, timeout: 5.0)
                    Logger.shared.error("AppState: Proofreading failed - \(error.localizedDescription)")
                }
            }
        }
    }
    // MARK: - Window Management
    
    @objc func showProofreadingDialog(_ sender: Any?) {
        WindowManager.shared.showWindow(
            id: "proofreading-dialog",
            title: "Proofreading Results",
            content: { ProofreadingDialog().environmentObject(self) },
            size: NSSize(width: 800, height: 500)
        )
    }
    
    @objc func showSettings(_ sender: Any?) {
        WindowManager.shared.showWindow(
            id: "settings",
            title: "Settings",
            content: { SettingsView().environmentObject(self) },
            size: NSSize(width: 400, height: 250)
        )
    }
}
