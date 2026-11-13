import SwiftUI

/// The neutral surface behind an expanded group's extent: the theme's `text/primary` at 12% on
/// the background shape alone (owner decision, 2026-11-13, #226 filmstrip, #227 grid).
///
/// The opacity never touches the container or the photo thumbnails; photos are never tinted.
/// The filmstrip draws it behind the current group's members, and the grid's expanded group
/// presentation draws it behind its members' tiles. It is deliberately distinct from the
/// current-photo selection ring, which stays the solid `text/primary` stroke.
struct ExpandedGroupSurface: View {
    /// The corner radius the surrounding layout draws: 9 in the filmstrip, 6 per grid tile.
    var cornerRadius: CGFloat = 9

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clove.text.primary)
            .opacity(0.12)
    }
}
