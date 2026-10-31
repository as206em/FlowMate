import Foundation

// One-line quick add (the menu bar search, the global New task box, the view model's field):
// the same words as the composer (ComposerInput), resolved against the projects, milestones and
// statuses that exist, then added through the composer's own `addTask(title:draft:projectId:)`.

/// What a one-line quick add will do once resolved against the workspace.
struct QuickAddPlan: Equatable {
    /// Where the task goes: `+project` when it names one, else the box's project
    let projectId: UUID
    let title: String
    let draft: ComposerDraft
    /// The tokens in words, for the preview and the "Added to X · High · Due Fri" note
    let applied: [String]
    /// A milestone token that matched nothing: "@betaa"
    let unmatchedMilestone: String?
    /// A `+project` that matched nothing: "+atlsa"
    let unmatchedProject: String?
}

extension TaskStore {
    /// The project a `+name` means: an exact name (ignoring case, spaces and punctuation), then a
    /// name starting with it, then one containing it. Archived projects don't count.
    func matchProject(_ query: String) -> Project? {
        let q = Self.matchKey(query)
        guard !q.isEmpty else { return nil }
        return projects.first { Self.matchKey($0.name) == q }
            ?? projects.first { Self.matchKey($0.name).hasPrefix(q) }
            ?? projects.first { Self.matchKey($0.name).contains(q) }
    }

    /// The status a `*name` means in the project's workflow, matched like `matchProject`.
    func matchStatus(_ query: String, projectId: UUID) -> WorkflowStatus? {
        let q = Self.matchKey(query)
        guard !q.isEmpty, let statuses = project(projectId)?.statuses else { return nil }
        return statuses.first { Self.matchKey($0.name) == q }
            ?? statuses.first { Self.matchKey($0.name).hasPrefix(q) }
            ?? statuses.first { Self.matchKey($0.name).contains(q) }
    }

    static func matchKey(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// Reads a quick-add line against the workspace. Tokens beat the box's own values
    /// (`milestoneId`, `sprintSlot`); `+project` moves the task (and drops a milestone given by the box).
    func planQuickAdd(_ text: String, projectId: UUID, milestoneId: UUID? = nil, sprintSlot: SprintSlot = .active,
                      now: Date = Date()) -> QuickAddPlan {
        let input = QuickAddInput.parse(text, now: now)
        var target = projectId
        var unmatchedProject: String?
        if let query = input.projectQuery {
            if let found = matchProject(query) { target = found.id } else { unmatchedProject = "+" + query }
        }
        var draft = ComposerDraft()
        draft.projectId = target
        draft.slot = input.slot ?? sprintSlot
        if let milestoneId, milestone(milestoneId)?.projectId == target { draft.milestoneId = milestoneId }
        draft.priority = input.priority
        draft.dueDate = input.dueDate
        draft.expectedMinutes = input.expectedMinutes

        var applied: [String] = []
        if let priority = input.priority { applied.append(priority.title) }
        if let query = input.statusQuery, let status = matchStatus(query, projectId: target) {
            draft.status = status
            applied.append(status.name)
        }
        var unmatchedMilestone: String?
        if let query = input.milestoneQuery {
            if let found = matchMilestone(query, projectId: target) {
                draft.milestoneId = found.id
                applied.append(found.name)
            } else {
                unmatchedMilestone = "@" + query
            }
        }
        if let slot = input.slot { applied.append(sprintLabel(slot, projectId: target)) }
        if let due = input.dueDate { applied.append("Due " + TaskDates.dueLabel(due, now: now)) }
        if let minutes = input.expectedMinutes { applied.append(TaskDurationParser.format(seconds: TimeInterval(minutes * 60))) }

        // A status word that names no status stays in the title, so nothing typed is lost
        var title = input.title
        if let query = input.statusQuery, draft.status == nil {
            title = ([title, "*" + query.replacingOccurrences(of: " ", with: "_")]).filter { !$0.isEmpty }.joined(separator: " ")
        }
        if unmatchedProject != nil, let query = input.projectQuery {
            title = ([title, "+" + query.replacingOccurrences(of: " ", with: "_")]).filter { !$0.isEmpty }.joined(separator: " ")
        }
        // A title made only of tokens keeps the text, so it's never lost
        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = text.trimmingCharacters(in: .whitespaces) }
        return QuickAddPlan(projectId: target, title: title, draft: draft, applied: applied,
                            unmatchedMilestone: unmatchedMilestone, unmatchedProject: unmatchedProject)
    }

    /// Adds a task from a one-line New task box: reads its tokens, applies them (tokens beat the
    /// box's chips) and remembers the project. One undo step.
    @discardableResult
    func quickAddTask(
        _ text: String,
        projectId: UUID,
        milestoneId: UUID? = nil,
        sprintSlot: SprintSlot = .active,
        now: Date = Date()
    ) -> QuickAddOutcome? {
        guard project(projectId) != nil else { return nil }
        let plan = planQuickAdd(text, projectId: projectId, milestoneId: milestoneId, sprintSlot: sprintSlot, now: now)
        guard let id = addTask(title: plan.title, draft: plan.draft, projectId: plan.projectId, now: now) else { return nil }
        return QuickAddOutcome(taskId: id, projectId: plan.projectId, applied: plan.applied,
                               unmatchedMilestone: plan.unmatchedMilestone)
    }

    /// What a quick-add line will do, in words: ["High", "◆ Beta", "Due Fri", "1h 30m"], with
    /// "→ Atlas" first when `+project` sends it elsewhere.
    func quickAddPreview(_ text: String, projectId: UUID, now: Date = Date()) -> [String] {
        let input = QuickAddInput.parse(text, now: now)
        let plan = planQuickAdd(text, projectId: projectId, now: now)
        var parts: [String] = []
        if plan.projectId != projectId, let name = project(plan.projectId)?.name { parts.append("→ " + name) }
        if let unmatched = plan.unmatchedProject { parts.append("No project “\(unmatched.dropFirst())”") }
        if let priority = input.priority { parts.append(priority.title) }
        if let status = plan.draft.status { parts.append(status.name) }
        if let query = input.milestoneQuery {
            parts.append("◆ " + (plan.draft.milestoneId.flatMap { milestone($0)?.name } ?? "No milestone “\(query)”"))
        }
        if let slot = input.slot { parts.append(sprintLabel(slot, projectId: plan.projectId)) }
        if let due = input.dueDate { parts.append("Due " + TaskDates.dueLabel(due, now: now)) }
        if let minutes = input.expectedMinutes { parts.append(Focus.durationString(minutes: minutes)) }
        return parts
    }

    /// The project a quick-add line goes to: its `+project`, else `projectId`.
    func quickAddTarget(_ text: String, projectId: UUID) -> Project? {
        let input = QuickAddInput.parse(text)
        if let query = input.projectQuery, let found = matchProject(query) { return found }
        return project(projectId)
    }

    /// Tab in a one-line box: completes the word being typed after # @ ! + or * with the first
    /// match, written as a token ("@beta_launch "). nil when there's nothing to complete.
    func completeQuickAdd(_ text: String, projectId: UUID?) -> String? {
        guard let active = ComposerInput.activeTrigger(text), active.trigger != .all else { return nil }
        let earlier = ComposerInput.removingActiveWord(text)
        let target = projectId.flatMap { quickAddTarget(earlier, projectId: $0)?.id } ?? projectId
        // The closest name first ("*do" is Done before To do)
        let rows = composerSuggestions(active.trigger, query: active.query, projectId: target).enumerated()
            .sorted { a, b in
                let sa = FuzzyMatch.score(active.query, in: a.element.title) ?? 0
                let sb = FuzzyMatch.score(active.query, in: b.element.title) ?? 0
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
        for row in rows {
            let word: String
            switch row.action {
            case let .slot(slot): word = ["active": "#now", "next": "#next", "backlog": "#backlog"][slot.rawValue] ?? "#now"
            case let .milestone(id): word = ComposerInput.word(.milestone, milestone(id)?.name ?? "")
            case let .priority(priority): word = "!" + priority.title.lowercased()
            case let .project(id): word = ComposerInput.word(.project, project(id)?.name ?? "")
            case let .status(status): word = ComposerInput.word(.status, status.name)
            case .newMilestone, .trigger, .pickDue, .pickTime: continue
            }
            return earlier + word + " "
        }
        return nil
    }
}
