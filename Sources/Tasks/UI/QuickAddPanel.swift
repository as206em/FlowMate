import AppKit
import SwiftUI

/// The floating "New task" box the global quick-add shortcut opens (Settings › General).
/// It floats above every app without bringing FlowMate forward: type, ↵ adds (with the New task
/// tokens !high @milestone due:fri ~90m), ⇧↵ adds and opens the task, Esc or a click elsewhere closes.
@MainActor
enum QuickAddPanel {
    private static var panel: QuickAddWindow?
    static let model = QuickAddBoxModel()
    /// The global shortcut as key caps (["⌃", "⌥", "N"]) for the shortcuts help; nil when off.
    static var shortcutKeys: [String]?

    static var isVisible: Bool { panel?.isVisible ?? false }

    static func toggle(store: TaskStore? = nil) {
        if isVisible { close() } else { show(store: store ?? .shared) }
    }

    static func show(store: TaskStore? = nil) {
        let store = store ?? .shared
        let panel = panel ?? makePanel(store: store)
        self.panel = panel
        model.prepare(store: store)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        model.focusToken = UUID()
    }

    static func close() {
        panel?.orderOut(nil)
    }

    private static func makePanel(store: TaskStore) -> QuickAddWindow {
        let panel = QuickAddWindow(
            contentRect: NSRect(x: 0, y: 0, width: QuickAddBox.width + 40, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .aqua)
        let root = QuickAddBox()
            .environmentObject(store)
            .environmentObject(model)
            .padding(20) // room for the shadow
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        return panel
    }

    /// Centered on the screen with the pointer, a third of the way down
    private static func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height / 3 - size.height / 2)
        panel.setFrameOrigin(origin)
    }
}

/// Borderless panels can't become key by default; this one needs typing.
final class QuickAddWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    /// A click in another app or window closes the box (nothing is lost: it only closes).
    /// The project picker's popover takes key for a moment; that doesn't count.
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            if let key = NSApp.keyWindow, key.className.contains("Popover") { return }
            self.orderOut(nil)
        }
    }
}

/// What the box is showing: the text, the target project and the "Added" note.
@MainActor
final class QuickAddBoxModel: ObservableObject {
    @Published var text = ""
    @Published var projectId: UUID?
    @Published var added: String?
    /// Changes each time the box opens so the field takes focus
    @Published var focusToken = UUID()

    func prepare(store: TaskStore) {
        if added != nil { text = "" }
        added = nil
        if let id = projectId, store.project(id).map({ !$0.isArchived }) != true { projectId = nil }
        if projectId == nil { projectId = store.defaultProject?.id }
    }

    /// Adds the task with its tokens and remembers the project. Returns the new task's id.
    @discardableResult
    func add(store: TaskStore) -> UUID? {
        guard let projectId, let outcome = store.quickAddTask(text, projectId: projectId) else { return nil }
        let name = store.project(outcome.projectId)?.name ?? "project"
        added = (["Added to \(name)"] + outcome.applied).joined(separator: " · ")
        text = ""
        return outcome.taskId
    }
}

/// The box: "New task" with the project chip, a large field and a preview line with the keys.
struct QuickAddBox: View {
    static let width: CGFloat = 520

    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: QuickAddBoxModel
    @FocusState private var focused: Bool
    @State private var pickingProject = false

    var body: some View {
        let target = model.projectId.flatMap { store.project($0) }
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                FocusAppTile(size: 18)
                Text("New task").font(Focus.groupTitle).foregroundColor(Focus.text)
                Spacer(minLength: 8)
                if let target { projectChip(target) }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .overlay(alignment: .bottom) { FocusDivider() }

            if let target {
                field(target)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Create a project first. New tasks need one to go to.")
                        .font(Focus.body)
                        .foregroundColor(Focus.text2)
                    Button("Open FlowMate") {
                        QuickAddPanel.close()
                        TasksWindow.show()
                    }
                    .buttonStyle(.focus())
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: Focus.radiusPanel).fill(Focus.raised))
        .overlay(RoundedRectangle(cornerRadius: Focus.radiusPanel).strokeBorder(Focus.lineStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Focus.radiusPanel))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        .focusLight()
        .onChange(of: model.focusToken) { _ in DispatchQueue.main.async { focused = true } }
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: model.text) { text in if !text.isEmpty { model.added = nil } }
    }

    @ViewBuilder
    private func field(_ target: Project) -> some View {
        TextField("What needs doing?  !high  @milestone  due:fri  ~1h", text: $model.text)
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .foregroundColor(Focus.text)
            .focused($focused)
            .onSubmit(submit)
            .onExitCommand { QuickAddPanel.close() }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .accessibilityLabel("New task title")
        FocusDivider()
        footer(target)
    }

    /// The preview of what ↵ does, or the "Added" note, plus the keys
    private func footer(_ target: Project) -> some View {
        HStack(spacing: 8) {
            if let added = model.added {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(Focus.ok)
                Text(added).font(.system(size: 12)).foregroundColor(Focus.text2).lineLimit(1)
            } else {
                FocusProjectTile(name: target.name, colorHex: target.colorHex, size: 14)
                Text(([target.name] + store.quickAddPreview(model.text, projectId: target.id)).joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(Focus.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            FocusKey(text: "↵ add")
            FocusKey(text: "⇧↵ add and open")
            FocusKey(text: "esc")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Focus.sidebar)
    }

    private func projectChip(_ target: Project) -> some View {
        Button { pickingProject.toggle() } label: {
            HStack(spacing: 5) {
                FocusProjectTile(name: target.name, colorHex: target.colorHex, size: 14)
                Text(target.name).font(.system(size: 12, weight: .medium)).foregroundColor(Focus.text2).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(Focus.text3)
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Focus.radiusTag).fill(Focus.sidebar))
            .overlay(RoundedRectangle(cornerRadius: Focus.radiusTag).strokeBorder(Focus.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New tasks go to \(target.name)")
        .accessibilityLabel("Add to \(target.name)")
        .popover(isPresented: $pickingProject, arrowEdge: .bottom) {
            FocusPopoverMenu(width: 220) {
                FocusMenuSection(title: "Add to", first: true)
                ForEach(store.projects) { project in
                    FocusMenuItem(isSelected: project.id == target.id) {
                        model.projectId = project.id
                        store.rememberProject(project.id)
                        pickingProject = false
                        focused = true
                    } label: {
                        FocusProjectTile(name: project.name, colorHex: project.colorHex)
                        Text(project.name).font(Focus.control).foregroundColor(Focus.text).lineLimit(1)
                    }
                }
            }
        }
    }

    /// ↵ adds and closes shortly after showing where it went; ⇧↵ adds and opens the task.
    private func submit() {
        let open = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        guard let id = model.add(store: store) else { return }
        if open {
            QuickAddPanel.close()
            TasksWindow.show(store: store, openTask: id)
            return
        }
        let note = model.added
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            // Still showing this note and nothing new typed: done
            if model.added == note, model.text.isEmpty { QuickAddPanel.close() }
        }
    }
}
