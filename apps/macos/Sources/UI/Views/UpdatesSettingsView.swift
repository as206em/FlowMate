import SwiftUI
import AppKit

// MARK: - Updates settings
struct UpdatesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var updates = UpdateService.shared
    @State private var restoreCandidate: DataBackupService.Backup?

    var body: some View {
        FocusSettingsPage(
            title: "Updates",
            subtitle: "FlowMate updates itself from GitHub. Your data is backed up before each update installs."
        ) {
            FocusSection(title: "Version") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(updates.currentVersion).font(Focus.clock).foregroundColor(Focus.text)
                        Spacer()
                        Button {
                            updates.checkForUpdates()
                        } label: {
                            Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.focus())
                        .disabled(!updates.isAvailable)
                    }
                    if !updates.isAvailable {
                        Text(AppChannel.current == .production
                             ? "Updates are off in this build. They work in the packaged FlowMate.app from a release."
                             : "Updates are off in FlowMate Dev. Only the released FlowMate updates itself.")
                            .font(Focus.meta).foregroundColor(Focus.text3)
                    } else if let last = updates.lastCheck {
                        Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(Focus.meta).foregroundColor(Focus.text3)
                    }
                    Toggle(isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.automaticallyChecks = $0 })) {
                        Text("Check for updates automatically").font(Focus.control).foregroundColor(Focus.text)
                    }
                    .toggleStyle(.focus).frame(maxWidth: 360).disabled(!updates.isAvailable)
                    Toggle(isOn: Binding(get: { updates.automaticallyDownloads }, set: { updates.automaticallyDownloads = $0 })) {
                        Text("Download updates in the background").font(Focus.control).foregroundColor(Focus.text)
                    }
                    .toggleStyle(.focus).frame(maxWidth: 360).disabled(!updates.isAvailable)
                }
            }

            FocusSection(
                title: "Backups",
                subtitle: "A copy of your tasks and settings, saved in the Backups folder next to your data. Logs aren't included."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { updates.backupBeforeUpdate }, set: { updates.backupBeforeUpdate = $0 })) {
                        Text("Back up before every update").font(Focus.control).foregroundColor(Focus.text)
                    }
                    .toggleStyle(.focus).frame(maxWidth: 360)

                    HStack(spacing: 12) {
                        Text("Keep the last").font(Focus.control).foregroundColor(Focus.text)
                        FocusPicker(options: [3, 5, 10, 20], selection: Binding(
                            get: { updates.backupsToKeep }, set: { updates.backupsToKeep = $0 })) { "\($0) backups" }
                    }

                    HStack(spacing: 8) {
                        Button {
                            updates.backUpNow()
                        } label: {
                            Label("Back up now", systemImage: "externaldrive.badge.plus")
                        }
                        .buttonStyle(.focus())

                        Button {
                            showBackupsFolder()
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.focus())
                    }

                    if let error = updates.lastBackupError {
                        Text(error).font(Focus.meta).foregroundColor(Focus.risk)
                    }

                    if updates.backups.isEmpty {
                        Text("No backups yet.").font(Focus.meta).foregroundColor(Focus.text3)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(updates.backups) { backup in
                                FocusRow {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(backup.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                                        Text("\(backup.created.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file))")
                                            .font(Focus.meta).foregroundColor(Focus.text3)
                                    }
                                    Spacer()
                                    Button("Restore…") { restoreCandidate = backup }
                                        .buttonStyle(.focus())
                                }
                            }
                        }
                    }
                }
            }
            .alert("Restore this backup?", isPresented: Binding(
                get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })) {
                Button("Cancel", role: .cancel) { restoreCandidate = nil }
                Button("Restore and restart", role: .destructive) {
                    if let backup = restoreCandidate { updates.restore(backup) }
                    restoreCandidate = nil
                }
            } message: {
                Text("Your current data is backed up first (as before-restore), then replaced by \(restoreCandidate?.name ?? "this backup"). FlowMate restarts.")
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.focus())
        }
        .onAppear { updates.refreshBackups() }
    }

    private func showBackupsFolder() {
        let folder = DataBackupService().backupsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
