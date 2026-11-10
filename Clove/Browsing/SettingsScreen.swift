import SwiftUI

/// Clove's settings (PRD Gesture-related settings).
///
/// Design placeholder: every setting arrives with the settings screen; this screen only makes the
/// route reachable from every other screen.
struct SettingsScreen: View {
    var body: some View {
        List {
            Section {
                Text("Settings are not built yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clove.settings.placeholder")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings")
    }
}
