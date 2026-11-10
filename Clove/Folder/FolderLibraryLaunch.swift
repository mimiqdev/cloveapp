import CloveCore
import Foundation

/// The library this launch browses (PRD P0-01, P0-13).
///
/// The launch environment value ``TestLibrary/launchVariable`` selects the in-memory sample, so
/// the UI test and the previews browse without a picker, a fixture or a permission. Every other
/// launch gets the real folder library over C11's Recents file and C4's Clove storage.
///
/// Preparing those app-private stores resolves Application Support paths and creates directories,
/// so it runs in a detached task instead of during the scene's first body evaluation; the library
/// awaits it on its first asynchronous call (PRD P0-02, P0-08). A failure there is reported as
/// storage entry explains, never as an empty library that pretends nothing is wrong.
@MainActor
enum FolderLibraryLaunch {
    /// The library for this launch, chosen by the launch environment (PRD P0-01, P0-13).
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any FolderLibrary {
        if environment[TestLibrary.launchVariable] == "1" {
            return TestLibrary.forLaunch(environment: environment)
        }
        return FolderLibrarySession(
            stores: Task.detached(priority: .userInitiated) {
                try FolderLibrarySession.Stores.applicationSupport()
            },
            settings: SettingsPersistence(storage: UserDefaultsSettingsStorage()).load())
    }
}
