import SwiftUI
import AppKit

// MARK: - Sidebar Item Model
struct SettingsSidebarItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let tag: SettingsTab
}

enum SettingsTab: Hashable {
    case proofreading
    case aiProviders
    case maintenance
}

// MARK: - Settings View with Sidebar
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .proofreading
    @State private var monitor: Any?
    
    private let sidebarItems = [
        SettingsSidebarItem(title: "Proofreading", icon: "doc.text.magnifyingglass", tag: .proofreading),
        SettingsSidebarItem(title: "AI Providers", icon: "cpu", tag: .aiProviders),
        SettingsSidebarItem(title: "Maintenance", icon: "wrench.and.screwdriver", tag: .maintenance)
    ]
    
    var body: some View {
        SettingsSplitView(
            selectedTab: $selectedTab,
            sidebarItems: sidebarItems,
            contentView: { selectedTab in
                Group {
                    switch selectedTab {
                    case .proofreading:
                        ProofreadingSettingsView()
                    case .aiProviders:
                        AIProvidersSettingsView()
                    case .maintenance:
                        MaintenanceSettingsView()
                    }
                }
            },
            onDismiss: {
                dismiss()
            }
        )
        .frame(minWidth: 600,  maxWidth:600, minHeight: 400, idealHeight: 450, maxHeight: .infinity)
        .onAppear {
            appState.checkConnection()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }
    
    private func setupKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                dismiss()
                return nil
            }
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - Split View with Sidebar
struct SettingsSplitView<Content: View>: NSViewRepresentable {
    @Binding var selectedTab: SettingsTab
    let sidebarItems: [SettingsSidebarItem]
    let contentView: (SettingsTab) -> Content
    let onDismiss: () -> Void
    
    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        
        // Create sidebar
        let sidebarView = createSidebar(context: context)
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebarView)
        
        // Create content view
        let contentHostingView = NSHostingView(rootView: createContentView())
        contentHostingView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(contentHostingView)
        
        // Set proper constraints - let NSSplitView handle positioning
        NSLayoutConstraint.activate([
            sidebarView.widthAnchor.constraint(equalToConstant: 200),
            splitView.widthAnchor.constraint(equalToConstant: 600),
        ])
        
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        
        return splitView
    }
    
    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // Update content view
        if splitView.arrangedSubviews.count > 1,
           let hostingView = splitView.arrangedSubviews[1] as? NSHostingView<AnyView> {
            hostingView.rootView = AnyView(createContentView())
        }
    }
    
    private func createSidebar(context: Context) -> NSView {
        let containerView = NSView()
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let outlineView = NSOutlineView()
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.focusRingType = .none
        outlineView.rowSizeStyle = .default
        outlineView.backgroundColor = .clear
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.width = 150
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        scrollView.documentView = outlineView
        
        containerView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.outlineView = outlineView
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        
        return containerView
    }
    
    private func createContentView() -> AnyView {
        AnyView(contentView(selectedTab))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: SettingsSplitView
        weak var outlineView: NSOutlineView?
        
        init(_ parent: SettingsSplitView) {
            self.parent = parent
        }
        
        // MARK: - NSOutlineViewDataSource
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return parent.sidebarItems.count
            }
            return 0
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            return parent.sidebarItems[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return false
        }
        
        // MARK: - NSOutlineViewDelegate
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let sidebarItem = item as? SettingsSidebarItem else { return nil }
            
            let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
            var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
                
                // Create image view
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cellView?.addSubview(imageView)
                cellView?.imageView = imageView
                
                // Create text field
                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isBordered = false
                textField.isEditable = false
                textField.backgroundColor = .clear
                textField.font = .systemFont(ofSize: 13)
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                // Layout constraints
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 8),
                    imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
            
            // Configure cell
            cellView?.textField?.stringValue = sidebarItem.title
            
            if let image = NSImage(systemSymbolName: sidebarItem.icon, accessibilityDescription: sidebarItem.title) {
                cellView?.imageView?.image = image
                cellView?.imageView?.contentTintColor = .secondaryLabelColor
            }
            
            return cellView
        }
        
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            return 28
        }
        
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            
            if selectedRow >= 0, selectedRow < parent.sidebarItems.count {
                let item = parent.sidebarItems[selectedRow]
                parent.selectedTab = item.tag
            }
        }
    }
}

// MARK: - Proofreading Settings Content
struct ProofreadingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editedPrompt: String = ""
    @FocusState private var isURLFieldFocused: Bool
    @FocusState private var isPromptEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        HStack {
                            Text("Provider:")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $appState.proofreadingProvider) {
                                ForEach(AIProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: appState.proofreadingProvider) { provider in
                                appState.setProvider(provider)
                            }
                        }
                        
                        HStack {
                            Text("Model:")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $appState.proofreadingModel) {
                                ForEach(appState.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: appState.proofreadingModel) { newValue in
                                appState.updateCurrentModel(newValue)
                            }
                        }
                        
                        HStack {
                            Text("Shortcut:")
                                .frame(width: 80, alignment: .leading)
                            TextField("", text: $appState.keyboardShortcut)
                                .onSubmit {
                                    appState.updateKeyboardShortcut(appState.keyboardShortcut)
                                }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Proofreading Instructions:")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextEditor(text: $editedPrompt)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .frame(height: 120)
                            .focused($isPromptEditorFocused)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom bar with action buttons
            Divider()
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("OK") {
                    appState.updateCurrentPrompt(editedPrompt)
                    appState.updateKeyboardShortcut(appState.keyboardShortcut)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            editedPrompt = appState.currentPrompt
            isURLFieldFocused = true
        }
    }
}

// MARK: - AI Providers Settings Content
struct AIProvidersSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool
    @State private var selectedProviderForConfig: AIProvider = .ollama
    @State private var connectionStatus: String = ""
    @State private var isTestingConnection: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Form {
                Picker("Configure Provider:", selection: $selectedProviderForConfig) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                
                if selectedProviderForConfig == .ollama {
                    TextField("URL:", text: $appState.ollamaURL)
                        .focused($isURLFieldFocused)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green : 
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120) // Fixed width to prevent layout shifts
                        
                        Spacer()
                        
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .ollama, url: appState.ollamaURL, apiKey: "")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isTestingConnection)
                    }
                } else {
                    TextField("URL:", text: $appState.openAIURL)
                        .focused($isURLFieldFocused)
                    SecureField("API Key:", text: $appState.openAIAPIKey)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green : 
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120) // Fixed width to prevent layout shifts
                        
                        Spacer()
                        
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .openai, url: appState.openAIURL, apiKey: appState.openAIAPIKey)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isTestingConnection)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            
            // Bottom bar with action buttons
            Divider()
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("OK") {
                    appState.updateProviderURL(selectedProviderForConfig == .ollama ? appState.ollamaURL : appState.openAIURL)
                    if selectedProviderForConfig == .openai {
                        appState.updateOpenAIAPIKey(appState.openAIAPIKey)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            isURLFieldFocused = true
        }
    }
    
    private func testConnection(provider: AIProvider, url: String, apiKey: String) async {
        await MainActor.run {
            connectionStatus = "Connecting..."
            isTestingConnection = true
        }
        
        do {
            let configuration = AIConfiguration(
                ollamaURL: provider == .ollama ? url : "http://127.0.0.1:11434",
                openAIURL: provider == .openai ? url : "https://api.openai.com",
                openAIAPIKey: apiKey
            )
            
            let service = AIServiceFactory.createService(for: provider, configuration: configuration)
            let models = try await service.listModels()
            
            await MainActor.run {
                connectionStatus = "Connected (\(models.count) models)"
                isTestingConnection = false
            }
        } catch {
            await MainActor.run {
                connectionStatus = "Error: \(error.localizedDescription)"
                isTestingConnection = false
            }
        }
    }
}

// MARK: - Maintenance Settings Content
struct MaintenanceSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var logFiles: [URL] = []
    @State private var totalLogSize: Int64 = 0
    @State private var showClearConfirmation = false
    @State private var showDeleteConfigConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Log Information Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Logs Information")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Log Files:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(logFiles.count)")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Total Size:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatBytes(totalLogSize))
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Log Directory:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(Logger.shared.getLogDirectory().lastPathComponent)
                                    .fontWeight(.medium)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    
                    Divider()
                    
                    // Actions Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Actions")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 12) {
                            Button(action: {
                                Logger.shared.openLogsFolder()
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                    Text("Open Logs Folder")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            
                            Button(action: {
                                showClearConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("Clear All Logs")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .foregroundColor(.red)
                            .alert("Clear All Logs?", isPresented: $showClearConfirmation) {
                                Button("Cancel", role: .cancel) { }
                                Button("Clear", role: .destructive) {
                                    clearLogs()
                                }
                            } message: {
                                Text("This will permanently delete all log files. This action cannot be undone.")
                            }
                            
                            Button(action: {
                                showDeleteConfigConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "trash.circle.fill")
                                    Text("Delete Current Configuration")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .foregroundColor(.red)
                            .alert("Delete Configuration?", isPresented: $showDeleteConfigConfirmation) {
                                Button("Cancel", role: .cancel) { }
                                Button("Delete & Restart", role: .destructive) {
                                    deleteConfigAndRestart()
                                }
                            } message: {
                                Text("This will delete all app settings and restart the application with default configuration. This action cannot be undone.")
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom bar with action buttons
            Divider()
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            refreshLogInfo()
        }
    }
    
    private func refreshLogInfo() {
        logFiles = Logger.shared.getLogFiles()
        totalLogSize = Logger.shared.getTotalLogSize()
    }
    
    private func clearLogs() {
        Logger.shared.clearAllLogs()
        refreshLogInfo()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func deleteConfigAndRestart() {
        // Get configuration manager from app state
        let configManager = appState.configurationManager
        
        // Delete configuration
        configManager.deleteConfiguration()
        
        // Log the action
        Logger.shared.warning("User deleted configuration - restarting app")
        
        // Restart app
        restartApplication()
    }
    
    private func restartApplication() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }
}

// MARK: - Preview
#Preview("Settings View") {
    SettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
}

#Preview("Proofreading Settings Content") {
    ProofreadingSettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
        .frame(width: 500, height: 400)
}

#Preview("AI Providers Settings Content") {
    AIProvidersSettingsView()
        .frame(width: 500, height: 400)
}
