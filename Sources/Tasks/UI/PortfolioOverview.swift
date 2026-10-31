import SwiftUI

/// All projects › Overview: a card per active project, so a slipping one shows without opening
/// each. Ordered by need for attention (overdue or at-risk milestone, overdue tasks, untouched for
/// a week) with a toggle for Name and Recent activity. A card opens its project; the overdue count
/// opens its List filtered to overdue; the milestone opens its page; the ring starts the next task.
struct PortfolioOverview: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    static let cardMinWidth: CGFloat = 300
    static let spacing: CGFloat = 16

    var body: some View {
        // Hours tracked and "Untouched N days" move with the clock
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let cards = store.portfolio(sortedBy: model.overviewSort, now: now)
        let attention = cards.filter { $0.attentionLevel > 0 }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(summary(count: cards.count, attention: attention))
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("Sort").font(Focus.meta).foregroundColor(Focus.text3)
                FocusTabs(options: PortfolioSort.allCases.map { (value: $0, label: $0.title) }, selection: $model.overviewSort)
                    .fixedSize()
                    .accessibilityLabel("Sort projects")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardMinWidth), spacing: Self.spacing, alignment: .top)],
                      alignment: .leading, spacing: Self.spacing) {
                ForEach(cards) { card in
                    ProjectOverviewCard(card: card, now: now)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(count: Int, attention: Int) -> String {
        let projects = "\(count) \(count == 1 ? "project" : "projects")"
        switch attention {
        case 0: return "\(projects) · all on track"
        case 1: return "\(projects) · 1 needs attention"
        default: return "\(projects) · \(attention) need attention"
        }
    }
}

/// One project on the Overview: tile and name with the play ring, the sprint line and bar, hours
/// tracked, overdue and in-progress counts, the next milestone and the last activity.
struct ProjectOverviewCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let card: ProjectOverview
    let now: Date

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .padding(.bottom, 12)
            sprintBlock
                .padding(.bottom, 14)
            stats
                .padding(.bottom, 14)
            FocusDivider()
            milestoneBlock
                .padding(.vertical, 12)
            FocusDivider()
            activityRow
                .padding(.top, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard)
            .strokeBorder(hovering ? Focus.lineStrong : Focus.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Focus.radiusCard))
        .onTapGesture { model.select(.project(card.project.id)) }
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAction(named: "Open project") { model.select(.project(card.project.id)) }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 10) {
            FocusProjectTile(project: card.project, size: 22)
            Text(card.project.name)
                .font(Focus.header)
                .foregroundColor(Focus.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if card.isRunning { FocusLiveDot() }
            Spacer(minLength: 8)
            playButton
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if card.isRunning {
            FocusTimerRing(progress: runningProgress, isRunning: true, size: 28, label: "\(card.project.name) timers") {
                store.pauseTimers(projectId: card.project.id)
            }
            .help("Pause \(card.project.name)")
        } else if let id = card.nextTaskId, let task = store.task(id) {
            FocusTimerRing(progress: store.progress(task, now: now), isRunning: false, size: 28, label: task.title) {
                store.startTimer(id)
                model.show(.init(message: "Started \(task.title)", openTaskId: id))
            }
            .help("Start \(task.title)")
        } else {
            FocusTimerRing(progress: 0, isRunning: false, size: 28, label: card.project.name) {}
                .disabled(true)
                .opacity(0.35)
                .help(card.project.usesSprints ? "Nothing to start: plan a task in \(card.project.sprint.name)" : "Nothing to start: add a task")
        }
    }

    private var runningProgress: Double {
        store.runningTasks.first { $0.projectId == card.project.id }.map { store.progress($0, now: now) } ?? 0
    }

    // MARK: - Sprint

    private var sprintBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: card.project.usesSprints ? "arrow.clockwise" : "tray.full")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Focus.text3)
                Text(card.sprintLine)
                    .font(Focus.meta)
                    .foregroundColor(card.project.usesSprints && card.sprintDay.isOver ? Focus.progress : Focus.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(card.sprintPlanned == 0 ? "Nothing planned" : "\(card.sprintDone) of \(card.sprintPlanned) done")
                    .font(Focus.meta.monospacedDigit())
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
                    .fixedSize()
            }
            FocusProgressBar(fraction: card.sprintPlanned == 0 ? 0 : Double(card.sprintDone) / Double(card.sprintPlanned))
                .help(!card.project.usesSprints ? "Done of every task on the board (no sprints)"
                      : card.sprintDay.isOver ? "The sprint's last day has passed: complete it in Sprints" : card.project.sprint.dateRange)
        }
    }

    // MARK: - Numbers

    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            if card.project.usesSprints { stat(Self.hours(card.trackedInSprint), "this sprint") }
            stat(Self.hours(card.trackedThisWeek), "this week")
            overdueStat
            stat("\(card.inProgressCount)", "in progress")
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = Focus.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
            Text(label)
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var overdueStat: some View {
        if card.overdueCount > 0 {
            OverdueStatButton(count: card.overdueCount) { model.showOverdueTasks(of: card.project.id) }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            stat("0", "overdue", color: Focus.text3)
        }
    }

    /// "3h 10m", "45m", "0m"
    static func hours(_ seconds: TimeInterval) -> String {
        Focus.durationString(minutes: Int((seconds / 60).rounded(.down)))
    }

    // MARK: - Milestone

    @ViewBuilder
    private var milestoneBlock: some View {
        if let milestone = card.nextMilestone, let forecast = card.nextMilestoneForecast {
            OverviewMilestoneButton(milestone: milestone, forecast: forecast, now: now) {
                model.showMilestone(milestone.id, store: store)
            }
        } else {
            HStack(spacing: 10) {
                MilestoneIcon(completed: false, colorHex: nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No open milestone").font(Focus.row).foregroundColor(Focus.text3).lineLimit(1)
                    Text("Add one in the project's Milestones tab").font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 40)
        }
    }

    // MARK: - Activity

    private var activityRow: some View {
        HStack(spacing: 6) {
            Image(systemName: card.isStale ? "moon.zzz" : "clock")
                .font(.system(size: 10.5, weight: .semibold))
            Text(card.isRunning ? "Running now" : PortfolioRules.activityLabel(untouchedDays: card.untouchedDays))
                .font(Focus.meta)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundColor(card.isStale && !card.isRunning ? Focus.progress : Focus.text3)
        .help("Last change \(TaskDates.dueLabel(card.lastActivity, now: now))")
    }

    private var accessibilitySummary: String {
        var parts = [card.project.name, card.sprintLine, "\(card.sprintDone) of \(card.sprintPlanned) done",
                     "\(card.overdueCount) overdue", "\(card.inProgressCount) in progress"]
        if let m = card.nextMilestone { parts.append("next milestone \(m.name)") }
        if let label = card.nextMilestoneForecast?.health.label { parts.append(label) }
        parts.append(PortfolioRules.activityLabel(untouchedDays: card.untouchedDays))
        return parts.joined(separator: ", ")
    }
}

/// The overdue count in `risk`; a click shows the project's overdue tasks.
private struct OverdueStatButton: View {
    let count: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundColor(Focus.risk)
                HStack(spacing: 3) {
                    Text("overdue").font(Focus.meta).foregroundColor(Focus.riskTint.text)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Focus.risk)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(hovering ? Focus.riskTint.fill : .clear))
            .padding(.horizontal, -6)
            .padding(.vertical, -2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help("Show the overdue tasks")
        .accessibilityLabel("\(count) overdue, show them")
    }
}

/// The next milestone: diamond, name, its flag, then progress, due date and hours left.
private struct OverviewMilestoneButton: View {
    let milestone: Milestone
    let forecast: MilestoneForecast
    let now: Date
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                MilestoneIcon(milestone)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(milestone.name)
                            .font(Focus.rowStrong)
                            .foregroundColor(Focus.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        dueText
                    }
                    HStack(spacing: 8) {
                        FocusProgressBar(fraction: forecast.progress.fraction)
                        Text("\(forecast.progress.done) of \(forecast.progress.total)")
                            .font(Focus.meta.monospacedDigit())
                            .foregroundColor(Focus.text3)
                            .fixedSize()
                        Text("·").font(Focus.meta).foregroundColor(Focus.text3)
                        Text(forecast.remainingLabel)
                            .font(Focus.meta.monospacedDigit())
                            .foregroundColor(forecast.health == .atRisk ? Focus.risk : Focus.text3)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(hovering ? Focus.hover : .clear))
            .padding(.horizontal, -6)
            .padding(.vertical, -4)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusPointerCursor()
        .help(helpText)
        .accessibilityLabel("\(milestone.name), \(forecast.progress.label), \(forecast.remainingLabel)\(forecast.health.label.map { ", " + $0 } ?? "")")
        .accessibilityHint("Shows the milestone")
    }

    @ViewBuilder
    private var dueText: some View {
        let risky = forecast.health.needsAttention
        HStack(spacing: 4) {
            if risky {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9.5, weight: .bold))
            }
            Text(dueLabel).font(Focus.meta).lineLimit(1)
        }
        .foregroundColor(risky ? Focus.risk : Focus.text3)
        .fixedSize()
    }

    private var dueLabel: String {
        guard let due = milestone.dueDate else { return "No date" }
        let date = "Due " + TaskDates.dueLabel(due, now: now)
        return forecast.health.label.map { "\($0) · \(date)" } ?? date
    }

    private var helpText: String {
        var text = "\(milestone.name): \(forecast.progress.label), \(forecast.remainingLabel)"
        if forecast.health == .atRisk, let available = forecast.hoursAvailable {
            text += ". At risk: about \(Focus.durationString(minutes: Int(available * 60))) of working time before it's due"
        } else if forecast.health == .overdue {
            text += ". Past its due date"
        }
        return text
    }
}
