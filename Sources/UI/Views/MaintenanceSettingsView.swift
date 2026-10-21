import SwiftUI
import AppKit

// MARK: - Maintenance Settings Content
struct MaintenanceSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var logFiles: [URL] = []
    @State private var totalLogSize: Int64 = 0
    @State private var showClearConfirmation = false
    @State private var showDeleteConfigConfirmation = false
    
    var body: some View {
        StampSettingsPage(
            title: "Maintenance",
            subtitle: "Logs and a clean start. Logs never contain the text you proofread."
        ) {
            StampCard(title: "Logs") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 24) {
                        stat("Files", "\(logFiles.count)")
                        stat("Size", formatBytes(totalLogSize))
                        stat("Kept for", "7 days")
                    }
                    HStack(spacing: 10) {
                        Button {
                            Logger.shared.openLogsFolder()
                        } label: {
                            Label("Open logs folder", systemImage: "folder")
                        }
                        .buttonStyle(.stamp(.default, size: .sm))

                        Button {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear all logs", systemImage: "trash")
                        }
                        .buttonStyle(.stamp(.default, size: .sm))
                    }
                }
            }
            .alert("Clear all logs?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { clearLogs() }
            } message: {
                Text("This permanently deletes every log file.")
            }

            StampCard(title: "Start over") {
                HStack(spacing: 12) {
                    Text("Delete all settings and your saved API key, then restart FlowMate with the defaults.")
                        .font(Stamp.small)
                        .foregroundColor(Stamp.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        showDeleteConfigConfirmation = true
                    } label: {
                        Text("Reset FlowMate").foregroundColor(Stamp.alert)
                    }
                    .buttonStyle(.stamp(.default, size: .sm))
                }
            }
            .alert("Reset FlowMate?", isPresented: $showDeleteConfigConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset and restart", role: .destructive) { deleteConfigAndRestart() }
            } message: {
                Text("All settings and the saved API key are deleted. This can't be undone.")
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.stamp(.default))
        }
        .onAppear {
            refreshLogInfo()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Stamp.caption).tracking(0.4).foregroundColor(Stamp.inkSubtle)
            Text(value).font(Stamp.numeral).foregroundColor(Stamp.ink)
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
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            // Not running from an app bundle (e.g. `swift run`): just quit
            NSApplication.shared.terminate(nil)
            return
        }

        // Start a helper that waits until this process has exited, then reopens the app.
        // Opening right away would only re-activate the instance that is about to quit.
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
            "flowmate-restart", String(pid), bundleURL.path
        ]
        do {
            try task.run()
        } catch {
            Logger.shared.error("Couldn't start relaunch helper", error: error)
        }
        NSApplication.shared.terminate(nil)
    }
}

#Preview("Maintenance Settings Content") {
    MaintenanceSettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
        .frame(width: 500, height: 400)
}
