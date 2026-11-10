import CloveCore
import SwiftUI

/// The group's photos beside the preview on regular width (PRD In-group culling, layout).
///
/// PRD In-group culling gives the iPad and the Duo inner screen a large preview with a sidebar
/// grid of the group, so a wide screen compares photos without the preview losing height. Each
/// frame shows its rating or Reject and dims a rejected photo, the same as the compact filmstrip,
/// and tapping one shows that photo (PRD In-group culling, layout and comparison).
///
/// Design placeholder: a system grid of thumbnails stands in for the visual design's sidebar.
struct GroupSidebar: View {
    /// The group's photos, in member order (PRD Similar groups step 1).
    let photos: [GridPhoto]

    /// The photo the preview shows (PRD P0-12).
    let current: PhotoIdentity?

    /// The grid thumbnails the frames draw (PRD P0-03).
    let thumbnails: any GridThumbnailSource

    /// Shows a tapped photo in the preview (PRD In-group culling).
    let open: (PhotoIdentity) -> Void

    /// The sidebar's frame size in points: large enough to judge a face without the preview.
    private static let frameSide: CGFloat = 92

    private let columns = [
        GridItem(.adaptive(minimum: GroupSidebar.frameSide), spacing: 4)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    Button {
                        open(photo.id)
                    } label: {
                        DetailPhotoFrame(
                            photo: photo, isCurrent: photo.id == current,
                            thumbnails: thumbnails, side: GroupSidebar.frameSide)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clove.group.frame.\(photo.id.stem.lowercased())")
                }
            }
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.group.sidebar")
    }
}
