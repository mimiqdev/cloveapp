import CloveCore
import SwiftUI

/// The scene's root: it owns this scene's browsing model and stores that model's state
/// (PRD P0-14).
///
/// The state itself lives in ``BrowsingModel``, never in a view's `@State`, so changing the layout
/// never resets it (G1 fold-state row). It is stored per scene through `@SceneStorage`, and
/// `project.yml` already generates `UIApplicationSupportsMultipleScenes = YES`, so two iPad
/// windows keep their own state. A launch reads the stored form back through CloveCore's
/// validation, which falls back to entry when it cannot use it (PRD P0-14).
struct RootView: View {
    /// This scene's stored browsing state; the key is per scene, so scenes never share it.
    @SceneStorage("clove.browsing.state") private var storedState: Data?

    @State private var browsing: BrowsingModel

    init(library: any FolderLibrary = TestLibrary.forLaunch()) {
        _browsing = State(initialValue: BrowsingModel(library: library))
    }

    var body: some View {
        BrowseShell(browsing: browsing)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clove.root")
            .onAppear { browsing.restore(from: storedState) }
            .onChange(of: browsing.state) { _, state in
                storedState = state.encoded()
            }
    }
}

#Preview {
    RootView(library: TestLibrary.sample)
}
