import SwiftUI

/// One or two quiet member cards peek above the cover, without an outline
/// (handoff components.md).
struct GroupStack<Content: View>: View {
    var peek: CGFloat = 8
    var peekingImages: [CGImage?]? = nil
    var cardBacking: CloveColour = Color.clove.bg.canvas
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .bottom) {
                peekingLayers(width: width, height: height)
                content()
                    .frame(width: width, height: max(0, height - peek))
                    .clipped()
                    .background(cardBacking)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    @ViewBuilder
    private func peekingLayers(width: CGFloat, height: CGFloat) -> some View {
        if let peekingImages, !peekingImages.isEmpty {
            let cards = Array(peekingImages.prefix(2))
            if cards.count == 2 {
                peekingCard(
                    image: cards[1],
                    width: max(0, width - 2 * (peek + 2)),
                    height: max(0, height - (peek - 2)),
                    opacity: 0.45,
                    placeholder: Color.clove.text.secondary,
                    placeholderOpacity: 0.35
                )
                .padding(.bottom, peek - 2)
                peekingCard(
                    image: cards[0],
                    width: max(0, width - 2 * (peek / 2 + 1)),
                    height: max(0, height - peek),
                    opacity: 0.72,
                    placeholder: Color.clove.surface.card,
                    placeholderOpacity: 1
                )
                .padding(.bottom, peek / 2)
            } else if cards.count == 1 {
                peekingCard(
                    image: cards[0],
                    width: max(0, width - 2 * (peek / 2 + 1)),
                    height: max(0, height - peek / 2),
                    opacity: 0.72,
                    placeholder: Color.clove.text.secondary,
                    placeholderOpacity: 0.35
                )
                .padding(.bottom, peek / 2)
            }
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.clove.text.secondary).opacity(0.35)
                .padding(.horizontal, peek + 2).padding(.bottom, peek - 2)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.clove.surface.card)
                .padding(.horizontal, peek / 2 + 1)
                .padding(.top, peek / 2).padding(.bottom, peek / 2)
        }
    }

    private func peekingCard(
        image: CGImage?,
        width: CGFloat,
        height: CGFloat,
        opacity: Double,
        placeholder: CloveColour,
        placeholderOpacity: Double
    ) -> some View {
        Group {
            if let image {
                Rectangle()
                    .fill(cardBacking)
                    .overlay {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .opacity(opacity)
                    }
            } else {
                Rectangle()
                    .fill(placeholder)
                    .opacity(placeholderOpacity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
