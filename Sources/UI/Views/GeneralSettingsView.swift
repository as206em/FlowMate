import SwiftUI

// MARK: - General settings: apply right away
struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StampSettingsPage(
            title: "General",
            subtitle: "How FlowMate starts and looks. Changes apply right away."
        ) {
            StampCard(title: "Startup and look") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )) {
                        Text("Open FlowMate at login").font(Stamp.label).foregroundColor(Stamp.ink)
                    }
                    .toggleStyle(.stamp)

                    if let error = appState.launchAtLoginError {
                        Text(error).font(Stamp.small).foregroundColor(Stamp.alert)
                    }

                    StampSegmented(
                        label: "Appearance",
                        options: [
                            .init(value: "system", label: "System"),
                            .init(value: "light", label: "Light"),
                            .init(value: "dark", label: "Dark")
                        ],
                        selection: Binding(
                            get: { appState.appearance },
                            set: { appState.updateAppearance($0) }
                        )
                    )
                    .frame(maxWidth: 360)
                }
            }

            StampCard(title: "Recent results") {
                HStack(spacing: 12) {
                    Button {
                        appState.updateMaxHistoryItems(appState.maxHistoryItems - 5)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.stamp(.default, size: .sm))
                    .disabled(appState.maxHistoryItems == 0)
                    .accessibilityLabel("Keep fewer")

                    Text(appState.maxHistoryItems == 0 ? "Off" : "\(appState.maxHistoryItems)")
                        .font(Stamp.numeral)
                        .foregroundColor(Stamp.ink)
                        .frame(minWidth: 36)

                    Button {
                        appState.updateMaxHistoryItems(appState.maxHistoryItems + 5)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.stamp(.default, size: .sm))
                    .disabled(appState.maxHistoryItems >= 100)
                    .accessibilityLabel("Keep more")

                    Text("Shown in the menu bar panel. Kept in memory only and cleared when FlowMate quits.")
                        .font(Stamp.small)
                        .foregroundColor(Stamp.inkSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StampCard(title: "Accessibility access") {
                HStack(spacing: 12) {
                    if appState.hasAccessibilityPermission {
                        StampBadge(text: "Granted", tone: .mint)
                        Text("FlowMate can read and replace selected text.")
                            .font(Stamp.small)
                            .foregroundColor(Stamp.inkMuted)
                    } else {
                        StampBadge(text: "Needed", tone: .sun)
                        Text("Needed for the shortcut and for replacing text.")
                            .font(Stamp.small)
                            .foregroundColor(Stamp.inkMuted)
                        Spacer()
                        Button("Open System Settings") {
                            appState.requestAccessibilityPermission()
                        }
                        .buttonStyle(.stamp(.secondary, size: .sm))
                    }
                }
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.stamp(.default))
        }
        .onAppear {
            appState.refreshLaunchAtLogin()
            appState.refreshAccessibilityPermission()
        }
    }
}
