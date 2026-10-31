import Foundation

/// Where FlowMate keeps its files (the workspace, the settings file and the logs):
/// ~/Library/Application Support/FlowMate for the released app, and
/// ~/Library/Application Support/FlowMate Dev for every dev build (see AppChannel).
///
/// For a smoke test on throwaway data, set FLOWMATE_DATA_DIR to another folder and everything
/// goes there instead. (FLOWMATE_WORKSPACE_FILE still points the workspace alone at one file.)
enum AppDataLocation {
    static let overrideKey = "FLOWMATE_DATA_DIR"

    /// The folder from FLOWMATE_DATA_DIR, when set.
    static var override: URL? { override(in: ProcessInfo.processInfo.environment) }

    static func override(in environment: [String: String]) -> URL? {
        guard let path = environment[overrideKey]?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// FlowMate's folder: the override, else this channel's folder in Application Support.
    static var directory: URL {
        directory(environment: ProcessInfo.processInfo.environment)
    }

    static func directory(environment: [String: String], channel: AppChannel = .current) -> URL {
        if let override = override(in: environment) { return override }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(channel.dataFolderName, isDirectory: true)
    }
}
