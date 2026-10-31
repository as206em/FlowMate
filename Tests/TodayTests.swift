import XCTest
@testable import FlowMate

/// Today (TaskScope.today, TodayPlan), pinning (TaskItem.focusDate, schema 9), the menu's Up next
/// and the notification planner.
@MainActor
final class TodayTests: XCTestCase {
    private let calendar = Calendar.current
    /// Fri Oct 30 2026, 12:00 local time
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
    private var today: Date { calendar.startOfDay(for: now) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func makeStore() async -> (TaskStore, UUID, UUID) {
        let store = TaskStore(repository: InMemoryWorkspaceRepository(.empty), saveDelay: 0.05)
        await store.load()
        let a = store.addProject(name: "Liloix", now: now)!
        let b = store.addProject(name: "BotX", now: now)!
        store.clearUndoHistory()
        return (store, a, b)
    }

    // MARK: - Today query

    func testTodayPlanSectionsAcrossProjects() async {
        let (store, a, b) = await makeStore()
        let overdue = store.addTask(title: "Overdue", projectId: a, now: now)!
        store.setDueDate(overdue, day(-2))
        let dueA = store.addTask(title: "Due A", projectId: a, now: now)!
        store.setDueDate(dueA, day(0))
        let dueB = store.addTask(title: "Due B high", projectId: b, now: now)!
        store.setDueDate(dueB, day(0))
        store.setPriority(dueB, .high)
        let pinned = store.addTask(title: "Pinned", projectId: b, now: now)!
        store.addToToday([pinned], now: now)
        let pinnedAndDue = store.addTask(title: "Pinned and due", projectId: a, now: now)!
        store.setDueDate(pinnedAndDue, day(0))
        store.addToToday([pinnedAndDue], now: now)
        let running = store.addTask(title: "Running", projectId: b, now: now)!
        store.setDueDate(running, day(0))
        store.startTimer(running, now: now.addingTimeInterval(-600))
        let done = store.addTask(title: "Done", projectId: a, now: now)!
        store.setCategory(done, .done, now: now)
        let doneYesterday = store.addTask(title: "Done yesterday", projectId: a, now: now)!
        store.setCategory(doneYesterday, .done, now: day(-1).addingTimeInterval(3600))
        let later = store.addTask(title: "Later", projectId: a, now: now)!
        store.setDueDate(later, day(3))

        let plan = store.todayPlan(now: now)
        XCTAssertEqual(plan.running.map(\.id), [running], "a running task shows under Running only")
        XCTAssertEqual(plan.overdue.map(\.id), [overdue])
        XCTAssertEqual(plan.dueToday.map(\.id), [dueB, dueA], "high priority first, across projects")
        XCTAssertEqual(plan.focus.map(\.id), [pinned, pinnedAndDue], "pinned ones under My focus, in pin order")
        XCTAssertEqual(plan.doneToday.map(\.id), [done])
        XCTAssertFalse(plan.allTasks.contains { $0.id == later })
        XCTAssertEqual(Set(plan.allTasks.map(\.id)).count, plan.allTasks.count, "each task in one section")
        // Badge: open tasks overdue, due today or pinned (running ones count too)
        XCTAssertEqual(store.todayCount(now: now), 6)
        XCTAssertEqual(store.dueCounts(now: now).dueToday, 4)
        XCTAssertEqual(store.dueCounts(now: now).overdue, 1)
    }

    func testPlannedIsExpectedMinusTrackedOfPinnedTasks() async {
        let (store, a, _) = await makeStore()
        let x = store.addTask(title: "X", projectId: a, now: now)!
        store.setExpectedMinutes(x, 240)
        let y = store.addTask(title: "Y", projectId: a, now: now)!
        store.setExpectedMinutes(y, 120)
        store.addToToday([x, y], now: now)
        store.addTimeEntry(taskId: x, start: now.addingTimeInterval(-5400), end: now.addingTimeInterval(-3600), now: now)
        // Running for 30 minutes: counts against the plan too
        store.startTimer(y, now: now.addingTimeInterval(-1800))
        let plan = store.todayPlan(now: now)
        XCTAssertEqual(plan.plannedSeconds, (240 - 30) * 60 + (120 - 30) * 60, accuracy: 1)
        XCTAssertEqual(plan.trackedSeconds, 3600, accuracy: 1)
        XCTAssertEqual(plan.trackedByProject.map(\.name), ["Liloix"])
    }

    func testTrackedTodayByProjectMostFirst() async {
        let (store, a, b) = await makeStore()
        let x = store.addTask(title: "X", projectId: a, now: now)!
        let y = store.addTask(title: "Y", projectId: b, now: now)!
        store.addTimeEntry(taskId: x, start: day(0).addingTimeInterval(9 * 3600), end: day(0).addingTimeInterval(11 * 3600), now: now)
        store.addTimeEntry(taskId: y, start: day(0).addingTimeInterval(8 * 3600), end: day(0).addingTimeInterval(8 * 3600 + 4800), now: now)
        // Yesterday doesn't count
        store.addTimeEntry(taskId: y, start: day(-1).addingTimeInterval(9 * 3600), end: day(-1).addingTimeInterval(15 * 3600), now: now)
        let plan = store.todayPlan(now: now)
        XCTAssertEqual(plan.trackedSeconds, 2 * 3600 + 4800, accuracy: 1)
        XCTAssertEqual(plan.trackedByProject.map(\.name), ["Liloix", "BotX"])
        XCTAssertEqual(plan.trackedByProject.map(\.seconds), [7200, 4800])
        XCTAssertEqual(store.menuTodaySummary(now: now), "Today 3h 20m")
    }

    func testFocusFromAnEarlierDayCarriesOver() async {
        let (store, a, _) = await makeStore()
        let old = store.addTask(title: "Old", projectId: a, now: now)!
        store.addToToday([old], now: day(-1).addingTimeInterval(3600))
        let older = store.addTask(title: "Older", projectId: a, now: now)!
        store.addToToday([older], now: day(-4).addingTimeInterval(3600))
        let closed = store.addTask(title: "Closed", projectId: a, now: now)!
        store.addToToday([closed], now: day(-1))
        store.setCategory(closed, .done, now: day(-1).addingTimeInterval(7200))

        let plan = store.todayPlan(now: now)
        XCTAssertEqual(Set(plan.focus.map(\.id)), [old, older], "open pins of earlier days roll into today")
        XCTAssertEqual(plan.carriedOver, 2)
        XCTAssertEqual(store.focusCarryLabel(store.task(old)!, now: now), "From yesterday")
        XCTAssertEqual(store.focusCarryLabel(store.task(older)!, now: now), "From Mon, Oct 26")
        XCTAssertFalse(plan.focus.contains { $0.id == closed }, "a finished task leaves My focus")

        // Pinning again makes it today's
        store.addToToday([old], now: now)
        XCTAssertNil(store.focusCarryLabel(store.task(old)!, now: now))
    }

    func testToggleMoveToTomorrowAndUndo() async {
        let (store, a, _) = await makeStore()
        let x = store.addTask(title: "X", projectId: a, now: now)!
        let y = store.addTask(title: "Y", projectId: a, now: now)!
        store.setDueDate(y, day(-3))
        store.clearUndoHistory()

        XCTAssertTrue(store.toggleToday([x], now: now))
        XCTAssertEqual(store.task(x)?.focusDate, today)
        XCTAssertFalse(store.toggleToday([x], now: now), "a second ⌘T removes it")
        XCTAssertNil(store.task(x)?.focusDate)
        store.undo()
        XCTAssertEqual(store.task(x)?.focusDate, today, "undo pins it again")

        // → Tomorrow: a pin moves to tomorrow (hidden today), an overdue date to tomorrow
        store.moveToDay([x, y], .tomorrow, now: now)
        XCTAssertEqual(store.task(x)?.focusDate, day(1))
        XCTAssertEqual(store.task(y)?.dueDate, day(1))
        XCTAssertTrue(store.todayPlan(now: now).focus.isEmpty)
        XCTAssertTrue(store.todayPlan(now: now).overdue.isEmpty)
        XCTAssertEqual(store.todayPlan(now: day(1).addingTimeInterval(3600)).focus.map(\.id), [x], "back tomorrow")
        store.undo()
        XCTAssertEqual(store.task(y)?.dueDate, day(-3), "one undo step")

        // Move all overdue to today
        store.moveToDay([y], .today, now: now)
        XCTAssertEqual(store.task(y)?.dueDate, today)
    }

    func testReorderFocusAndDropIn() async {
        let (store, a, _) = await makeStore()
        let x = store.addTask(title: "X", projectId: a, now: now)!
        let y = store.addTask(title: "Y", projectId: a, now: now)!
        let z = store.addTask(title: "Z", projectId: a, now: now)!
        store.addToToday([x, y], now: now)
        store.moveInFocus(y, before: x, now: now)
        XCTAssertEqual(store.todayPlan(now: now).focus.map(\.id), [y, x])
        // A task dragged in from another section is pinned where it lands
        store.moveInFocus(z, before: x, now: now)
        XCTAssertEqual(store.todayPlan(now: now).focus.map(\.id), [y, z, x])
        XCTAssertEqual(store.task(z)?.focusDate, today)
    }

    func testArchivedProjectsStayOutOfToday() async {
        let (store, a, b) = await makeStore()
        let x = store.addTask(title: "X", projectId: b, now: now)!
        store.setDueDate(x, today)
        store.addTask(title: "Y", projectId: a, now: now)
        store.archiveProject(b, now: now)
        XCTAssertTrue(store.todayPlan(now: now).dueToday.isEmpty)
        XCTAssertEqual(store.todayCount(now: now), 0)
    }

    // MARK: - Schema 9

    func testSchema8TasksLoadUnpinnedAndPinsRoundTrip() throws {
        let pid = UUID(), tid = UUID()
        let json = """
        {"schemaVersion": 8,
         "projects": [{"id": "\(pid.uuidString)", "name": "Liloix", "colorHex": 4280391411}],
         "tasks": [{"id": "\(tid.uuidString)", "projectId": "\(pid.uuidString)", "title": "Write", "statusId": "todo",
                    "statusCategory": "notStarted", "sprintSlot": "active"}]}
        """
        let decoder = LocalJSONWorkspaceRepository.makeDecoder()
        var ws = try decoder.decode(Workspace.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(ws.schemaVersion, 10)
        XCTAssertEqual(ws.tasks.count, 1)
        XCTAssertNil(ws.tasks[0].focusDate, "nothing is pinned in older files")
        XCTAssertEqual(ws.tasks[0].title, "Write")

        ws.tasks[0].focusDate = today
        ws.tasks[0].focusIndex = 3
        let data = try LocalJSONWorkspaceRepository.makeEncoder().encode(ws)
        let back = try decoder.decode(Workspace.self, from: data)
        XCTAssertEqual(back.tasks[0].focusDate, today)
        XCTAssertEqual(back.tasks[0].focusIndex, 3)
    }

    // MARK: - View model

    func testTodayScopeKeyboardOrderAndWindowRestore() async {
        let (store, a, _) = await makeStore()
        let x = store.addTask(title: "X", projectId: a)!
        store.setDueDate(x, Date())
        let y = store.addTask(title: "Y", projectId: a)!
        store.addToToday([y])
        let defaults = UserDefaults(suiteName: "today-\(UUID())")!
        let model = TasksViewModel(defaults: defaults, stateKey: "state")
        model.select(.today)
        XCTAssertTrue(model.tabs.isEmpty)
        XCTAssertFalse(model.showsFilterBar)
        XCTAssertEqual(model.visibleTasks(store).map(\.id), [x, y], "Due today, then My focus")
        XCTAssertEqual(model.moveSelection(1, store: store), x)
        XCTAssertEqual(model.moveSelection(1, store: store), y)
        XCTAssertEqual(model.defaultComposerKey(store), TasksViewModel.listComposerKey(TasksViewModel.todayFocusKey))
        model.toggleGroup(TasksViewModel.todayDueKey)
        XCTAssertEqual(model.visibleTasks(store).map(\.id), [y], "a folded section is skipped")

        // ⌘T on the selection
        model.selectedTaskId = y
        XCTAssertTrue(model.perform(.toggleToday, store: store))
        XCTAssertNil(store.task(y)?.focusDate)
        XCTAssertEqual(TasksShortcut.match(keyCode: 17, characters: "t", modifiers: [.command]), .toggleToday)

        let restored = TasksViewModel(defaults: defaults, stateKey: "state")
        XCTAssertEqual(restored.scope, .today, "the window reopens on Today")
        XCTAssertEqual(TaskScope(storageKey: "today"), .today)
        restored.select(.all)
        XCTAssertEqual(restored.sidebarScopes(store).prefix(2), [.today, .all])
        XCTAssertTrue(restored.perform(.previousScope, store: store))
        XCTAssertEqual(restored.scope, .today)
    }

    func testComposerOnTodayPinsTheTask() async {
        let (store, a, _) = await makeStore()
        var draft = ComposerDraft()
        draft.apply(preset: .sprint(.active), in: .today)
        XCTAssertTrue(draft.pinToday)
        let id = store.addTask(title: "From Today", draft: draft, projectId: a, now: now)!
        XCTAssertEqual(store.task(id)?.focusDate, today)
        XCTAssertEqual(store.todayPlan(now: now).focus.map(\.id), [id])
    }

    // MARK: - Up next

    func testUpNextOrderAndCap() async {
        let (store, a, b) = await makeStore()
        let sprintLow = store.addTask(title: "Sprint low", projectId: a, now: now)!
        store.setPriority(sprintLow, .low)
        let sprintHigh = store.addTask(title: "Sprint high", projectId: b, now: now)!
        store.setPriority(sprintHigh, .high)
        let pinned = store.addTask(title: "Pinned", projectId: a, sprintSlot: .backlog, now: now)!
        store.addToToday([pinned], now: now)
        let due = store.addTask(title: "Due", projectId: b, sprintSlot: .next, now: now)!
        store.setDueDate(due, today)
        let overdue = store.addTask(title: "Overdue", projectId: a, sprintSlot: .backlog, now: now)!
        store.setDueDate(overdue, day(-1))
        let inProgress = store.addTask(title: "In progress", projectId: a, now: now)!
        store.setCategory(inProgress, .started, now: now)
        store.setDueDate(inProgress, today)
        let backlog = store.addTask(title: "Backlog", projectId: a, sprintSlot: .backlog, now: now)!

        let next = store.upNext(now: now).map(\.id)
        XCTAssertEqual(next, [overdue, due, pinned, sprintHigh, sprintLow])
        XCTAssertFalse(next.contains(inProgress), "already listed under In progress")
        XCTAssertFalse(next.contains(backlog))
        XCTAssertEqual(store.upNext(limit: 2, now: now).map(\.id), [overdue, due])
        XCTAssertEqual(store.menuBrowseItems(now: now).items.suffix(5), next.map { MenuRowItem.upNext($0) })
        XCTAssertEqual(store.menuTodaySummary(now: now), "Today 0m · 2 due · 1 overdue")
    }

    // MARK: - Notifications

    private func input(_ store: TaskStore) -> NotificationPlanInput { store.notificationInput(now: now) }

    func testMorningSummaryAndDueRemindersForTodayAndTomorrow() async {
        let (store, a, _) = await makeStore()
        let morningNow = day(0).addingTimeInterval(7 * 3600) // 7:00, before the 9:00 summary
        let x = store.addTask(title: "Ship build", projectId: a, now: now)!
        store.setDueDate(x, today)
        let y = store.addTask(title: "Old", projectId: a, now: now)!
        store.setDueDate(y, day(-1))
        let z = store.addTask(title: "Tomorrow's", projectId: a, now: now)!
        store.setDueDate(z, day(1))
        let settings = NotificationSettings(morningSummary: true, dueReminders: true)

        let plan = NotificationPlanner.plan(store.notificationInput(now: morningNow), settings: settings, now: morningNow)
        let morning = plan.filter { $0.kind == .morning }
        XCTAssertEqual(morning.map(\.body), ["1 due today, 1 overdue", "1 due today, 2 overdue"], "today, then tomorrow")
        XCTAssertEqual(morning.first?.fireDate, day(0).addingTimeInterval(9 * 3600))
        XCTAssertEqual(morning.first?.target, .today)
        let due = plan.filter { $0.kind == .due }
        XCTAssertEqual(due.map(\.title), ["Ship build", "Tomorrow's"])
        XCTAssertEqual(due.first?.body, "Due today · Liloix")
        XCTAssertEqual(due.first?.target, .task(x))

        // After 9:00 today's are past: only tomorrow's remain
        let later = NotificationPlanner.plan(input(store), settings: settings, now: now)
        XCTAssertEqual(later.filter { $0.kind == .morning }.count, 1)
        XCTAssertEqual(later.first { $0.kind == .morning }?.fireDate, day(1).addingTimeInterval(9 * 3600))

        // Off: nothing
        XCTAssertTrue(NotificationPlanner.plan(input(store), settings: NotificationSettings(longRunAlerts: false, sleepAlerts: false), now: now).isEmpty)
    }

    func testDueRemindersAreCappedPerDay() async {
        let (store, a, _) = await makeStore()
        for i in 0..<6 {
            let id = store.addTask(title: "T\(i)", projectId: a, now: now)!
            store.setDueDate(id, day(1))
        }
        let plan = NotificationPlanner.plan(input(store), settings: NotificationSettings(dueReminders: true), now: now)
        XCTAssertEqual(plan.count, NotificationPlanner.dueReminderLimit)
        XCTAssertEqual(plan.last?.title, "3 more due today")
    }

    func testMilestoneReminderTwoDaysBefore() async {
        let (store, a, _) = await makeStore()
        let m = store.addMilestone(projectId: a, name: "Marketing")!
        store.setMilestoneDue(m, to: day(4))
        for i in 0..<9 {
            let id = store.addTask(title: "M\(i)", projectId: a, milestoneId: m, now: now)!
            if i < 4 { store.setCategory(id, .done, now: now) }
        }
        let past = store.addMilestone(projectId: a, name: "Soon")!
        store.setMilestoneDue(past, to: day(1)) // its reminder day has passed
        let plan = NotificationPlanner.plan(input(store), settings: NotificationSettings(milestoneReminders: true), now: now)
        XCTAssertEqual(plan.map(\.title), ["Marketing is due in 2 days"])
        XCTAssertEqual(plan.first?.body, "4 of 9 done · Liloix")
        XCTAssertEqual(plan.first?.fireDate, day(2).addingTimeInterval(9 * 3600))
        XCTAssertEqual(plan.first?.target, .milestone(m))
    }

    func testLongRunAndSleepPrompts() async {
        let (store, a, _) = await makeStore()
        let x = store.addTask(title: "Deep work", projectId: a, now: now)!
        store.startTimer(x, now: now.addingTimeInterval(-3600))
        let settings = NotificationSettings()
        var plan = NotificationPlanner.plan(input(store), settings: settings, now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.kind, .longRun)
        XCTAssertEqual(plan.first?.title, "Still working on Deep work?")
        XCTAssertEqual(plan.first?.fireDate, now.addingTimeInterval(2 * 3600), "3h after the start")
        XCTAssertEqual(plan.first?.taskId, x)
        XCTAssertEqual(plan.first?.kind.categoryId, NotificationPlanner.longRunCategory)
        let firstId = plan.first!.id

        // Keep: the next one is a full interval later, under a new id
        store.keepRunning(x, now: now)
        plan = NotificationPlanner.plan(input(store), settings: settings, now: now)
        XCTAssertEqual(plan.first?.fireDate, now.addingTimeInterval(3 * 3600))
        XCTAssertNotEqual(plan.first?.id, firstId)

        // Sleep gap: an immediate prompt
        store.systemWillSleep(at: now.addingTimeInterval(-1800))
        store.systemDidWake(at: now)
        plan = NotificationPlanner.plan(input(store), settings: settings, now: now)
        let away = plan.first { $0.kind == .away }
        XCTAssertNil(away?.fireDate)
        XCTAssertEqual(away?.title, "A timer ran while your Mac slept 30m")
        XCTAssertTrue(PlannedNotification.Kind.away.onlyWhenInBackground)

        // Prompt off in General › Timers: no long-run notification
        store.setLongRunPromptMinutes(0)
        XCTAssertFalse(NotificationPlanner.plan(input(store), settings: settings, now: now).contains { $0.kind == .longRun })
    }

    func testDiffAddsRemovesAndNeverDuplicates() {
        let fire = now.addingTimeInterval(3600)
        let a = PlannedNotification(id: "flowmate.a", kind: .morning, title: "Today", body: "1 due today", fireDate: fire, target: .today)
        let b = PlannedNotification(id: "flowmate.b", kind: .due, title: "X", body: "Due today · L", fireDate: fire, target: .today)
        let prompt = PlannedNotification(id: "flowmate.away-1", kind: .away, title: "Slept", body: "", fireDate: nil, target: .today)

        var changes = NotificationPlanner.diff(pending: [:], delivered: [], plan: [a, b, prompt], now: now)
        XCTAssertEqual(changes.add.map(\.id), ["flowmate.a", "flowmate.b", "flowmate.away-1"])

        // Already there: nothing to do
        changes = NotificationPlanner.diff(pending: [a.id: a.signature, b.id: b.signature], delivered: [prompt.id],
                                           plan: [a, b, prompt], now: now)
        XCTAssertTrue(changes.isEmpty)
        // Sent this run but cleared by the user: not sent again
        changes = NotificationPlanner.diff(pending: [a.id: a.signature, b.id: b.signature], delivered: [],
                                           plan: [a, b, prompt], posted: [prompt.id], now: now)
        XCTAssertTrue(changes.add.isEmpty)

        // Changed text: replaced; gone from the plan: removed; someone else's: left alone
        let a2 = PlannedNotification(id: a.id, kind: .morning, title: "Today", body: "2 due today", fireDate: fire, target: .today)
        changes = NotificationPlanner.diff(pending: [a.id: a.signature, b.id: b.signature, "other": "x"],
                                           delivered: [prompt.id, "flowmate.morning-old"], plan: [a2], now: now)
        XCTAssertEqual(changes.removePending, [a.id, b.id])
        XCTAssertEqual(changes.add.map(\.body), ["2 due today"])
        XCTAssertEqual(changes.removeDelivered, [prompt.id], "an answered prompt is taken back; a shown summary stays")

        // A time already past isn't scheduled
        let past = PlannedNotification(id: "flowmate.c", kind: .longRun, title: "", body: "", fireDate: now.addingTimeInterval(-5), target: .today)
        XCTAssertTrue(NotificationPlanner.diff(pending: [:], delivered: [], plan: [past], now: now).add.isEmpty)
    }

    func testServiceSchedulesThroughTheClientAndHandlesActions() async {
        let (store, a, _) = await makeStore()
        let x = store.addTask(title: "X", projectId: a)!
        store.setDueDate(x, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!)
        let client = FakeNotificationClient()
        let service = TaskNotifications(client: client)
        service.debounce = 0
        service.settings = NotificationSettings(morningSummary: true, dueReminders: true)
        service.start(store: store)
        await service.reschedule()
        XCTAssertTrue(client.added.isEmpty, "nothing without permission")
        let status = await service.requestAuthorizationIfNeeded()
        XCTAssertEqual(status, .authorized)
        await service.reschedule()
        let first = client.pendingIds
        XCTAssertTrue(first.contains { $0.hasPrefix("flowmate.morning-") })
        XCTAssertTrue(first.contains { $0.hasPrefix("flowmate.due-\(x.uuidString)") })
        let addedCount = client.added.count
        await service.reschedule()
        XCTAssertEqual(client.added.count, addedCount, "rescheduling the same plan adds nothing")

        service.settings.dueReminders = false
        await service.reschedule()
        XCTAssertFalse(client.pendingIds.contains { $0.hasPrefix("flowmate.due-") })

        // Actions
        store.startTimer(x)
        service.handle(action: NotificationAction.pause, userInfo: ["taskId": x.uuidString], store: store)
        XCTAssertFalse(store.isRunning(x))
        XCTAssertEqual(service.handle(action: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: ["target": "task:\(x.uuidString)"], store: store),
                       .task(x))
        XCTAssertEqual(NotificationTarget(stringValue: "today"), .today)
        XCTAssertFalse(TaskNotifications.presentsWhileActive(kind: "longRun"))
        XCTAssertTrue(TaskNotifications.presentsWhileActive(kind: "morning"))
    }
}

/// Notification Center stand-in: always allows once asked.
@MainActor
private final class FakeNotificationClient: NotificationCenterClient {
    var status: NotificationAuthorization = .notDetermined
    var pendingStore: [String: String] = [:]
    var deliveredStore: Set<String> = []
    var added: [PlannedNotification] = []
    var pendingIds: Set<String> { Set(pendingStore.keys) }

    func authorization() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool { status = .authorized; return true }
    func pending() async -> [String: String] { pendingStore }
    func delivered() async -> Set<String> { deliveredStore }
    func add(_ notification: PlannedNotification) async {
        added.append(notification)
        if notification.fireDate == nil { deliveredStore.insert(notification.id) } else { pendingStore[notification.id] = notification.signature }
    }
    func removePending(_ ids: [String]) { ids.forEach { pendingStore[$0] = nil } }
    func removeDelivered(_ ids: [String]) { ids.forEach { deliveredStore.remove($0) } }
    func registerCategories() {}
}
