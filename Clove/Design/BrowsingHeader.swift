import SwiftUI

/// The handoff's compact navigation title and subtitle, between Back and the view tools.
struct BrowsingHeader<
    TitleAccessory: View, Subtitle: View, LeadingTools: View, Tools: View
>: View {
    let title: String
    var titleIdentifier = "clove.browsing.title"
    var backTitle: String? = nil
    var showsBack = true
    var usesInlineFlow = false
    var height: CGFloat = 64
    var background: CloveColour = Color.clove.bg.canvas
    let back: () -> Void
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let titleAccessory: () -> TitleAccessory
    @ViewBuilder let leadingTools: () -> LeadingTools
    @ViewBuilder let tools: () -> Tools

    @Environment(\.appLanguage) private var language

    init(
        title: String,
        titleIdentifier: String = "clove.browsing.title",
        backTitle: String? = nil,
        showsBack: Bool = true,
        usesInlineFlow: Bool = false,
        height: CGFloat = 64,
        background: CloveColour = Color.clove.bg.canvas,
        back: @escaping () -> Void,
        @ViewBuilder subtitle: @escaping () -> Subtitle,
        @ViewBuilder titleAccessory: @escaping () -> TitleAccessory = { EmptyView() },
        @ViewBuilder leadingTools: @escaping () -> LeadingTools = { EmptyView() },
        @ViewBuilder tools: @escaping () -> Tools
    ) {
        self.title = title
        self.titleIdentifier = titleIdentifier
        self.backTitle = backTitle
        self.showsBack = showsBack
        self.usesInlineFlow = usesInlineFlow
        self.height = height
        self.background = background
        self.back = back
        self.subtitle = subtitle
        self.titleAccessory = titleAccessory
        self.leadingTools = leadingTools
        self.tools = tools
    }

    var body: some View {
        let backLabel = AppLocalization.string("Back", language: language)
        Group {
            if usesInlineFlow {
                HStack(spacing: showsBack ? 8 : 6) {
                    if showsBack {
                        backButton(label: backLabel)
                            .layoutPriority(1)
                    }
                    leadingTools()
                        .layoutPriority(1)
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: showsBack ? .center : .leading)
                        .layoutPriority(0)
                    tools()
                        .layoutPriority(1)
                }
                .padding(.horizontal, 16)
            } else {
                GeometryReader { proxy in
                    ZStack {
                        titleBlock
                            .frame(
                                maxWidth: max(
                                    proxy.size.width - (backTitle != nil ? 520 : 240), 100))
                        HStack(spacing: 8) {
                            if showsBack {
                                backButton(label: backLabel)
                            }
                            leadingTools()
                            Spacer(minLength: 0)
                            tools()
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .frame(height: height)
        .foregroundStyle(Color.clove.text.primary)
        .background(background)
        .reportHeaderControlFrame("clove.browsing.header")
    }

    private var titleBlock: some View {
        VStack(alignment: (usesInlineFlow && !showsBack) ? .leading : .center, spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier(titleIdentifier)
                    .reportHeaderControlFrame(titleIdentifier)
                titleAccessory()
                    .layoutPriority(1)
            }
            subtitle()
                .font(.caption)
                .foregroundStyle(Color.clove.text.secondary)
        }
    }

    @ViewBuilder
    private func backButton(label backLabel: String) -> some View {
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
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier("clove.nav.back")
            .reportHeaderControlFrame("clove.nav.back")
        } else {
            GlassIconButton(
                label: backLabel, symbol: "chevron.left",
                identifier: "clove.nav.back", action: back
            )
            .reportHeaderControlFrame("clove.nav.back")
        }
    }
}
