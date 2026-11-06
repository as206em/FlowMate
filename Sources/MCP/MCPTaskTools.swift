import Foundation

struct MCPToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// The tools the temporary MCP server offers. Each one calls TaskStore, so changes appear in the
/// app at once, are saved like any other edit and undo with ⌘Z.
@MainActor
struct MCPTaskTools {
    let store: TaskStore

    static let instructions = """
    FlowMate task manager. Call get_overview first: it lists projects (with their statuses), the \
    active sprint, labels and task types. Projects, statuses, labels and types are matched by name \
    (case and spacing ignored); tasks by id (a unique prefix of 6+ characters works). Sprint slots are \
    "active", "next" and "backlog". Dates are YYYY-MM-DD or words like "today", "tomorrow", "fri", "3d". \
    Every change can be undone in the app with ⌘Z.
    """

    // MARK: - Definitions

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:],
                             required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    private static let string: [String: Any] = ["type": "string"]
    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func integer(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }
    private static func boolean(_ description: String) -> [String: Any] { ["type": "boolean", "description": description] }
    private static func choice(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    private static var taskFields: [String: Any] {
        [
            "project": string("Project name or id"),
            "priority": choice(["high", "medium", "low"], "Priority"),
            "sprint": choice(["active", "next", "backlog"], "Sprint slot"),
            "status": string("A status of the task's project, by name (e.g. \"In progress\"), or a kind: not started, started, done, canceled"),
            "due": string("Due date: YYYY-MM-DD, today, tomorrow, fri, 3d… ; \"none\" clears it (update only)"),
            "expected_minutes": integer("Expected time in minutes"),
            "notes": string("Markdown description"),
            "labels": ["type": "array", "items": string, "description": "Label names; missing ones are created. On update this replaces the task's labels."],
            "type": string("Task type name (Build, Customers, Sales…); \"none\" clears it (update only)"),
            "pin_today": boolean("Pin to (true) or unpin from (false) Today's My focus"),
        ]
    }

    static var definitions: [[String: Any]] {
        var create = taskFields
        create["title"] = string("Task title")
        create["subtasks"] = ["type": "array", "items": string, "description": "Subtask titles"]
        var update = taskFields
        update["id"] = string("Task id")
        update["title"] = string("New title")
        return [
            tool("get_overview", "Projects (id, statuses, whether they use sprints), the active sprint, labels, task types and counts. Call this first."),
            tool("list_tasks", "List tasks in list order (the order the app shows them). Open tasks only unless include_closed is set.", [
                "project": string("Project name or id"),
                "sprint": choice(["active", "next", "backlog"], "Only this sprint slot"),
                "status": string("Status name or kind"),
                "priority": choice(["high", "medium", "low"], "Only this priority"),
                "label": string("Only tasks with this label"),
                "query": string("Words that must appear in the title"),
                "today": boolean("Only tasks pinned to Today"),
                "include_closed": boolean("Include done and canceled tasks"),
                "limit": integer("Maximum tasks (default 50)"),
            ]),
            tool("get_task", "One task with its description, subtasks, labels and time.", ["id": string("Task id")], required: ["id"]),
            tool("create_task", "Create a task. The project is required.", create, required: ["title", "project"]),
            tool("update_task", "Change any of a task's fields. Only the fields you pass change.", update, required: ["id"]),
            tool("complete_task", "Mark tasks done (or, with undo: true, back to the first Not started status).", [
                "ids": ["type": "array", "items": string, "description": "Task ids"],
                "undo": boolean("Reopen instead"),
            ], required: ["ids"]),
            tool("move_task", "Move a task up, down, to the top or to the bottom of its group. The group is its sprint slot (active, next or backlog) across projects, or Today's My focus with list: \"today\".", [
                "id": string("Task id"),
                "direction": choice(["up", "down", "top", "bottom"], "Where to move it"),
                "steps": integer("Rows to move for up/down (default 1)"),
                "list": choice(["sprint", "today"], "Which ordering: its sprint group (default) or Today's My focus"),
            ], required: ["id", "direction"]),
            tool("delete_task", "Delete a task (undo with ⌘Z in the app).", ["id": string("Task id")], required: ["id"]),
            tool("add_subtask", "Add a subtask to a task.", ["id": string("Task id"), "title": string("Subtask title")], required: ["id", "title"]),
            tool("create_project", "Create a project.", ["name": string("Project name")], required: ["name"]),
        ]
    }

    // MARK: - Dispatch

    func call(_ name: String, _ args: [String: Any]) throws -> String {
        switch name {
        case "get_overview": return json(overview())
        case "list_tasks": return try json(listTasks(args))
        case "get_task": return try json(taskDetail(try task(args)))
        case "create_task": return try json(createTask(args))
        case "update_task": return try json(updateTask(args))
        case "complete_task": return try json(completeTasks(args))
        case "move_task": return try json(moveTask(args))
        case "delete_task":
            let task = try task(args)
            store.deleteTask(task.id)
            return json(["deleted": task.title])
        case "add_subtask":
            let task = try task(args)
            guard let title = args["title"] as? String, store.addSubtask(task.id, title: title) != nil else {
                throw MCPToolError("A subtask needs a title.")
            }
            return json(taskDetail(try self.task(["id": task.id.uuidString])))
        case "create_project":
            guard let name = args["name"] as? String, let id = store.addProject(name: name) else {
                throw MCPToolError("A project needs a name.")
            }
            return json(["id": id.uuidString, "name": name])
        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Tools

    private func overview() -> [String: Any] {
        let ws = store.workspace
        let sprint = ws.sprint
        return [
            "projects": store.projects.map { p in
                [
                    "id": p.id.uuidString, "name": p.name, "usesSprints": p.usesSprints,
                    "statuses": p.statuses.map { ["name": $0.name, "kind": Self.kind($0.category)] },
                    "openTasks": ws.tasks.filter { $0.projectId == p.id && !$0.isClosed }.count,
                ] as [String: Any]
            },
            "sprint": [
                "name": sprint.name, "goal": sprint.goal, "start": Self.day(sprint.startDate), "end": Self.day(sprint.endDate),
            ],
            "labels": ws.labels.map(\.name),
            "taskTypes": ws.taskTypes.map { ["name": $0.name, "bucket": "\($0.bucket)", "impact": $0.impact] as [String: Any] },
            "priorities": ["high", "medium", "low"],
            "sprintSlots": ["active", "next", "backlog"],
            "today": Self.day(Date()),
        ]
    }

    private func listTasks(_ args: [String: Any]) throws -> [String: Any] {
        var tasks = store.tasks(in: .all)
        if let name = args["project"] as? String {
            let project = try project(name)
            tasks = tasks.filter { $0.projectId == project.id }
        }
        if args["include_closed"] as? Bool != true { tasks = tasks.filter { !$0.isClosed && $0.sprintSlot != .closed } }
        if let slot = args["sprint"] as? String { tasks = tasks.filter { $0.sprintSlot == (try? Self.slot(slot)) } }
        if let priority = args["priority"] as? String { tasks = tasks.filter { $0.priority.rawValue == priority.lowercased() } }
        if let status = args["status"] as? String {
            tasks = tasks.filter { task in
                guard let project = store.project(task.projectId) else { return false }
                return (try? resolveStatus(status, in: project))?.id == task.statusId
            }
        }
        if let label = args["label"] as? String {
            let id = store.matchLabel(label)?.id
            tasks = tasks.filter { id != nil && $0.labelIds.contains(id!) }
        }
        if let query = (args["query"] as? String)?.lowercased(), !query.isEmpty { tasks = tasks.filter { $0.title.lowercased().contains(query) } }
        if args["today"] as? Bool == true { tasks = tasks.filter(\.isPinned) }
        let limit = max(1, min(args["limit"] as? Int ?? 50, 200))
        return ["total": tasks.count, "tasks": tasks.prefix(limit).map(summary)]
    }

    private func createTask(_ args: [String: Any]) throws -> [String: Any] {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw MCPToolError("A task needs a title.")
        }
        guard let projectName = args["project"] as? String else {
            throw MCPToolError("A task needs a project. Projects: " + store.projects.map(\.name).joined(separator: ", "))
        }
        let project = try project(projectName)
        var draft = ComposerDraft()
        if let value = args["priority"] as? String { draft.priority = try Self.priority(value) }
        if let value = args["sprint"] as? String { draft.slot = try Self.slot(value) }
        if let value = args["status"] as? String { draft.status = try resolveStatus(value, in: project) }
        if let value = args["due"] as? String { draft.dueDate = try Self.date(value) }
        if let value = args["expected_minutes"] as? Int { draft.expectedMinutes = max(1, value) }
        if let value = args["type"] as? String { draft.typeId = try taskType(value)?.id }
        if args["pin_today"] as? Bool == true { draft.pinToday = true }
        for name in args["labels"] as? [String] ?? [] {
            if let label = store.matchLabel(name) { draft.labelIds.append(label.id) } else { draft.newLabelNames.append(name) }
        }
        guard let id = store.addTask(title: title, draft: draft, projectId: project.id) else {
            throw MCPToolError("Could not create the task.")
        }
        if let notes = args["notes"] as? String, !notes.isEmpty { store.setNotes(id, notes) }
        for subtask in args["subtasks"] as? [String] ?? [] { store.addSubtask(id, title: subtask) }
        return taskDetail(try task(["id": id.uuidString]))
    }

    private func updateTask(_ args: [String: Any]) throws -> [String: Any] {
        let current = try task(args)
        let id = current.id
        // Resolve everything first, so a bad value changes nothing
        let project = try (args["project"] as? String).map { try self.project($0) }
        let finalProject = project ?? store.project(current.projectId)!
        let status = try (args["status"] as? String).map { try resolveStatus($0, in: finalProject) }
        let priority = try (args["priority"] as? String).map(Self.priority)
        let slot = try (args["sprint"] as? String).map(Self.slot)
        var due: Date??
        if let text = args["due"] as? String { due = text.lowercased() == "none" ? .some(nil) : .some(try Self.date(text)) }
        var type: UUID??
        if let text = args["type"] as? String { type = text.lowercased() == "none" ? .some(nil) : .some(try taskType(text)?.id) }
        undoGroupRun("Update task") {
            if let project, project.id != current.projectId { store.setProject(id, project.id) }
            if let title = args["title"] as? String { store.setTitle(id, title) }
            if let notes = args["notes"] as? String { store.setNotes(id, notes) }
            if let priority { store.setPriority(id, priority) }
            if let slot, finalProject.usesSprints { store.setSprintSlot(id, slot) }
            if let status { store.setStatus(id, status) }
            if let due { store.setDueDate(id, due) }
            if let minutes = args["expected_minutes"] as? Int { store.setExpectedMinutes(id, minutes) }
            if let type { store.setType([id], type) }
            if let names = args["labels"] as? [String] {
                let ids = names.compactMap { store.matchLabel($0)?.id ?? store.addLabel($0) }
                store.setLabels(id, ids)
            }
            if let pin = args["pin_today"] as? Bool {
                if pin { store.addToToday([id]) } else { store.removeFromToday([id]) }
            }
        }
        return taskDetail(try task(["id": id.uuidString]))
    }

    private func completeTasks(_ args: [String: Any]) throws -> [String: Any] {
        let ids = try (args["ids"] as? [String] ?? []).map { try task(["id": $0]).id }
        guard !ids.isEmpty else { throw MCPToolError("Pass at least one task id.") }
        if args["undo"] as? Bool == true {
            store.setCategory(ids, .notStarted)
        } else {
            store.setCategory(ids, .done)
        }
        return ["tasks": ids.compactMap { store.task($0) }.map(summary)]
    }

    private func moveTask(_ args: [String: Any]) throws -> [String: Any] {
        let task = try task(args)
        let direction = (args["direction"] as? String ?? "").lowercased()
        let inToday = (args["list"] as? String)?.lowercased() == "today"
        let order: [UUID]
        if inToday {
            order = store.todayPlan().focus.map(\.id)
            guard order.contains(task.id) else { throw MCPToolError("That task isn't in Today's My focus. Pin it first with update_task pin_today.") }
        } else {
            order = store.workspace.tasks.filter { $0.sprintSlot == task.sprintSlot && !$0.isClosed }
                .sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        }
        let before = order
        switch direction {
        case "up", "down":
            let steps = max(1, min(args["steps"] as? Int ?? 1, 100))
            for _ in 0..<steps {
                // Re-read the order each step: it changes as the task moves
                let current = inToday ? store.todayPlan().focus.map(\.id)
                    : store.workspace.tasks.filter { $0.sprintSlot == task.sprintSlot && !$0.isClosed }
                        .sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
                if !store.moveWithinGroup([task.id], offset: direction == "up" ? -1 : 1, order: current, focus: inToday) { break }
            }
        case "top", "bottom":
            if inToday {
                if direction == "top" { store.moveInFocus(task.id, before: order.first) } else { store.moveInFocus(task.id, before: nil) }
            } else if direction == "top" {
                if let first = order.first, first != task.id { store.reorder(task.id, before: first) }
            } else if let last = order.last, last != task.id {
                store.place(task.id, after: last)
            }
        default:
            throw MCPToolError("direction must be up, down, top or bottom.")
        }
        let after = inToday ? store.todayPlan().focus.map(\.id)
            : store.workspace.tasks.filter { $0.sprintSlot == task.sprintSlot && !$0.isClosed }
                .sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        return [
            "moved": before != after,
            "position": (after.firstIndex(of: task.id) ?? 0) + 1,
            "of": after.count,
            "order": after.compactMap { store.task($0)?.title },
        ]
    }

    // MARK: - Lookups

    private func undoGroupRun(_ name: String, _ body: () -> Void) { store.undoGroup(name, body) }

    private func project(_ query: String) throws -> Project {
        if let id = UUID(uuidString: query), let project = store.project(id) { return project }
        if let project = store.matchProject(query) { return project }
        throw MCPToolError("No project matches “\(query)”. Projects: " + store.projects.map(\.name).joined(separator: ", "))
    }

    private func task(_ args: [String: Any]) throws -> TaskItem {
        guard let text = (args["id"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else {
            throw MCPToolError("Pass a task id.")
        }
        if let id = UUID(uuidString: text), let task = store.task(id) { return task }
        if text.count >= 6 {
            let found = store.workspace.tasks.filter { $0.id.uuidString.lowercased().hasPrefix(text) }
            if found.count == 1 { return found[0] }
            if found.count > 1 { throw MCPToolError("“\(text)” matches several tasks; use the full id.") }
        }
        throw MCPToolError("No task with id “\(text)”. Use list_tasks to find ids.")
    }

    private func resolveStatus(_ query: String, in project: Project) throws -> WorkflowStatus {
        if let status = store.matchStatus(query, projectId: project.id) { return status }
        let key = TaskStore.matchKey(query)
        let category: StatusCategory? = switch key {
        case "notstarted", "todo", "open": .notStarted
        case "started", "inprogress", "doing": .started
        case "done", "complete", "completed": .done
        case "canceled", "cancelled": .canceled
        default: nil
        }
        if let category, let status = project.statuses.first(where: { $0.category == category }) { return status }
        throw MCPToolError("No status “\(query)” in \(project.name). Statuses: " + project.statuses.map(\.name).joined(separator: ", "))
    }

    private func taskType(_ query: String) throws -> TaskType? {
        let key = TaskStore.matchKey(query)
        if let type = store.taskTypes.first(where: { TaskStore.matchKey($0.name) == key }) { return type }
        throw MCPToolError("No task type “\(query)”. Types: " + store.taskTypes.map(\.name).joined(separator: ", "))
    }

    private static func priority(_ value: String) throws -> TaskPriority {
        guard let priority = TaskPriority(rawValue: value.lowercased()) else { throw MCPToolError("priority must be high, medium or low.") }
        return priority
    }

    private static func slot(_ value: String) throws -> SprintSlot {
        guard let slot = SprintSlot(rawValue: value.lowercased()), SprintSlot.plannable.contains(slot) else {
            throw MCPToolError("sprint must be active, next or backlog.")
        }
        return slot
    }

    private static func date(_ value: String) throws -> Date {
        guard let date = TaskDateParser.parse(value) else { throw MCPToolError("Couldn't read the date “\(value)”. Use YYYY-MM-DD, today, tomorrow, fri or 3d.") }
        return date
    }

    // MARK: - Output

    private static func kind(_ category: StatusCategory) -> String {
        switch category {
        case .notStarted: return "not started"
        case .started: return "started"
        case .done: return "done"
        case .canceled: return "canceled"
        }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func summary(_ task: TaskItem) -> [String: Any] {
        let project = store.project(task.projectId)
        var out: [String: Any] = [
            "id": task.id.uuidString,
            "title": task.title,
            "project": project?.name ?? "",
            "status": project?.status(task.statusId)?.name ?? task.statusId,
            "statusKind": Self.kind(task.statusCategory),
            "priority": task.priority.rawValue,
            "sprint": task.sprintSlot.rawValue,
            "expectedMinutes": task.expectedMinutes,
            "pinnedToday": task.isPinned,
        ]
        if let due = task.dueDate { out["due"] = Self.day(due) }
        let labels = task.labelIds.compactMap { store.label($0)?.name }
        if !labels.isEmpty { out["labels"] = labels }
        if let type = store.taskType(of: task) { out["type"] = type.name }
        return out
    }

    private func taskDetail(_ task: TaskItem) -> [String: Any] {
        var out = summary(task)
        out["notes"] = task.notes
        out["subtasks"] = task.subtasks.map { ["title": $0.title, "done": $0.isDone] as [String: Any] }
        out["spentMinutes"] = Int(task.spentSeconds / 60)
        out["running"] = store.isRunning(task.id)
        return out
    }

    private func json(_ object: Any) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
