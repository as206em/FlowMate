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
}

// MARK: - Settings View with Sidebar
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .proofreading
    @State private var monitor: Any?
    
    private let sidebarItems = [
        SettingsSidebarItem(title: "Proofreading", icon: "doc.text.magnifyingglass", tag: .proofreading),
        SettingsSidebarItem(title: "AI Providers", icon: "cpu", tag: .aiProviders)
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
    @FocusState private var isURLFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Form {
                Picker("Model:", selection: $appState.currentModel) {
                    ForEach(appState.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                
                TextField("Shortcut:", text: $appState.keyboardShortcut)
                    .onSubmit {
                        appState.updateKeyboardShortcut(appState.keyboardShortcut)
                    }
                
                HStack {
                    Spacer()
                    Button("Test Connection") {
                        appState.checkConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
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
            isURLFieldFocused = true
        }
    }
}

// MARK: - AI Providers Settings Content
struct AIProvidersSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Form {
                Picker("Provider:", selection: $appState.currentProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appState.currentProvider) { provider in
                    appState.setProvider(provider)
                }
                
                if appState.currentProvider == .ollama {
                    TextField("URL:", text: $appState.ollamaURL)
                        .focused($isURLFieldFocused)
                } else {
                    TextField("URL:", text: $appState.openAIURL)
                        .focused($isURLFieldFocused)
                }
                
                if appState.currentProvider == .openai {
                    SecureField("API Key:", text: $appState.openAIAPIKey)
                }
                
                HStack {
                    Spacer()
                    Button("Test Connection") {
                        appState.checkConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
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
                    appState.updateProviderURL(appState.currentProvider == .ollama ? appState.ollamaURL : appState.openAIURL)
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
}

// MARK: - Preview
#Preview("Settings View") {
    SettingsView()
        .environmentObject(AppState())
}

#Preview("Proofreading Settings Content") {
    ProofreadingSettingsView()
        .environmentObject(AppState())
        .frame(width: 500, height: 400)
}

#Preview("AI Providers Settings Content") {
    AIProvidersSettingsView()
        .frame(width: 500, height: 400)
}
