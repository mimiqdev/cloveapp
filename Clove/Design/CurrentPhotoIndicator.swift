import SwiftUI

/// The quiet indicator marking the photo currently open in detail across the filmstrip and split
/// Photo Preview grid: a 1.5 pt inset outline and centered 14 × 2 pt bottom locator in `accent`.
///
/// The indicator adapts to the tile's corner radius (6 pt on filmstrip thumbnails and split-grid
/// group members, 5 pt on a collapsed group stack's front cover card, 0 pt on square split-grid
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
