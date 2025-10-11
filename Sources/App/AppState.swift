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
    
    private func setupKeyboardShortcut() {
        keyboardShortcutManager.setupShortcut(keyboardShortcut) { [weak self] in
            self?.handleProofreadingShortcut()
        }
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
    
    func updateProviderURL(_ url: String) {
        switch proofreadingProvider {
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
    
    func updateKeyboardShortcut(_ shortcut: String) {
        keyboardShortcut = shortcut
        configurationManager.updateProofreadingConfig { $0.keyboardShortcut = shortcut }
        setupKeyboardShortcut()
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
            // Store previous clipboard contents to restore later
            let pasteboard = NSPasteboard.general
            let previousClipboard = pasteboard.string(forType: .string)
            
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
                    switch result {
                    case .success(let correctedText):
                        self.correctedText = correctedText
                        
                        // Copy corrected text to clipboard
                        self.clipboardService.copyToClipboard(correctedText)
                        
                        // Small delay to ensure clipboard is updated
                        usleep(50000) // 50ms
                        
                        // Paste to replace selected text
                        self.clipboardService.pasteFromClipboard()
                        
                        // Wait for paste operation to complete
                        usleep(150000) // 150ms
                        
                        // Restore previous clipboard if it was different
                        if let previousClipboard = previousClipboard, 
                           previousClipboard != selectedText,
                           previousClipboard != correctedText {
                            self.clipboardService.copyToClipboard(previousClipboard)
                        }
                        
                        // Update status to success with 2 second timeout
                        self.statusManager.updateStatus(
                            state: .success,
                            priority: .proofreading,
                            timeout: 2.0
                        )
                        
                        Logger.shared.info("AppState: Text replaced successfully")
                        
                    case .failure(let error):
                        self.correctedText = "Error: \(error.localizedDescription)"
                        
                        // Restore previous clipboard on error
                        if let previousClipboard = previousClipboard {
                            self.clipboardService.copyToClipboard(previousClipboard)
                        }
                        
                        // Update status to failure with 5 second timeout
                        self.statusManager.updateStatus(
                            state: .failure,
                            priority: .proofreading,
                            timeout: 5.0
                        )
                        
                        Logger.shared.error("AppState: Proofreading failed - \(error.localizedDescription)")
                    }
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
