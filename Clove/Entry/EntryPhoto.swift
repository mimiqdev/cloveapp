import CloveCore
import SwiftUI

/// A recent folder's cached photo, or a token-coloured frame (handoff Entry).
struct EntryPhoto: View {
    let photo: PhotoIdentity?
    let browsing: BrowsingModel
    @State private var image: CGImage?

    private struct Request: Hashable {
        let photo: PhotoIdentity?
        let generation: Int
    }

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
        .onChange(of: photo) { image = nil }
        .task(id: Request(photo: photo, generation: browsing.entryPreviewGeneration)) {
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
