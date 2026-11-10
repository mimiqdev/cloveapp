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
/// Design placeholder: system stars, the Reject symbol and a system selection border stand in for
/// the visual design's overlays.
struct DetailPhotoFrame: View {
    /// The photo the frame draws (PRD P0-05).
    let photo: GridPhoto

    /// Whether this is the photo on screen (PRD P0-04).
    let isCurrent: Bool

    /// The grid thumbnails the frame draws (PRD P0-03).
    let thumbnails: any GridThumbnailSource

    /// The frame's side in points; the filmstrip uses one size and a sidebar grid another.
    var side: CGFloat = 56

    @State private var thumbnail: CGImage?

    var body: some View {
        pixels
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { border }
            .overlay(alignment: .bottomLeading) { marks }
            // PRD In-group culling: rejected photos are dimmed, so a cull decision reads at a
            // glance in the strip (PRD In-group culling, comparison and elimination).
            .opacity(photo.marks.isRejected ? 0.45 : 1)
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
            Color.secondary.opacity(0.2)
        }
    }

    /// The rating and Reject the photo carries, over its thumbnail (PRD In-group culling, layout).
    @ViewBuilder private var marks: some View {
        HStack(spacing: 3) {
            if photo.marks.rating != .unrated {
                Label("\(photo.marks.rating.rawValue)", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            if photo.marks.isRejected {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
        .padding(3)
    }

    /// The border that says which photo is on screen (PRD P0-04).
    private var border: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2.5)
    }
}
