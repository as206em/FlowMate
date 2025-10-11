import SwiftUI
import AppKit
import Foundation

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

// MARK: - Preview
#Preview("Settings View") {
    SettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
}
