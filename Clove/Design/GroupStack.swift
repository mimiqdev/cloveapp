import SwiftUI

/// Two quiet cards peek above the cover, without an outline (handoff components.md).
struct GroupStack<Content: View>: View {
    var peek: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.clove.text.secondary).opacity(0.35)
                    .padding(.horizontal, peek + 2).padding(.bottom, peek - 2)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.clove.surface.card)
                    .padding(.horizontal, peek / 2 + 1)
                    .padding(.top, peek / 2).padding(.bottom, peek / 2)
                content()
                    .frame(width: proxy.size.width, height: max(0, proxy.size.height - peek))
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}
