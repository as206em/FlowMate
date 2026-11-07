import SwiftUI

// The task panel's Time section (sessions by day, edited in place, "Add time…"), the inspector's
// Created / Updated / Completed dates, and the "Timers ran while your Mac slept" prompt.

enum TimeLogFormat {
    /// "Tue Oct 28" (with the year when it isn't this year)
    static func day(_ date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEMMMd" : "EEEMMMdyyyy")
        return formatter.string(from: date)
    }

    /// "09:12" (or "9:12 AM", following the locale)
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    /// "09:12–10:40", with "+1" when it ends on a later day
    static func range(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return "\(clock(start))–\(clock(end))" + (days > 0 ? " +\(days)" : "")
    }

    /// "Oct 28, 2026 at 09:12"
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyyjmm")
        return formatter.string(from: date)
    }

    /// "1h 28m"; under a minute "< 1m"
    static func duration(_ seconds: TimeInterval) -> String {
        seconds > 0 && seconds < 60 ? "< 1m" : TaskDurationParser.format(seconds: seconds)
    }
}

// MARK: - Time section

/// "Time": every session of the task grouped by day, newest first, with the running one on top.
/// Hover a session to edit its start and end in place or delete it; "Add time…" adds one by hand.
/// The total follows every change, and each change is an undo step.
struct TaskTimeLogSection: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    @State private var adding = false
    @State private var editingId: UUID?
    @State private var showsAllDays = false

    /// Days shown before "Show all"
    private static let dayLimit = 5

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [TimeEntry]
        var id: Date { day }
        var total: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
    }

    var body: some View {
        let groups = dayGroups
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(spacing: 0) {
                runningRow
                if groups.isEmpty, !store.isRunning(task.id) {
                    Text("No time tracked yet. Start the timer, or add time you spent by hand.")
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                }
                let shown = showsAllDays ? groups : Array(groups.prefix(Self.dayLimit))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, group in
                    if index > 0 || store.isRunning(task.id) { FocusDivider() }
                    dayHeader(group)
                    ForEach(group.entries) { entry in
                        TimeEntryRow(entry: entry, editing: Binding(
                            get: { editingId == entry.id },
                            set: { editingId = $0 ? entry.id : (editingId == entry.id ? nil : editingId) }
                        ))
                    }
                }
                if groups.count > Self.dayLimit {
                    FocusDivider()
                    Button(showsAllDays ? "Show fewer days" : "Show all \(groups.count) days") { showsAllDays.toggle() }
                        .buttonStyle(.plain)
                        .font(Focus.meta)
                        .foregroundColor(Focus.text2)
                        .focusPointerCursor()
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }
            }
            .focusPanel()
            .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Time").font(Focus.body.weight(.semibold)).foregroundColor(Focus.text)
            LiveTime { now in
                Text(TimeLogFormat.duration(store.elapsed(task, now: now)))
                    .font(Focus.body.monospacedDigit())
                    .foregroundColor(store.isRunning(task.id) ? Focus.liveText : Focus.text3)
                    .accessibilityLabel("Total time spent")
            }
            Spacer()
            Button {
                adding = true
            } label: {
                Label("Add time…", systemImage: "plus")
            }
            .buttonStyle(.focus(.ghost, compact: true))
            .help("Add time you spent without the timer")
            .popover(isPresented: $adding, arrowEdge: .bottom) {
                AddTimeEditor(task: task) { adding = false }
                    .environmentObject(store)
            }
        }
    }

    /// The session in progress: start – now and its live length. It becomes an entry when the timer stops.
    @ViewBuilder
    private var runningRow: some View {
        if let started = store.startedAt(task.id) {
            LiveTime { now in
                HStack(spacing: 10) {
                    FocusLiveDot()
                    Text("\(TimeLogFormat.day(started, now: now)) · \(TimeLogFormat.clock(started))–now")
                        .font(Focus.row.monospacedDigit())
                        .foregroundColor(Focus.text)
                    Spacer(minLength: 8)
                    Text(Focus.clockString(max(0, now.timeIntervalSince(started))))
                        .font(Focus.clock)
                        .foregroundColor(Focus.liveText)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(Focus.liveSoft)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Running since \(TimeLogFormat.clock(started))")
            }
        }
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack {
            Text(TimeLogFormat.day(group.day).uppercased())
                .font(Focus.caption)
                .tracking(0.5)
                .foregroundColor(Focus.text3)
            Spacer()
            Text(TimeLogFormat.duration(group.total))
                .font(Focus.caption.monospacedDigit())
                .foregroundColor(Focus.text3)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// Entries by the day they started, newest day first; within a day, newest first.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: store.timeEntries(of: task.id)) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, entries: (byDay[day] ?? []).sorted { $0.start > $1.start })
        }
    }
}

/// One session: "09:12–10:40 · 1h 28m", its source when it isn't the timer, and its note.
/// On hover: Edit (start, end and note in place) and Delete.
private struct TimeEntryRow: View {
    @EnvironmentObject private var store: TaskStore
    let entry: TimeEntry
    @Binding var editing: Bool

    @State private var hovering = false

    var body: some View {
        Group {
            if editing {
                TimeEntryEditor(entry: entry) { editing = false }
            } else {
                display
            }
        }
        .background(hovering && !editing ? Focus.hover : .clear)
        .onHover { hovering = $0 }
    }

    private var display: some View {
        HStack(spacing: 10) {
            Text(TimeLogFormat.range(entry.start, entry.end))
                .font(Focus.row.monospacedDigit())
                .foregroundColor(Focus.text)
            Text("·").font(Focus.row).foregroundColor(Focus.text3)
            Text(TimeLogFormat.duration(entry.duration))
                .font(Focus.row.monospacedDigit())
                .foregroundColor(Focus.text2)
            if entry.source != .timer {
                FocusTag(text: entry.source == .manual ? "Added" : "Imported")
                    .help(entry.source == .manual
                          ? "Added by hand"
                          : "Time tracked before sessions were kept, as one entry")
            }
            if let note = entry.note {
                Text(note)
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(note)
            }
            Spacer(minLength: 8)
            if hovering {
                FocusIconButton(systemName: "pencil", label: "Edit session", size: 24) { editing = true }
                    .help("Edit the start, end and note")
                FocusIconButton(systemName: "trash", label: "Delete session", size: 24) { store.deleteTimeEntry(entry.id) }
                    .help("Delete this session (⌘Z undoes it)")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = true }
        .contextMenu {
            Button("Edit…") { editing = true }
            Button("Delete session") { store.deleteTimeEntry(entry.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimeLogFormat.range(entry.start, entry.end)), \(TimeLogFormat.duration(entry.duration))")
    }
}

/// Start and end (date and time) and a note, checked as you change them: the end must come after
/// the start and can't be in the future. ↵ or Save applies (one undo step), Esc or Cancel leaves.
private struct TimeEntryEditor: View {
    @EnvironmentObject private var store: TaskStore
    let entry: TimeEntry
    let close: () -> Void

    @State private var start = Date()
    @State private var end = Date()
    @State private var note = ""

    var body: some View {
        let problem = TaskStore.validate(start: start, end: end, now: Date())
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                picker("Start", $start)
                Text("–").foregroundColor(Focus.text3)
                picker("End", $end)
                Spacer(minLength: 0)
                if problem == nil {
                    Text(TimeLogFormat.duration(end.timeIntervalSince(start)))
                        .font(Focus.meta.monospacedDigit())
                        .foregroundColor(Focus.text3)
                }
            }
            HStack(spacing: 8) {
                TextField("Note (optional)", text: $note)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .focusField()
                    .onSubmit(save)
                    .accessibilityLabel("Note")
                Button("Cancel", action: close)
                    .buttonStyle(.focus(.ghost, compact: true))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.focus(compact: true))
                    .disabled(problem != nil)
                    .keyboardShortcut(.defaultAction)
            }
            if let problem {
                Text(problem.message).font(.system(size: 12)).foregroundColor(Focus.risk)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Focus.sidebar)
        .onAppear {
            start = entry.start
            end = entry.end
            note = entry.note ?? ""
        }
    }

    private func picker(_ label: String, _ value: Binding<Date>) -> some View {
        DatePicker(label, selection: value, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.field)
            .accessibilityLabel(label)
            .fixedSize()
    }

    private func save() {
        let now = Date()
        guard TaskStore.validate(start: start, end: end, now: now) == nil else { return }
        store.undoGroup("Edit time") {
            store.updateTimeEntry(entry.id, start: start, end: end, now: now)
            store.setTimeEntryNote(entry.id, note, now: now)
        }
        close()
    }
}

/// "Add time…": a day, a start time, then a duration ("1h 30m") or an end time, and a note.
struct AddTimeEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    enum Mode: Hashable { case duration, end }

    @State private var day = Date()
    @State private var start = Date()
    @State private var end = Date()
    @State private var mode: Mode = .duration
    @State private var durationText = "30m"
    @State private var note = ""
    @FocusState private var durationFocused: Bool

    var body: some View {
        let range = resolved
        let problem = range.flatMap { TaskStore.validate(start: $0.start, end: $0.end, now: Date()) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Add time").font(Focus.header).foregroundColor(Focus.text)
            row("Day") {
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
            }
            row("Start") {
                DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
            }
            FocusTabs(options: [(Mode.duration, "Duration"), (Mode.end, "End time")], selection: $mode)
            if mode == .duration {
                row("Duration") {
                    TextField("1h 30m", text: $durationText)
                        .textFieldStyle(.plain)
                        .font(Focus.control.monospacedDigit())
                        .focusField(focused: durationFocused)
                        .focused($durationFocused)
                        .onSubmit(add)
                        .accessibilityLabel("Duration")
                }
            } else {
                row("End") {
                    DatePicker("End", selection: $end, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }
            row("Note") {
                TextField("Optional", text: $note)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .focusField()
                    .onSubmit(add)
                    .accessibilityLabel("Note")
            }
            Group {
                if range == nil {
                    Text("Type a duration such as 1h 30m, 45m or 1:15").foregroundColor(Focus.risk)
                } else if let problem {
                    Text(problem.message).foregroundColor(Focus.risk)
                } else if let range {
                    Text("\(TimeLogFormat.day(range.start)) · \(TimeLogFormat.range(range.start, range.end)) · \(TimeLogFormat.duration(range.end.timeIntervalSince(range.start)))")
                        .foregroundColor(Focus.text3)
                }
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(.focus(.ghost))
                    .keyboardShortcut(.cancelAction)
                Button("Add time", action: add)
                    .buttonStyle(.focus())
                    .disabled(range == nil || problem != nil)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Focus.raised)
        .focusLight()
        .onAppear {
            // Default: the half hour that just ended
            let now = Date()
            day = now
            start = now.addingTimeInterval(-30 * 60)
            end = now
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Focus.meta).foregroundColor(Focus.text3).frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// The day's date with the start time, then the end from the duration or the end time (an end
    /// time before the start means the next day). Nil when the duration can't be read.
    private var resolved: (start: Date, end: Date)? {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: start)
        guard let startDate = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) else { return nil }
        switch mode {
        case .duration:
            guard let seconds = TaskDurationParser.seconds(durationText), seconds > 0 else { return nil }
            return (startDate, startDate.addingTimeInterval(seconds))
        case .end:
            let endTime = calendar.dateComponents([.hour, .minute], from: end)
            guard var endDate = calendar.date(bySettingHour: endTime.hour ?? 0, minute: endTime.minute ?? 0, second: 0, of: day) else { return nil }
            if endDate <= startDate, let next = calendar.date(byAdding: .day, value: 1, to: endDate) { endDate = next }
            return (startDate, endDate)
        }
    }

    private func add() {
        guard let range = resolved,
              case .success = store.addTimeEntry(taskId: task.id, start: range.start, end: range.end, note: note) else { return }
        close()
    }
}

// MARK: - Inspector dates

/// Created, Updated and Completed (or Canceled) under the inspector's properties.
struct TaskDatesSection: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line("Created", task.createdAt)
            line("Updated", task.updatedAt)
            if let completed = task.completedAt {
                line(task.isCanceled ? "Canceled" : "Completed", completed)
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { FocusDivider() }
    }

    private func line(_ label: String, _ date: Date) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .frame(width: 86, alignment: .leading)
            Text(TimeLogFormat.stamp(date))
                .font(Focus.meta)
                .foregroundColor(Focus.text2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sleep prompt

/// "Timers ran while your Mac slept 2h 05m" with Keep and Discard sleep time. Quiet like the
/// long-run prompt: it never changes a timer by itself.
struct AwayPrompt: View {
    @EnvironmentObject private var store: TaskStore
    var compact = false

    var body: some View {
        if !store.awayGaps.isEmpty {
            if compact {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(compactTitle).font(.system(size: 12, weight: .medium)).foregroundColor(Focus.text).lineLimit(1)
                        Text("Still counted: \(tasksLine)").font(.system(size: 12)).foregroundColor(Focus.text3).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Button("Keep") { store.keepAwayTime() }
                        .buttonStyle(.focus(.ghost, compact: true))
                    Button("Discard") { store.discardAwayTime() }
                        .buttonStyle(.focus(compact: true))
                        .help("Discard sleep time: the timers don't count it")
                }
            } else {
                FocusBanner(
                    systemImage: "moon.zzz",
                    title: title,
                    message: message,
                    primaryTitle: store.awayGaps.contains { $0.kind == .sleep } ? "Discard sleep time" : "Discard away time",
                    primaryAction: { store.discardAwayTime() },
                    secondaryTitle: "Keep",
                    secondaryAction: { store.keepAwayTime() }
                )
            }
        }
    }

    private var slept: Bool { store.awayGaps.contains { $0.kind == .sleep } }

    /// "Timers ran while your Mac slept 2h 05m"
    private var title: String {
        let what = slept ? "slept" : "was locked"
        let count = store.awayTasks.count
        return "\(count == 1 ? "A timer" : "Timers") ran while your Mac \(what) \(Self.length(store.awayDuration))"
    }

    /// "Your Mac slept 2h 05m", short enough for the menu
    private var compactTitle: String {
        "Your Mac \(slept ? "slept" : "was locked") \(Self.length(store.awayDuration))"
    }

    private var tasksLine: String {
        let names = store.awayTasks.map(\.title)
        guard let first = names.first else { return "" }
        return names.count == 1 ? first : "\(first) and \(names.count - 1) more"
    }

    /// "Website and 1 more kept counting from 18:02 to 20:07. Discard takes that time out."
    private var message: String {
        guard let start = store.awayGaps.map(\.start).min(), let end = store.awayGaps.map(\.end).max() else { return "" }
        return "\(tasksLine) kept counting from \(TimeLogFormat.clock(start)) to \(TimeLogFormat.clock(end)). Discard takes that time out; ⌘Z puts it back."
    }

    /// "2h 05m", "45m"
    static func length(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : String(format: "%dh %02dm", h, m)
    }
}

/// The window's version of the prompt, under the long-run banner.
struct AwayBanner: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        if !store.awayGaps.isEmpty {
            AwayPrompt()
                .padding(.horizontal, 28)
                .padding(.top, 12)
        }
    }
}
