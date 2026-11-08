import SwiftUI

/// Placeholder root view until the main flow lands.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Clove")
                .font(.largeTitle)
            Text("Repository skeleton")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.root")
    }
}

#Preview {
    RootView()
}
