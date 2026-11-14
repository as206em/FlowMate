import AppKit
import Combine
import SwiftUI

/// FlowMate's menu bar icon and the dropdown panel it opens.
///
/// This is our own NSStatusItem and NSPanel rather than SwiftUI's `MenuBarExtra(.window)`:
/// that window doesn't follow its content when it gets shorter (a timer paused, a task done).
/// Its frosted backdrop and shadow stay at the old height, a see-through band above and below
/// the content, and SwiftUI offers no way to fix that. Here the panel is an ordinary window whose
/// SwiftUI content sets its size (`sizingOptions`), so AppKit resizes it, backdrop and shadow
/// included, like any other window.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanelWindow?
    private var makeContent: (() -> AnyView)?
    private var label: (() -> (icon: String, title: String))?
    private var shownLabel: (icon: String, title: String)?
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    /// The panel's top edge, under the menu bar; it stays there as the panel grows or shrinks
    private var anchorTop: CGFloat = 0

    var isOpen: Bool { panel?.isVisible ?? false }
    var openPanel: NSWindow? { isOpen ? panel : nil }

    /// Puts the icon in the menu bar. Call once the app has finished launching.
    func install(appState: AppState, statusManager: StatusManager, store: TaskStore) {
        guard statusItem == nil else { return }
        makeContent = {
            AnyView(StatusMenuView()
                .environmentObject(appState)
                .environmentObject(statusManager)
                .environmentObject(store))
        }
        label = { [unowned store, unowned statusManager] in
            // The status icon, plus how many timers run when any do (or the running clock, if chosen).
            // A dev build says DEV, so it can't be mistaken for the released app next to it.
            let running = store.workspace.runningTimers.count
            let timers = running == 0 ? nil
                : store.preferences.showsMenuBarClock ? MenuBarClockText.title(store: store, now: store.ticker.now)
                : "\(running)"
            let title = [AppChannel.current == .development ? "DEV" : nil, timers]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return (statusManager.currentIcon, title)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        statusItem = item
        updateLabel()

        // objectWillChange fires before the change lands: read the new values on the next pass
        Publishers.Merge3(
            statusManager.objectWillChange.map { _ in () },
            store.objectWillChange.map { _ in () },
            store.ticker.objectWillChange.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.updateLabel() }
        .store(in: &cancellables)
    }

    private func updateLabel() {
        guard let button = statusItem?.button, let current = label?() else { return }
        if let shownLabel, shownLabel == current { return }
        shownLabel = current
        let image = NSImage(systemSymbolName: current.icon, accessibilityDescription: "FlowMate")
        image?.isTemplate = true
        button.image = image
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: current.title.isEmpty ? "" : " " + current.title,
                                                    attributes: [.font: font])
        button.imagePosition = current.title.isEmpty ? .imageOnly : .imageLeading
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if isOpen { close() } else { open() }
    }

    /// Opens the panel under the menu bar icon, ready for typing.
    func open() {
        guard !isOpen, let makeContent, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let panel = panel ?? MenuBarPanelWindow()
        self.panel = panel

        // A fresh view each time, as a menu would be: the search starts empty, onAppear runs.
        // As the window's content view controller with .preferredContentSize, its SwiftUI size
        // becomes the window's size, now and whenever rows come and go.
        let hosting = NSHostingController(rootView: makeContent())
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 10
        hosting.view.layer?.cornerCurve = .continuous
        hosting.view.layer?.masksToBounds = true
        let size = hosting.sizeThatFits(in: NSSize(width: Focus.menuWidth, height: 10_000))
        panel.contentViewController = hosting

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        anchorTop = min(buttonRect.minY, visible.maxY) - 5
        let x = min(max(buttonRect.minX, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchorTop - size.height, width: size.width, height: size.height), display: false)

        // Takes key without bringing FlowMate's other windows forward (a non-activating panel)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        // A click in another app closes it, as a menu would. (Clicks in FlowMate's own windows
        // take key from the panel, which closes it too, see MenuBarPanelWindow.resignKey.)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        // Drop the view so nothing in it keeps updating while it's hidden
        panel.contentViewController = nil
        statusItem?.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Keeps the panel's top edge under the menu bar when its content changes height.
    fileprivate func panelDidResize(_ panel: NSWindow) {
        guard isOpen, abs(panel.frame.maxY - anchorTop) > 0.5 else { return }
        panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: anchorTop))
    }
}

/// The dropdown's window: borderless with rounded corners and a shadow. It takes key so the
/// search field can be typed in.
final class MenuBarPanelWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Focus.menuWidth, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        appearance = NSAppearance(named: .aqua)
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                MenuBarController.shared.panelDidResize(self)
                // The shadow follows the rounded content; recompute it at the new size
                self.invalidateShadow()
            }
        }
    }

    override var canBecomeKey: Bool { true }

    /// Esc (when the menu itself doesn't use it) closes the panel
    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { MenuBarController.shared.close() }
    }

    /// Losing key to another window closes it, as a menu would. The project picker's popover
    /// takes key for a moment; that doesn't count.
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            if let key = NSApp.keyWindow, key.className.contains("Popover") { return }
            MainActor.assumeIsolated { MenuBarController.shared.close() }
        }
    }
}
