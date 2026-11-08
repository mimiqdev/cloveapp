import SwiftUI

/// S5 — Is the data needed for grouping available?
///
/// Placeholder screen. The spike adds its folder picker, checklist, and
/// measurements in this folder only; shared harness code lives in
/// `CloveLab/Shared/`.
struct S5View: View {
    var body: some View {
        ContentUnavailableView {
            Label("S5", systemImage: "wrench.and.screwdriver")
        } description: {
            VStack {
                Text("Is the data needed for grouping available?")
                Text("Not implemented yet")
            }
        }
        .navigationTitle("S5")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S5")
    }
}

#Preview {
    NavigationStack {
        S5View()
    }
}
