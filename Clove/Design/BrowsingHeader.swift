import SwiftUI

/// The handoff's compact navigation title and subtitle, between Back and the view tools.
struct BrowsingHeader<Subtitle: View, LeadingTools: View, Tools: View>: View {
    let title: String
    var titleIdentifier = "clove.browsing.title"
    var backTitle: String? = nil
    let back: () -> Void
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let leadingTools: () -> LeadingTools
    @ViewBuilder let tools: () -> Tools

    init(
        title: String,
        titleIdentifier: String = "clove.browsing.title",
        backTitle: String? = nil,
        back: @escaping () -> Void,
        @ViewBuilder subtitle: @escaping () -> Subtitle,
        @ViewBuilder leadingTools: @escaping () -> LeadingTools = { EmptyView() },
        @ViewBuilder tools: @escaping () -> Tools
    ) {
        self.title = title
        self.titleIdentifier = titleIdentifier
        self.backTitle = backTitle
        self.back = back
        self.subtitle = subtitle
        self.leadingTools = leadingTools
        self.tools = tools
    }

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
                                .labelStyle(.titleAndIcon)
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
                    leadingTools()
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
