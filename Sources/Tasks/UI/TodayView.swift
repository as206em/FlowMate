import SwiftUI

// The Today page (TaskScope.today): what to work on today across every project, in three blocks.
//
//   This week     Make against Reach of the time tracked this week, with the Reach target; when
//                 one side is behind it says so, and Start next leans that way (Next best's boost)
//   Today focus   running, overdue, due today, pinned, then done today
//   Current sprint the active sprint's open tasks that aren't in Today focus
//
// Rows are the list's rows (status circle, project, title, type, due, expected, timer ring;
// click opens the panel; ↑/↓ ↵ Space work). Hovering an overdue, due or pinned row shows
// "→ Tomorrow". The time tracked today is in the header, once.

struct TodayView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        let plan = store.todayPlan()
        let sections = TasksViewModel.todaySections(plan, store: store)
        var builder = TaskTableBuilder()
        builder.spacer("top", 4)
        builder.append(.weekMix)
        builder.spacer("after-mix", 12)
        for section in sections {
            let isFocus = section.key == TasksViewModel.todayKey
            if !isFocus { builder.spacer("before-\(section.key)", 24) }
            builder.group(
                key: section.key,
                title: section.title,
                hint: isFocus ? hint(plan) : "· \(store.sprint.name)",
                tasks: model.sortedForGroup(section.tasks, section.key, store: store),
                emptyText: "Nothing for today. Press ⌘T on a selected task or right-click › Add to Today; it stays here until it's done. Or add one below with ⌘N.",
                showProject: true,
                drop: isFocus ? .focus : nil,
                composerIsDefault: isFocus,
                composerOnTop: model.isComposerPinned(TasksViewModel.listComposerKey(section.key)),
                open: !model.isCollapsed(section.key),
                gap: 0,
                actions: isFocus ? actions(hasOverdue: !plan.overdue.isEmpty, running: plan.running.count) : [],
                liveHint: nil,
                risk: isFocus && !plan.overdue.isEmpty,
                draggable: true,
                sortable: true,
                display: RowDisplay.maker(store: store, model: model, today: true)
            )
        }
        builder.spacer("bottom", 72)
        return TaskTable(
            showProject: true,
            excluding: [.sprint, .priority],
            rows: builder.rows,
            drops: builder.drops,
            draggable: builder.draggable
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func hint(_ plan: TodayPlan) -> String {
        var parts: [String] = []
        if !plan.overdue.isEmpty { parts.append("\(plan.overdue.count) overdue") }
        if plan.carriedOver > 0 { parts.append("\(plan.carriedOver) from earlier days") }
        return parts.isEmpty ? "" : "· " + parts.joined(separator: " · ")
    }

    private func actions(hasOverdue: Bool, running: Int) -> [GroupHeaderAction] {
        var result: [GroupHeaderAction] = []
        if running > 1 { result.append(.pauseAll) }
        if hasOverdue { result += [.moveOverdueToToday, .moveOverdueToTomorrow] }
        return result
    }
}

enum TodayFormat {
    /// "3h 20m", "45m", "0m"
    static func duration(_ seconds: TimeInterval) -> String {
        Focus.durationString(minutes: max(0, Int(seconds / 60)))
    }

    /// "Friday, October 31"
    static func longDay(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
}

/// The header's title on Today: "Today" and the date.
struct TodayHeaderTitle: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Focus.text2)
            Text("Today")
                .font(Focus.header)
                .foregroundColor(Focus.text)
            Text(TodayFormat.longDay(Date()))
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .lineLimit(1)
        }
    }
}

/// "Tracked today": the total, one bar split by project in their colors, and the projects with
/// their time ("Liloix 2h · BotX 1h 20m"). Follows running timers.
struct TodayTrackedPanel: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        LiveTime { now in
            let plan = store.todayPlan(now: now)
            content(plan)
        }
    }

    private func content(_ plan: TodayPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TodayFormat.duration(plan.trackedSeconds))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundColor(plan.running.isEmpty ? Focus.text : Focus.liveText)
                Text(plan.trackedSeconds < 60 ? "Nothing tracked yet today. Start a timer with Space or its ring." : summary(plan))
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if plan.trackedSeconds >= 60 {
                bar(plan)
                legend(plan)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusPanel()
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tracked today \(TodayFormat.duration(plan.trackedSeconds)). \(summary(plan))")
    }

    /// "Liloix 2h · BotX 1h 20m"
    private func summary(_ plan: TodayPlan) -> String {
        plan.trackedByProject.map { "\($0.name) \(TodayFormat.duration($0.seconds))" }.joined(separator: " · ")
    }

    private func bar(_ plan: TodayPlan) -> some View {
        GeometryReader { geo in
            let total = max(1, plan.trackedByProject.reduce(0) { $0 + $1.seconds })
            let gaps = CGFloat(max(0, plan.trackedByProject.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(plan.trackedByProject, id: \.projectId) { item in
                    Capsule()
                        .fill(Color(hex: item.colorHex))
                        .frame(width: max(3, (geo.size.width - gaps) * CGFloat(item.seconds / total)))
                }
            }
        }
        .frame(height: 6)
    }

    private func legend(_ plan: TodayPlan) -> some View {
        HStack(spacing: 14) {
            ForEach(plan.trackedByProject.prefix(6), id: \.projectId) { item in
                HStack(spacing: 6) {
                    FocusProjectTile(name: item.name, colorHex: item.colorHex, size: 14, icon: item.icon)
                    Text(item.name).font(Focus.meta).foregroundColor(Focus.text2).lineLimit(1)
                    Text(TodayFormat.duration(item.seconds)).font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text3)
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }
}
