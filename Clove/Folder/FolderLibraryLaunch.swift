import CloveCore
import Foundation

/// The library this launch browses (PRD P0-01, P0-13).
///
/// The launch environment value ``TestLibrary/launchVariable`` selects the in-memory sample, so
/// the UI test and the previews browse without a picker, a fixture or a permission. Every other
/// launch gets the real folder library over C11's Recents file and C4's Clove storage.
///
/// A launch that cannot build those app-private stores falls back to the empty test library
/// instead of stopping: the app still starts at entry, and entry simply has no folder to open or
/// to remember.
@MainActor
enum FolderLibraryLaunch {
    /// The library for this launch, chosen by the launch environment (PRD P0-01, P0-13).
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any FolderLibrary {
        if environment[TestLibrary.launchVariable] == "1" {
            return TestLibrary.forLaunch(environment: environment)
        }
        return session() ?? TestLibrary()
    }

    /// Builds the real library over C11's Recents file and C4's Clove storage.
    private static func session() -> FolderLibrarySession? {
        do {
            let store = try RecentFolderStore.applicationSupport()
            let marksDirectory = try CloveMarkStore.applicationSupportDirectory()
            return FolderLibrarySession(
                access: FolderAccess(store: store),
                writes: MarkWriteQueue(storeDirectory: marksDirectory),
                settings: SettingsPersistence(storage: UserDefaultsSettingsStorage()).load())
        } catch {
            return nil
        }
    }
}
