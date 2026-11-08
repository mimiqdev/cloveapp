import SwiftUI

/// S2 — Are previews fast enough?
///
/// Placeholder screen. The spike adds its folder picker, checklist, and
/// measurements in this folder only; shared harness code lives in
/// `CloveLab/Shared/`.
struct S2View: View {
    var body: some View {
        ContentUnavailableView {
            Label("S2", systemImage: "wrench.and.screwdriver")
        } description: {
            VStack {
                Text("Are previews fast enough?")
                Text("Not implemented yet")
            }
        }
        .navigationTitle("S2")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S2")
    }
}

#Preview {
    NavigationStack {
        S2View()
    }
}
