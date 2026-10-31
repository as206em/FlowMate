import Foundation

// The New task composer's typing rules: words it recognises move out of the title into the
// property row below it (sprint, milestone, priority, due, time, project), and a word starting
// with # @ ! + or / opens a menu to pick from. Pure functions, so they're easy to test.
//
//   2h  90m  1h30m  1.5h  ~45m   expected time
//   #now #next #backlog          sprint (#active, #sprint, #current and #later also work)
//   @beta                        milestone (matched by name in the project)
//   !high !med !low  !1 !2 !3    priority
//   due:fri  today  tomorrow     due date (due: takes anything TaskDateParser reads)
//   +atlas                       project
//   /                            a menu of all of the above

/// The properties the composer has collected for the next task. nil means "not set".
struct ComposerDraft: Equatable {
    var projectId: UUID?
    /// Set by the group the composer sits in (Board column, List grouped by status): a status of
    /// the project's workflow, matched by name and category in another project
    var status: WorkflowStatus?
    /// Set by an All projects column or group: the first status of this category in the project
    var category: StatusCategory?
    var slot: SprintSlot = .active
    var milestoneId: UUID?
    var priority: TaskPriority?
    var dueDate: Date?
    var expectedMinutes: Int?

    /// Anything besides the defaults (which keeps the composer open)
    var hasValues: Bool {
        slot != .active || milestoneId != nil || priority != nil || dueDate != nil || expectedMinutes != nil
    }
}

/// One recognised word, before it is applied to the draft.
enum ComposerToken: Equatable {
    case minutes(Int)
    case slot(SprintSlot)
    case milestone(String)
    case priority(TaskPriority)
    case due(Date)
    case project(String)
}

/// A word that opens a picking menu.
enum ComposerTrigger: Character, CaseIterable {
    case sprint = "#"
    case milestone = "@"
    case priority = "!"
    case project = "+"
    case all = "/"
}

enum ComposerInput {
    /// What a finished word means, or nil when it's part of the title.
    static func token(_ word: String, now: Date = Date(), calendar: Calendar = .current) -> ComposerToken? {
        let lower = word.lowercased()
        guard let first = lower.first else { return nil }
        switch first {
        case "#":
            return slot(String(lower.dropFirst())).map(ComposerToken.slot)
        case "@":
            let name = String(word.dropFirst()).replacingOccurrences(of: "_", with: " ")
            return name.isEmpty ? nil : .milestone(name)
        case "!":
            return priority(String(lower.dropFirst())).map(ComposerToken.priority)
        case "+":
            let name = String(word.dropFirst()).replacingOccurrences(of: "_", with: " ")
            return name.isEmpty ? nil : .project(name)
        case "~":
            guard let minutes = TaskDurationParser.minutes(String(lower.dropFirst())), minutes > 0 else { return nil }
            return .minutes(minutes)
        default:
            break
        }
        if lower.hasPrefix("due:"), lower.count > 4,
           let date = TaskDateParser.parse(String(lower.dropFirst(4)).replacingOccurrences(of: "_", with: " "), now: now, calendar: calendar) {
            return .due(date)
        }
        if ["today", "tomorrow", "tmr", "tmrw"].contains(lower), let date = TaskDateParser.parse(lower, now: now, calendar: calendar) {
            return .due(date)
        }
        // A bare duration needs a unit, so a number in a title ("Fix 2 bugs") stays text
        if lower.range(of: #"^\d+(?:[.,]\d+)?(?:h|hr|hrs)(?:\d+m)?$|^\d+(?:m|min|mins)$"#, options: .regularExpression) != nil,
           let minutes = TaskDurationParser.minutes(lower), minutes > 0 {
            return .minutes(minutes)
        }
        return nil
    }

    static func slot(_ word: String) -> SprintSlot? {
        switch word {
        case "now", "active", "sprint", "current", "this": return .active
        case "next": return .next
        case "backlog", "later", "someday": return .backlog
        default: return nil
        }
    }

    static func priority(_ word: String) -> TaskPriority? {
        switch word {
        case "high", "hi", "h", "1": return .high
        case "medium", "med", "m", "2": return .medium
        case "low", "lo", "l", "3": return .low
        default: return nil
        }
    }

    /// Takes the finished words it recognises out of the text. A word is finished once a space
    /// follows it; with `final`, the last word counts too (on ↵). `accepts` says whether a token can
    /// be used (a milestone or project that exists); refused words stay in the title.
    static func extract(
        _ text: String,
        final: Bool = false,
        now: Date = Date(),
        accepts: (ComposerToken) -> Bool = { _ in true }
    ) -> (text: String, tokens: [ComposerToken]) {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard words.count > 1 || final else { return (text, []) }
        var kept: [String] = []
        var tokens: [ComposerToken] = []
        for (index, word) in words.enumerated() {
            let finished = final || index < words.count - 1
            if finished, let token = token(word, now: now), accepts(token) {
                tokens.append(token)
            } else {
                kept.append(word)
            }
        }
        guard !tokens.isEmpty else { return (text, []) }
        // Removing a word leaves its spaces behind: squeeze runs of spaces, keep a trailing one
        var result = kept.joined(separator: " ")
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        if result.hasPrefix(" ") { result.removeFirst() }
        return (result, tokens)
    }

    /// The word being typed at the end of the text when it starts with # @ ! + or /:
    /// the trigger and what follows it ("#ne" → sprint, "ne").
    static func activeTrigger(_ text: String) -> (trigger: ComposerTrigger, query: String)? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              let first = last.first, let trigger = ComposerTrigger(rawValue: first) else { return nil }
        return (trigger, String(last.dropFirst()))
    }

    /// The text without the word being typed (after a pick from the menu)
    static func removingActiveWord(_ text: String) -> String {
        guard let space = text.lastIndex(of: " ") else { return "" }
        return String(text[...space])
    }
}

/// One row of the composer's menu.
struct ComposerSuggestion: Identifiable, Equatable {
    enum Action: Equatable {
        case slot(SprintSlot)
        case milestone(UUID)
        case newMilestone(String)
        case priority(TaskPriority)
        case project(UUID)
        /// "/" menu: switch to that trigger's menu
        case trigger(ComposerTrigger)
        /// "/" menu: open the due date or time picker
        case pickDue
        case pickTime
    }

    let id: String
    let title: String
    var detail: String = ""
    let action: Action
}

extension TaskStore {
    /// The menu for a trigger word, filtered by what follows it.
    func composerSuggestions(_ trigger: ComposerTrigger, query: String, projectId: UUID?) -> [ComposerSuggestion] {
        let q = query.lowercased().filter { $0.isLetter || $0.isNumber }
        func matches(_ text: String) -> Bool {
            q.isEmpty || text.lowercased().filter { $0.isLetter || $0.isNumber }.contains(q)
        }
        switch trigger {
        case .sprint:
            guard let projectId else { return [] }
            let words: [SprintSlot: String] = [.active: "#now", .next: "#next", .backlog: "#backlog"]
            return SprintSlot.plannable
                .filter { matches(sprintLabel($0, projectId: projectId)) || matches(words[$0] ?? "") }
                .map { slot in
                    let state = slot == .active ? " · active" : slot == .next ? " · next" : ""
                    return ComposerSuggestion(id: "slot-\(slot)", title: sprintLabel(slot, projectId: projectId) + state,
                                              detail: words[slot] ?? "", action: .slot(slot))
                }
        case .milestone:
            guard let projectId else { return [] }
            let open = milestones(of: projectId).filter { !$0.isCompleted && matches($0.name) }
            var rows = open.map {
                ComposerSuggestion(id: "ms-\($0.id)", title: "◆ " + $0.name,
                                   detail: $0.dueDate.map { SprintState.shortDate($0) } ?? "", action: .milestone($0.id))
            }
            let name = query.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !open.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                rows.append(ComposerSuggestion(id: "ms-new", title: "New milestone “\(name)”", action: .newMilestone(name)))
            }
            return rows
        case .priority:
            return [TaskPriority.high, .medium, .low]
                .filter { matches($0.title) || ComposerInput.priority(q) == $0 }
                .map { ComposerSuggestion(id: "p-\($0.title)", title: $0.title, detail: "!\($0.title.lowercased())", action: .priority($0)) }
        case .project:
            return projects.filter { matches($0.name) }
                .map { ComposerSuggestion(id: "pr-\($0.id)", title: $0.name, action: .project($0.id)) }
        case .all:
            let all: [ComposerSuggestion] = [
                .init(id: "all-sprint", title: "Sprint", detail: "#", action: .trigger(.sprint)),
                .init(id: "all-milestone", title: "Milestone", detail: "@", action: .trigger(.milestone)),
                .init(id: "all-priority", title: "Priority", detail: "!", action: .trigger(.priority)),
                .init(id: "all-due", title: "Due date", detail: "due:fri", action: .pickDue),
                .init(id: "all-time", title: "Expected time", detail: "2h", action: .pickTime),
                .init(id: "all-project", title: "Project", detail: "+", action: .trigger(.project)),
            ]
            return all.filter { matches($0.title) }
        }
    }

    /// Adds the composer's task with all its properties. One undo step; remembers the project.
    @discardableResult
    func addTask(title: String, draft: ComposerDraft, projectId: UUID, now: Date = Date()) -> UUID? {
        undoGroup("Add task") { () -> UUID? in
            guard let id = addTask(title: title, projectId: projectId, milestoneId: draft.milestoneId,
                                   sprintSlot: draft.slot, now: now) else { return nil }
            if let priority = draft.priority { setPriority(id, priority) }
            if let due = draft.dueDate { setDueDate(id, due) }
            if let minutes = draft.expectedMinutes { setExpectedMinutes(id, minutes) }
            if let status = draft.status {
                setStatus(id, status, now: now)
            } else if let category = draft.category {
                setCategory(id, category, now: now)
            }
            rememberProject(projectId)
            return id
        }
    }
}
