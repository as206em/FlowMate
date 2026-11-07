import SwiftUI

// MARK: - Cloud sync settings
/// Server address, token and device name are drafts until Save changes; the switch applies at once.
struct CloudSyncSettingsView: View {
    @ObservedObject private var sync = CloudSyncController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var token = ""
    @State private var deviceName = ""
    @State private var test: TestStatus?
    @State private var loaded = false

    enum TestStatus: Equatable {
        case testing
        case connected(String)
        case failed(String)
    }

    private var settings: CloudSyncSettings { sync.status.state.settings }

    private var draft: CloudSyncSettings {
        CloudSyncSettings(enabled: settings.enabled, serverURL: serverURL, deviceName: deviceName)
    }

    private var hasChanges: Bool {
        draft != settings || token.trimmingCharacters(in: .whitespacesAndNewlines) != sync.token
    }

    var body: some View {
        FocusSettingsPage(
            title: "Cloud sync",
            subtitle: "Keep a copy of your tasks on a FlowMate server. Your data stays on this Mac too, and works offline."
        ) {
            if let conflict = sync.status.state.conflict {
                conflictBanner(conflict)
            }

            FocusSection(title: "Sync") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { settings.enabled },
                        set: { on in
                            var next = draft
                            next.enabled = on
                            Task { await sync.apply(settings: next, token: token) }
                        }
                    )) {
                        Text("Sync tasks with the server").font(Focus.control).foregroundColor(Focus.text)
                    }
                    .toggleStyle(.focus)
                    .frame(maxWidth: 360)
                    .disabled(!settings.enabled && (CloudSyncClient.baseURL(from: serverURL) == nil || token.isEmpty))

                    HStack(spacing: 8) {
                        statusLabel.frame(maxWidth: .infinity, alignment: .leading)
                        Button("Sync now") { Task { await sync.syncNow() } }
                            .buttonStyle(.focus())
                            .fixedSize()
                            .disabled(!sync.status.isActive || sync.isWorking || sync.status.isSyncing)
                    }
                    if let error = sync.actionError {
                        Text(error).font(.system(size: 12)).foregroundColor(Focus.risk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            FocusSection(title: "Server") {
                VStack(alignment: .leading, spacing: 12) {
                    FocusLabeled(label: "Server address") {
                        TextField("https://api.example.com", text: $serverURL).focusField()
                    }
                    FocusLabeled(label: "Token", hint: "Stored in your Keychain") {
                        SecureField("fm_…", text: $token).focusField()
                    }
                    FocusLabeled(label: "Device name", hint: "Shown when another device sees your changes") {
                        TextField(CloudSyncSettings.defaultDeviceName, text: $deviceName).focusField()
                    }
                    HStack(spacing: 8) {
                        testText.frame(maxWidth: .infinity, alignment: .leading)
                        Button("Test connection") { Task { await runTest() } }
                            .buttonStyle(.focus())
                            .fixedSize()
                            .disabled(test == .testing)
                    }
                }
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.focus())
                .keyboardShortcut(.cancelAction)
            Button("Save changes") {
                Task { await sync.apply(settings: draft, token: token) }
            }
            .buttonStyle(.focus(.primary))
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasChanges)
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: sync.status.state.settings) { _ in
            if !loaded { loadDrafts() }
        }
    }

    private func loadDrafts() {
        serverURL = settings.serverURL
        deviceName = settings.deviceName
        token = sync.token
        loaded = true
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLabel: some View {
        let status = sync.status
        if !status.state.settings.enabled {
            FocusStatusLabel(text: "Off", tone: .pending)
        } else if !status.isActive {
            FocusStatusLabel(text: "Add a server address and token", tone: .risk)
        } else if status.isSyncing || sync.isWorking {
            FocusStatusLabel(text: "Syncing…", tone: .pending)
        } else if status.state.conflict != nil {
            FocusStatusLabel(text: "Waiting for you to choose a copy", tone: .risk)
        } else if status.isOffline {
            FocusStatusLabel(text: "Offline · will sync when the server is back", tone: .pending)
        } else if let error = status.state.lastError {
            FocusStatusLabel(text: error, tone: .risk)
        } else if let at = status.state.lastSyncAt {
            FocusStatusLabel(
                text: status.localDirty == true ? "Changes waiting to sync" : "Last synced \(Self.relative(at))",
                tone: status.localDirty == true ? .pending : .ok
            )
        } else {
            FocusStatusLabel(text: "Not synced yet", tone: .pending)
        }
    }

    private func conflictBanner(_ conflict: CloudConflict) -> some View {
        let device = conflict.updatedByDevice.map { " on \($0)" } ?? ""
        let when = conflict.updatedAt.map { " \(Self.relative($0))" } ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            FocusNotice(text: "Your tasks changed here and in the cloud (changed\(device)\(when)). Pick the copy to keep; the other one is replaced.")
            HStack(spacing: 8) {
                Button("Use cloud copy") { Task { await sync.useCloudCopy() } }
                    .buttonStyle(.focus())
                Button("Keep this Mac's copy") { Task { await sync.keepThisMacCopy() } }
                    .buttonStyle(.focus())
                Spacer()
            }
            .disabled(sync.isWorking)
            Text("Using the cloud copy keeps this Mac's file next to it, so nothing is lost.")
                .font(Focus.meta).foregroundColor(Focus.text3)
        }
    }

    @ViewBuilder
    private var testText: some View {
        switch test {
        case .none:
            Text(" ").font(Focus.meta)
        case .testing:
            Text("Connecting…").font(Focus.meta).foregroundColor(Focus.text3)
        case let .connected(text):
            Label(text, systemImage: "checkmark.circle")
                .font(Focus.meta.weight(.medium))
                .foregroundColor(Focus.ok)
                .lineLimit(2)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(Focus.meta)
                .foregroundColor(Focus.risk)
                .lineLimit(3)
        }
    }

    private func runTest() async {
        test = .testing
        do {
            let me = try await sync.testConnection(serverURL: serverURL, token: token)
            let who = me.user.displayName ?? me.user.email ?? "Connected"
            let workspace = me.primaryWorkspace.map { " · \($0.name)" } ?? " · no workspace"
            test = .connected(who + workspace)
        } catch {
            test = .failed(error.localizedDescription)
        }
    }

    private static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
