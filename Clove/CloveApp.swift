import SwiftUI

@main
struct CloveApp: App {
    /// The app-wide settings, created once so every scene shares one value (PRD Gesture-related
    /// settings).
    @State private var settings = SettingsStore.launch()

    var body: some Scene {
        WindowGroup {
            // The store lives outside the scene because settings are app-wide while browsing
            // state is per scene; RootView hands it to the environment every screen reads.
            RootView(settings: settings)
        }
    }
}
