import SwiftUI

/// Placeholder root view for the debug app used by device verification.
struct LabRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Clove Lab")
                .font(.largeTitle)
            Text("Repository skeleton")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clovelab.root")
    }
}

#Preview {
    LabRootView()
}
