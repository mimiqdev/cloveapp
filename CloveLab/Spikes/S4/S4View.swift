import SwiftUI

/// S4 — Can metadata be changed without re-encoding?
///
/// Placeholder screen. The spike adds its folder picker, checklist, and
/// measurements in this folder only; shared harness code lives in
/// `CloveLab/Shared/`.
struct S4View: View {
    var body: some View {
        ContentUnavailableView {
            Label("S4", systemImage: "wrench.and.screwdriver")
        } description: {
            VStack {
                Text("Can metadata be changed without re-encoding?")
                Text("Not implemented yet")
            }
        }
        .navigationTitle("S4")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S4")
    }
}

#Preview {
    NavigationStack {
        S4View()
    }
}
