import SwiftUI
import AppKit

// MARK: - Settings window: Stamp sidebar plus the selected section
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab
    @State private var monitor: Any?
    private let keyMonitorService: KeyMonitorServiceProtocol = KeyMonitorService()

    init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Stamp.line).frame(width: Stamp.stroke1)
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .proofreading: ProofreadingSettingsView()
                case .aiProviders: AIProvidersSettingsView()
                case .maintenance: MaintenanceSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Stamp.paper)
        .onAppear {
            appState.checkConnection()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(Stamp.heading)
                .foregroundColor(Stamp.ink)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)

            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let isSelected = tab == selectedTab
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.displayName, systemImage: tab.icon)
                        .font(Stamp.label)
                        .foregroundColor(isSelected ? Stamp.onFill : Stamp.ink)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .background {
                            if isSelected {
                                Color.clear.stampSurface(fill: Stamp.sky, radius: Stamp.radiusMd, shadow: .sm)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Spacer()

            Group {
                switch appState.connectionState {
                case .checking: StampBadge(text: "Checking…", tone: .sun)
                case .connected: StampBadge(text: "\(appState.proofreadingProvider.displayName) ready", tone: .mint)
                case .failed: StampBadge(text: "\(appState.proofreadingProvider.displayName) offline", tone: .alert)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func setupKeyMonitor() {
        monitor = keyMonitorService.setupEscapeKeyMonitor(dismissAction: {
            // Only react to Esc pressed in the Settings window, and not while recording a shortcut
            guard WindowManager.shared.isKeyWindow(id: "settings"), !ShortcutRecorder.isRecording else { return }
            dismiss()
        })
    }

    private func removeKeyMonitor() {
        keyMonitorService.removeKeyMonitor(monitor)
        self.monitor = nil
    }
}

/// The page layout every settings section shares: a title, a short description,
/// scrolling content and an optional footer with actions
struct StampSettingsPage<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(Stamp.heading).foregroundColor(Stamp.ink)
                        Text(subtitle).font(Stamp.body).foregroundColor(Stamp.inkMuted)
                    }
                    content
                }
                .padding(24)
                // Room for the hard shadows on the right and bottom
                .padding(.trailing, 6)
            }
            Rectangle().fill(Stamp.lineSoft).frame(height: 1)
            HStack(spacing: 12) {
                Spacer()
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }
}

#Preview("Settings View") {
    SettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
}
