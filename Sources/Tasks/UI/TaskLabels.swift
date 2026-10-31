import AppKit
import SwiftUI

// Labels in the window: chips on rows, cards and the task panel, the multi-select picker (task
// panel, row cell, bulk bar, composer chip) and the Labels sheet that adds, renames, recolors
// and deletes them. The single-key L picker is QuickPickerView with TaskQuickAction.labels.

// MARK: - Fitting chips into a width

/// Which chips of a row fit a width, and how many are left for "+2". At least one chip shows
/// (narrowed to fit when it has to).
enum LabelChipLayout {
    static func fit(_ widths: [CGFloat], width: CGFloat, spacing: CGFloat,
                    moreWidth: (Int) -> CGFloat) -> (widths: [CGFloat], more: Int) {
        guard !widths.isEmpty else { return ([], 0) }
        for shown in stride(from: widths.count, through: 1, by: -1) {
            let rest = widths.count - shown
            let chips = widths.prefix(shown).reduce(0, +) + spacing * CGFloat(shown - 1)
            let total = chips + (rest > 0 ? spacing + moreWidth(rest) : 0)
            if total <= width { return (Array(widths.prefix(shown)), rest) }
        }
        let rest = widths.count - 1
        let room = width - (rest > 0 ? spacing + moreWidth(rest) : 0)
        return ([max(24, min(widths[0], room))], rest)
    }
}

// MARK: - Chips

/// One label: a dot in its color and the name in its darkened tint, on a 10% fill.
struct LabelChip: View {
    let label: TaskLabel
    var height: CGFloat = 20

    var body: some View {
        let tint = Focus.colorTint(label.colorHex)
        HStack(spacing: 4) {
            Circle().fill(tint.icon).frame(width: 6, height: 6)
            Text(label.name).font(.system(size: 12, weight: .medium)).foregroundColor(tint.text).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(tint.fill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Label \(label.name)")
    }

    /// The chip's width for a name, as drawn
    static func width(_ name: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        return ceil((name as NSString).size(withAttributes: [.font: font]).width) + 6 + 4 + 6 + 6
    }
}

/// A task's labels on one line, as many as fit, then "+2". Empty when it has none.
struct TaskLabelChips: View {
    let labels: [TaskLabel]

    var body: some View {
        if !labels.isEmpty {
            GeometryReader { geo in
                let layout = LabelChipLayout.fit(labels.map { LabelChip.width($0.name) }, width: geo.size.width, spacing: 4) { n in
                    ceil(("+\(n)" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width) + 6
                }
                HStack(spacing: 4) {
                    ForEach(Array(layout.widths.enumerated()), id: \.offset) { index, width in
                        LabelChip(label: labels[index]).frame(maxWidth: width, alignment: .leading)
                    }
                    if layout.more > 0 {
                        Text("+\(layout.more)").font(.system(size: 12, weight: .medium)).foregroundColor(Focus.text3)
                            .help(labels.suffix(layout.more).map(\.name).joined(separator: ", "))
                    }
                }
            }
            .frame(height: 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Labels: " + labels.map(\.name).joined(separator: ", "))
        }
    }
}

// MARK: - The picker

/// A label's check in a multi-select picker.
enum LabelCheck: Equatable {
    case off, on
    /// Some of the selected tasks have it
    case mixed
}

/// Type to filter, click (or ↵) to toggle, "Create label “x”" for a new name, and Manage labels.
/// Stays open while you toggle; Esc or a click outside closes it.
struct LabelsPicker: View {
    @EnvironmentObject private var store: TaskStore
    let state: (UUID) -> LabelCheck
    let toggle: (UUID) -> Void
    let create: (String) -> Void
    var manage: (() -> Void)?
    var title = "Labels"

    @State private var query = ""
    @State private var highlight = 0
    @FocusState private var focused: Bool

    private enum Row: Identifiable, Equatable {
        case label(TaskLabel)
        case create(String)
        var id: String {
            switch self {
            case let .label(label): return label.id.uuidString
            case let .create(name): return "create-" + name
            }
        }
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = store.labels
        let shown: [TaskLabel]
        if q.isEmpty {
            shown = all
        } else {
            shown = all.enumerated()
                .compactMap { index, label in FuzzyMatch.score(q, in: label.name).map { ($0, index, label) } }
                .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
                .map(\.2)
        }
        var rows = shown.map(Row.label)
        let name = TaskLabel.cleanName(q)
        if !name.isEmpty, store.matchLabel(name) == nil, !all.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            rows.append(.create(name))
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        let current = rows.isEmpty ? nil : min(highlight, rows.count - 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "tag").font(.system(size: 11, weight: .semibold)).foregroundColor(Focus.text3)
                TextField(store.labels.isEmpty ? "Type a label name…" : "Filter or create…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundColor(Focus.text)
                    .focused($focused)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            FocusDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if rows.isEmpty {
                            Text(store.labels.isEmpty ? "No labels yet. Type a name to create one." : "No matches")
                                .font(.system(size: 12))
                                .foregroundColor(Focus.text3)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row, highlighted: index == current)
                                .id(row.id)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlight) { _ in
                    if let current, rows.indices.contains(current) { proxy.scrollTo(rows[current].id) }
                }
            }
            FocusDivider()
            HStack(spacing: 6) {
                Text("↵ toggle · esc close").font(.system(size: 11.5)).foregroundColor(Focus.text3)
                Spacer(minLength: 4)
                if let manage {
                    Button("Manage labels…", action: manage)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Focus.text2)
                        .focusPointerCursor()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .frame(width: 260)
        .background(Focus.raised)
        .focusLight()
        .background(KeyDownMonitor { handle($0, rows: rows) })
        .onChange(of: query) { _ in highlight = 0 }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    @ViewBuilder
    private func rowView(_ row: Row, highlighted: Bool) -> some View {
        switch row {
        case let .label(label):
            LabelPickerRow(highlighted: highlighted, check: state(label.id)) { toggle(label.id) } label: {
                Circle().fill(Color(hex: label.colorHex)).frame(width: 8, height: 8).frame(width: 16)
                Text(label.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
            }
        case let .create(name):
            LabelPickerRow(highlighted: highlighted, check: .off) { pickCreate(name) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundColor(Focus.text3).frame(width: 16)
                Text("Create label “\(name)”").font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
            }
        }
    }

    private func pickCreate(_ name: String) {
        create(name)
        query = ""
    }

    private func handle(_ event: NSEvent, rows: [Row]) -> Bool {
        guard let key = ListKey(event) else { return false }
        switch key {
        case .up: highlight = max(min(highlight, rows.count - 1) - 1, 0)
        case .down: highlight = min(highlight + 1, max(rows.count - 1, 0))
        case .returnKey:
            guard !rows.isEmpty else { return true }
            switch rows[min(highlight, rows.count - 1)] {
            case let .label(label): toggle(label.id)
            case let .create(name): pickCreate(name)
            }
        case .escape: return false
        case .tab: return true
        }
        return true
    }
}

/// A picker row with a check (✓ on, – for some of the tasks).
struct LabelPickerRow<Label: View>: View {
    let highlighted: Bool
    let check: LabelCheck
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                label()
                Spacer(minLength: 8)
                switch check {
                case .on: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(Focus.text2)
                case .mixed: Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundColor(Focus.text3)
                case .off: EmptyView()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Focus.radiusControl)
                .fill(highlighted ? Focus.selected : (hovering ? Focus.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(check == .on ? .isSelected : [])
        .accessibilityValue(check == .mixed ? "Some" : "")
    }
}

/// The picker on tasks (the task panel, a row's Labels cell, the bulk bar): each toggle is one
/// undo step. `toast` says so in a toast (bulk bar).
struct TaskLabelsEditor: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let taskIds: [UUID]
    var toast = false
    var close: () -> Void = {}

    var body: some View {
        LabelsPicker(
            state: { id in store.allHave(id, taskIds) ? .on : (store.someHave(id, taskIds) ? .mixed : .off) },
            toggle: { id in model.toggleLabel(id, on: taskIds, store: store, toast: toast) },
            create: { name in model.createLabel(name, adding: taskIds, store: store, toast: toast) },
            manage: {
                close()
                model.showingLabelsManager = true
            }
        )
    }
}

/// The task panel's Labels field: the chips (or "Add labels") in a field; opens the picker.
struct TaskLabelsField: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let task: TaskItem

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let labels = store.labels(of: task)
        Button { open = true } label: {
            HStack(spacing: 7) {
                if labels.isEmpty {
                    Text("Add labels").font(Focus.control).foregroundColor(Focus.text3)
                    Spacer(minLength: 0)
                } else {
                    TaskLabelChips(labels: labels)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Focus.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusField(focused: hovering || open)
        .onHover { hovering = $0 }
        .accessibilityLabel(labels.isEmpty ? "Labels: none" : "Labels: " + labels.map(\.name).joined(separator: ", "))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TaskLabelsEditor(taskIds: [task.id]) { open = false }
                .environmentObject(store)
                .environmentObject(model)
        }
    }
}

// MARK: - The Labels sheet

/// Every label with its color, name and how many tasks use it: add, rename (click the name),
/// recolor (the dot), delete (Undo in the window's toast). Opened from a picker's Manage labels,
/// the Label filter or ⌘K.
struct LabelsManagerSheet: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var renameError = false
    @FocusState private var newFocused: Bool
    @FocusState private var renameFocused: Bool

    var body: some View {
        let usage = store.labelUsage()
        let labels = store.labels
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Labels").font(Focus.pageTitle).foregroundColor(Focus.text)
                Text("Shared by every project. Add them to tasks with L, the task panel, or %name in any New task box.")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(labels.enumerated()), id: \.element.id) { index, label in
                            row(label, count: usage[label.id] ?? 0)
                                .overlay(alignment: .top) { if index > 0 { FocusDivider() } }
                        }
                        if labels.isEmpty {
                            Text("No labels yet. Add one below, or type %name when adding a task.")
                                .font(Focus.body)
                                .foregroundColor(Focus.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: labels.count < 8)
                FocusDivider()
                newRow
            }
            .focusPanel()
            .padding(.horizontal, 24)

            HStack {
                Text(labels.isEmpty ? "" : "\(labels.count) \(labels.count == 1 ? "label" : "labels")")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.focus())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .background(Focus.canvas)
        .focusLight()
    }

    private func row(_ label: TaskLabel, count: Int) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(TaskLabel.palette, id: \.self) { hex in
                    Button {
                        store.setLabelColor(label.id, colorHex: hex)
                    } label: {
                        if hex == label.colorHex {
                            SwiftUI.Label(Focus.colorName(hex), systemImage: "checkmark")
                        } else {
                            Text(Focus.colorName(hex))
                        }
                    }
                }
            } label: {
                Circle().fill(Color(hex: label.colorHex)).frame(width: 12, height: 12)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Color: \(Focus.colorName(label.colorHex))")
            .accessibilityLabel("Color of \(label.name)")

            if renaming == label.id {
                TextField("Label name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Focus.control)
                    .focused($renameFocused)
                    .onSubmit { finishRename(label.id) }
                    .onExitCommand { renaming = nil }
                    .onChange(of: renameFocused) { focused in if !focused, renaming == label.id { finishRename(label.id) } }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(Focus.raised))
                    .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag)
                        .strokeBorder(renameError ? Focus.risk : Focus.lineStrong, lineWidth: 1))
                    .help(renameError ? "Another label has this name" : "")
            } else {
                Button {
                    renameText = label.name
                    renameError = false
                    renaming = label.id
                    DispatchQueue.main.async { renameFocused = true }
                } label: {
                    LabelChip(label: label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to rename")
                .accessibilityLabel("Rename \(label.name)")
            }
            Text(count == 0 ? "Unused" : "\(count) \(count == 1 ? "task" : "tasks")")
                .font(Focus.meta.monospacedDigit())
                .foregroundColor(Focus.text3)
                .fixedSize()
            Button {
                if count > 0 {
                    model.showLabel(label.id, store: store)
                    dismiss()
                }
            } label: {
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(count > 0 ? Focus.text2 : Focus.text3.opacity(0.4))
            .disabled(count == 0)
            .help("Show its tasks in All projects")
            .accessibilityLabel("Show tasks labeled \(label.name)")
            FocusIconButton(systemName: "trash", label: "Delete \(label.name)", size: 24) {
                model.deleteLabel(label.id, store: store)
            }
            .help(count > 0 ? "Delete; it comes off \(count) \(count == 1 ? "task" : "tasks"). Undo brings it back." : "Delete")
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
            TextField("New label", text: $newName)
                .textFieldStyle(.plain)
                .font(Focus.control)
                .focused($newFocused)
                .onSubmit {
                    guard store.addLabel(newName) != nil else { return }
                    newName = ""
                    DispatchQueue.main.async { newFocused = true }
                }
                .accessibilityLabel("New label name")
            if !newName.isEmpty { FocusKey(text: "↵ add") }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 42)
        .onAppear { if store.labels.isEmpty { DispatchQueue.main.async { newFocused = true } } }
    }

    private func finishRename(_ id: UUID) {
        guard renaming == id else { return }
        if renameText.trimmingCharacters(in: .whitespaces).isEmpty || store.label(id)?.name == TaskLabel.cleanName(renameText) {
            renaming = nil
            return
        }
        if store.renameLabel(id, to: renameText) {
            renaming = nil
        } else {
            renameError = true
            renameFocused = true
        }
    }
}
