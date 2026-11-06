import SwiftUI

// The cards that answer "what now" and "am I balanced" in one place each:
//
//   WeekMixCard     Today and Overview: the time tracked this week, Make against Reach, with the
//                   sprint's Reach target and a plain sentence when one side is behind
//   StartNextCard   Today: the one task Next best ranks first, with a big play button and Skip
//   SprintCard      Sprints: the sprint's dates, its plan against capacity, the Make / Reach split
//                   of the plan, per-project capacity (All projects), Fill sprint and the ⋯ menu
//   NoticeCard      a short sentence with one action (List: "Nothing from BotX is in Sprint 2")

/// Make is the product work, Reach getting it to people. The colors match SprintMixBar.
enum MixColors {
    static let make = Focus.text3
    static let reach = Color(hex: 0x2FB67C)
    static let reachText = Color(hex: 0x1B7A50)
}

/// The tint of a "needs you" verdict (Overview) and of notices.
enum VerdictTone: Equatable {
    case risk, warn, good, live

    var fill: Color {
        switch self {
        case .risk: return Focus.riskTint.fill
        case .warn: return Focus.progressTint.fill
        case .good: return Color(hex: 0xE8F5EC)
        case .live: return Focus.liveSoft
        }
    }

    var text: Color {
        switch self {
        case .risk: return Focus.riskTint.text
        case .warn: return Focus.progressTint.text
        case .good: return Color(hex: 0x1F6B40)
        case .live: return Focus.liveText
        }
    }
}

/// "Make 14h · Reach 3h (18%)" with a sentence when a side is behind.
enum MixWords {
    static func sentence(_ mix: SprintMix, picking: Bool) -> String? {
        switch mix.behind {
        case .reach?: return picking ? "Reach is behind, so the next pick is Reach work." : "Reach is behind its target."
        case .make?: return picking ? "Make is behind, so the next pick is product work." : "Make is behind its target."
        case nil: return nil
        }
    }
}

// MARK: - Week mix

/// This week's tracked time, Make against Reach, with the target to change in place.
struct WeekMixCard: View {
    @EnvironmentObject private var store: TaskStore
    /// Today says what the next pick does about it
    var picking = false

    var body: some View {
        LiveTime { now in
            content(store.trackedMix(in: PortfolioRules.weekInterval(now), now: now))
        }
    }

    private func content(_ mix: SprintMix) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FocusCaption(text: "This week · Make vs Reach")
                Spacer(minLength: 8)
                Text("Reach target").font(Focus.meta).foregroundColor(Focus.text3)
                FocusPicker(
                    options: [nil] + SprintState.reachTargetChoices.map(Optional.some),
                    selection: Binding(get: { store.sprint.reachTargetPercent }, set: { store.setReachTarget($0) }),
                    title: { $0.map { "\($0)%" } ?? "None" }
                )
                .fixedSize()
            }
            SprintMixBar(mix: mix, height: 10)
            HStack(spacing: 6) {
                if mix.hasTypedWork {
                    Text("Make \(Focus.durationString(minutes: mix.makeMinutes))")
                        .font(Focus.rowStrong.monospacedDigit()).foregroundColor(Focus.text)
                    Text("·").foregroundColor(Focus.text3)
                    Text("Reach \(Focus.durationString(minutes: mix.reachMinutes))")
                        .font(Focus.rowStrong.monospacedDigit()).foregroundColor(MixColors.reachText)
                    if let percent = mix.reachPercent {
                        Text("(\(percent)%)").font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text3)
                    }
                    Spacer(minLength: 8)
                    if let sentence = MixWords.sentence(mix, picking: picking) {
                        Text(sentence).font(Focus.meta.weight(.semibold)).foregroundColor(Focus.progressTint.text)
                    }
                } else {
                    Text("Nothing typed tracked this week yet. Give tasks a type (Make or Reach) and start their timers to see the balance.")
                        .font(Focus.meta)
                        .foregroundColor(Focus.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusPanel()
        .help(help(mix))
    }

    private func help(_ mix: SprintMix) -> String {
        var text = "Time tracked this week on typed tasks."
        if mix.untypedMinutes > 0 { text += " \(Focus.durationString(minutes: mix.untypedMinutes)) was on tasks without a type." }
        return text
    }
}

// MARK: - Start next

/// The first task Next best ranks (minus skipped ones): one big play button, why it's first, Skip.
struct StartNextCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel

    /// The task the card shows, or nil when there's nothing to rank.
    @MainActor
    static func pick(store: TaskStore, model: TasksViewModel, now: Date = Date()) -> NextBestItem? {
        store.nextBest(now: now).ranked.first { !model.skippedNextBest.contains($0.task.id) }
    }

    var body: some View {
        LiveTime { now in
            if let item = Self.pick(store: store, model: model, now: now) {
                card(item, now: now)
            }
        }
    }

    private func card(_ item: NextBestItem, now: Date) -> some View {
        let task = item.task
        let project = store.project(task.projectId)
        let type = store.taskType(of: task)
        return VStack(alignment: .leading, spacing: 8) {
            FocusCaption(text: "Start next")
            HStack(spacing: 14) {
                FocusTimerRing(progress: store.progress(task, now: now), isRunning: false, size: 40, label: "Start \(task.title)") {
                    store.startTimer(task.id)
                    model.show(.init(message: "Started \(task.title)", openTaskId: task.id))
                }
                .help("Start \(task.title)")
                VStack(alignment: .leading, spacing: 3) {
                    Button { model.clickTitle(task.id, store: store, modifiers: []) } label: {
                        Text(task.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Focus.text)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .focusPointerCursor()
                    .help("Open the task")
                    HStack(spacing: 6) {
                        if let project {
                            FocusProjectTile(project: project, size: 14)
                            Text(project.name).font(Focus.meta).foregroundColor(Focus.text2)
                        }
                        if let type {
                            Text("·").foregroundColor(Focus.text3)
                            Circle().fill(Color(hex: type.colorHex)).frame(width: 7, height: 7)
                            Text("\(type.name) · \(type.bucket.title)").font(Focus.meta)
                                .foregroundColor(type.bucket == .reach ? MixColors.reachText : Focus.text2)
                        }
                        Text("·").foregroundColor(Focus.text3)
                        Text(why(item.score)).font(Focus.meta).foregroundColor(Focus.text3)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 12)
                Button("Skip") {
                    model.skippedNextBest.insert(task.id)
                }
                .buttonStyle(.focus(.ghost))
                .help("Show the next one. Right-click a task › Next best to change its rank for good.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Focus.radiusPanel).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusPanel).strokeBorder(Focus.doneTint.border, lineWidth: 1.5))
        .help("Score \(item.score.score): \(item.score.reason)")
    }

    /// "Impact 8 · 30m left · closes the Reach gap"
    private func why(_ score: NextBestScore) -> String {
        var parts: [String] = []
        if score.pinnedTop { parts.append("sent to top") }
        parts.append("impact \(score.impact)")
        parts.append("\(Focus.durationString(minutes: score.minutesLeft)) left")
        if score.boost > 0, let type = score.typeName { parts.append("\(type) closes the gap") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sprint card

/// The Sprints tab's one place for the sprint's numbers.
struct SprintCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope

    @State private var showingMenu = false

    /// The planned bar and the Make / Reach bar side by side, the same thickness
    static let barHeight: CGFloat = 10

    var body: some View {
        LiveTime { now in
            content(now: now)
        }
    }

    private func content(now: Date) -> some View {
        let sprint = store.sprint
        let load = store.slotLoad(scope: scope, slot: .active, now: now)
        let mix = store.sprintMix(scope: scope)
        let day = PortfolioRules.sprintDay(sprint, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(sprint.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Focus.text)
                Text("· \(sprint.dateRange) · \(daysLeft(day))").font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                if !sprint.goal.isEmpty {
                    Text("· \(sprint.goal)").font(Focus.meta).foregroundColor(Focus.text2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { showingMenu = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).frame(width: 18)
                }
                .buttonStyle(.focus(.ghost))
                .help("Goal, dates, Reach target, Plan sprints, Complete sprint")
                .accessibilityLabel("Sprint menu")
                .popover(isPresented: $showingMenu, arrowEdge: .bottom) {
                    SprintMenu(scope: scope, close: { showingMenu = false })
                        .environmentObject(store)
                        .environmentObject(model)
                }
                Button("Fill sprint") { SprintActions.fill(scope: scope, store: store, model: model) }
                    .buttonStyle(.focus(.primary))
                    .help(GroupHeaderAction.fillToCapacity(scope: scope).help)
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(Focus.durationString(minutes: load.plannedMinutes)).font(Focus.rowStrong.monospacedDigit())
                            .foregroundColor(CapacityColors.color(load.level) == Focus.text3 ? Focus.text : CapacityColors.color(load.level))
                        Text(load.capacityMinutes.map { "of \(Focus.durationString(minutes: $0)) planned" } ?? "planned")
                            .font(Focus.meta).foregroundColor(Focus.text3)
                        Spacer(minLength: 0)
                        Text("\(store.sprintCompletion(scope: scope).percentText) done")
                            .font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text3)
                    }
                    PlanBar(fraction: fraction(load.plannedMinutes, load.capacityMinutes), level: load.level, height: SprintCard.barHeight)
                    if load.capacityMinutes == nil {
                        Text("Set Hours per week in the project's settings to plan against your capacity.")
                            .font(Focus.meta).foregroundColor(Focus.text3)
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Make \(Focus.durationString(minutes: mix.makeMinutes))").font(Focus.rowStrong.monospacedDigit())
                        Text("·").foregroundColor(Focus.text3)
                        Text("Reach \(Focus.durationString(minutes: mix.reachMinutes))").font(Focus.rowStrong.monospacedDigit())
                            .foregroundColor(MixColors.reachText)
                        Spacer(minLength: 0)
                        Text(mix.targetPercent.map { "target \($0)% Reach" } ?? "no target")
                            .font(Focus.meta).foregroundColor(Focus.text3)
                    }
                    SprintMixBar(mix: mix, height: SprintCard.barHeight)
                    if let sentence = MixWords.sentence(mix, picking: false) {
                        Text(sentence).font(Focus.meta.weight(.semibold)).foregroundColor(Focus.progressTint.text)
                    } else if !mix.hasTypedWork {
                        Text("No typed tasks planned yet.").font(Focus.meta).foregroundColor(Focus.text3)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if scope.projectId == nil {
                projectRows(now: now)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusPanel()
    }

    /// All projects: each sprint project's plan against its own capacity.
    @ViewBuilder
    private func projectRows(now: Date) -> some View {
        let projects = store.projects.filter(\.usesSprints)
        if projects.count > 1 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 24)], alignment: .leading, spacing: 8) {
                ForEach(projects) { project in
                    let load = store.slotLoad(scope: .project(project.id), slot: .active, now: now)
                    HStack(spacing: 8) {
                        FocusProjectTile(project: project, size: 16)
                        Text(project.name).font(Focus.meta).foregroundColor(Focus.text2).lineLimit(1).frame(width: 70, alignment: .leading)
                        PlanBar(fraction: fraction(load.plannedMinutes, load.capacityMinutes), level: load.level, height: 6)
                        Text(load.capacityMinutes.map { "\(Focus.durationString(minutes: load.plannedMinutes)) of \(Focus.durationString(minutes: $0))" }
                             ?? Focus.durationString(minutes: load.plannedMinutes))
                            .font(Focus.meta.monospacedDigit())
                            .foregroundColor(load.plannedMinutes == 0 ? Focus.progressTint.text : Focus.text3)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }

    private func fraction(_ planned: Int, _ capacity: Int?) -> Double {
        guard let capacity, capacity > 0 else { return 0 }
        return min(1, Double(planned) / Double(capacity))
    }

    private func daysLeft(_ day: SprintDay) -> String {
        if !day.hasStarted { return "starts \(SprintState.shortDate(store.sprint.startDate))" }
        if day.isOver { return "ended, complete it in ⋯" }
        let left = day.length - day.day + 1
        return "\(left) \(left == 1 ? "day" : "days") left"
    }
}

/// Planned against capacity, drawn like SprintMixBar so the two read as a pair: the track, the
/// plan in the done color, amber from 90% and red past the capacity.
struct PlanBar: View {
    let fraction: Double
    let level: CapacityLevel
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Focus.ringTrack)
                if fraction > 0 {
                    Capsule().fill(color).frame(width: max(height, min(1, fraction) * geo.size.width))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Planned")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent of capacity")
    }

    private var color: Color {
        switch level {
        case .under: return Focus.done
        case .near: return Focus.progress
        case .over: return Focus.risk
        }
    }
}

/// Fill sprint, shared by the sprint card and the Suggested group's Add all.
enum SprintActions {
    @MainActor
    static func fill(scope: TaskScope, store: TaskStore, model: TasksViewModel) {
        guard store.sprintCapacityMinutes(in: scope) != nil else {
            model.show(.init(message: "Set Hours per week in the project's settings first: the sprint fills up to that capacity"))
            return
        }
        let moved = store.fillSprintToCapacity(scope: scope)
        if moved.isEmpty {
            model.show(.init(message: "Nothing in the backlog fits what's left of the capacity"))
        } else {
            model.showUndoToast("\(TaskStore.taskCount(moved.count)) added to \(store.sprintName())", store: store)
        }
    }
}

// MARK: - Notice

/// What a notice's button does.
enum NoticeAction: Equatable {
    /// Switch to the Sprints tab
    case planInSprints

    var title: String {
        switch self {
        case .planInSprints: return "Plan in Sprints"
        }
    }
}

/// One sentence with one button, in amber.
struct NoticeCard: View {
    @EnvironmentObject private var model: TasksViewModel
    let text: String
    let action: NoticeAction?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Focus.progress)
            Text(text).font(Focus.body).foregroundColor(Focus.progressTint.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.title) {
                    switch action {
                    case .planInSprints: model.tab = .sprints
                    }
                }
                .buttonStyle(.focus())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Focus.radiusPanel).fill(Focus.progressTint.fill))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusPanel).strokeBorder(Focus.progressTint.border, lineWidth: 1))
    }
}
