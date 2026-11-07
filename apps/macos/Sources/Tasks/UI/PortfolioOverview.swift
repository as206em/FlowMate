import SwiftUI

/// All projects › Overview: this week's Make vs Reach on top, then one row per active project with
/// a single "Needs you" verdict (overdue, nothing planned, Reach light, untouched, or on track),
/// its sprint progress and its plan's Make / Reach split. Rows that need you come first. A row opens
/// its project, an overdue verdict its overdue tasks, and the ring starts the project's next task.
struct PortfolioOverview: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    var body: some View {
        // Hours tracked and "Untouched N days" move with the clock
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let rows = store.portfolio(sortedBy: .attention, now: now).map { card in
            (card: card, mix: store.sprintMix(scope: .project(card.project.id)))
        }
        let ordered = OverviewVerdict.ordered(rows.map { ($0.card, $0.mix) })
        return VStack(alignment: .leading, spacing: 16) {
            WeekMixCard()
            VStack(spacing: 0) {
                OverviewHeaderRow()
                ForEach(Array(ordered.enumerated()), id: \.element.card.id) { index, row in
                    if index > 0 { FocusDivider() }
                    ProjectOverviewRow(card: row.card, mix: row.mix, verdict: row.verdict, now: now)
                }
            }
            .focusPanel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What a project needs from you, in one chip.
struct OverviewVerdict: Equatable {
    let text: String
    let tone: VerdictTone
    /// Higher comes first
    let rank: Int
    /// A click shows the project's overdue tasks
    var opensOverdue = false

    static func of(_ card: ProjectOverview, mix: SprintMix) -> OverviewVerdict {
        if card.overdueCount > 0 {
            return OverviewVerdict(text: "\(card.overdueCount) overdue", tone: .risk, rank: 4, opensOverdue: true)
        }
        if card.project.usesSprints, card.sprintPlanned == 0, card.openCount > 0 {
            return OverviewVerdict(text: "Nothing planned in \(card.sprint.name)", tone: .warn, rank: 3)
        }
        if card.isStale, !card.isRunning {
            return OverviewVerdict(text: PortfolioRules.activityLabel(untouchedDays: card.untouchedDays), tone: .warn, rank: 2)
        }
        if mix.behind == .reach {
            return OverviewVerdict(text: "Reach is light", tone: .warn, rank: 1)
        }
        if card.isRunning { return OverviewVerdict(text: "Running now", tone: .live, rank: 0) }
        return OverviewVerdict(text: "On track", tone: .good, rank: 0)
    }

    /// Verdict first (highest rank), then the attention order the cards came in.
    static func ordered(_ rows: [(ProjectOverview, SprintMix)]) -> [(card: ProjectOverview, mix: SprintMix, verdict: OverviewVerdict)] {
        rows.enumerated()
            .map { (offset: $0.offset, card: $0.element.0, mix: $0.element.1, verdict: of($0.element.0, mix: $0.element.1)) }
            .sorted { $0.verdict.rank != $1.verdict.rank ? $0.verdict.rank > $1.verdict.rank : $0.offset < $1.offset }
            .map { (card: $0.card, mix: $0.mix, verdict: $0.verdict) }
    }
}

private enum OverviewColumns {
    static let name: CGFloat = 170
    static let sprint: CGFloat = 190
    static let mix: CGFloat = 150
    static let ring: CGFloat = 30
}

private struct OverviewHeaderRow: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        HStack(spacing: 16) {
            FocusCaption(text: "Project").frame(width: OverviewColumns.name, alignment: .leading)
            FocusCaption(text: "Needs you").frame(maxWidth: .infinity, alignment: .leading)
            FocusCaption(text: store.sprint.name).frame(width: OverviewColumns.sprint, alignment: .leading)
            FocusCaption(text: "Plan: Make · Reach").frame(width: OverviewColumns.mix, alignment: .leading)
            Color.clear.frame(width: OverviewColumns.ring, height: 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Color(hex: 0xF7F7F5))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Focus.radiusPanel, topTrailingRadius: Focus.radiusPanel))
    }
}

/// One project on the Overview.
struct ProjectOverviewRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let card: ProjectOverview
    let mix: SprintMix
    let verdict: OverviewVerdict
    let now: Date

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                FocusProjectTile(project: card.project, size: 22)
                Text(card.project.name)
                    .font(Focus.rowStrong)
                    .foregroundColor(Focus.text)
                    .lineLimit(1)
                if card.isRunning { FocusLiveDot() }
            }
            .frame(width: OverviewColumns.name, alignment: .leading)
            verdictChip
                .frame(maxWidth: .infinity, alignment: .leading)
            sprintCell
                .frame(width: OverviewColumns.sprint, alignment: .leading)
            mixCell
                .frame(width: OverviewColumns.mix, alignment: .leading)
            playButton
                .frame(width: OverviewColumns.ring)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(hovering ? Focus.hover : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.select(.project(card.project.id)) }
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.project.name), \(verdict.text)")
        .accessibilityAction(named: "Open project") { model.select(.project(card.project.id)) }
    }

    @ViewBuilder
    private var verdictChip: some View {
        let chip = Text(verdict.text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(verdict.tone.text)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(verdict.tone.fill))
        if verdict.opensOverdue {
            Button { model.showOverdueTasks(of: card.project.id) } label: { chip }
                .buttonStyle(.plain)
                .help("Show the overdue tasks")
        } else {
            chip
        }
    }

    private var sprintCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            if card.project.usesSprints {
                FocusProgressBar(fraction: card.sprintPlanned == 0 ? 0 : Double(card.sprintDone) / Double(card.sprintPlanned), height: 5)
                Text(card.sprintPlanned == 0 ? "Nothing planned" : "\(card.sprintDone) of \(card.sprintPlanned) done")
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
            } else {
                Text("No sprints · \(card.openCount) open").font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
            }
        }
    }

    private var mixCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            if mix.hasTypedWork {
                SprintMixBar(mix: mix, height: 5)
                Text("\(Focus.durationString(minutes: mix.makeMinutes)) · \(Focus.durationString(minutes: mix.reachMinutes))")
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
            } else {
                Text("–").font(Focus.meta).foregroundColor(Focus.text3)
            }
        }
        .help(mix.hasTypedWork ? "Planned in \(store.sprint.name): \(mix.label)" : "No typed tasks planned")
    }

    @ViewBuilder
    private var playButton: some View {
        if card.isRunning {
            FocusTimerRing(progress: runningProgress, isRunning: true, size: 26, label: "\(card.project.name) timers") {
                store.pauseTimers(projectId: card.project.id)
            }
            .help("Pause \(card.project.name)")
        } else if let id = card.nextTaskId, let task = store.task(id) {
            FocusTimerRing(progress: store.progress(task, now: now), isRunning: false, size: 26, label: task.title) {
                store.startTimer(id)
                model.show(.init(message: "Started \(task.title)", openTaskId: id))
            }
            .help("Start \(task.title)")
        } else {
            Color.clear.frame(width: 26, height: 26)
        }
    }

    private var runningProgress: Double {
        store.runningTasks.first { $0.projectId == card.project.id }.map { store.progress($0, now: now) } ?? 0
    }
}
