import AppKit
import XCTest
@testable import FlowMate

/// Keyboard speed: single-key actions and their pickers, the ⌘K palette, sidebar and panel
/// navigation, the one quick-add language in every box, timer keys and hotkeys.
@MainActor
final class KeyboardSpeedTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeStore(_ preset: WorkflowPreset = .simple) async -> (TaskStore, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let pid = store.addProject(name: "Alpha", now: t0)!
        if preset != .simple { store.applyWorkflowPreset(projectId: pid, preset, now: t0) }
        store.clearUndoHistory()
        return (store, pid)
    }

    private func match(_ keyCode: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) -> TasksShortcut? {
        TasksShortcut.match(keyCode: keyCode, characters: characters, modifiers: modifiers)
    }

    // MARK: - Key table

    func testSingleKeysAndNewShortcutsMatch() {
        XCTAssertEqual(match(1, "s"), .pickStatus)
        XCTAssertEqual(match(35, "p"), .pickPriority)
        XCTAssertEqual(match(46, "m"), .pickMilestone)
        XCTAssertEqual(match(15, "r"), .pickSprint)
        XCTAssertEqual(match(2, "d"), .pickDue)
        XCTAssertEqual(match(14, "e"), .pickExpected)
        XCTAssertEqual(match(17, "t"), .pickTimeSpent)
        XCTAssertEqual(match(46, "M", .shift), .pickProject)
        XCTAssertEqual(match(7, "x"), .toggleDone)
        XCTAssertEqual(match(18, "1"), .priority1)
        XCTAssertEqual(match(19, "2"), .priority2)
        XCTAssertEqual(match(20, "3"), .priority3)
        XCTAssertEqual(match(21, "4"), .priority4)
        XCTAssertEqual(match(126, "", .option), .moveUp)
        XCTAssertEqual(match(125, "", .option), .moveDown)
        XCTAssertEqual(match(0, "a", [.command, .shift]), .deselectAll)
        XCTAssertEqual(match(40, "k", .command), .palette)
        XCTAssertEqual(match(29, "0", .command), .focusSidebar)
        XCTAssertEqual(match(34, "i", .command), .togglePanel)
        XCTAssertEqual(match(49, " ", .shift), .pauseAllTimers)
        XCTAssertEqual(match(49, " ", .option), .soloTimer)
        XCTAssertEqual(match(123, ""), .left)
        XCTAssertEqual(match(124, ""), .right)

        // The existing ones keep their keys
        XCTAssertEqual(match(45, "n", .command), .newTask)
        XCTAssertEqual(match(3, "f", .command), .find)
        XCTAssertEqual(match(18, "1", .command), .tab1)
        XCTAssertEqual(match(17, "t", .command), .toggleToday)
        XCTAssertEqual(match(2, "d", .command), .duplicate)
        XCTAssertEqual(match(51, "", .command), .delete)
        XCTAssertEqual(match(6, "z", .command), .undo)
        XCTAssertEqual(match(49, " "), .toggleTimer)
        XCTAssertEqual(match(36, "\r"), .open)
        XCTAssertEqual(match(53, ""), .clearSelection)
        XCTAssertEqual(match(0, "a", .command), .selectAll)

        // Nothing else grabs plain letters or ⌃ chords
        XCTAssertNil(match(11, "b"))
        XCTAssertNil(match(1, "s", .control))
        XCTAssertNil(match(1, "s", .option))
    }

    func testSingleKeysWaitWhileTyping() {
        let typingOnly: [TasksShortcut] = [.pickStatus, .pickPriority, .pickMilestone, .pickSprint, .pickDue, .pickExpected,
                                           .pickTimeSpent, .pickProject, .toggleDone, .priority1, .priority2, .priority3,
                                           .priority4, .moveUp, .moveDown, .deselectAll, .togglePanel, .pauseAllTimers,
                                           .soloTimer, .left, .right, .toggleTimer, .undo]
        for shortcut in typingOnly {
            XCTAssertFalse(TasksKeyMonitor.applies(shortcut, typing: true, controlFocused: false, selectingText: false),
                           "\(shortcut) belongs to the text field while typing")
            XCTAssertTrue(TasksKeyMonitor.applies(shortcut, typing: false, controlFocused: false, selectingText: false))
        }
        // ⌘K and ⌘0 work from a field, like ⌘N and ⌘F
        for shortcut: TasksShortcut in [.palette, .focusSidebar, .newTask, .find] {
            XCTAssertTrue(TasksKeyMonitor.applies(shortcut, typing: true, controlFocused: false, selectingText: false))
        }
        // A focused button keeps Space; selectable text keeps the arrows
        XCTAssertFalse(TasksKeyMonitor.applies(.soloTimer, typing: false, controlFocused: true, selectingText: false))
        XCTAssertFalse(TasksKeyMonitor.applies(.pauseAllTimers, typing: false, controlFocused: true, selectingText: false))
        XCTAssertTrue(TasksKeyMonitor.applies(.pickStatus, typing: false, controlFocused: true, selectingText: false))
        XCTAssertFalse(TasksKeyMonitor.applies(.left, typing: false, controlFocused: false, selectingText: true))
    }

    // MARK: - Single-key pickers

    func testPickersOpenOnTheSelectionAndAnchorToRowBulkBarOrPanel() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list

        XCTAssertFalse(model.perform(.pickStatus, store: store), "nothing selected: the key passes through")
        XCTAssertNil(model.quickPicker)

        model.selectedTaskId = a
        XCTAssertTrue(model.perform(.pickStatus, store: store))
        XCTAssertEqual(model.quickPicker?.action, .status)
        XCTAssertEqual(model.quickPicker?.taskIds, [a])
        XCTAssertEqual(model.quickPicker?.anchor, .task(a))

        model.select(ids: [a, b])
        XCTAssertTrue(model.perform(.pickDue, store: store))
        XCTAssertEqual(Set(model.quickPicker!.taskIds), [a, b])
        XCTAssertEqual(model.quickPicker?.anchor, .bulk)

        model.openTask(b)
        XCTAssertTrue(model.perform(.pickMilestone, store: store))
        XCTAssertEqual(model.quickPicker?.taskIds, [b], "the open task")
        XCTAssertEqual(model.quickPicker?.anchor, .panel)

        XCTAssertFalse(model.perform(.pickProject, store: store), "one project: nowhere to move")
        store.addProject(name: "Beta", now: t0)
        XCTAssertTrue(model.perform(.pickProject, store: store))
        XCTAssertEqual(model.quickPicker?.action, .project)
    }

    func testMultiSelectSingleKeyEditsAreOneUndoStep() async {
        let (store, pid) = await makeStore()
        let ids = (0..<3).map { store.addTask(title: "T\($0)", projectId: pid, now: t0)! }
        store.clearUndoHistory()
        let model = TasksViewModel()
        model.select(.project(pid))
        model.select(ids: ids)

        // 1: high priority on all three
        XCTAssertTrue(model.perform(.priority1, store: store))
        XCTAssertTrue(ids.allSatisfy { store.task($0)?.priority == .high })
        XCTAssertEqual(store.undoStack.count, 1)
        XCTAssertEqual(model.toast?.message, "3 tasks set to high priority")
        XCTAssertFalse(model.perform(.priority4, store: store), "there's no fourth level")

        // D, then "fri" + ↵
        let options = model.quickPickOptions(.due, ids: ids, query: "fri", store: store, now: t0)
        let typed = try? XCTUnwrap(options.first)
        XCTAssertEqual(typed?.isTyped, true)
        guard case let .due(date)? = typed?.value, let friday = date else { return XCTFail("a typed date") }
        XCTAssertEqual(Calendar.current.component(.weekday, from: friday), 6)
        model.applyQuickPick(typed!.value, ids: ids, store: store, now: t0)
        XCTAssertTrue(ids.allSatisfy { store.task($0)?.dueDate == friday })
        XCTAssertEqual(store.undoStack.count, 2)

        // Presets are listed too, and "tom" finds Tomorrow without a duplicate typed row
        let presets = model.quickPickOptions(.due, ids: ids, query: "", store: store, now: t0).map(\.title)
        XCTAssertEqual(Array(presets.prefix(3)), ["Today", "Tomorrow", "Next week"])
        XCTAssertTrue(presets.contains("No due date"))
        let tomorrow = model.quickPickOptions(.due, ids: ids, query: "tom", store: store, now: t0)
        XCTAssertEqual(tomorrow.map(\.title).filter { $0 == "Tomorrow" }.count, 1)
        XCTAssertFalse(tomorrow.contains { $0.isTyped })

        // S: a status of the shared workflow
        let done = store.project(pid)!.firstStatus(.done)
        let status = model.quickPickOptions(.status, ids: ids, query: "don", store: store).first
        XCTAssertEqual(status?.value, .status(done))
        model.applyQuickPick(status!.value, ids: ids, store: store)
        XCTAssertTrue(ids.allSatisfy { store.task($0)?.statusId == done.id })

        // E typed, T adjust and set
        model.applyQuickPick(model.quickPickOptions(.expected, ids: ids, query: "90m", store: store).first!.value, ids: ids, store: store)
        XCTAssertTrue(ids.allSatisfy { store.task($0)?.expectedMinutes == 90 })
        let plus = model.quickPickOptions(.timeSpent, ids: ids, query: "+15m", store: store).first!
        XCTAssertEqual(plus.value, .adjustSpent(900))
        model.applyQuickPick(plus.value, ids: ids, store: store, now: t0)
        XCTAssertTrue(ids.allSatisfy { store.elapsed($0, now: t0) == 900 })
        XCTAssertEqual(model.quickPickOptions(.timeSpent, ids: ids, query: "-5m", store: store).first?.value, .adjustSpent(-300))
        XCTAssertEqual(model.quickPickOptions(.timeSpent, ids: ids, query: "1h", store: store).first?.value, .setSpent(3600))

        // M: a new milestone by typing its name, one step
        let before = store.undoStack.count
        let new = model.quickPickOptions(.milestone, ids: ids, query: "Beta", store: store).first!
        XCTAssertEqual(new.value, .newMilestone("Beta"))
        model.applyQuickPick(new.value, ids: ids, store: store)
        let beta = store.milestones(of: pid).first { $0.name == "Beta" }
        XCTAssertNotNil(beta)
        XCTAssertTrue(ids.allSatisfy { store.task($0)?.milestoneId == beta?.id })
        XCTAssertEqual(store.undoStack.count, before + 1)
        XCTAssertEqual(model.quickPickOptions(.milestone, ids: ids, query: "", store: store).first { $0.isCurrent }?.value,
                       .milestone(beta?.id))

        // Every edit undoes
        store.undo()
        XCTAssertTrue(ids.allSatisfy { store.task($0)?.milestoneId == nil })
        XCTAssertTrue(store.milestones(of: pid).isEmpty)
    }

    func testPickerOptionsAcrossProjectsUseSharedStatusesAndCategories() async {
        let (store, pid) = await makeStore(.dev)
        let other = store.addProject(name: "Beta", now: t0)!
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: other, now: t0)!
        let model = TasksViewModel()
        let options = model.quickPickOptions(.status, ids: [a, b], query: "", store: store)
        XCTAssertTrue(options.contains { $0.value == .category(.done) })
        XCTAssertFalse(options.contains { $0.title == "Review" }, "Beta's workflow has no Review")
        XCTAssertEqual(model.quickPickOptions(.milestone, ids: [a, b], query: "", store: store).map(\.title), ["No milestone"])
        XCTAssertEqual(model.quickPickOptions(.project, ids: [a], query: "bet", store: store).first?.value, .project(other))
    }

    // MARK: - X with custom workflows

    func testToggleDoneUsesTheWorkflowsDoneAndFirstNotStartedStatuses() async {
        let (store, pid) = await makeStore(.dev)
        let review = store.project(pid)!.statuses.first { $0.name == "Review" }!
        let task = store.addTask(title: "Ship", projectId: pid, status: review, now: t0)!
        let shipped = store.addStatus(projectId: pid, name: "Shipped", category: .done)!
        // Shipped goes first among the done statuses
        let doneIndex = store.project(pid)!.statuses.firstIndex { $0.category == .done }!
        store.moveStatus(projectId: pid, statusId: shipped, to: doneIndex)
        store.clearUndoHistory()
        let model = TasksViewModel()
        model.select(.project(pid))
        model.selectedTaskId = task

        XCTAssertTrue(model.perform(.toggleDone, store: store))
        XCTAssertEqual(store.task(task)?.statusId, shipped, "the workflow's first done status")
        XCTAssertEqual(model.toast?.message, "Task marked done")
        XCTAssertTrue(model.perform(.toggleDone, store: store))
        XCTAssertEqual(store.task(task)?.statusId, "backlog", "back to the first Not started status")
        XCTAssertEqual(store.undoStack.count, 2)
        store.undo()
        XCTAssertEqual(store.task(task)?.statusId, shipped)

        // Several: when one isn't done, all become done
        let other = store.addTask(title: "Other", projectId: pid, now: t0)!
        model.select(ids: [task, other])
        model.perform(.toggleDone, store: store)
        XCTAssertEqual(store.task(other)?.statusCategory, .done)
        XCTAssertEqual(store.task(task)?.statusId, shipped)
    }

    // MARK: - ⌥↑ / ⌥↓

    func testOptionArrowsMoveRowsWithinTheirGroup() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let c = store.addTask(title: "C", projectId: pid, now: t0)!
        let d = store.addTask(title: "D", projectId: pid, now: t0)!
        store.clearUndoHistory()
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list
        func order() -> [UUID] { model.listGroups(store).flatMap(\.tasks).map(\.id) }
        XCTAssertEqual(order(), [a, b, c, d])

        model.selectedTaskId = c
        XCTAssertTrue(model.perform(.moveUp, store: store))
        XCTAssertEqual(order(), [a, c, b, d])
        XCTAssertTrue(model.perform(.moveDown, store: store))
        XCTAssertTrue(model.perform(.moveDown, store: store))
        XCTAssertEqual(order(), [a, b, d, c], "down to the end of the group")
        XCTAssertTrue(model.perform(.moveDown, store: store))
        XCTAssertEqual(order(), [a, b, d, c], "already last: nothing moves")
        XCTAssertEqual(store.undoStack.count, 3)
        store.undo()
        XCTAssertEqual(order(), [a, b, c, d])

        // Several rows move as a block
        model.select(ids: [b, c])
        model.perform(.moveUp, store: store)
        XCTAssertEqual(order(), [b, c, a, d])
        model.perform(.moveUp, store: store)
        XCTAssertEqual(order(), [b, c, a, d], "the block is at the top")

        // A sorted list has no manual order: it says so instead
        model.sort = TaskSort(key: .priority, ascending: false)
        XCTAssertTrue(model.perform(.moveDown, store: store))
        XCTAssertEqual(model.toast?.message, "Sort by Manual to move tasks by hand")

        // Board columns keep their own order
        model.sort = .manual
        model.tab = .board
        model.selectedTaskId = a
        model.perform(.moveUp, store: store)
        XCTAssertEqual(model.allBoardTasks(store).map(\.id), [b, a, c, d])
    }

    func testOptionArrowsReorderMyFocusOnToday() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.addToToday([a, b], now: t0)
        let model = TasksViewModel()
        model.select(.today)
        model.selectedTaskId = b
        XCTAssertEqual(store.todayPlan(now: t0).focus.map(\.id), [a, b])
        XCTAssertTrue(model.moveSelectionWithinGroup(-1, store: store, now: t0))
        XCTAssertEqual(store.todayPlan(now: t0).focus.map(\.id), [b, a])
    }

    // MARK: - Palette

    func testPaletteRanksPlacesTasksAndCommandsInOneList() async {
        let (store, pid) = await makeStore()
        let atlas = store.addProject(name: "Atlas", now: t0)!
        let launch = store.addMilestone(projectId: atlas, name: "Beta launch")!
        let task = store.addTask(title: "Write the launch post", projectId: pid, now: t0)!
        store.addTask(title: "Unrelated", projectId: pid, now: t0)
        let model = TasksViewModel()
        model.select(.project(pid))

        model.paletteQuery = "atlas"
        XCTAssertEqual(model.paletteResults(store).items.first, .project(atlas))
        model.paletteQuery = "launch"
        let items = model.paletteResults(store).items
        XCTAssertTrue(items.contains(.milestone(launch)))
        XCTAssertTrue(items.contains(.task(task)))
        XCTAssertFalse(items.contains { if case .task = $0 { return $0 != .task(task) } else { return false } })
        model.paletteQuery = "bl"
        XCTAssertEqual(model.paletteResults(store).items.first, .milestone(launch), "initials")
        model.paletteQuery = "tod"
        XCTAssertEqual(model.paletteResults(store).items.first, .today)

        // ">" lists commands only
        model.tab = .list
        model.paletteQuery = "> board"
        let commands = model.paletteResults(store).items
        XCTAssertEqual(commands.first, .command(.switchTab(.board)))
        XCTAssertTrue(commands.allSatisfy { if case .command = $0 { return true } else { return false } })
        model.paletteQuery = ">"
        XCTAssertTrue(model.paletteResults(store).items.contains(.command(.newTask)))
        model.paletteQuery = "new mile"
        XCTAssertEqual(model.paletteResults(store).items.first, .command(.newMilestone(pid)), "the project on screen first")

        // ↑/↓ and the row ↵ runs
        model.paletteQuery = "launch"
        XCTAssertEqual(model.paletteCurrent(store), model.paletteResults(store).items.first)
        model.movePaletteHighlight(1, store: store)
        XCTAssertEqual(model.paletteCurrent(store), model.paletteResults(store).items[1])
        model.paletteQuery = "launc"
        XCTAssertNil(model.paletteHighlight, "new text starts at the top again")
    }

    func testPaletteGoesOrOpensThePanelAndRemembersRecentPicks() async throws {
        let suite = "FlowMateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (store, pid) = await makeStore()
        let atlas = store.addProject(name: "Atlas", now: t0)!
        let task = store.addTask(title: "Fix login", projectId: atlas, now: t0)!
        let model = TasksViewModel(defaults: defaults)
        model.select(.project(pid))

        model.openPalette(store: store)
        XCTAssertTrue(model.showingPalette)
        XCTAssertTrue(defaults.bool(forKey: TasksViewModel.paletteHintDismissedKey), "using it retires the ⌘K hint")
        XCTAssertEqual(model.paletteResults(store).items.prefix(3), [.today, .project(pid), .project(atlas)], "nothing recent yet")

        // ⇧↵ on a task: its panel, over the view on screen
        model.runPaletteItem(.task(task), inPanel: true, store: store)
        XCTAssertFalse(model.showingPalette)
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(model.openTaskId, task)

        // ↵ on a task: goes to its project and opens it
        model.closePanel()
        model.runPaletteItem(.task(task), store: store)
        XCTAssertEqual(model.scope, .project(atlas))
        XCTAssertEqual(model.openTaskId, task)

        // ↵ on a project goes there; ⇧↵ opens its panel
        model.runPaletteItem(.project(pid), store: store)
        XCTAssertEqual(model.scope, .project(pid))
        model.runPaletteItem(.project(atlas), inPanel: true, store: store)
        XCTAssertEqual(model.scope, .project(pid))
        XCTAssertEqual(model.openDetail, .project(atlas))

        // Recent picks, newest first, kept between launches
        let reopened = TasksViewModel(defaults: defaults)
        reopened.openPalette(store: store)
        XCTAssertEqual(Array(reopened.paletteResults(store).items.prefix(3)), [.project(atlas), .project(pid), .task(task)])
        store.deleteTask(task)
        XCTAssertFalse(reopened.paletteResults(store).items.contains(.task(task)), "gone tasks drop out")
    }

    func testPaletteCommandsRun() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .board

        model.run(.showOverdue, store: store)
        XCTAssertEqual(model.filter.due, [.overdue])
        model.run(.groupBy(.priority), store: store)
        XCTAssertEqual(model.effectiveTab, .list)
        XCTAssertEqual(model.grouping, .priority)
        model.run(.switchTab(.sprints), store: store)
        XCTAssertEqual(model.tab, .sprints)
        model.run(.newMilestone(other), store: store)
        XCTAssertTrue(model.isProjectExpanded(other))
        XCTAssertEqual(model.focusRequest?.field, .newMilestone(other))
        model.run(.completeSprint(pid), store: store)
        XCTAssertEqual(model.completingSprintProjectId, pid)
        model.run(.toggleMilestones(other), store: store)
        XCTAssertFalse(model.isProjectExpanded(other))

        var opened = false
        TasksViewModel.openSettings = { opened = true }
        model.run(.openSettings, store: store)
        XCTAssertTrue(opened)
        TasksViewModel.openSettings = {}

        store.startTimer(a, now: t0)
        XCTAssertTrue(model.paletteCommands(store).contains(.pauseAllTimers))
        model.run(.pauseAllTimers, store: store)
        XCTAssertFalse(store.hasRunningTimers)

        // Task commands appear for the selection the palette opened with, and act on it
        XCTAssertFalse(model.paletteCommands(store).contains(.toggleDone))
        model.tab = .list
        model.selectedTaskId = a
        model.openPalette(store: store)
        XCTAssertTrue(model.paletteCommands(store).contains(.quickAction(.status)))
        model.runPaletteItem(.command(.quickAction(.priority)), store: store)
        XCTAssertEqual(model.quickPicker?.action, .priority)
        XCTAssertEqual(model.quickPicker?.taskIds, [a])
        model.runPaletteItem(.command(.toggleDone), store: store)
        XCTAssertEqual(store.task(a)?.statusCategory, .done)
        XCTAssertEqual(model.paletteKeys(.quickAction(.project)), ["⇧", "M"])

        // While open, the palette has the keyboard: only ⌘K gets through (and closes it)
        model.openPalette(store: store)
        XCTAssertFalse(model.perform(.newTask, store: store))
        XCTAssertTrue(model.perform(.palette, store: store))
        XCTAssertFalse(model.showingPalette)
    }

    // MARK: - Navigation

    func testSidebarTakesTheKeyboardWithCommandZero() async {
        let (store, pid) = await makeStore()
        let other = store.addProject(name: "Beta", now: t0)!
        let m = store.addMilestone(projectId: pid, name: "M1")!
        let model = TasksViewModel()
        model.select(.project(pid))

        XCTAssertTrue(model.perform(.focusSidebar, store: store))
        XCTAssertEqual(model.sidebarCursor, .project(pid))
        XCTAssertTrue(model.perform(.right, store: store))
        XCTAssertTrue(model.isProjectExpanded(pid), "→ lists its milestones")
        XCTAssertTrue(model.perform(.right, store: store))
        XCTAssertEqual(model.sidebarCursor, .milestone(m, projectId: pid), "→ again steps into them")
        XCTAssertTrue(model.perform(.left, store: store))
        XCTAssertEqual(model.sidebarCursor, .project(pid), "← goes back to the project")
        XCTAssertTrue(model.perform(.left, store: store))
        XCTAssertFalse(model.isProjectExpanded(pid))
        XCTAssertTrue(model.perform(.selectNext, store: store))
        XCTAssertEqual(model.sidebarCursor, .project(other))
        XCTAssertEqual(model.scope, .project(pid), "moving the cursor doesn't change the view")
        XCTAssertTrue(model.perform(.open, store: store))
        XCTAssertEqual(model.scope, .project(other))
        XCTAssertNil(model.sidebarCursor, "↵ hands the keyboard back to the list")

        model.perform(.focusSidebar, store: store)
        model.perform(.selectPrevious, store: store)
        XCTAssertTrue(model.perform(.clearSelection, store: store))
        XCTAssertNil(model.sidebarCursor, "esc returns to the list")
        XCTAssertEqual(model.scope, .project(other))
    }

    func testArrowsFollowTheOpenPanelAndCommandIToggles() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        let m1 = store.addMilestone(projectId: pid, name: "M1")!
        let m2 = store.addMilestone(projectId: pid, name: "M2")!
        let model = TasksViewModel()
        model.select(.project(pid))
        model.tab = .list

        model.selectedTaskId = a
        XCTAssertTrue(model.perform(.togglePanel, store: store))
        XCTAssertEqual(model.openTaskId, a)
        XCTAssertTrue(model.perform(.selectNext, store: store), "↓ works with the panel open")
        XCTAssertEqual(model.openTaskId, b)
        XCTAssertEqual(model.selectedTaskId, b)
        XCTAssertFalse(model.perform(.selectNext, store: store), "at the end")
        XCTAssertTrue(model.perform(.togglePanel, store: store))
        XCTAssertFalse(model.isPanelOpen)

        // ⌘[ ⌘] walk the milestones while a milestone panel is open
        model.openMilestone(m1)
        XCTAssertTrue(model.perform(.nextTask, store: store))
        XCTAssertEqual(model.openDetail, .milestone(m2))
        XCTAssertFalse(model.perform(.nextTask, store: store))
        XCTAssertTrue(model.perform(.previousTask, store: store))
        XCTAssertEqual(model.openDetail, .milestone(m1))
        XCTAssertFalse(model.perform(.selectNext, store: store), "a milestone panel keeps the arrows for scrolling")

        // ⌘I with nothing selected: the panel of what's on screen
        model.closePanel()
        model.selectedTaskId = nil
        model.perform(.togglePanel, store: store)
        XCTAssertEqual(model.openDetail, .project(pid))

        // ⇧⌘A selects nothing
        model.closePanel()
        model.select(ids: [a, b])
        XCTAssertTrue(model.perform(.deselectAll, store: store))
        XCTAssertTrue(model.selectedTaskIds.isEmpty)
    }

    // MARK: - One quick-add language

    func testComposerTokensIncludeStatusAndQuotes() {
        let now = t0
        XCTAssertEqual(ComposerInput.token("*review"), .status("review"))
        XCTAssertEqual(ComposerInput.token("*\"in review\""), .status("in review"))
        XCTAssertNil(ComposerInput.token("*"))
        XCTAssertNil(ComposerInput.token("**bold**"))
        XCTAssertEqual(ComposerInput.token("+\"side project\""), .project("side project"))
        XCTAssertEqual(ComposerInput.token("@beta_launch"), .milestone("beta launch"))
        XCTAssertNotNil(ComposerInput.token("due:\"nov 18\"", now: now))
        XCTAssertEqual(ComposerInput.activeTrigger("Write *rev")?.trigger, .status)
        XCTAssertEqual(ComposerInput.words("Ship @\"Beta launch\" now"), ["Ship", "@\"Beta launch\"", "now"])
        XCTAssertEqual(ComposerInput.extract("Fix *review ").tokens, [.status("review")])
    }

    func testQuickAddInputReadsEveryToken() {
        let input = QuickAddInput.parse("Fix login +atlas #next *review !high @beta due:fri ~1h30m", now: t0)
        XCTAssertEqual(input.title, "Fix login")
        XCTAssertEqual(input.projectQuery, "atlas")
        XCTAssertEqual(input.slot, .next)
        XCTAssertEqual(input.statusQuery, "review")
        XCTAssertEqual(input.priority, .high)
        XCTAssertEqual(input.milestoneQuery, "beta")
        XCTAssertNotNil(input.dueDate)
        XCTAssertEqual(input.expectedMinutes, 90)
        // The composer's bare words work here too
        let bare = QuickAddInput.parse("Call Sam tomorrow 2h #backlog", now: t0)
        XCTAssertEqual(bare.title, "Call Sam")
        XCTAssertEqual(bare.expectedMinutes, 120)
        XCTAssertEqual(bare.slot, .backlog)
        XCTAssertEqual(bare.dueDate, Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: t0)))
        XCTAssertEqual(QuickAddInput.parse("Fix 2 bugs in #1 spot").title, "Fix 2 bugs in #1 spot")
    }

    func testMenuBarQuickAddReadsProjectSprintAndStatus() async {
        let (store, pid) = await makeStore()
        let atlas = store.addProject(name: "Atlas", now: t0)!
        store.applyWorkflowPreset(projectId: atlas, .dev, now: t0)
        let beta = store.addMilestone(projectId: atlas, name: "Beta launch")!
        store.clearUndoHistory()

        // What the menu bar's ⌘↵ and the List's field call
        let outcome = store.quickAddTask("Write post +atl #next *review @beta !low ~45m", projectId: pid, now: t0)!
        let task = store.task(outcome.taskId)!
        XCTAssertEqual(task.title, "Write post")
        XCTAssertEqual(task.projectId, atlas, "+project overrides the box's project")
        XCTAssertEqual(task.sprintSlot, .next)
        XCTAssertEqual(task.statusId, "review")
        XCTAssertEqual(task.milestoneId, beta)
        XCTAssertEqual(task.priority, .low)
        XCTAssertEqual(task.expectedMinutes, 45)
        XCTAssertEqual(outcome.projectId, atlas)
        XCTAssertEqual(store.preferences.lastProjectId, atlas, "and becomes the remembered project")
        XCTAssertEqual(store.undoStack.count, 1)

        // Words that name nothing stay in the title
        let miss = store.quickAddTask("Idea +nowhere *nostatus", projectId: pid, now: t0)!
        XCTAssertEqual(store.task(miss.taskId)?.title, "Idea *nostatus +nowhere")
        XCTAssertEqual(store.task(miss.taskId)?.projectId, pid)

        // The preview and the menu's Add row name where it goes
        XCTAssertEqual(store.quickAddPreview("X +atlas !high", projectId: pid, now: t0), ["→ Atlas", "High"])
        XCTAssertEqual(store.quickAddTarget("X +atlas", projectId: pid)?.id, atlas)
        XCTAssertEqual(store.planQuickAdd("X +atlas", projectId: pid).projectId, atlas)
    }

    func testGlobalBoxAndComposerShareTheLanguage() async {
        let (store, pid) = await makeStore()
        let atlas = store.addProject(name: "Atlas", now: t0)!
        let box = QuickAddBoxModel()
        box.prepare(store: store)
        box.text = "Plan +atlas #backlog !high"
        let id = box.add(store: store)!
        XCTAssertEqual(store.task(id)?.projectId, atlas)
        XCTAssertEqual(store.task(id)?.sprintSlot, .backlog)
        XCTAssertEqual(box.projectId, atlas, "the box now adds to Atlas")
        XCTAssertEqual(box.added, "Added to Atlas · High · Backlog")

        // The composer reads the same words (live, then on ↵) into its draft
        let result = ComposerInput.extract("Plan +atlas #backlog *done !high", final: true)
        XCTAssertEqual(result.text, "Plan")
        XCTAssertEqual(result.tokens, [.project("atlas"), .slot(.backlog), .status("done"), .priority(.high)])
        var draft = ComposerDraft()
        draft.slot = .backlog
        draft.status = store.matchStatus("done", projectId: pid)
        let composed = store.addTask(title: "Plan", draft: draft, projectId: pid, now: t0)!
        XCTAssertEqual(store.task(composed)?.statusCategory, .done)
    }

    func testTabCompletesTheWordBeingTyped() async {
        let (store, pid) = await makeStore()
        let atlas = store.addProject(name: "Atlas works", now: t0)!
        store.addMilestone(projectId: pid, name: "Beta launch")
        store.addMilestone(projectId: atlas, name: "Gamma")
        XCTAssertEqual(store.completeQuickAdd("Fix @be", projectId: pid), "Fix @Beta_launch ")
        XCTAssertEqual(store.completeQuickAdd("Fix +atl", projectId: pid), "Fix +Atlas_works ")
        XCTAssertEqual(store.completeQuickAdd("Fix #ne", projectId: pid), "Fix #next ")
        XCTAssertEqual(store.completeQuickAdd("Fix !h", projectId: pid), "Fix !high ")
        XCTAssertEqual(store.completeQuickAdd("Fix *do", projectId: pid), "Fix *Done ")
        XCTAssertEqual(store.completeQuickAdd("Fix +atlas @ga", projectId: pid), "Fix +atlas @Gamma ", "milestones of the +project")
        XCTAssertNil(store.completeQuickAdd("Fix it", projectId: pid))
        XCTAssertNil(store.completeQuickAdd("Fix @zzz", projectId: pid))
        // A completed word reads back as the same thing
        let input = QuickAddInput.parse("Fix @Beta_launch +Atlas_works")
        XCTAssertEqual(store.matchMilestone(input.milestoneQuery!, projectId: pid)?.name, "Beta launch")
        XCTAssertEqual(store.matchProject(input.projectQuery!)?.id, atlas)
    }

    // MARK: - Timers

    func testTimerKeysSoloPauseAllAndTheLastTimerHotkey() async {
        let (store, pid) = await makeStore()
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let b = store.addTask(title: "B", projectId: pid, now: t0)!
        store.startTimer(a, now: t0)
        store.startTimer(b, now: t0.addingTimeInterval(60))

        store.startTimerExclusively(a, now: t0.addingTimeInterval(120))
        XCTAssertTrue(store.isRunning(a))
        XCTAssertFalse(store.isRunning(b), "⌥-click pauses the others")

        let model = TasksViewModel()
        model.select(.project(pid))
        model.selectedTaskId = b
        XCTAssertTrue(model.perform(.soloTimer, store: store))
        XCTAssertTrue(store.isRunning(b))
        XCTAssertFalse(store.isRunning(a))
        XCTAssertTrue(model.perform(.pauseAllTimers, store: store))
        XCTAssertFalse(store.hasRunningTimers)
        XCTAssertFalse(model.perform(.pauseAllTimers, store: store), "nothing running: ⇧Space passes through")

        // The hotkey resumes the task worked on last, then pauses it
        XCTAssertEqual(store.lastTimerTaskId(), b)
        XCTAssertEqual(store.toggleLastTimer(now: t0.addingTimeInterval(600))?.running, true)
        XCTAssertTrue(store.isRunning(b))
        store.startTimer(a, now: t0.addingTimeInterval(700))
        let paused = store.toggleLastTimer(now: t0.addingTimeInterval(800))
        XCTAssertEqual(paused?.taskId, a, "the one started last")
        XCTAssertEqual(paused?.running, false)
        XCTAssertTrue(store.isRunning(b))
    }

    private final class MockShortcuts: KeyboardShortcutManagerProtocol {
        var current: String?
        func setupShortcut(_ shortcut: String, handler: @escaping () -> Void) -> Bool {
            guard KeyboardShortcutManager.isValidShortcut(shortcut) else { return false }
            current = shortcut
            return true
        }
        func removeShortcut() { current = nil }
    }

    func testTaskHotkeysAreOptionalAndNeverClash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("KeyboardSpeed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = ConfigurationManager(configURL: dir.appendingPathComponent("config.json"))
        let timer = MockShortcuts(), search = MockShortcuts()
        let appState = AppState(configurationManager: config, statusManager: StatusManager(),
                                keyboardShortcutManager: MockShortcuts(), quickAddShortcutManager: MockShortcuts(),
                                timerShortcutManager: timer, menuSearchShortcutManager: search)
        XCTAssertEqual(appState.timerShortcut, "", "off by default")
        XCTAssertNil(timer.current)
        XCTAssertNil(TasksShortcutsHelp.timerShortcutKeys)

        XCTAssertTrue(appState.updateTimerShortcut("control+option+p"))
        XCTAssertEqual(timer.current, "control+option+p")
        XCTAssertEqual(config.getAppSettings().timerShortcut, "control+option+p")
        XCTAssertEqual(TasksShortcutsHelp.timerShortcutKeys, ["⌃", "⌥", "P"])

        XCTAssertFalse(appState.updateMenuSearchShortcut("control+option+p"), "the timer has it")
        XCTAssertNotNil(appState.menuSearchShortcutError)
        XCTAssertFalse(appState.updateMenuSearchShortcut(AppSettings.defaultQuickAddShortcut), "Quick add has it")
        XCTAssertFalse(appState.updateMenuSearchShortcut("command+."), "proofreading has it")
        XCTAssertTrue(appState.updateMenuSearchShortcut("control+option+space"))
        XCTAssertEqual(search.current, "control+option+space")
        XCTAssertFalse(appState.updateQuickAddShortcut("control+option+space"), "nor can Quick add take it")

        XCTAssertTrue(appState.updateTimerShortcut(""))
        XCTAssertNil(timer.current)
        XCTAssertNil(TasksShortcutsHelp.timerShortcutKeys)
        XCTAssertTrue(appState.updateMenuSearchShortcut(""))
    }

    // MARK: - Fuzzy matching

    func testFuzzyMatchOrdersExactPrefixWordAndLetters() {
        let exact = FuzzyMatch.score("atlas", in: "Atlas")!
        let prefix = FuzzyMatch.score("atl", in: "Atlas")!
        let word = FuzzyMatch.score("lau", in: "Beta launch")!
        let inside = FuzzyMatch.score("unc", in: "Beta launch")!
        let initials = FuzzyMatch.score("bl", in: "Beta launch")!
        let letters = FuzzyMatch.score("btlnch", in: "Beta launch")!
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, word)
        XCTAssertGreaterThan(word, inside)
        XCTAssertGreaterThan(inside, initials)
        XCTAssertGreaterThan(initials, letters)
        XCTAssertNil(FuzzyMatch.score("xyz", in: "Beta launch"))
        XCTAssertNotNil(FuzzyMatch.score("lau bet", in: "Beta launch"), "words in any order")
        XCTAssertEqual(FuzzyMatch.score("", in: "x"), 0)
    }

    // MARK: - Discoverability

    func testRowMenuShowsTheRealKeys() async throws {
        let (store, pid) = await makeStore()
        store.addProject(name: "Beta", now: t0)
        let a = store.addTask(title: "A", projectId: pid, now: t0)!
        let model = TasksViewModel()
        model.select(.project(pid))
        let controller = TaskRowController()
        controller.store = store
        controller.model = model
        let menu = controller.makeMenu(task: a, rename: {})!
        func item(_ title: String) -> NSMenuItem? { menu.items.first { $0.title == title } }
        XCTAssertEqual(item("Status…")?.keyEquivalent, "s")
        XCTAssertEqual(item("Status…")?.keyEquivalentModifierMask, [])
        XCTAssertEqual(item("Move to project…")?.keyEquivalent, "m")
        XCTAssertEqual(item("Move to project…")?.keyEquivalentModifierMask, .shift)
        XCTAssertEqual(item("Mark done")?.keyEquivalent, "x")
        XCTAssertEqual(item("Add to Today")?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(item("Duplicate")?.keyEquivalent, "d")
        XCTAssertEqual(item("Delete task")?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(item("Start timer")?.keyEquivalent, " ")

        // Choosing one opens the same picker on that row (once the menu has closed)
        let due = try XCTUnwrap(item("Due date…"))
        _ = (try XCTUnwrap(due.target) as AnyObject).perform(try XCTUnwrap(due.action), with: due)
        let exp = expectation(description: "picker")
        DispatchQueue.main.async { DispatchQueue.main.async { exp.fulfill() } }
        await fulfillment(of: [exp], timeout: 1)
        XCTAssertEqual(model.quickPicker?.action, .due)
        XCTAssertEqual(model.quickPicker?.taskIds, [a])
    }

    func testEveryPickerKeyIsInTheHelpSheet() {
        let keys = Set(TasksShortcutsHelp.sections.flatMap(\.shortcuts).map { $0.keys.joined() })
        for action in TaskQuickAction.allCases {
            XCTAssertTrue(keys.contains(action.keyLabel), "\(action) is listed")
        }
        for listed in ["⌘K", "⌘0", "⌘I", "X", "⌥↑↓", "⇧Space", "⌥Space", "⇧⌘A", "⌘1–9"] {
            XCTAssertTrue(keys.contains(listed), "\(listed) is listed")
        }
    }
}
