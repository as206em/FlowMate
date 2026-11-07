import Foundation

// Labels: workspace-wide tags a task can carry several of. Managed in the Labels sheet (add,
// rename, recolor, delete with usage counts), set from the task panel, the row menu, the L key,
// the bulk bar and the `%label` word of every New task box. Every change is one undo step.
extension TaskStore {
    // MARK: - Reading

    /// Every label, sorted by name (the order every menu and chip row uses).
    var labels: [TaskLabel] {
        workspace.labels.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func label(_ id: UUID) -> TaskLabel? { workspace.labels.first { $0.id == id } }

    /// A task's labels in name order (ids that no longer exist are skipped).
    func labels(of task: TaskItem) -> [TaskLabel] {
        guard !task.labelIds.isEmpty else { return [] }
        let ids = Set(task.labelIds)
        return labels.filter { ids.contains($0.id) }
    }

    /// How many tasks carry each label (archived projects included).
    func labelUsage() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for task in workspace.tasks { for id in task.labelIds { counts[id, default: 0] += 1 } }
        return counts
    }

    /// The label a `%name` word means: the same name, ignoring case, spaces and punctuation. No
    /// prefix match, so a new name is never swallowed by a longer one that exists.
    func matchLabel(_ query: String) -> TaskLabel? {
        let q = Self.matchKey(query)
        guard !q.isEmpty else { return nil }
        return labels.first { Self.matchKey($0.name) == q }
    }

    // MARK: - Managing

    /// Adds a label (a palette color the others use least unless one is given). A name that exists
    /// already (ignoring case) returns that label instead. nil for a blank name.
    @discardableResult
    func addLabel(_ name: String, colorHex: UInt32? = nil) -> UUID? {
        let name = TaskLabel.cleanName(name)
        guard !name.isEmpty else { return nil }
        if let existing = workspace.labels.first(where: { $0.name.lowercased() == name.lowercased() }) { return existing.id }
        let label = TaskLabel(name: name, colorHex: colorHex ?? TaskLabel.nextColor(used: workspace.labels.map(\.colorHex)))
        mutate("Add label") { $0.labels.append(label) }
        return label.id
    }

    /// Renames a label. A blank name, or one another label has, is refused (returns false).
    @discardableResult
    func renameLabel(_ id: UUID, to name: String) -> Bool {
        let name = TaskLabel.cleanName(name)
        guard !name.isEmpty, label(id) != nil else { return false }
        if workspace.labels.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) { return false }
        mutate("Rename label") { ws in
            guard let i = ws.labels.firstIndex(where: { $0.id == id }) else { return }
            ws.labels[i].name = name
        }
        return true
    }

    func setLabelColor(_ id: UUID, colorHex: UInt32) {
        mutate("Change label color") { ws in
            guard let i = ws.labels.firstIndex(where: { $0.id == id }) else { return }
            ws.labels[i].colorHex = colorHex
        }
    }

    /// Deletes a label: it comes off every task and out of every saved view's filter. One undo step.
    func deleteLabel(_ id: UUID, now: Date = Date()) {
        mutate("Delete label") { ws in
            ws.labels.removeAll { $0.id == id }
            for i in ws.tasks.indices where ws.tasks[i].labelIds.contains(id) {
                ws.tasks[i].labelIds.removeAll { $0 == id }
                ws.tasks[i].updatedAt = now
            }
            for i in ws.savedViews.indices { ws.savedViews[i].options.filter.labels.remove(id) }
        }
    }

    // MARK: - On tasks

    /// Replaces a task's labels (unknown ids are dropped by the store).
    func setLabels(_ id: UUID, _ labelIds: [UUID]) {
        var seen = Set<UUID>()
        let ids = labelIds.filter { seen.insert($0).inserted }
        updateTask(id, action: "Change labels") { $0.labelIds = ids }
    }

    /// Adds a label to tasks that don't have it yet. One undo step.
    func addLabel(_ labelId: UUID, to ids: [UUID]) {
        guard label(labelId) != nil else { return }
        undoGroup("Add label") {
            for id in existing(ids) {
                updateTask(id, action: "Add label") { if !$0.labelIds.contains(labelId) { $0.labelIds.append(labelId) } }
            }
        }
    }

    /// Takes a label off the tasks. One undo step.
    func removeLabel(_ labelId: UUID, from ids: [UUID]) {
        undoGroup("Remove label") {
            for id in existing(ids) {
                updateTask(id, action: "Remove label") { $0.labelIds.removeAll { $0 == labelId } }
            }
        }
    }

    /// Whether every one of the tasks has the label (a picker's check mark).
    func allHave(_ labelId: UUID, _ ids: [UUID]) -> Bool {
        let tasks = existing(ids).compactMap { task($0) }
        return !tasks.isEmpty && tasks.allSatisfy { $0.labelIds.contains(labelId) }
    }

    /// Some of the tasks have the label, some don't (a picker shows a dash).
    func someHave(_ labelId: UUID, _ ids: [UUID]) -> Bool {
        let tasks = existing(ids).compactMap { task($0) }
        return tasks.contains { $0.labelIds.contains(labelId) } && !tasks.allSatisfy { $0.labelIds.contains(labelId) }
    }

    /// A picker row: off when every task has it, else on for all of them. Returns true when it
    /// was added.
    @discardableResult
    func toggleLabel(_ labelId: UUID, on ids: [UUID]) -> Bool {
        if allHave(labelId, ids) {
            removeLabel(labelId, from: ids)
            return false
        }
        addLabel(labelId, to: ids)
        return true
    }

    /// "Create label 'x'" in a picker: makes it (or finds it) and adds it to the tasks. One undo step.
    @discardableResult
    func createLabel(_ name: String, adding ids: [UUID]) -> UUID? {
        undoGroup("Add label") { () -> UUID? in
            guard let labelId = addLabel(name) else { return nil }
            if !ids.isEmpty { addLabel(labelId, to: ids) }
            return labelId
        }
    }
}
