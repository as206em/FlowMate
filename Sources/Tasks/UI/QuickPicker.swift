import AppKit
import SwiftUI

// The single-key pickers (S, P, M, R, D, E, T, L, ⇧M): a field that filters as you type, the options
// below it, ↑/↓ to move, ↵ to choose, Esc to close. L (labels) toggles instead and stays open:
// ↵ or Space (with the field empty) toggles the highlighted label. It hangs from the selected row or card, the
// bulk bar for several tasks, or the task panel. Options and what they do: TasksViewModel+Keyboard.

// MARK: - Keys in a field

/// Watches key presses in its own window while active and hands them to `handle`; a key it
/// returns true for goes no further. IME composition (marked text) is left alone.
struct KeyDownMonitor: NSViewRepresentable {
    var isActive = true
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isActive = isActive
        view.handle = handle
    }

    final class MonitorView: NSView {
        var isActive = true
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive, let window = self.window, event.window === window else { return event }
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                return self.handle?(event) == true ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

/// The keys a list in a popover or overlay uses.
enum ListKey: Equatable {
    case up, down, tab, escape
    case returnKey(shift: Bool)

    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 126 where flags.isEmpty: self = .up
        case 125 where flags.isEmpty: self = .down
        case 48 where flags.isEmpty: self = .tab
        case 53: self = .escape
        case 36 where flags.subtracting(.shift).isEmpty, 76 where flags.subtracting(.shift).isEmpty:
            self = .returnKey(shift: flags.contains(.shift))
        default: return nil
        }
    }
}

// MARK: - Anchors

/// Where a picker can hang: views that registered under a key (a board card "task-<id>", the bulk
/// bar, the task panel, a row of the milestone panel) and the native tables, which find a task's
/// row themselves. One task can be on screen twice (a board card under the milestone panel's row):
/// the anchor registered last wins while it's in the window, and the other takes over when it goes.
@MainActor
enum QuickPickerAnchors {
    private final class Weak { weak var view: NSView? ; init(_ view: NSView) { self.view = view } }
    private static var views: [String: [Weak]] = [:]
    private static var tables: [WeakTable] = []

    private final class WeakTable { weak var provider: TaskRowAnchorProvider?; init(_ p: TaskRowAnchorProvider) { provider = p } }

    static func register(_ view: NSView, key: String) {
        var list = (views[key] ?? []).filter { $0.view != nil && $0.view !== view }
        list.append(Weak(view))
        views[key] = list
    }

    static func unregister(_ view: NSView, key: String) {
        let list = (views[key] ?? []).filter { $0.view != nil && $0.view !== view }
        views[key] = list.isEmpty ? nil : list
    }

    /// The views registered under a key, latest first (for tests)
    static func registered(_ key: String) -> [NSView] {
        (views[key] ?? []).reversed().compactMap(\.view)
    }

    static func register(table provider: TaskRowAnchorProvider) {
        tables.removeAll { $0.provider == nil || $0.provider === provider }
        tables.append(WeakTable(provider))
    }

    static func key(_ anchor: QuickPickerRequest.Anchor) -> String {
        switch anchor {
        case let .task(id): return "task-\(id.uuidString)"
        case .bulk: return "bulk"
        case .panel: return "panel"
        }
    }

    /// A view and a rect in it to show the picker from, in this window.
    static func resolve(_ anchor: QuickPickerRequest.Anchor, in window: NSWindow) -> (view: NSView, rect: NSRect)? {
        for view in registered(key(anchor)) where view.window === window && !view.isHiddenOrHasHiddenAncestor {
            return (view, view.bounds)
        }
        if case let .task(id) = anchor {
            for table in tables {
                if let found = table.provider?.anchor(forTask: id), found.view.window === window { return found }
            }
        }
        return nil
    }
}

/// A native task table that can say where a task's row is.
@MainActor
protocol TaskRowAnchorProvider: AnyObject {
    func anchor(forTask id: UUID) -> (view: NSView, rect: NSRect)?
}

/// Registers the view it sits behind as a picker anchor.
struct QuickPickerAnchor: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.key = key
    }

    final class AnchorView: NSView {
        var key = "" {
            didSet {
                guard key != oldValue else { return }
                MainActor.assumeIsolated {
                    QuickPickerAnchors.unregister(self, key: oldValue)
                    if window != nil { QuickPickerAnchors.register(self, key: key) }
                }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MainActor.assumeIsolated {
                if window != nil { QuickPickerAnchors.register(self, key: key) } else { QuickPickerAnchors.unregister(self, key: key) }
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    /// Lets a single-key picker hang from this view.
    func quickPickerAnchor(_ anchor: QuickPickerRequest.Anchor) -> some View {
        background(QuickPickerAnchor(key: QuickPickerAnchors.key(anchor)))
    }
}

// MARK: - Presenting

/// Shows the model's picker as a popover from its anchor (or the top of the window when the row
/// is off screen), and clears the request when the popover closes.
@MainActor
final class QuickPickerPresenter: NSObject, NSPopoverDelegate {
    static let shared = QuickPickerPresenter()

    private var popover: NSPopover?
    private var shownId: UUID?
    private weak var model: TasksViewModel?

    func update(model: TasksViewModel, store: TaskStore, window: NSWindow?) {
        self.model = model
        guard let request = model.quickPicker else {
            if popover?.isShown == true { popover?.close() }
            shownId = nil
            return
        }
        guard request.id != shownId, let window, let content = window.contentView else { return }
        popover?.close()
        shownId = request.id
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let view = QuickPickerView(request: request) { [weak popover] in popover?.close() }
            .environmentObject(store)
            .environmentObject(model)
        popover.contentViewController = NSHostingController(rootView: view)
        let anchor = QuickPickerAnchors.resolve(request.anchor, in: window)
            ?? (content, NSRect(x: content.bounds.midX - 1, y: content.bounds.maxY - 120, width: 2, height: 2))
        let edge: NSRectEdge = request.anchor == .bulk ? .maxY : .minY
        popover.show(relativeTo: anchor.rect, of: anchor.view, preferredEdge: anchor.view.isFlipped ? (edge == .minY ? .maxY : .minY) : edge)
        popover.contentViewController?.view.window?.makeKey()
        self.popover = popover
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        popover = nil
        if let model, model.quickPicker?.id == shownId { model.quickPicker = nil }
        shownId = nil
    }
}

/// Watches the model's picker request for the window it's in.
struct QuickPickerHost: NSViewRepresentable {
    @ObservedObject var model: TasksViewModel
    let store: TaskStore

    func makeNSView(context: Context) -> NSView { HostView() }

    func updateNSView(_ view: NSView, context: Context) {
        let window = view.window
        let model = model
        let store = store
        // After this update, so the row's anchor is in place
        DispatchQueue.main.async {
            QuickPickerPresenter.shared.update(model: model, store: store, window: window ?? view.window)
        }
    }

    private final class HostView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: - The picker

struct QuickPickerView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: TasksViewModel
    let request: QuickPickerRequest
    let close: () -> Void

    @State private var query: String

    init(request: QuickPickerRequest, query: String = "", close: @escaping () -> Void) {
        self.request = request
        self.close = close
        _query = State(initialValue: query)
    }
    @State private var highlight = 0
    @FocusState private var focused: Bool

    static let width: CGFloat = 280

    var body: some View {
        let options = model.quickPickOptions(request.action, ids: request.taskIds, query: query, store: store)
        let current = options.isEmpty ? nil : min(highlight, options.count - 1)
        VStack(alignment: .leading, spacing: 0) {
            header
            field
            FocusDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if options.isEmpty {
                            Text(emptyText)
                                .font(.system(size: 12))
                                .foregroundColor(Focus.text3)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            QuickPickRow(option: option, highlighted: index == current) { choose(option) }
                                .id(option.id)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlight) { _ in
                    if let current, options.indices.contains(current) { proxy.scrollTo(options[current].id) }
                }
            }
            FocusDivider()
            Text(request.action.isMultiSelect ? "↑↓ choose · ↵ or space toggle · esc close" : "↑↓ choose · ↵ set · esc close")
                .font(.system(size: 11.5))
                .foregroundColor(Focus.text3)
                .padding(.horizontal, 12)
                .frame(height: 26)
        }
        .frame(width: Self.width)
        .background(Focus.raised)
        .focusLight()
        .background(KeyDownMonitor { handle($0, options: options) })
        .onChange(of: query) { _ in highlight = 0 }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(request.action.title).font(Focus.caption).tracking(0.5).textCase(.uppercase).foregroundColor(Focus.text3)
            if request.taskIds.count > 1 {
                Text("· \(request.taskIds.count) tasks".uppercased()).font(Focus.caption).tracking(0.5).foregroundColor(Focus.text3)
            } else if let task = request.taskIds.first.flatMap({ store.task($0) }) {
                Text("· " + task.title).font(.system(size: 11.5)).foregroundColor(Focus.text3).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 3) { ForEach(request.action.keys, id: \.self) { FocusKey(text: $0) } }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var field: some View {
        TextField(request.action.placeholder, text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(Focus.text)
            .focused($focused)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .accessibilityLabel(request.action.title)
    }

    private var emptyText: String {
        switch request.action {
        case .due: return "Type a date such as fri, nov 18 or 3d"
        case .expected: return "Type a time such as 1h 30m or 45m"
        case .timeSpent: return "Type 1h 15m to set it, or +15m / -5m"
        default: return "No matches"
        }
    }

    private func handle(_ event: NSEvent, options: [QuickPickOption]) -> Bool {
        // Space toggles a label while nothing is typed (a typed name can have spaces)
        if request.action.isMultiSelect, event.keyCode == 49, query.isEmpty,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            if !options.isEmpty { choose(options[min(highlight, options.count - 1)]) }
            return true
        }
        guard let key = ListKey(event) else { return false }
        switch key {
        case .up: highlight = max(min(highlight, options.count - 1) - 1, 0)
        case .down: highlight = min(highlight + 1, max(options.count - 1, 0))
        case .returnKey:
            guard !options.isEmpty else { return true }
            choose(options[min(highlight, options.count - 1)])
        case .escape: close()
        case .tab: return true
        }
        return true
    }

    private func choose(_ option: QuickPickOption) {
        model.applyQuickPick(option.value, ids: request.taskIds, store: store)
        if request.action.isMultiSelect {
            // Stays open for the next one; a new label was typed, so the field starts over
            if option.isTyped { query = "" }
        } else {
            close()
        }
    }
}

/// One option: its icon, title, detail and a check on the current value.
private struct QuickPickRow: View {
    let option: QuickPickOption
    let highlighted: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon.frame(width: 16)
                Text(option.title).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                Spacer(minLength: 8)
                if !option.detail.isEmpty {
                    Text(option.detail).font(Focus.meta).foregroundColor(Focus.text3).lineLimit(1)
                }
                if option.isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(Focus.text2)
                } else if option.isMixed {
                    Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundColor(Focus.text3)
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
        .accessibilityAddTraits(option.isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        switch option.icon {
        case .none: Color.clear.frame(width: 1, height: 1)
        case let .status(status): WorkflowStatusIcon(status: status, size: 14)
        case let .category(category): FocusStatusIcon(kind: category.focusKind, size: 14)
        case let .priority(priority): FocusPriorityBars(level: priority.focusLevel)
        case let .milestone(color):
            Image(systemName: color == nil ? "diamond" : "diamond.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color.map { Color(hex: $0) } ?? Focus.text3)
        case let .project(name, colorHex, icon): FocusProjectTile(name: name, colorHex: colorHex, size: 14, icon: icon)
        case let .symbol(name):
            Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundColor(Focus.text3)
        case let .label(hex):
            Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
        }
    }
}
