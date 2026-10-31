import SwiftUI
import AppKit

// MARK: - Settings window: Focus sidebar plus the selected section
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
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .notifications: NotificationsSettingsView()
                case .proofreading: ProofreadingSettingsView()
                case .aiProviders: AIProvidersSettingsView()
                case .maintenance: MaintenanceSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Focus.canvas)
        .focusLight()
        .onAppear {
            appState.checkConnection()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the window's traffic lights
            Color.clear.frame(height: 30)

            HStack(spacing: 9) {
                FocusAppTile()
                Text("Settings").font(.system(size: 14, weight: .semibold)).foregroundColor(Focus.text)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)

            ForEach(SettingsTab.allCases, id: \.self) { tab in
                FocusSidebarItem(selected: tab == selectedTab, action: { selectedTab = tab }) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                    Text(tab.displayName).frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            Group {
                let name = appState.proofreadingProvider.displayName
                switch appState.connectionState {
                case .checking: FocusStatusLabel(text: "Checking \(name)…", tone: .pending)
                case .connected: FocusStatusLabel(text: "\(name) ready", tone: .ok)
                case .failed: FocusStatusLabel(text: "\(name) offline", tone: .risk)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 14)
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Focus.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Focus.hairline).frame(width: 1) }
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
struct FocusSettingsPage<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(Focus.pageTitle).foregroundColor(Focus.text)
                        Text(subtitle).font(Focus.meta).foregroundColor(Focus.text3)
                    }
                    .padding(.bottom, 4)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FocusDivider()
            HStack(spacing: 8) {
                Spacer()
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
    }
}

#Preview("Settings View") {
    SettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
}
