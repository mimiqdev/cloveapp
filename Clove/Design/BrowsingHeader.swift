import SwiftUI

/// The handoff's compact navigation title and subtitle, between Back and the view tools.
struct BrowsingHeader<Subtitle: View, Tools: View>: View {
    let title: String
    var titleIdentifier = "clove.browsing.title"
    var backTitle: String? = nil
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
                    if let backTitle {
                        Button(action: back) {
                            Label(backTitle, systemImage: "chevron.left")
                                .lineLimit(1)
                                .frame(maxWidth: 160, alignment: .leading)
                                .frame(height: 40)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("clove.nav.back")
                    } else {
                        GlassIconButton(
                            label: "Back", symbol: "chevron.left", identifier: "clove.nav.back",
                            action: back)
                    }
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
