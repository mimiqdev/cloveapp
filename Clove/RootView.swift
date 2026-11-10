import CloveCore
import SwiftUI

/// The scene's root: it owns this scene's browsing model and stores that model's state
/// (PRD P0-14).
///
/// The state itself lives in ``BrowsingModel``, never in a view's `@State`, so changing the layout
/// never resets it (G1 fold-state row). It is stored per scene through `@SceneStorage`, and
/// `project.yml` already generates `UIApplicationSupportsMultipleScenes = YES`, so two iPad
/// windows keep their own state. A launch reads the stored form back through CloveCore's
/// validation, which falls back to entry when it cannot use it (PRD P0-14), and a stored folder is
/// reopened through C11 before that validation, so a location that is gone lands on entry with the
/// reason on its Recents item (PRD P0-02).
struct RootView: View {
    /// This scene's stored browsing state; the key is per scene, so scenes never share it.
    @SceneStorage("clove.browsing.state") private var storedState: Data?

    /// The app-wide settings this scene reads and the environment carries (PRD Gesture-related
    /// settings). The store belongs to the app, not to the scene.
    private let settings: SettingsStore

    @State private var browsing: BrowsingModel

    /// Creates the scene over the app's settings and the library this launch browses
    /// (PRD P0-01, P0-13).
    ///
    /// The library is created once per scene, so two windows never share one folder's scan or
    /// write queue. It reads the rejects folder name from the settings store when a folder opens,
    /// so a renamed folder applies to the next open. A preview passes its own library.
    init(settings: SettingsStore, library: (any FolderLibrary)? = nil) {
        self.settings = settings
        _browsing = State(
            initialValue: BrowsingModel(
                library: library ?? FolderLibraryLaunch.make(settings: settings)))
    }

    var body: some View {
        BrowseShell(browsing: browsing)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clove.root")
            .task { await browsing.restore(from: storedState) }
            .onChange(of: browsing.state) { _, state in
                storedState = state.encoded()
            }
            .onChange(of: settings.settings.similarGroupsEnabled) { _, enabled in
                // The store owns the choice; the open folder applies it now, and the library
                // reads the store again when the next folder opens (PRD P0-11, PRD Similar
                // groups). It lives here rather than on the grid because a compact layout shows
                // Settings instead of the grid while the toggle changes.
                Task { await browsing.setSimilarGroupsEnabled(enabled) }
            }
            .environment(settings)
    }
}

#Preview {
    RootView(settings: .sample, library: TestLibrary.sample)
}
