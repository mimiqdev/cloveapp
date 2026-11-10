import CloveCore
import SwiftUI

/// The strip of the photos detail navigates, with the current one marked (PRD P0-04).
///
/// The frames are U3's grid thumbnails for the grid's current order and filter, so the filmstrip
/// shows exactly the photos an edge tap moves through. Each frame shows its rating or Reject, and
/// a rejected frame is dimmed (PRD In-group culling, layout). Tapping a frame opens that photo.
/// The strip scrolls to the current photo when it changes, so a tap on an edge keeps it in view.
///
/// The group view draws the same strip over the group's members, so both screens identify and
/// dim a photo the same way (PRD In-group culling).
///
/// Design placeholder: plain frames with a system selection border stand in for the design.
struct DetailFilmstrip: View {
    /// The photos in the screen's order: the grid's order and filter in detail, the group's
    /// member order in the group view (PRD P0-03, P0-04; PRD In-group culling).
    let photos: [GridPhoto]

    /// The photo the screen shows now (PRD P0-04).
    let current: PhotoIdentity?

    /// The grid thumbnails the frames draw (PRD P0-03).
    let thumbnails: any GridThumbnailSource

    /// Opens a tapped photo (PRD P0-04).
    let open: (PhotoIdentity) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(photos) { photo in
                        Button {
                            open(photo.id)
                        } label: {
                            DetailPhotoFrame(
                                photo: photo, isCurrent: photo.id == current,
                                thumbnails: thumbnails)
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
                        .accessibilityIdentifier(
                            "clove.detail.filmstrip.\(photo.id.stem.lowercased())")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .onChange(of: current, initial: true) { _, photo in
                guard let photo else { return }
                withAnimation { proxy.scrollTo(photo, anchor: .center) }
            }
        }
        .frame(height: 64)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.filmstrip")
    }
}
