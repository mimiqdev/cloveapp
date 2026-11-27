import CloveCore
import SwiftUI

/// One photo's frame in a filmstrip: its thumbnail, its marks, and its accessibility selection
/// trait (PRD P0-04; PRD In-group culling, layout).
///
/// Rejected thumbnails dim without a reject badge; filmstrips compose tile elevation and
/// ``FilmstripCurrentPhotoMarker`` outside this frame so the marker stays at full opacity.
struct DetailPhotoFrame: View {
    /// The photo the frame draws (PRD P0-05).
    let photo: GridPhoto

    /// Whether this is the photo on screen (PRD P0-04).
    let isCurrent: Bool

    /// The grid thumbnails the frame draws (PRD P0-03).
    let thumbnails: any GridThumbnailSource

    /// The frame's side in points; the filmstrip uses one size and Compare another.
    var side: CGFloat = 56
    var height: CGFloat?
    var showsMarks = true
    var appliesRejectedDimming = true
    @Environment(\.appLanguage) private var language

    @State private var thumbnail: CGImage?

    var body: some View {
        pixels
            .frame(width: side, height: height ?? side)
            .clipped()
            // PRD In-group culling: rejected photos dim neutrally with desaturation so a cull
            // decision reads at a glance without white haze on Light themes.
            .rejectedThumbnailDimming(appliesRejectedDimming && photo.marks.isRejected)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottomLeading) {
                if showsMarks { marks }
            }
            .task(id: photo.id) {
                guard thumbnail == nil else { return }
                if case .image(let pixels) = await thumbnails.thumbnail(
                    for: photo.id, priority: .visible)
                {
                    thumbnail = pixels
                }
            }
            .accessibilityLabel(photo.fileName)
            .accessibilityValue(MarkSummary.text(for: photo.marks, language: language))
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
            if let stars = photo.marks.rating.starCount {
                Label("\(stars)", systemImage: "star.fill")
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
}
