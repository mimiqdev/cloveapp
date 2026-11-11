import SwiftUI

/// The handoff's compact navigation title and subtitle, between Back and the view tools.
struct BrowsingHeader<Subtitle: View, Tools: View>: View {
    let title: String
    var titleIdentifier = "clove.browsing.title"
    let back: () -> Void
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let tools: () -> Tools

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier(titleIdentifier)
                    subtitle()
                        .font(.caption)
                        .foregroundStyle(Color.clove.text.secondary)
                }
                .frame(width: max(proxy.size.width - 192, 80))
                HStack(spacing: 8) {
                    GlassIconButton(
                        label: "Back", symbol: "chevron.left", identifier: "clove.nav.back",
                        action: back)
                    Spacer(minLength: 0)
                    tools()
                }
                .padding(.horizontal, 16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 64)
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.bg.canvas)
    }
}
