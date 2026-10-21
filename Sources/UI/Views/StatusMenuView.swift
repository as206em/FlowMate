import SwiftUI
import AppKit

/// The panel that opens from the menu bar icon, in the Stamp style.
struct StatusMenuView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let notice = notice {
                notice
            }

            Button {
                MenuBarPanel.close()
                appState.proofreadClipboard()
            } label: {
                Label("Proofread clipboard", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.stamp(.primary, size: .lg, fullWidth: true))
            .disabled(appState.isProcessing)

            StampSegmented(
                label: "Provider",
                options: AIProvider.allCases.map { .init(value: $0, label: $0.displayName) },
                selection: Binding(
                    get: { appState.proofreadingProvider },
                    set: { appState.setProvider($0) }
                )
            )

            StampLabeled(label: "Model") {
                if appState.modelChoices.isEmpty {
                    Text("No models found")
                        .font(Stamp.body)
                        .foregroundColor(Stamp.inkSubtle)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .stampSurface(fill: Stamp.paperSunk, shadow: .none)
                } else {
                    StampPicker(
                        options: appState.modelChoices,
                        selection: Binding(
                            get: { appState.proofreadingModel },
                            set: { appState.updateCurrentModel($0) }
                        ),
                        title: { $0 }
                    )
                }
            }

            Toggle(isOn: Binding(
                get: { appState.showDialog },
                set: { appState.updateShowDialog($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review first").font(Stamp.label).foregroundColor(Stamp.ink)
                    Text("Off: replace right away").font(Stamp.small).foregroundColor(Stamp.inkSubtle)
                }
            }
            .toggleStyle(.stamp)
            .padding(12)
            .stampSurface(fill: Stamp.paperRaised, shadow: .none)

            if !appState.history.isEmpty {
                recent
            }

            HStack(spacing: 8) {
                Button {
                    MenuBarPanel.close()
                    appState.showSettings(nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.stamp(.default, size: .sm, fullWidth: true))
                .keyboardShortcut(",")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.stamp(.ghost, size: .sm))
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Stamp.paper)
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.line")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Stamp.onFill)
                .frame(width: 38, height: 38)
                .stampSurface(fill: Stamp.sun, shadow: .sm)

            VStack(alignment: .leading, spacing: 1) {
                Text("FlowMate").font(Stamp.title).foregroundColor(Stamp.ink)
                Text("Select text, press \(KeyboardShortcutManager.displayString(for: appState.keyboardShortcut))")
                    .font(Stamp.small)
                    .foregroundColor(Stamp.inkSubtle)
            }

            Spacer(minLength: 4)

            switch appState.connectionState {
            case .checking:
                StampBadge(text: "Checking", tone: .sun)
            case .connected:
                StampBadge(text: "Connected", tone: .mint)
            case .failed:
                StampBadge(text: "Offline", tone: .alert)
            }
        }
    }

    /// The one most important problem, if any, with a way to fix it
    private var notice: AnyView? {
        if !appState.hasAccessibilityPermission {
            return AnyView(noticeRow(
                text: "FlowMate needs Accessibility access to read and replace selected text.",
                action: "Allow access",
                perform: { appState.requestAccessibilityPermission() }
            ))
        }
        if case .failed = appState.connectionState {
            return AnyView(noticeRow(
                text: "Can't reach \(appState.proofreadingProvider.displayName). Check that it's running.",
                action: "Retry",
                perform: { appState.checkConnection() }
            ))
        }
        if appState.isSelectedModelMissing {
            return AnyView(noticeRow(
                text: "Model “\(appState.proofreadingModel)” isn't installed. Pick another below.",
                action: nil,
                perform: {}
            ))
        }
        return nil
    }

    private func noticeRow(text: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Stamp.ink)
            Text(text)
                .font(Stamp.small)
                .foregroundColor(Stamp.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action, action: perform)
                    .buttonStyle(.stamp(.default, size: .sm))
            }
        }
        .padding(10)
        .stampSurface(fill: Stamp.tomatoSoft, shadow: .none)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECENT").font(Stamp.caption).tracking(0.4).foregroundColor(Stamp.inkSubtle)
                Spacer()
                Button("Clear") { appState.clearHistory() }
                    .buttonStyle(.plain)
                    .font(Stamp.small.weight(.bold))
                    .foregroundColor(Stamp.inkSubtle)
            }
            VStack(spacing: 0) {
                ForEach(Array(appState.history.prefix(4).enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle().fill(Stamp.lineSoft).frame(height: 1)
                    }
                    Button {
                        MenuBarPanel.close()
                        appState.showHistoryItem(item)
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.preview)
                                .font(Stamp.small)
                                .foregroundColor(Stamp.ink)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                                .font(Stamp.numeral)
                                .foregroundColor(Stamp.inkSubtle)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .stampSurface(fill: Stamp.paperRaised, shadow: .none)
        }
    }
}

/// Helpers for the menu bar panel window
enum MenuBarPanel {
    /// Closes the panel, e.g. before opening another window
    static func close() {
        let panel = NSApp.windows.first { $0.className.contains("MenuBarExtra") && $0.isVisible }
        (panel ?? NSApp.keyWindow)?.close()
    }
}
