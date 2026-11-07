import Foundation

/// Planning, timers, bulk edits and the numbers that drive Next best. The agent's view of Today,
/// Overview and Sprints is built from the same store queries those screens use.
extension MCPTaskTools {
    // MARK: - Definitions

    static var moreDefinitions: [[String: Any]] {
        let ids: [String: Any] = ["type": "array", "items": string, "description": "Task ids"]
        var bulkFields = taskFields
        bulkFields["ids"] = ids
        var createItem = taskFields
        createItem["title"] = string("Task title")
        createItem["subtasks"] = ["type": "array", "items": string, "description": "Subtask titles"]
        return [
            tool("get_today", "What to do now: the single Today list (running, overdue, due today, pinned, done today), the Start next pick with its reason, this week's tracked Make/Reach split against the Reach target, and the next few ranked tasks.", [
                "skip": ["type": "array", "items": string, "description": "Task ids to pass over when choosing Start next"],
                "limit": integer("How many ranked tasks to return (default 5)"),
            ]),
            tool("get_project_status", "One row per project like the Overview: a verdict (\"2 overdue\", \"Nothing planned in Sprint 2\", \"Untouched 12 days\", \"Reach is light\", \"On track\"), sprint progress, overdue, in-progress and the task its play button would start. Projects that need attention come first."),
            tool("get_sprint", "The active sprint: dates, goal, planned time against capacity, the Make/Reach split against the target, the next and backlog loads, and the backlog tasks Fill sprint would add (suggested)."),
            tool("fill_sprint", "Move the best-scoring backlog tasks into the active sprint until its capacity is used. dry_run previews without moving. Needs a weekly capacity on at least one project.", [
                "dry_run": boolean("Only list what would move"),
            ]),
            tool("complete_sprint", "Complete the active sprint and start the next one.", [
                "unfinished": choice(["move_to_next_sprint", "move_to_backlog", "keep_in_sprint"], "What happens to unfinished tasks (default move_to_next_sprint)"),
                "next_goal": string("Goal of the new sprint"),
            ]),
            tool("start_timer", "Start a task's timer. A not started task moves to its first Started status.", [
                "id": string("Task id"),
                "exclusive": boolean("Pause every other timer first"),
            ], required: ["id"]),
            tool("pause_timer", "Pause a task's timer.", ["id": string("Task id")], required: ["id"]),
            tool("pause_all_timers", "Pause every running timer."),
            tool("create_tasks", "Create several tasks at once (one undo step). Each item takes the fields of create_task; a top-level project is the default for items without one.", [
                "project": string("Default project name or id"),
                "tasks": ["type": "array", "items": ["type": "object", "properties": createItem, "required": ["title"]], "description": "Tasks to create"],
            ], required: ["tasks"]),
            tool("update_tasks", "Apply the same change to many tasks (one undo step). Takes the fields of update_task.", bulkFields, required: ["ids"]),
            tool("nudge_task", "Change where Next best ranks a task: up (+5, then 10, then 15 points per press), down, top (first for today) or reset.", [
                "id": string("Task id"),
                "action": choice(["up", "down", "top", "reset"], "Nudge to apply"),
            ], required: ["id", "action"]),
            tool("set_reach_target", "The share of typed time meant for Reach work (20–70). Omit percent to remove the target.", [
                "percent": integer("1–99, or omit for no target"),
            ]),
            tool("set_sprint_goal", "Set the active sprint's goal.", ["goal": string("Goal text")], required: ["goal"]),
            tool("set_impact", "Set how valuable work is (1–10) for Next best, on a project or on tasks. Omit impact to go back to inheriting.", [
                "project": string("Project name or id"),
                "ids": ids,
                "impact": integer("1–10"),
            ]),
            tool("update_project", "Change a project. Only the fields you pass change.", [
                "project": string("Project name or id"),
                "name": string("New name"),
                "notes": string("Markdown description"),
                "target_date": string("Target date (YYYY-MM-DD, fri, 3d…) or \"none\""),
                "archived": boolean("Archive or unarchive"),
                "uses_sprints": boolean("Plan this project in sprints"),
                "weekly_capacity_hours": ["type": "number", "description": "Hours a week on this project; 0 clears it"],
                "impact": integer("1–10; 0 clears it"),
            ], required: ["project"]),
            tool("update_subtask", "Rename, tick or remove a subtask (ids come from get_task).", [
                "id": string("Task id"),
                "subtask_id": string("Subtask id"),
                "title": string("New title"),
                "done": boolean("Ticked or not"),
                "remove": boolean("Delete the subtask"),
            ], required: ["id", "subtask_id"]),
            tool("add_time", "Log time spent away from the timer. It ends ended_minutes_ago minutes ago (default now) and lasts `minutes`.", [
                "id": string("Task id"),
                "minutes": integer("Minutes worked"),
                "ended_minutes_ago": integer("How long ago it ended (default 0)"),
                "note": string("Note"),
            ], required: ["id", "minutes"]),
            tool("get_time_log", "A task's tracked sessions, newest first.", ["id": string("Task id"), "limit": integer("Default 20")], required: ["id"]),
            tool("create_label", "Create a workspace label.", ["name": string("Label name")], required: ["name"]),
            tool("rename_label", "Rename a label.", ["label": string("Current name"), "new_name": string("New name")], required: ["label", "new_name"]),
            tool("create_type", "Create a task type that counts as Make or Reach.", [
                "name": string("Type name"),
                "bucket": choice(["make", "reach"], "Make (building) or Reach (getting it to people)"),
                "impact": integer("1–10 (default 5)"),
            ], required: ["name", "bucket"]),
            tool("quick_add", "Add a task from one line in FlowMate's quick-add language: +project !high #next %label ^type *status due:fri 2h. A project argument is the default.", [
                "text": string("The line, e.g. \"+atlas fix login !high due:fri 2h\""),
                "project": string("Project when the line has no +project"),
            ], required: ["text"]),
            tool("undo_last", "Undo the most recent change in the app, whoever made it (the same as ⌘Z). Returns what was undone."),
            tool("redo_last", "Redo the last undone change."),
        ]
    }

    // MARK: - Dispatch

    func callMore(_ name: String, _ args: [String: Any]) throws -> String {
        switch name {
        case "get_today": return json(today(args))
        case "get_project_status": return json(projectStatus())
        case "get_sprint": return json(sprint())
        case "fill_sprint": return try json(fillSprint(args))
        case "complete_sprint": return json(completeSprint(args))
        case "start_timer":
            let task = try task(args)
            if args["exclusive"] as? Bool == true { store.startTimerExclusively(task.id) } else { store.startTimer(task.id) }
            return json(taskDetail(try self.task(["id": task.id.uuidString])))
        case "pause_timer":
            let task = try task(args)
            store.pauseTimer(task.id)
            return json(taskDetail(try self.task(["id": task.id.uuidString])))
        case "pause_all_timers":
            let count = store.workspace.runningTimers.count
            store.pauseAllTimers()
            return json(["paused": count])
        case "create_tasks": return try json(createTasks(args))
        case "update_tasks": return try json(updateTasks(args))
        case "nudge_task": return try json(nudge(args))
        case "set_reach_target":
            store.setReachTarget(args["percent"] as? Int)
            return json(["reachTargetPercent": store.sprint.reachTargetPercent as Any? ?? NSNull()])
        case "set_sprint_goal":
            store.setSprintGoal(args["goal"] as? String ?? "")
            return json(["goal": store.sprint.goal])
        case "set_impact": return try json(setImpact(args))
        case "update_project": return try json(updateProject(args))
        case "update_subtask": return try json(updateSubtask(args))
        case "add_time": return try json(addTime(args))
        case "get_time_log": return try json(timeLog(args))
        case "create_label":
            guard let name = args["name"] as? String, let id = store.addLabel(name) else { throw MCPToolError("A label needs a name.") }
            return json(["id": id.uuidString, "labels": store.workspace.labels.map(\.name)])
        case "rename_label":
            guard let query = args["label"] as? String, let label = store.matchLabel(query) else {
                throw MCPToolError("No such label. Labels: " + store.workspace.labels.map(\.name).joined(separator: ", "))
            }
            guard store.renameLabel(label.id, to: args["new_name"] as? String ?? "") else {
                throw MCPToolError("Couldn't rename: the name is empty or already used.")
            }
            return json(["labels": store.workspace.labels.map(\.name)])
        case "create_type":
            guard let bucket = TypeBucket(rawValue: (args["bucket"] as? String ?? "").lowercased()) else {
                throw MCPToolError("bucket must be make or reach.")
            }
            guard let name = args["name"] as? String,
                  store.addTaskType(name, bucket: bucket, impact: ImpactScale.clamped(args["impact"] as? Int ?? ImpactScale.neutral)) != nil else {
                throw MCPToolError("Couldn't create the type: the name is empty or already used.")
            }
            return json(["types": store.taskTypes.map(\.name)])
        case "quick_add": return try json(quickAdd(args))
        case "undo_last":
            guard let undone = store.undo() else { throw MCPToolError("Nothing to undo.") }
            return json(["undone": undone])
        case "redo_last":
            guard let redone = store.redo() else { throw MCPToolError("Nothing to redo.") }
            return json(["redone": redone])
        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Reading

    private func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

    private func mixSummary(_ mix: SprintMix) -> [String: Any] {
        var out: [String: Any] = [
            "makeMinutes": mix.makeMinutes, "reachMinutes": mix.reachMinutes, "untypedMinutes": mix.untypedMinutes,
        ]
        if let percent = mix.reachPercent { out["reachPercent"] = percent }
        if let target = mix.targetPercent { out["targetPercent"] = target }
        if let behind = mix.behind { out["behind"] = behind.rawValue }
        return out
    }

    private func today(_ args: [String: Any]) -> [String: Any] {
        let now = Date()
        let plan = store.todayPlan(now: now)
        let skip = Set((args["skip"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        let list = store.nextBest(now: now)
        let ranked = list.ranked.filter { !skip.contains($0.task.id) }
        func row(_ item: NextBestItem) -> [String: Any] {
            var out = summary(item.task)
            out["score"] = item.score.score
            out["reason"] = item.score.reason
            return out
        }
        var out: [String: Any] = [
            "running": plan.running.map(summary),
            "inProgress": plan.inProgress.map(summary),
            "overdue": plan.overdue.map(summary),
            "dueToday": plan.dueToday.map(summary),
            "pinned": plan.focus.map(summary),
            "doneToday": plan.doneToday.map(summary),
            "trackedTodayMinutes": minutes(plan.trackedSeconds),
            "plannedMinutesLeftInPinned": minutes(plan.plannedSeconds),
            "thisWeek": mixSummary(store.trackedMix(in: PortfolioRules.weekInterval(now), now: now)),
            "next": ranked.prefix(max(1, min(args["limit"] as? Int ?? 5, 25))).map(row),
            "keepWarm": list.keepWarm.map { item -> [String: Any] in
                var row = summary(item.task)
                row["why"] = item.keepWarm ?? ""
                return row
            },
        ]
        if let first = ranked.first { out["startNext"] = row(first) }
        return out
    }

    private func projectStatus() -> [String: Any] {
        let now = Date()
        let rows = store.projects.compactMap { project -> (ProjectOverview, OverviewVerdict)? in
            guard let overview = store.projectOverview(project.id, now: now) else { return nil }
            return (overview, OverviewVerdict.of(overview, mix: store.sprintMix(scope: .project(project.id))))
        }
        .sorted { $0.1.rank > $1.1.rank }
        return ["projects": rows.map { overview, verdict -> [String: Any] in
            var out: [String: Any] = [
                "id": overview.project.id.uuidString,
                "name": overview.project.name,
                "verdict": verdict.text,
                "needsAttention": verdict.rank > 0,
                "sprintLine": overview.sprintLine,
                "sprintDone": overview.sprintDone,
                "sprintPlanned": overview.sprintPlanned,
                "openTasks": overview.openCount,
                "overdue": overview.overdueCount,
                "inProgress": overview.inProgressCount,
                "untouchedDays": overview.untouchedDays,
                "trackedThisWeekMinutes": minutes(overview.trackedThisWeek),
                "running": overview.isRunning,
            ]
            if let next = overview.nextTaskId.flatMap({ store.task($0) }) { out["nextTask"] = summary(next) }
            return out
        }]
    }

    private func sprint() -> [String: Any] {
        let now = Date()
        let sprint = store.sprint
        func load(_ slot: SprintSlot) -> [String: Any] {
            let load = store.slotLoad(slot: slot, now: now)
            var out: [String: Any] = ["tasks": load.count, "plannedMinutes": load.plannedMinutes]
            if let capacity = load.capacityMinutes { out["capacityMinutes"] = capacity }
            if let left = load.remainingMinutes { out["minutesLeft"] = left }
            out["summary"] = load.label
            return out
        }
        return [
            "name": sprint.name, "number": sprint.number, "goal": sprint.goal,
            "start": Self.day(sprint.startDate), "end": Self.day(sprint.endDate), "lengthWeeks": sprint.lengthWeeks,
            "active": load(.active), "next": load(.next), "backlog": load(.backlog),
            "mix": mixSummary(store.sprintMix()),
            "suggested": store.fillPicks(now: now).compactMap { store.task($0) }.map(summary),
        ]
    }

    // MARK: - Planning

    private func fillSprint(_ args: [String: Any]) throws -> [String: Any] {
        guard store.sprintCapacityMinutes() != nil else {
            throw MCPToolError("No capacity set. Give a project weekly_capacity_hours with update_project first.")
        }
        if args["dry_run"] as? Bool == true {
            return ["wouldMove": store.fillPicks().compactMap { store.task($0) }.map(summary)]
        }
        let moved = store.fillSprintToCapacity()
        return ["moved": moved.compactMap { store.task($0) }.map(summary), "active": sprint()["active"] ?? [:]]
    }

    private func completeSprint(_ args: [String: Any]) -> [String: Any] {
        let choice = (args["unfinished"] as? String ?? "move_to_next_sprint").lowercased()
        let unfinished: UnfinishedSprintTasks = switch choice {
        case "move_to_backlog": .moveToBacklog
        case "keep_in_sprint": .keepInSprint
        default: .moveToNextSprint
        }
        let before = store.sprint.name
        store.completeSprint(unfinished: unfinished, nextGoal: args["next_goal"] as? String ?? "")
        return ["completed": before, "now": sprint()]
    }

    // MARK: - Bulk

    private func createTasks(_ args: [String: Any]) throws -> [String: Any] {
        guard let items = args["tasks"] as? [[String: Any]], !items.isEmpty else { throw MCPToolError("Pass at least one task.") }
        var created: [[String: Any]] = []
        var errors: [[String: Any]] = []
        store.undoGroup("Add tasks") {
            for (index, var item) in items.enumerated() {
                if item["project"] == nil, let project = args["project"] { item["project"] = project }
                do { created.append(try createTask(item)) } catch let failure as MCPToolError {
                    errors.append(["index": index, "title": item["title"] as? String ?? "", "error": failure.message])
                } catch {
                    errors.append(["index": index, "error": error.localizedDescription])
                }
            }
        }
        return ["created": created.count, "tasks": created.map { $0.filter { ["id", "title", "project", "sprint", "priority"].contains($0.key) } }, "errors": errors]
    }

    private func updateTasks(_ args: [String: Any]) throws -> [String: Any] {
        let ids = try (args["ids"] as? [String] ?? []).map { try task(["id": $0]).id }
        guard !ids.isEmpty else { throw MCPToolError("Pass at least one task id.") }
        var changed: [[String: Any]] = []
        var errors: [[String: Any]] = []
        store.undoGroup("Update tasks") {
            for id in ids {
                var item = args
                item["id"] = id.uuidString
                item["ids"] = nil
                // One title can't name many tasks
                item["title"] = nil
                do {
                    let updated = try updateTask(item)
                    changed.append(updated.filter { ["id", "title", "status", "sprint", "priority", "project"].contains($0.key) })
                } catch let failure as MCPToolError {
                    errors.append(["id": id.uuidString, "error": failure.message])
                } catch {
                    errors.append(["id": id.uuidString, "error": error.localizedDescription])
                }
            }
        }
        return ["updated": changed.count, "tasks": changed, "errors": errors]
    }

    private func nudge(_ args: [String: Any]) throws -> [String: Any] {
        let task = try task(args)
        switch (args["action"] as? String ?? "").lowercased() {
        case "up": store.sendNextBest(task.id, up: true)
        case "down": store.sendNextBest(task.id, up: false)
        case "top": store.sendToTop(task.id)
        case "reset": store.resetNextBest(task.id)
        default: throw MCPToolError("action must be up, down, top or reset.")
        }
        let updated = try self.task(["id": task.id.uuidString])
        var out = summary(updated)
        let score = store.nextBestScore(updated, behind: store.sprintMix().behind)
        out["score"] = score.score
        out["reason"] = score.reason
        return out
    }

    // MARK: - Numbers

    private func setImpact(_ args: [String: Any]) throws -> [String: Any] {
        let impact = args["impact"] as? Int
        if let impact, !(1...10).contains(impact) { throw MCPToolError("impact must be 1–10.") }
        if let name = args["project"] as? String {
            let project = try project(name)
            store.setProjectImpact(project.id, impact)
            return ["project": project.name, "impact": impact as Any? ?? NSNull()]
        }
        let ids = try (args["ids"] as? [String] ?? []).map { try task(["id": $0]).id }
        guard !ids.isEmpty else { throw MCPToolError("Pass a project, or task ids.") }
        store.setTaskImpact(ids, impact)
        return ["tasks": ids.compactMap { store.task($0) }.map(summary), "impact": impact as Any? ?? NSNull()]
    }

    private func updateProject(_ args: [String: Any]) throws -> [String: Any] {
        // Archived projects count here, so one can be brought back by name
        let query = args["project"] as? String ?? ""
        let key = TaskStore.matchKey(query)
        guard let project = (UUID(uuidString: query).flatMap { store.project($0) })
            ?? store.allProjects.first(where: { TaskStore.matchKey($0.name) == key })
            ?? (try? self.project(query)) else {
            throw MCPToolError("No project matches “\(query)”. Projects: " + store.allProjects.map(\.name).joined(separator: ", "))
        }
        let id = project.id
        var target: Date??
        if let text = args["target_date"] as? String { target = text.lowercased() == "none" ? .some(nil) : .some(try Self.date(text)) }
        if let impact = args["impact"] as? Int, impact != 0, !(1...10).contains(impact) { throw MCPToolError("impact must be 1–10, or 0 to clear.") }
        store.undoGroup("Update project") {
            if let name = args["name"] as? String { store.renameProject(id, to: name) }
            if let notes = args["notes"] as? String { store.setProjectNotes(id, notes) }
            if let target { store.setProjectTargetDate(id, target) }
            if let on = args["uses_sprints"] as? Bool { store.setUsesSprints(id, on) }
            if let hours = args["weekly_capacity_hours"] as? Double { store.setWeeklyCapacity(id, hours: hours > 0 ? hours : nil) }
            if let impact = args["impact"] as? Int { store.setProjectImpact(id, impact == 0 ? nil : impact) }
            if let archived = args["archived"] as? Bool {
                if archived { store.archiveProject(id) } else { store.unarchiveProject(id) }
            }
        }
        let updated = store.project(id)!
        var out: [String: Any] = [
            "id": id.uuidString, "name": updated.name, "archived": updated.isArchived, "usesSprints": updated.usesSprints,
        ]
        if let hours = updated.weeklyCapacityHours { out["weeklyCapacityHours"] = hours }
        if let impact = updated.impact { out["impact"] = impact }
        if let date = updated.targetDate { out["targetDate"] = Self.day(date) }
        return out
    }

    // MARK: - Subtasks and time

    private func updateSubtask(_ args: [String: Any]) throws -> [String: Any] {
        let task = try task(args)
        guard let text = args["subtask_id"] as? String, let subtaskId = UUID(uuidString: text),
              let subtask = task.subtasks.first(where: { $0.id == subtaskId }) else {
            throw MCPToolError("No such subtask. Use get_task to see subtask ids.")
        }
        store.undoGroup("Edit subtask") {
            if args["remove"] as? Bool == true {
                store.removeSubtask(task.id, subtaskId)
                return
            }
            if let title = args["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                store.renameSubtask(task.id, subtaskId, to: title)
            }
            if let done = args["done"] as? Bool, done != subtask.isDone { store.toggleSubtask(task.id, subtaskId) }
        }
        return taskDetail(try self.task(["id": task.id.uuidString]))
    }

    private func addTime(_ args: [String: Any]) throws -> [String: Any] {
        let task = try task(args)
        guard let minutes = args["minutes"] as? Int, minutes > 0 else { throw MCPToolError("minutes must be a positive number.") }
        let now = Date()
        let end = now.addingTimeInterval(-Double(max(0, args["ended_minutes_ago"] as? Int ?? 0)) * 60)
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        switch store.addTimeEntry(taskId: task.id, start: start, end: end, note: args["note"] as? String, now: now) {
        case .success: return taskDetail(try self.task(["id": task.id.uuidString]))
        case let .failure(problem): throw MCPToolError("Couldn't add the time: \(problem)")
        }
    }

    private func timeLog(_ args: [String: Any]) throws -> [String: Any] {
        let task = try task(args)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let entries = store.timeEntries(of: task.id).sorted { $0.end > $1.end }
            .prefix(max(1, min(args["limit"] as? Int ?? 20, 200)))
        return [
            "task": task.title,
            "spentMinutes": Int(task.spentSeconds / 60),
            "sessions": entries.map { entry -> [String: Any] in
                var row: [String: Any] = [
                    "start": formatter.string(from: entry.start), "end": formatter.string(from: entry.end),
                    "minutes": Int(entry.end.timeIntervalSince(entry.start) / 60), "source": "\(entry.source)",
                ]
                if let note = entry.note { row["note"] = note }
                return row
            },
        ]
    }

    // MARK: - Quick add

    private func quickAdd(_ args: [String: Any]) throws -> [String: Any] {
        guard let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MCPToolError("Pass the line to add.")
        }
        let base: Project
        if let name = args["project"] as? String { base = try project(name) }
        else if let first = store.projects.first { base = first }
        else { throw MCPToolError("There are no projects yet. Create one first.") }
        guard let outcome = store.quickAddTask(text, projectId: base.id) else { throw MCPToolError("Couldn't add the task.") }
        var out = taskDetail(try task(["id": outcome.taskId.uuidString]))
        out["applied"] = outcome.applied
        return out
    }
}
