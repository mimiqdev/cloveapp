import SwiftUI

/// S3 — How should XMP be read and written?
///
/// Placeholder screen. The spike adds its folder picker, checklist, and
/// measurements in this folder only; shared harness code lives in
/// `CloveLab/Shared/`.
struct S3View: View {
    var body: some View {
        ContentUnavailableView {
            Label("S3", systemImage: "wrench.and.screwdriver")
        } description: {
            VStack {
                Text("How should XMP be read and written?")
                Text("Not implemented yet")
            }
        }
        .navigationTitle("S3")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S3")
    }
}

#Preview {
    NavigationStack {
        S3View()
    }
}
