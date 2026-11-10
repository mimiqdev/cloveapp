import CloveCore
import SwiftUI

/// The strip of the photos detail navigates, with the current one marked (PRD P0-04).
///
/// The frames are U3's grid thumbnails for the grid's current order and filter, so the filmstrip
/// shows exactly the photos an edge tap moves through. Tapping a frame opens that photo. The
/// strip scrolls to the current photo when it changes, so a tap on an edge keeps it in view.
///
/// Design placeholder: plain frames with a system selection border stand in for the design.
struct DetailFilmstrip: View {
    /// The photos in the grid's order and filter (PRD P0-03, P0-04).
    let photos: [GridPhoto]

    /// The photo detail shows now (PRD P0-04).
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
                            DetailFilmstripFrame(
                                photo: photo, isCurrent: photo.id == current,
                                thumbnails: thumbnails)
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
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

/// One filmstrip frame: the photo's grid thumbnail, selected when it is the photo on screen.
private struct DetailFilmstripFrame: View {
    let photo: GridPhoto
    let isCurrent: Bool
    let thumbnails: any GridThumbnailSource

    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        // PRD P0-04: a frame that fails to draw is a state, not a blank picture presented as
        // loaded. The placeholder keeps the empty frame rather than claiming an image.
        .task(id: photo.id) {
            guard thumbnail == nil else { return }
            if case .image(let pixels) = await thumbnails.thumbnail(
                for: photo.id, priority: .visible)
            {
                thumbnail = pixels
            }
        }
        .accessibilityLabel(photo.fileName)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityIdentifier("clove.detail.filmstrip.\(photo.id.stem.lowercased())")
    }
}
