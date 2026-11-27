import SwiftUI

/// Neutral darkroom dimming and desaturation for rejected photo thumbnails.
///
/// Compositing over pure black with reduced saturation avoids the pale "white haze" caused by
/// translucent thumbnails blending against light `surface/card`, `bg/canvas`, or `bg/stage`
/// backgrounds, and keeps photos untinted by theme palette colours across all 12 themes.
struct RejectedThumbnailDimming: ViewModifier {
    /// Retained brightness of a dimmed rejected thumbnail over neutral black (`0.42–0.45`).
    static let brightness: Double = 0.44

    /// Neutral black scrim opacity matching `1 - brightness` (`0.56`).
    static let scrimOpacity: Double = 1 - brightness

    /// Retained saturation of a dimmed rejected thumbnail.
    static let saturation: Double = 0.15

    let isDimmed: Bool

    func body(content: Content) -> some View {
        content
            .saturation(isDimmed ? Self.saturation : 1)
            .background {
                Color.black.opacity(isDimmed ? 1 : 0)
            }
            .overlay {
                Color.black
                    .opacity(isDimmed ? Self.scrimOpacity : 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Applies neutral darkroom dimming and desaturation when `isDimmed` is `true`.
    func rejectedThumbnailDimming(_ isDimmed: Bool = true) -> some View {
        modifier(RejectedThumbnailDimming(isDimmed: isDimmed))
    }
}
