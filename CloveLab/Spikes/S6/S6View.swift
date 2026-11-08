import SwiftUI

/// S6 — How long does scanning take?
///
/// Placeholder screen. The spike adds its folder picker, checklist, and
/// measurements in this folder only; shared harness code lives in
/// `CloveLab/Shared/`.
struct S6View: View {
    var body: some View {
        ContentUnavailableView {
            Label("S6", systemImage: "wrench.and.screwdriver")
        } description: {
            VStack {
                Text("How long does scanning take?")
                Text("Not implemented yet")
            }
        }
        .navigationTitle("S6")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S6")
    }
}

#Preview {
    NavigationStack {
        S6View()
    }
}
