import SwiftUI

// MARK: - General Settings Content
struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Launch FlowMate at login", isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    ))
                    if let error = appState.launchAtLoginError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Picker("Appearance:", selection: Binding(
                        get: { appState.appearance },
                        set: { appState.updateAppearance($0) }
                    )) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }

                Section {
                    Stepper(value: Binding(
                        get: { appState.maxHistoryItems },
                        set: { appState.updateMaxHistoryItems($0) }
                    ), in: 0...100, step: 5) {
                        Text(appState.maxHistoryItems == 0 ? "Recent results: off" : "Recent results to keep: \(appState.maxHistoryItems)")
                    }
                    Text("Shown in the menu bar under Recent. Kept in memory only and cleared when FlowMate quits.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    HStack {
                        Image(systemName: appState.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(appState.hasAccessibilityPermission ? .green : .orange)
                        Text(appState.hasAccessibilityPermission
                             ? "Accessibility access granted"
                             : "Accessibility access needed for the shortcut and for replacing text")
                        Spacer()
                        if !appState.hasAccessibilityPermission {
                            Button("Open System Settings") {
                                appState.requestAccessibilityPermission()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)

            Divider()

            HStack {
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
            appState.refreshLaunchAtLogin()
            appState.refreshAccessibilityPermission()
        }
    }
}
