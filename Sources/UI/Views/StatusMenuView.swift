import SwiftUI

/// Contents of the menu bar menu. Rendered as a native menu (MenuBarExtra .menu style),
/// so only buttons, text, toggles, pickers, submenus and dividers are used.
struct StatusMenuView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        statusSection

        Divider()

        Button("Proofread Clipboard") {
            appState.proofreadClipboard()
        }
        .disabled(appState.isProcessing)

        Text("Proofread selection: \(KeyboardShortcutManager.displayString(for: appState.keyboardShortcut))")

        Divider()

        Picker("Provider", selection: Binding(
            get: { appState.proofreadingProvider },
            set: { appState.setProvider($0) }
        )) {
            ForEach(AIProvider.allCases, id: \.self) { provider in
                Text(provider.displayName).tag(provider)
            }
        }

        Picker("Model", selection: Binding(
            get: { appState.proofreadingModel },
            set: { appState.updateCurrentModel($0) }
        )) {
            ForEach(modelChoices, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        .disabled(appState.availableModels.isEmpty)

        Toggle("Show Results Before Replacing", isOn: Binding(
            get: { appState.showDialog },
            set: { appState.updateShowDialog($0) }
        ))

        if !appState.history.isEmpty {
            Menu("Recent") {
                ForEach(appState.history) { item in
                    Button(item.preview) {
                        appState.showHistoryItem(item)
                    }
                }
                Divider()
                Button("Clear Recent") {
                    appState.clearHistory()
                }
            }
        }

        Divider()

        Button("Settings…") {
            appState.showSettings(nil)
        }
        .keyboardShortcut(",")

        Button("Quit FlowMate") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusSection: some View {
        Text("\(appState.proofreadingProvider.displayName) · \(appState.proofreadingModel.isEmpty ? "no model" : appState.proofreadingModel)")

        switch appState.connectionState {
        case .checking:
            Label("Checking connection…", systemImage: "ellipsis.circle")
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
        case .failed:
            Label("Not connected – check Settings", systemImage: "xmark.circle")
            Button("Retry Connection") {
                appState.checkConnection()
            }
        }

        if appState.isSelectedModelMissing {
            Label("Model “\(appState.proofreadingModel)” not found – pick one below", systemImage: "exclamationmark.triangle")
        }

        if !appState.hasAccessibilityPermission {
            Button("Allow Accessibility Access…") {
                appState.requestAccessibilityPermission()
            }
        }
    }

    /// Available models, plus the selected one if it's missing, so the picker always has a matching tag
    private var modelChoices: [String] {
        var models = appState.availableModels
        if !appState.proofreadingModel.isEmpty && !models.contains(appState.proofreadingModel) {
            models.insert(appState.proofreadingModel, at: 0)
        }
        return models
    }
}
