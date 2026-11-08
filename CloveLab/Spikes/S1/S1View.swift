import SwiftUI

/// S1 — Can folder access be remembered and restored reliably?
///
/// Placeholder screen. The spike adds its folder picker, checklist, and
/// measurements in this folder only; shared harness code lives in
/// `CloveLab/Shared/`.
struct S1View: View {
    var body: some View {
        ContentUnavailableView {
            Label("S1", systemImage: "wrench.and.screwdriver")
        } description: {
            VStack {
                Text("Can folder access be remembered and restored reliably?")
                Text("Not implemented yet")
            }
        }
        .navigationTitle("S1")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S1")
    }
}

#Preview {
    NavigationStack {
        S1View()
    }
}
