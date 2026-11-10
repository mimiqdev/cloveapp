import CloveCore
import SwiftUI

/// A recent folder's cached photo, or a token-coloured frame (handoff Entry).
struct EntryPhoto: View {
    let photo: PhotoIdentity?
    let browsing: BrowsingModel
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(Color.clove.surface.card)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Color.clove.rating.off)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .task(id: photo) {
            image = nil
            guard let photo else { return }
            if case .image(let loaded) = await browsing.entryThumbnail(for: photo),
                !Task.isCancelled
            {
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}
