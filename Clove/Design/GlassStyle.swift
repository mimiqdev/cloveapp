import SwiftUI

/// The one glass material every floating control uses (`design/handoff/components.md`, Shared glass
/// style).
///
/// From iOS 26 the system's Liquid Glass draws the material. Older versions, and iOS 18 is the
/// minimum, fall back to the handoff's recipe: the theme's `surface/glass` token over the system's
/// background blur, with a soft drop shadow of about 16. Glass goes over the content, never on the
/// photo itself.
private struct CloveGlass<S: Shape>: ViewModifier {
    /// The outline the glass is clipped to, such as a circle or the controls' capsule.
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(Color.clove.surface.glass) }
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
    }
}

extension View {
    /// Draws the shared glass material behind the view, in ``shape`` (components.md).
    func cloveGlass(in shape: some Shape) -> some View {
        modifier(CloveGlass(shape: shape))
    }
}
