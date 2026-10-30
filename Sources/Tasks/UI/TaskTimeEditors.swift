import SwiftUI

// Fixing tracked time: the time cell's popover (spent + expected), "Adjust time…", the
// "Still working on X?" prompt and its "Stop at…" picker.

/// The list's time cell popover: time spent (editable) above the expected time.
struct TaskTimeEditor: View {
    let task: TaskItem
    let close: () -> Void

    var body: some View {
        FocusPopoverMenu(width: 250, maxHeight: 520) {
            FocusMenuSection(title: "Time spent", first: true)
            TaskTimeSpentEditor(task: task)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            TaskExpectedChoices(task: task, close: close)
        }
    }
}

/// Time spent: a field ("1h 12m", ↵ sets it) with Set and Reset, then −15m / −5m / +5m / +15m.
/// A running timer keeps running from the new total. Each change is an undo step
/// (quick taps in a row are one).
struct TaskTimeSpentEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var autofocus = false

    @State private var draft = ""
    @FocusState private var focused: Bool

    private static let steps: [Int] = [-15, -5, 5, 15]

    var body: some View {
        let parsed = TaskDurationParser.seconds(draft)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("1h 15m", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Focus.control.monospacedDigit())
                    .focused($focused)
                    .onSubmit(apply)
                    .focusField(focused: focused)
                    .accessibilityLabel("Time spent")
                Button("Set", action: apply)
                    .buttonStyle(.focus())
                    .disabled(parsed == nil)
                Button("Reset") {
                    store.setTimeSpent(task.id, seconds: 0)
                    refresh()
                }
                .buttonStyle(.focus(.ghost, compact: true))
                .help("Set the time spent to zero")
            }
            if parsed == nil, !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Type a time such as 1h 15m, 45m or 1:15")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.risk)
            }
            HStack(spacing: 4) {
                ForEach(Self.steps, id: \.self) { minutes in
                    Button(minutes < 0 ? "−\(-minutes)m" : "+\(minutes)m") {
                        store.adjustTimeSpent(task.id, by: TimeInterval(minutes * 60))
                        refresh()
                    }
                    .buttonStyle(.focus(.ghost, compact: true))
                    .font(Focus.control.monospacedDigit())
                    .accessibilityLabel(minutes < 0 ? "Remove \(-minutes) minutes" : "Add \(minutes) minutes")
                }
                Spacer(minLength: 0)
            }
            Text(store.isRunning(task.id)
                 ? "The timer keeps running from the new time. ⌘Z undoes a change."
                 : "⌘Z undoes a change.")
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            refresh()
            if autofocus { DispatchQueue.main.async { focused = true } }
        }
    }

    private func refresh() {
        draft = TaskDurationParser.format(seconds: store.elapsed(task.id))
    }

    private func apply() {
        guard let seconds = TaskDurationParser.seconds(draft) else { return }
        store.setTimeSpent(task.id, seconds: seconds)
        refresh()
        focused = false
    }
}

/// "Adjust time…" from the right-click menu: a small sheet around TaskTimeSpentEditor.
struct AdjustTimeSheet: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adjust time").font(Focus.pageTitle).foregroundColor(Focus.text)
                Text(task.title).font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
            }
            LiveTime { now in
                HStack(spacing: 8) {
                    Text("Spent").font(Focus.body).foregroundColor(Focus.text2)
                    Text(Focus.clockString(store.elapsed(task.id, now: now)))
                        .font(Focus.clock)
                        .foregroundColor(store.isRunning(task.id) ? Focus.liveText : Focus.text)
                    Text("of \(Focus.durationString(minutes: task.expectedMinutes)) expected")
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                }
            }
            TaskTimeSpentEditor(task: task, autofocus: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.focus())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Focus.canvas)
        .focusLight()
    }
}

/// "Stop at…": pause a timer as if you'd stopped it earlier. Quick choices, then any time
/// between its start and now. The time after that isn't counted.
struct StopAtEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    @State private var time = Date()

    var body: some View {
        let now = Date()
        let start = store.startedAt(task.id) ?? now
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                FocusMenuSection(title: "Stop the timer at", first: true)
                ForEach(choices(start: start, now: now), id: \.title) { choice in
                    FocusMenuItem {
                        store.stopTimer(task.id, at: choice.time, now: now)
                        close()
                    } label: {
                        Text(choice.title).font(Focus.control).foregroundColor(Focus.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Self.clock(choice.time)).font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text3)
                    }
                }
            }
            .padding(4)
            FocusDivider()
            VStack(alignment: .leading, spacing: 8) {
                FocusCaption(text: "Another time")
                DatePicker(
                    "Stop at",
                    selection: $time,
                    in: start...max(start, now),
                    displayedComponents: Calendar.current.isDate(start, inSameDayAs: now) ? [.hourAndMinute] : [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.field)
                let counted = max(0, min(time, now).timeIntervalSince(start))
                Text("Counts \(TaskDurationParser.format(seconds: counted)) of this session.")
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text3)
                Button("Stop at \(Self.clock(time))") {
                    store.stopTimer(task.id, at: time)
                    close()
                }
                .buttonStyle(.focus())
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(Focus.raised)
        .focusLight()
        .onAppear {
            // Start from when the expected time ran out, if that's already past
            let expectedEnd = start.addingTimeInterval(max(0, Double(task.expectedMinutes * 60) - task.spentSeconds))
            time = min(max(expectedEnd, start), now)
        }
    }

    private struct Choice {
        let title: String
        let time: Date
    }

    private func choices(start: Date, now: Date) -> [Choice] {
        var result = [Choice(title: "Now", time: now)]
        for minutes in [15, 30, 60] {
            let time = now.addingTimeInterval(TimeInterval(-minutes * 60))
            if time > start {
                result.append(Choice(title: minutes == 60 ? "1 hour ago" : "\(minutes) minutes ago", time: time))
            }
        }
        let expectedEnd = start.addingTimeInterval(max(0, Double(task.expectedMinutes * 60) - task.spentSeconds))
        if expectedEnd > start, expectedEnd < now {
            result.append(Choice(title: "At the estimate", time: expectedEnd))
        }
        return result
    }

    /// "14:05", or "Mon 14:05" when it isn't today
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "jmm" : "EEEjmm")
        return formatter.string(from: date)
    }
}

/// "Still working on X? Its timer has run 3h 10m." with Keep and Stop at…. Quiet: no sound, no
/// window coming forward, and it never stops a timer by itself. `compact` is the menu bar version.
struct LongRunPrompt: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    var compact = false

    @State private var stopping = false

    var body: some View {
        LiveTime { now in
            HStack(spacing: 10) {
                if !compact { FocusLiveDot() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(compact ? "Still working on this?" : "Still working on \(task.title)?")
                        .font(compact ? .system(size: 12, weight: .medium) : Focus.control)
                        .foregroundColor(Focus.text)
                        .lineLimit(1)
                    Text("Running for \(TaskDurationParser.format(seconds: store.sessionLength(task.id, now: now))) without a break.")
                        .font(.system(size: 12))
                        .foregroundColor(Focus.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Keep") { store.keepRunning(task.id) }
                    .buttonStyle(.focus(.ghost))
                    .help("Keep the timer running; ask again later")
                Button("Stop at…") { stopping = true }
                    .buttonStyle(.focus())
                    .popover(isPresented: $stopping, arrowEdge: .bottom) {
                        StopAtEditor(task: task) { stopping = false }
                            .environmentObject(store)
                    }
            }
        }
    }
}

/// Banner above the main view while any timer has run past the prompt time.
struct LongRunBanner: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        LiveTime { now in
            let tasks = store.longRunningTasks(now: now)
            if !tasks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                        if index > 0 { FocusDivider() }
                        LongRunPrompt(task: task)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(Focus.lineStrong, lineWidth: 1))
                .padding(.horizontal, 28)
                .padding(.top, 12)
            }
        }
    }
}
