import Foundation

/// Where FlowMate keeps its files: ~/Library/Application Support/FlowMate (the workspace, the
/// settings file and the logs).
///
/// For a second copy of the app or a smoke test, set FLOWMATE_DATA_DIR to another folder and
/// everything goes there instead, so the real data is never read or written. Without it nothing
/// changes. (FLOWMATE_WORKSPACE_FILE still points the workspace alone at one file.)
enum AppDataLocation {
    static let overrideKey = "FLOWMATE_DATA_DIR"

    /// The folder from FLOWMATE_DATA_DIR, when set.
    static var override: URL? { override(in: ProcessInfo.processInfo.environment) }

    static func override(in environment: [String: String]) -> URL? {
        guard let path = environment[overrideKey]?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// FlowMate's folder: the override, else Application Support/FlowMate.
    static var directory: URL {
        directory(environment: ProcessInfo.processInfo.environment)
    }

    static func directory(environment: [String: String]) -> URL {
        if let override = override(in: environment) { return override }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("FlowMate", isDirectory: true)
    }
}
