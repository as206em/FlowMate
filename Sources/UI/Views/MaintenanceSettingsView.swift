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
