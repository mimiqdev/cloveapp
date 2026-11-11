import CloveCore
import SwiftUI

/// One photo's frame in a filmstrip or a group's sidebar: its thumbnail, its marks and the border
/// that says which photo is on screen (PRD P0-04; PRD In-group culling, layout).
///
/// PRD In-group culling requires every photo of a group to show its rating or Reject and rejected
/// photos to be dimmed, so the frame carries both and the group's filmstrip and sidebar grid draw
/// it. The detail filmstrip draws the same frame, because marks on the strip are useful there
/// too and one frame keeps the two screens from drifting apart.
///
/// A frame that fails to draw is a state, not a blank picture presented as loaded (PRD Scan
/// scope): the placeholder keeps the empty frame rather than claiming an image.
///
/// Rejected thumbnails dim without a reject badge; the current frame keeps its thin ring.
struct DetailPhotoFrame: View {
    /// The photo the frame draws (PRD P0-05).
    let photo: GridPhoto

    /// Whether this is the photo on screen (PRD P0-04).
    let isCurrent: Bool

    /// The grid thumbnails the frame draws (PRD P0-03).
    let thumbnails: any GridThumbnailSource

    /// The frame's side in points; the filmstrip uses one size and a sidebar grid another.
    var side: CGFloat = 56
    var height: CGFloat?
    @Environment(\.cloveTheme) private var theme

    @State private var thumbnail: CGImage?

    var body: some View {
        pixels
            .frame(width: side, height: height ?? side)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { border }
            .overlay(alignment: .bottomLeading) { marks }
            // PRD In-group culling: rejected photos are dimmed, so a cull decision reads at a
            // glance in the strip (PRD In-group culling, comparison and elimination).
            .opacity(photo.marks.isRejected ? theme.tokens.rejectedOpacity : 1)
            .task(id: photo.id) {
                guard thumbnail == nil else { return }
                if case .image(let pixels) = await thumbnails.thumbnail(
                    for: photo.id, priority: .visible)
                {
                    thumbnail = pixels
                }
            }
            .accessibilityLabel(photo.fileName)
            .accessibilityValue(MarkSummary.text(for: photo.marks))
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// The photo's grid thumbnail, or the empty frame while it loads or fails.
    @ViewBuilder private var pixels: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(Color.clove.surface.card)
        }
    }

    /// The rating and Reject the photo carries, over its thumbnail (PRD In-group culling, layout).
    @ViewBuilder private var marks: some View {
        HStack(spacing: 3) {
            if photo.marks.rating != .unrated {
                Label("\(photo.marks.rating.rawValue)", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(Color.clove.rating.on)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.clove.surface.glass, in: Capsule())
            }
        }
        .padding(3)
    }

    /// The border that says which photo is on screen (PRD P0-04).
    private var border: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.clove.text.primary, lineWidth: isCurrent ? 2 : 0)
    }
}
