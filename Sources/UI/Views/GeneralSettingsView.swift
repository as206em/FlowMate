import SwiftUI

// MARK: - General settings: apply right away
struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    /// Timer settings live with the task data
    @ObservedObject private var tasks = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FocusSettingsPage(
            title: "General",
            subtitle: "How FlowMate starts. Changes apply right away."
        ) {
            FocusSection(title: "Startup") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )) {
                        Text("Open FlowMate at login").font(Focus.control).foregroundColor(Focus.text)
                    }
                    .toggleStyle(.focus)
                    .frame(maxWidth: 360)

                    if let error = appState.launchAtLoginError {
                        Text(error).font(.system(size: 12)).foregroundColor(Focus.risk)
                    }
                }
            }

            FocusSection(
                title: "Quick add",
                subtitle: "A shortcut that opens a small New task box over any app. The same words as everywhere work there: !high, @milestone, +project, #next, *status, due:fri and ~90m (Tab completes them)."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ShortcutRecorder(shortcut: Binding(
                        get: { appState.quickAddShortcut },
                        set: { appState.updateQuickAddShortcut($0) }
                    ))
                    .frame(maxWidth: 360)
                    if let error = appState.quickAddShortcutError {
                        Text(error).font(.system(size: 12)).foregroundColor(Focus.risk)
                    }
                    HStack(spacing: 8) {
                        if !appState.quickAddShortcut.isEmpty {
                            Button("Turn off") { appState.updateQuickAddShortcut("") }
                                .buttonStyle(.focus(.ghost))
                        }
                        if appState.quickAddShortcut != AppSettings.defaultQuickAddShortcut,
                           !KeyboardShortcutManager.isSameShortcut(AppSettings.defaultQuickAddShortcut, appState.keyboardShortcut) {
                            Button("Use \(KeyboardShortcutManager.displayString(for: AppSettings.defaultQuickAddShortcut))") {
                                appState.updateQuickAddShortcut(AppSettings.defaultQuickAddShortcut)
                            }
                            .buttonStyle(.focus(.ghost))
                        }
                        Button("Try it") { QuickAddPanel.show() }
                            .buttonStyle(.focus())
                    }
                }
            }

            FocusSection(
                title: "Task hotkeys",
                subtitle: "Optional shortcuts that work over any app. Both are off until you record one."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    hotkey(
                        label: "Pause or resume the last timer",
                        hint: "Pauses the timer you started last; with none running, starts the task you worked on last",
                        shortcut: appState.timerShortcut,
                        error: appState.timerShortcutError,
                        set: { appState.updateTimerShortcut($0) }
                    )
                    hotkey(
                        label: "Open the menu bar with search focused",
                        hint: "Type to find a task, or add one with !high, @milestone, +project, #next and due:fri",
                        shortcut: appState.menuSearchShortcut,
                        error: appState.menuSearchShortcutError,
                        set: { appState.updateMenuSearchShortcut($0) }
                    )
                }
            }

            FocusSection(
                title: "Timers",
                subtitle: "Timers never stop each other, and stop by themselves only when you're away. ⌥-click a play button (or ⌥Space) to run only that one; ⇧Space in the window pauses all."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(
                        get: { tasks.preferences.showsMenuBarClock },
                        set: { tasks.setShowsMenuBarClock($0) }
                    )) {
                        Text("Show the running timer in the menu bar").font(Focus.control).foregroundColor(Focus.text)
                    }
                    .toggleStyle(.focus)
                    .frame(maxWidth: 360)

                    FocusLabeled(
                        label: "Ask “Still working on it?” after",
                        hint: "A quiet prompt in the menu and the window, with Keep or Stop at… (and in Notification Center, see Notifications)"
                    ) {
                        FocusTabs(
                            options: WorkspacePreferences.longRunChoices.map { minutes in
                                (value: minutes, label: minutes == 0 ? "Never" : "\(minutes / 60)h")
                            },
                            selection: Binding(
                                get: { tasks.preferences.longRunPromptMinutes },
                                set: { tasks.setLongRunPromptMinutes($0) }
                            )
                        )
                        .fixedSize()
                    }

                    FocusLabeled(
                        label: "Stop timers when I'm away for",
                        hint: "No key press or mouse move for this long stops every running timer, and the idle minutes aren't counted"
                    ) {
                        FocusTabs(
                            options: WorkspacePreferences.idleStopChoices.map { minutes in
                                (value: minutes, label: minutes == 0 ? "Never" : "\(minutes)m")
                            },
                            selection: Binding(
                                get: { tasks.preferences.idleStopMinutes },
                                set: { tasks.setIdleStopMinutes($0) }
                            )
                        )
                        .fixedSize()
                    }
                }
            }

            FocusSection(
                title: "Recent results",
                subtitle: "Shown in the menu bar panel. Kept in memory only and cleared when FlowMate quits."
            ) {
                HStack(spacing: 8) {
                    Button {
                        appState.updateMaxHistoryItems(appState.maxHistoryItems - 5)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.focus())
                    .disabled(appState.maxHistoryItems == 0)
                    .accessibilityLabel("Keep fewer")

                    Text(appState.maxHistoryItems == 0 ? "Off" : "\(appState.maxHistoryItems)")
                        .font(Focus.clock)
                        .foregroundColor(Focus.text)
                        .frame(minWidth: 40)

                    Button {
                        appState.updateMaxHistoryItems(appState.maxHistoryItems + 5)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.focus())
                    .disabled(appState.maxHistoryItems >= 100)
                    .accessibilityLabel("Keep more")
                }
            }

            FocusSection(title: "Accessibility access") {
                HStack(spacing: 12) {
                    if appState.hasAccessibilityPermission {
                        FocusStatusLabel(text: "Granted", tone: .ok)
                        Text("FlowMate can read and replace selected text.")
                            .font(Focus.meta)
                            .foregroundColor(Focus.text2)
                    } else {
                        FocusStatusLabel(text: "Needed", tone: .risk)
                        Text("Needed for the shortcut and for replacing text.")
                            .font(Focus.meta)
                            .foregroundColor(Focus.text2)
                        Spacer()
                        Button("Open System Settings") {
                            appState.requestAccessibilityPermission()
                        }
                        .buttonStyle(.focus())
                    }
                }
            }
        } footer: {
            Button("Close") { dismiss() }
                .buttonStyle(.focus())
        }
        .onAppear {
            appState.quickAddShortcutError = nil
            appState.timerShortcutError = nil
            appState.menuSearchShortcutError = nil
            appState.refreshLaunchAtLogin()
            appState.refreshAccessibilityPermission()
        }
    }

    /// A labeled recorder for one optional hotkey, with Turn off and its error.
    private func hotkey(label: String, hint: String, shortcut: String, error: String?,
                        set: @escaping (String) -> Void) -> some View {
        FocusLabeled(label: label, hint: hint) {
            VStack(alignment: .leading, spacing: 8) {
                ShortcutRecorder(shortcut: Binding(get: { shortcut }, set: { set($0) }))
                    .frame(maxWidth: 360)
                if let error {
                    Text(error).font(.system(size: 12)).foregroundColor(Focus.risk)
                }
                if !shortcut.isEmpty {
                    Button("Turn off") { set("") }
                        .buttonStyle(.focus(.ghost))
                }
            }
        }
    }
}
