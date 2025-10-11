import SwiftUI
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var currentPrompt: String = "You are a text proofreader. Your task is to correct typos and grammar errors in the provided text while strictly preserving the original meaning, formatting, and style."
    @Published var availableModels: [String] = []
    @Published var isProcessing: Bool = false
    @Published var showProofreadingDialog: Bool = false
    @Published var correctedText: String = ""
    @Published var originalText: String = ""
    @Published var ollamaURL: String = "http://127.0.0.1:11434"
    @Published var openAIURL: String = "https://api.openai.com"
    @Published var openAIAPIKey: String = ""
    @Published var keyboardShortcut: String = "command+."
    @Published var showDiffByDefault: Bool = true
    @Published var proofreadingProvider: AIProvider = .ollama
    @Published var proofreadingModel: String = "gemma3:4b"
    
    // Computed properties for backward compatibility
    var currentModel: String {
        get { proofreadingModel }
        set { proofreadingModel = newValue }
    }
    
    var currentProvider: AIProvider {
        get { proofreadingProvider }
        set { proofreadingProvider = newValue }
    }
    
    let configurationManager: ConfigurationManager
    @Published var aiService: AIService!
    private var cancellables = Set<AnyCancellable>()
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
        self.statusManager = statusManager
        self.keyboardShortcutManager = keyboardShortcutManager ?? KeyboardShortcutManager()
        self.clipboardService = clipboardService ?? ClipboardService()
        self.promptBuilder = promptBuilder ?? PromptBuilder()
        self.proofreadingService = proofreadingService ?? ProofreadingService()
        
        if let configurationManager = configurationManager {
            self.configurationManager = configurationManager
        } else {
            // Create configuration manager synchronously by using unsafeTransfer
            let configManager = ConfigurationManager()
            self.configurationManager = configManager
        }
        
        Logger.shared.info("AppState: Initializing AppState")
        
        // Load initial values from configuration manager
        let config = self.configurationManager.config
        currentProvider = AIProvider(rawValue: config.proofreading.selectedProvider) ?? .ollama
        currentPrompt = config.proofreading.defaultPrompt
        keyboardShortcut = config.proofreading.keyboardShortcut
        currentModel = config.proofreading.selectedModel
        showDiffByDefault = config.proofreading.showDiffByDefault
        
        // Load provider settings from the configuration
        // Load Ollama settings
        ollamaURL = config.providers.ollama.url
        
        // Load OpenAI settings
        openAIURL = config.providers.openai.url
        openAIAPIKey = config.providers.openai.apiKey ?? ""
        
        // Set the current provider's URL and API key to the AppState properties
        if currentProvider == .ollama {
            // ollamaURL is already set above
        } else {
            // openAIURL and openAIAPIKey are already set above
        }
        
        // Initialize the AI service
        updateAIService()
        
        setupKeyboardShortcut()
        preloadConnection()
        
        Logger.shared.info("AppState: Initialization complete - Provider: \(currentProvider.rawValue), Model: \(currentModel)")
    }
    
    private func updateAIService() {
        let configuration = AIConfiguration(
            ollamaURL: ollamaURL,
            openAIURL: openAIURL,
            openAIAPIKey: openAIAPIKey
        )
        
        aiService = AIServiceFactory.createService(
            for: currentProvider,
            configuration: configuration
        )
    }
    
    func setProvider(_ provider: AIProvider) {
        Logger.shared.info("AppState: Switching provider to \(provider.rawValue)")
        currentProvider = provider
        
        // Update configuration manager
        configurationManager.updateProofreadingConfig { config in
            config.selectedProvider = provider.rawValue
        }
        
        updateAIService() // Recreate service with new provider
        checkConnection() // Test new provider connection
    }
    
    private func preloadConnection() {
        // Immediately check connection on startup
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
            Logger.shared.info("AppState: Checking connection for provider: \(currentProvider)")
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
    
    func updateProviderURL(_ url: String) {
        switch currentProvider {
        case .ollama:
            ollamaURL = url
            // Update configuration manager
            configurationManager.updateProvidersConfig { providers in
                providers.ollama.url = url
            }
        case .openai:
            openAIURL = url
            // Update configuration manager
            configurationManager.updateProvidersConfig { providers in
                providers.openai.url = url
            }
        }
        updateAIService() // Recreate service with new configuration
        checkConnection()
    }
    
    func updateKeyboardShortcut(_ shortcut: String) {
        keyboardShortcut = shortcut
        // Update configuration manager
        configurationManager.updateProofreadingConfig { config in
            config.keyboardShortcut = shortcut
        }
        setupKeyboardShortcut()
    }
    
    func updateCurrentPrompt(_ prompt: String) {
        currentPrompt = prompt
        // Update configuration manager
        configurationManager.updateProofreadingConfig { config in
            config.defaultPrompt = prompt
        }
    }
    
    func updateCurrentModel(_ model: String) {
        currentModel = model
        // Update configuration manager
        configurationManager.updateProofreadingConfig { config in
            config.selectedModel = model
        }
    }
    
    func updateShowDiffByDefault(_ showDiff: Bool) {
        showDiffByDefault = showDiff
        // Update configuration manager
        configurationManager.updateProofreadingConfig { config in
            config.showDiffByDefault = showDiff
        }
    }
    
    func updateOpenAIAPIKey(_ apiKey: String) {
        openAIAPIKey = apiKey
        // Update configuration manager
        configurationManager.updateProvidersConfig { providers in
            providers.openai.apiKey = apiKey
        }
    }
    
    func handleProofreadingShortcut() {
        guard let selectedText = clipboardService.getSelectedText() else {
            Logger.shared.warning("AppState: No text selected for proofreading")
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
        
        // Show dialog immediately with loading state
        self.correctedText = ""
        self.isProcessing = true
        self.showProofreadingDialog(nil)
        
        // Perform proofreading using the service
        Task {
            let result = await proofreadingService.proofread(
                text: selectedText,
                model: currentModel,
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
    }
    
    
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
