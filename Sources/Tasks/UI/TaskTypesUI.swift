import SwiftUI

// Task types, impact pickers, the sprint's Make / Reach mix and the Next best panel on Today.
// The rules live in TaskStore+Ranking.swift.

// MARK: - Pickers

/// The task panel's Type field: the workspace's types by bucket, None, and Edit types….
struct TaskTypeField: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    var body: some View {
        let current = store.taskType(of: task)
        Menu {
            ForEach(TypeBucket.allCases) { bucket in
                let types = store.taskTypes.filter { $0.bucket == bucket }
                if !types.isEmpty {
                    Section(bucket.title) {
                        ForEach(types) { type in
                            Button {
                                store.setType([task.id], type.id)
                            } label: {
                                if type.id == task.typeId {
                                    SwiftUI.Label(type.name, systemImage: "checkmark")
                                } else {
                                    Text(type.name)
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("None") { store.setType([task.id], nil) }
            Button("Edit types…") { model.showingTypesManager = true }
        } label: {
            HStack(spacing: 7) {
                if let current {
                    Circle().fill(Color(hex: current.colorHex)).frame(width: 8, height: 8)
                    Text(current.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                    Text(current.bucket.title).font(Focus.meta).foregroundColor(Focus.text3)
                } else {
                    Text("None").font(Focus.control).foregroundColor(Focus.text3)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Focus.text3)
            }
            .focusField()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Type")
    }
}

/// A 1–10 impact dropdown with an inherit choice: "Inherit · 7" when nil.
struct ImpactPicker: View {
    let value: Int?
    /// What nil means here, e.g. "Inherit · 7" or "Not set · 5"
    let unsetTitle: String
    let onChange: (Int?) -> Void

    var body: some View {
        FocusPicker(
            options: [nil] + ImpactScale.choices.map(Optional.some),
            selection: Binding(get: { value }, set: onChange),
            title: { $0.map(ImpactScale.title) ?? unsetTitle }
        )
        .accessibilityLabel("Impact")
    }
}

// MARK: - Types sheet

/// Add, rename, re-bucket, re-weigh and delete the workspace's task types.
struct TaskTypesSheet: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newBucket: TypeBucket = .reach
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @FocusState private var newFocused: Bool

    var body: some View {
        let usage = store.typeUsage()
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Task types").font(Focus.pageTitle).foregroundColor(Focus.text)
                Text("Make is building and running the product; Reach is customers, sales and marketing. The sprint compares the two, and impact (1–10) moves a type's tasks in Next best. Type ^name in any New task box.")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            VStack(spacing: 0) {
                ForEach(Array(store.taskTypes.enumerated()), id: \.element.id) { index, type in
                    row(type, count: usage[type.id] ?? 0)
                        .overlay(alignment: .top) { if index > 0 { FocusDivider() } }
                }
                if store.taskTypes.isEmpty {
                    Text("No types. Add one below.")
                        .font(Focus.body)
                        .foregroundColor(Focus.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                FocusDivider()
                newRow
            }
            .focusPanel()
            .padding(.horizontal, 24)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.focus())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560)
        .background(Focus.canvas)
        .focusLight()
    }

    private func row(_ type: TaskType, count: Int) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(TaskLabel.palette, id: \.self) { hex in
                    Button(Focus.colorName(hex)) { store.setTypeColor(type.id, hex) }
                }
            } label: {
                Circle().fill(Color(hex: type.colorHex)).frame(width: 12, height: 12)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Color of \(type.name)")

            if renaming == type.id {
                TextField("Type name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .focused($renameFocused)
                    .onSubmit { finishRename(type.id) }
                    .onExitCommand { renaming = nil }
                    .onChange(of: renameFocused) { focused in if !focused, renaming == type.id { finishRename(type.id) } }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(Focus.raised))
            } else {
                Button {
                    renameText = type.name
                    renaming = type.id
                    DispatchQueue.main.async { renameFocused = true }
                } label: {
                    Text(type.name).font(Focus.control).foregroundColor(Focus.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to rename")
            }
            FocusPicker(
                options: TypeBucket.allCases,
                selection: Binding(get: { type.bucket }, set: { store.setTypeBucket(type.id, $0) }),
                title: { $0.title }
            )
            .frame(width: 92)
            .help(type.bucket.help)
            FocusPicker(
                options: ImpactScale.choices,
                selection: Binding(get: { type.impact }, set: { store.setTypeImpact(type.id, $0) }),
                title: { "Impact \($0)" }
            )
            .frame(width: 104)
            Text(count == 0 ? "Unused" : "\(count) \(count == 1 ? "task" : "tasks")")
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(Focus.text3)
                .frame(width: 58, alignment: .trailing)
            FocusIconButton(systemName: "trash", label: "Delete \(type.name)", size: 24) {
                store.deleteTaskType(type.id)
            }
            .help(count > 0 ? "Delete; its \(count) \(count == 1 ? "task becomes" : "tasks become") untyped. ⌘Z brings it back." : "Delete")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 42)
    }

    private var newRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Focus.text3)
                .frame(width: 22)
            TextField("New type", text: $newName)
                .textFieldStyle(.plain)
                .font(Focus.control)
                .focused($newFocused)
                .onSubmit {
                    guard store.addTaskType(newName, bucket: newBucket) != nil else { return }
                    newName = ""
                    DispatchQueue.main.async { newFocused = true }
                }
                .accessibilityLabel("New type name")
            FocusPicker(options: TypeBucket.allCases, selection: $newBucket, title: { $0.title })
                .frame(width: 92)
            if !newName.isEmpty { FocusKey(text: "↵ add") }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 42)
    }

    private func finishRename(_ id: UUID) {
        guard renaming == id else { return }
        _ = store.renameTaskType(id, to: renameText)
        renaming = nil
    }
}

// MARK: - Mix

/// A thin two-part bar: Make in the neutral color, Reach in green, and a tick at the target.
struct SprintMixBar: View {
    let mix: SprintMix

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let reach = CGFloat(mix.reachPercent ?? 0) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Focus.ringTrack)
                if mix.hasTypedWork {
                    HStack(spacing: 2) {
                        if mix.makeMinutes > 0 {
                            Capsule().fill(Focus.text3).frame(width: max(3, (width - 2) * (1 - reach)))
                        }
                        if mix.reachMinutes > 0 {
                            Capsule().fill(Color(hex: 0x2FB67C)).frame(width: max(3, (width - 2) * reach))
                        }
                    }
                }
                if let target = mix.targetPercent {
                    // Reach sits on the right, so its target share is measured from the right edge
                    Rectangle().fill(Focus.text)
                        .frame(width: 2, height: 10)
                        .offset(x: width * (1 - CGFloat(target) / 100) - 1)
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("\(mix.label). \(mix.shareLabel ?? "")")
    }
}

/// The mix in a sprint group header: "Make 14h · Reach 3h", amber with "Reach is light".
struct SprintMixHint: View {
    let mix: SprintMix

    var body: some View {
        if mix.hasTypedWork {
            Text("· " + mix.label + (mix.warning.map { " · \($0)" } ?? ""))
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(mix.behind == nil ? Focus.text3 : Focus.progress)
                .lineLimit(1)
                .help(help)
        }
    }

    private var help: String {
        var text = (mix.shareLabel ?? "") + " of the typed time."
        if mix.untypedMinutes > 0 { text += " \(Focus.durationString(minutes: mix.untypedMinutes)) has no type." }
        if mix.targetPercent == nil { text += " Set a Reach target in the sprint menu." }
        return text
    }
}

/// The sprint menu's mix: the bar, the numbers, the target and Edit types….
struct SprintMixSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let scope: TaskScope

    var body: some View {
        let mix = store.sprintMix(scope: scope)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FocusCaption(text: "Make / Reach")
                Spacer()
                Button("Edit types…") { model.showingTypesManager = true }
                    .buttonStyle(.plain)
                    .font(Focus.meta)
                    .foregroundColor(Focus.text2)
            }
            SprintMixBar(mix: mix)
            Text(mix.hasTypedWork ? [mix.label, mix.shareLabel, mix.warning].compactMap { $0 }.joined(separator: " · ")
                                  : "No typed tasks in the sprint yet. Give tasks a type in the task panel or with ^name.")
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(mix.behind == nil ? Focus.text3 : Focus.progress)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Reach target").font(Focus.meta).foregroundColor(Focus.text2)
                FocusPicker(
                    options: [nil] + SprintState.reachTargetChoices.map(Optional.some),
                    selection: Binding(get: { store.sprint.reachTargetPercent }, set: { store.setReachTarget($0) }),
                    title: { $0.map { "\($0)% of typed time" } ?? "No target" }
                )
            }
        }
    }
}

// MARK: - Next best

/// Today's Next best: the open current work of every project ranked 0–100, with the reason on each
/// row, Send up / down / to top and Back to normal, and Keep warm rows for projects left too long.
struct NextBestPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @AppStorage("nextBestExpanded") private var expanded = false

    static let collapsedCount = 5
    static let expandedCount = 15

    var body: some View {
        LiveTime { now in
            let shown = expanded ? Self.expandedCount : Self.collapsedCount
            let list = store.nextBest(shown: shown, now: now)
            VStack(alignment: .leading, spacing: 0) {
                header(list)
                ForEach(Array(list.ranked.prefix(shown).enumerated()), id: \.element.id) { index, item in
                    NextBestRow(item: item, rank: index + 1, now: now)
                        .overlay(alignment: .top) { FocusDivider() }
                }
                if !list.keepWarm.isEmpty {
                    FocusCaption(text: "Keep warm")
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(list.keepWarm) { item in
                        NextBestRow(item: item, rank: nil, now: now)
                            .overlay(alignment: .top) { FocusDivider() }
                    }
                }
                if list.ranked.count > Self.collapsedCount {
                    Button(expanded ? "Show fewer" : "Show \(min(list.ranked.count, Self.expandedCount) - Self.collapsedCount) more") {
                        expanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(Focus.meta)
                    .foregroundColor(Focus.text2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { FocusDivider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusPanel()
        }
    }

    private func header(_ list: NextBestList) -> some View {
        let mix = store.sprintMix()
        return HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Focus.text2)
            Text("Next best").font(Focus.groupTitle).foregroundColor(Focus.text)
            Text("\(list.ranked.count)").font(Focus.row.monospacedDigit()).foregroundColor(Focus.text3)
            Text("Across every project: impact ÷ effort, 0–100")
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let warning = mix.warning {
                Text(warning).font(Focus.meta).foregroundColor(Focus.progress).lineLimit(1)
                    .help("\(mix.shareLabel ?? ""). Tasks of the light bucket get +\(ImpactRules.behindBoost).")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

/// One Next best row: rank, score, project, title and reason; hover shows the nudge buttons.
private struct NextBestRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let item: NextBestItem
    let rank: Int?
    let now: Date

    @State private var hovering = false

    var body: some View {
        let task = item.task
        let project = store.project(task.projectId)
        HStack(spacing: 10) {
            Text(rank.map { "\($0)" } ?? "")
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(Focus.text3)
                .frame(width: 16, alignment: .trailing)
            scoreBadge
            if let project {
                FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 16, icon: project.icon)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title).font(Focus.row).foregroundColor(Focus.text).lineLimit(1)
                    if let type = store.taskType(of: task) {
                        Text(type.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: type.colorHex))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(hex: type.colorHex).opacity(0.12)))
                    }
                }
                Text(item.keepWarm ?? item.score.reason)
                    .font(Focus.meta)
                    .foregroundColor(item.keepWarm == nil ? Focus.text3 : Focus.progress)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if hovering || task.isNudged { controls(task) }
            FocusTimerRing(progress: store.progress(task, now: now), isRunning: store.isRunning(task.id), size: 26, label: task.title) {
                store.toggleTimer(task.id)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(hovering ? Focus.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.openTask(task.id) }
        .contextMenu {
            Button("Send up") { store.sendNextBest(task.id, up: true) }
            Button("Send down") { store.sendNextBest(task.id, up: false) }
            Button("Send to top") { store.sendToTop(task.id) }
            if task.isNudged { Button("Back to normal") { store.resetNextBest(task.id) } }
            Divider()
            Button("Open") { model.openTask(task.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank.map { "\($0). " } ?? "")\(task.title), score \(item.score.score). \(item.keepWarm ?? item.score.reason)")
    }

    private var scoreBadge: some View {
        let score = item.score.score
        return Text("\(score)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundColor(score >= 70 ? .white : Focus.text)
            .frame(width: 32, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(score >= 70 ? Focus.done : Focus.ringTrack))
            .overlay(alignment: .topTrailing) {
                if item.score.pinnedTop {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundColor(Focus.text2).offset(x: 4, y: -4)
                }
            }
            .help("Score \(score) of 100 = \(item.score.base) base"
                + (item.score.boost > 0 ? " + \(item.score.boost) mix" : "")
                + (item.score.nudge != 0 ? " \(item.score.nudge > 0 ? "+" : "−") \(abs(item.score.nudge)) nudge" : ""))
    }

    private func controls(_ task: TaskItem) -> some View {
        HStack(spacing: 2) {
            FocusIconButton(systemName: "chevron.up", label: "Send up", size: 24) { store.sendNextBest(task.id, up: true) }
                .help(nextStepHelp(task, up: true))
            FocusIconButton(systemName: "chevron.down", label: "Send down", size: 24) { store.sendNextBest(task.id, up: false) }
                .help(nextStepHelp(task, up: false))
            FocusIconButton(systemName: "arrow.up.to.line", label: "Send to top", size: 24) { store.sendToTop(task.id) }
                .help("Send to top: first in Next best for today")
            if task.isNudged {
                FocusIconButton(systemName: "arrow.uturn.backward", label: "Back to normal", size: 24) { store.resetNextBest(task.id) }
                    .help("Back to normal: clear the nudge and the pin")
            }
        }
    }

    private func nextStepHelp(_ task: TaskItem, up: Bool) -> String {
        let result = ImpactRules.press(up: up, nudge: task.nudge, run: task.nudgeRun)
        let delta = result.nudge - task.nudge
        return "\(up ? "Send up" : "Send down") (\(delta >= 0 ? "+" : "−")\(abs(delta)))"
    }
}

// MARK: - Score popover

/// The Sprints view's Score cell popover: the number, how it's made, and the nudges.
struct TaskScoreEditor: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let close: () -> Void

    var body: some View {
        let score = store.nextBestScore(task, behind: store.sprintMix().behind)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(score.score)").font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundColor(Focus.text)
                Text("of 100").font(Focus.meta).foregroundColor(Focus.text3)
            }
            VStack(alignment: .leading, spacing: 3) {
                line("Impact", "\(score.impact) (\(score.impactSource))")
                line("Effort", "\(Focus.durationString(minutes: score.minutesLeft)) left → base \(score.base)")
                if score.boost > 0 { line("Mix", "+\(score.boost), its bucket is behind the target") }
                if score.nudge != 0 { line("Nudge", score.nudge > 0 ? "+\(score.nudge)" : "\(score.nudge)") }
                if score.pinnedTop { line("Pinned", "First in Next best today") }
            }
            FocusDivider()
            HStack(spacing: 6) {
                Button("Send up") { store.sendNextBest(task.id, up: true) }.buttonStyle(.focus(.ghost))
                Button("Send down") { store.sendNextBest(task.id, up: false) }.buttonStyle(.focus(.ghost))
                Button("To top") { store.sendToTop(task.id) }.buttonStyle(.focus(.ghost))
            }
            if task.isNudged {
                Button("Back to normal") { store.resetNextBest(task.id) }.buttonStyle(.focus(.ghost))
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .background(Focus.raised)
        .focusLight()
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(Focus.meta).foregroundColor(Focus.text3).frame(width: 52, alignment: .leading)
            Text(value).font(Focus.meta.monospacedDigit()).foregroundColor(Focus.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
