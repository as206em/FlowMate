import AppKit

/// Copying a task's id so an agent with FlowMate's MCP tools can pick it up: the id alone, which
/// `get_task` takes and answers with the task's details and subtasks.
enum TaskIdentifierCopy {
    /// What lands on the clipboard: the full id (the MCP tools also accept a unique prefix of 6+).
    static func text(for id: UUID) -> String { id.uuidString }

    /// Puts the task's id on `pasteboard` (the general one by default).
    static func copy(_ id: UUID, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text(for: id), forType: .string)
    }

    /// The toast after a copy
    static let toastMessage = "Task ID copied. Paste it to an agent with FlowMate's MCP tools to pick it up"
}
