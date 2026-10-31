import SwiftUI

// The project panel's settings: the icon picker, the capacity field, and the defaults for new
// tasks and for opening the project (see TaskStore+Capacity.swift).

// MARK: - Icon

/// The project's tile as a button; a click opens the icon picker.
struct ProjectIconButton: View {
    @EnvironmentObject private var store: TaskStore
    let project: Project

    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 8) {
                FocusProjectTile(project: project, size: 22)
                Text(iconName).font(Focus.control).foregroundColor(Focus.text2).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Focus.text3)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(height: Focus.controlHeight)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusPointerCursor()
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            ProjectIconPicker(project: project) { icon in
                store.setProjectIcon(project.id, icon)
                picking = false
            }
        }
        .accessibilityLabel("Project icon, \(iconName)")
    }

    private var iconName: String {
        switch project.icon {
        case .emoji?: return "Emoji"
        case .symbol?: return "Symbol"
        case nil: return "Letter \(project.initial)"
        }
    }
}

/// Popover: the letter, a grid of emoji (or type any), and a grid of SF Symbols in the project color.
struct ProjectIconPicker: View {
    let project: Project
    let pick: (ProjectIcon?) -> Void

    @State private var typed = ""

    static let emoji = ["🚀", "🧭", "🛠️", "📦", "🧪", "📱", "💻", "🌐", "🎨", "✍️", "📚", "🎯",
                        "📈", "💡", "🔒", "⚡️", "🌱", "🏠", "🎧", "🎮", "🧩", "🗂️", "🧾", "❤️"]
    static let symbols = ["hammer", "wrench.and.screwdriver", "shippingbox", "paintbrush", "book", "flag",
                          "star", "bolt", "leaf", "globe", "house", "briefcase",
                          "chart.bar", "cpu", "terminal", "doc.text", "camera", "music.note",
                          "gamecontroller", "heart", "lock", "cart", "airplane", "graduationcap"]

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { pick(nil) } label: {
                    HStack(spacing: 8) {
                        FocusProjectTile(name: project.name, colorHex: project.colorHex, size: 22)
                        Text("Letter").font(Focus.control).foregroundColor(Focus.text)
                        if project.icon == nil {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(Focus.text2)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: Focus.controlHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                TextField("Type an emoji", text: $typed)
                    .focusField()
                    .frame(width: 120)
                    .onSubmit(useTyped)
                    .onChange(of: typed) { _ in if ProjectIcon.emoji(from: typed) != nil { useTyped() } }
            }
            FocusCaption(text: "Emoji")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Self.emoji, id: \.self) { emoji in
                    cell(selected: project.icon == .emoji(emoji), help: emoji) { pick(.emoji(emoji)) } label: {
                        Text(emoji).font(.system(size: 17))
                    }
                }
            }
            FocusCaption(text: "Symbols")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    cell(selected: project.icon == .symbol(symbol), help: symbol) { pick(.symbol(symbol)) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: project.colorHex))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 290)
        .background(Focus.raised)
        .focusLight()
    }

    private func useTyped() {
        guard let icon = ProjectIcon.emoji(from: typed) else { return }
        typed = ""
        pick(icon)
    }

    private func cell<Label: View>(selected: Bool, help: String, action: @escaping () -> Void,
                                   @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(selected ? Focus.selected : .clear))
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(selected ? Focus.text3 : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(FocusIconCellStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A hover fill for the picker's grid cells.
private struct FocusIconCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverCell(configuration: configuration)
    }

    private struct HoverCell: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(hovering ? Focus.hover : .clear))
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Capacity

/// "Hours per week on this project": a number of hours with − and +, empty when not set.
struct CapacityField: View {
    @EnvironmentObject private var store: TaskStore
    let project: Project

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            step("minus") { max(0, (project.weeklyCapacityHours ?? 0) - 1) }
                .disabled((project.weeklyCapacityHours ?? 0) <= 0)
            TextField("Not set", text: $text)
                .textFieldStyle(.plain)
                .font(Focus.control.monospacedDigit())
                .foregroundColor(Focus.text)
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { f in if !f { commit() } }
                .accessibilityLabel("Hours per week on this project")
            if project.weeklyCapacityHours != nil {
                Text("h / week").font(Focus.meta).foregroundColor(Focus.text3).fixedSize()
            }
            step("plus") { (project.weeklyCapacityHours ?? 0) + 1 }
        }
        .frame(height: Focus.controlHeight)
        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(focused ? Focus.lineStrong : Focus.hairline, lineWidth: 1))
        .onAppear { text = Self.text(project.weeklyCapacityHours) }
        .onChange(of: project.weeklyCapacityHours) { hours in if !focused { text = Self.text(hours) } }
    }

    static func text(_ hours: Double?) -> String {
        guard let hours else { return "" }
        return hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
    }

    /// "20", "7.5", "20h"; blank or 0 clears it
    static func parse(_ text: String) -> Double? {
        let cleaned = text.lowercased().replacingOccurrences(of: "h", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned).flatMap { $0 > 0 ? $0 : nil }
    }

    private func commit() {
        let hours = Self.parse(text)
        if hours != project.weeklyCapacityHours { store.setWeeklyCapacity(project.id, hours: hours) }
        text = Self.text(Project.cleanCapacity(hours))
    }

    private func step(_ icon: String, _ value: @escaping () -> Double) -> some View {
        Button {
            let hours = value()
            store.setWeeklyCapacity(project.id, hours: hours)
            text = Self.text(Project.cleanCapacity(hours))
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Focus.text2)
                .frame(width: 28, height: Focus.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "One hour more" : "One hour less")
    }
}

// MARK: - Defaults

/// "Opens on", "Expected time" and "Sprint" for new tasks.
struct ProjectDefaultsSection: View {
    @EnvironmentObject private var store: TaskStore
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FocusCaption(text: "Defaults").padding(.top, 12)
            SidePanelProperty(label: "Opens on") {
                FocusPicker(
                    options: [nil] + ProjectView.allCases.filter { $0 != .sprints || project.usesSprints }.map { Optional($0) },
                    selection: Binding(get: { project.defaultView }, set: { store.setDefaultView(project.id, $0) }),
                    title: { $0?.title ?? "Last used" }
                )
                .accessibilityLabel("Opens on")
            }
            SidePanelProperty(label: "New task time") {
                FocusPicker(
                    options: [nil] + TaskItem.expectedChoices.map { Optional($0) },
                    selection: Binding(get: { project.defaultExpectedMinutes }, set: { store.setDefaultExpectedMinutes(project.id, $0) }),
                    title: { $0.map { Focus.durationString(minutes: $0) } ?? "\(Focus.durationString(minutes: TaskItem.defaultExpectedMinutes)) (standard)" }
                )
                .accessibilityLabel("Expected time of new tasks")
            }
            if project.usesSprints {
                SidePanelProperty(label: "New task sprint") {
                    FocusPicker(
                        options: SprintSlot.plannable,
                        selection: Binding(get: { project.defaultSprintSlot }, set: { store.setDefaultSprintSlot(project.id, $0) }),
                        title: { slot in
                            switch slot {
                            case .active: return "Active sprint"
                            case .next: return "Next sprint"
                            default: return "Backlog"
                            }
                        }
                    )
                    .accessibilityLabel("Sprint of new tasks")
                }
            }
            Text(hint)
                .font(.system(size: 12))
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { FocusDivider() }
    }

    private var hint: String {
        let opens = project.defaultView.map { "Opens on \($0.title) from the sidebar, menu bar and Overview." }
            ?? "Opens on the view you used last."
        return opens + " A group, column or typed word still picks a new task's sprint and time."
    }
}
