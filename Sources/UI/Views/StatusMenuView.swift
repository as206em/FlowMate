import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusSection
            Divider()
            actionButtons
            Divider()
            quitButton
        }
        .padding(16)
        .frame(width: 280)
    }
    
    private var statusSection: some View {
            HStack {
                Circle()
                    .frame(width: 12, height: 12)
                Text("FlowMate")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { appState.showSettings(nil) }) {
                Label("Settings", systemImage: "gear")
                    .symbolVariant(.none)
                    .symbolRenderingMode(.monochrome)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var quitButton: some View {
        Button(action: { NSApplication.shared.terminate(nil) }) {
            Label("Quit", systemImage: "power")
                .symbolVariant(.none)
                .symbolRenderingMode(.monochrome)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
    
}
