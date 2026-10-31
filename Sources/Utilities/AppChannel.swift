import Foundation

/// Which copy of FlowMate this is: the released app or a development build.
///
/// macOS keeps an app's settings, permissions, login item and notifications under its bundle ID,
/// so the two copies use different ones. Only the release (release.yml) is built with the
/// production ID. Everything else — build-app.sh by default, `swift run`, tests — is a dev build:
/// "FlowMate Dev" with its own data folder and Keychain entry, so it never reads or writes the
/// released app's tasks and settings, and both can run side by side.
enum AppChannel: Equatable {
    case production
    case development

    static let productionBundleID = "com.asem-mkl.FlowMate"
    static let developmentBundleID = "com.asem-mkl.FlowMate.dev"

    /// This process's channel, from its bundle ID.
    static let current = channel(bundleID: Bundle.main.bundleIdentifier)

    /// Production only for the release's exact bundle ID; anything else is a dev build.
    static func channel(bundleID: String?) -> AppChannel {
        bundleID == productionBundleID ? .production : .development
    }

    /// The app's name in its own windows and menus.
    var displayName: String { self == .production ? "FlowMate" : "FlowMate Dev" }

    /// The folder in Application Support that holds the workspace, settings and logs.
    var dataFolderName: String { displayName }

    /// The Keychain service API keys are saved under.
    var keychainService: String { self == .production ? Self.productionBundleID : Self.developmentBundleID }
}
