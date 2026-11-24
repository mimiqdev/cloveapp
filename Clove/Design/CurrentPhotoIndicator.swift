import SwiftUI

/// The quiet indicator marking the photo currently open in detail across Grid, Split Photo Preview,
/// and the group photo grid picker: a 1.5 pt inset outline and centered 14 × 2 pt bottom locator
/// in `accent`.
///
/// The indicator adapts to the tile's corner radius (6 pt on split-grid group members and grid
/// picker tiles, 5 pt on a collapsed group stack's front cover card, 0 pt on square split-grid
/// photos) with no fill, glow, shadow, photo tint, or layout change.
struct CurrentPhotoIndicator: View {
    /// Corner radius matching the thumbnail or cover card being outlined.
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.clove.accent, lineWidth: 1.5)
            Capsule()
                .fill(Color.clove.accent)
                .frame(width: 14, height: 2)
                .padding(.bottom, 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The opaque two-tone current-photo marker centered 2 pt beneath a raised filmstrip thumbnail
/// (issue #407): a 12 × 4 pt capsule filled with `text/primary` and outlined inside by a 1 pt
/// `bg/canvas` edge so it stays legible over dark, bright, and split backgrounds.
struct FilmstripCurrentPhotoMarker: View {
    static let size = CGSize(width: 12, height: 4)
    static let lift: CGFloat = 6
    static let gap: CGFloat = 2

    var body: some View {
        Capsule()
            .fill(Color.clove.text.primary)
            .overlay {
                Capsule()
                    .strokeBorder(Color.clove.bg.canvas, lineWidth: 1)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Raises the current filmstrip thumbnail or collapsed stack by 6 pt relative to neighbors and
/// anchors ``FilmstripCurrentPhotoMarker`` 2 pt below it inside a constant-height slot so
/// selection changes never shift neighboring tiles or resize the filmstrip band.
struct FilmstripRaisedTile<Content: View>: View {
    let width: CGFloat
    let baseHeight: CGFloat
    let isCurrent: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(
                    width: width,
                    height: baseHeight + FilmstripCurrentPhotoMarker.lift
                )
            content()
                .frame(width: width, height: baseHeight)
                .offset(y: isCurrent ? -FilmstripCurrentPhotoMarker.lift : 0)
            if isCurrent {
                FilmstripCurrentPhotoMarker()
            }
        }
        .frame(width: width, height: baseHeight + FilmstripCurrentPhotoMarker.lift)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Suppresses the system scroll-edge blur on horizontal filmstrips so raised thumbnails,
    /// top peeking stack cards, and bottom two-tone markers remain crisp.
    @ViewBuilder
    func filmstripScrollEdgeEffectHidden() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}
