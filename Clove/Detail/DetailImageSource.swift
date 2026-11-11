import CloveCore
import CloveImaging
import CoreGraphics
import Foundation

enum DetailImageOutcome: Sendable {
    case image(DetailImage)
    case unavailable(DetailFailure)
    case deferred
}

/// The selected colour source and pixel demand for one photo.
struct DetailPixelRequest: Hashable, Sendable {
    enum Need: Hashable, Sendable {
        case preview
        case screenRender
        case morePixels
        case fullResolution
    }

    let displayPixels: Int
    let need: Need
    let mode: PhotoDisplayMode
    let screenPixels: Int

    init(
        displayPixels: Int, need: Need, mode: PhotoDisplayMode = .rawFirst,
        screenPixels: Int? = nil
    ) {
        self.displayPixels = min(max(displayPixels, 1), DetailPixelLimit.maximumEdge)
        self.need = need
        self.mode = mode
        self.screenPixels = min(max(screenPixels ?? displayPixels, 1), DetailPixelLimit.maximumEdge)
    }
}

struct DetailNeighbour: Hashable, Sendable {
    let photo: PhotoIdentity
    let position: Int
}

/// The current photo, two neighbours, and direction of travel in this screen's order.
struct DetailPhotoWindow: Hashable, Sendable {
    let id: UUID
    let current: DetailNeighbour
    let neighbours: [DetailNeighbour]
    let direction: Int
    let mode: PhotoDisplayMode
    let screenPixels: Int

    func request(need: DetailPixelRequest.Need = .preview) -> DetailPixelRequest {
        DetailPixelRequest(
            displayPixels: screenPixels, need: need, mode: mode,
            screenPixels: screenPixels)
    }
}

/// The shared detail/group view asks only for photo identities and display needs.
/// Folder reads remain admitted through the folder session; the test library
/// generates its own pixels. Leaving cancels work and releases the full image.
@MainActor
protocol DetailImageSource: AnyObject {
    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    func prepare(_ window: DetailPhotoWindow) async
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome
    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async
    func leave(window: UUID) async
}

extension DetailImageSource {
    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        if case .image(let pixels) = await gridThumbnails.thumbnail(for: photo, priority: .visible)
        {
            return pixels
        }
        return nil
    }
    func prepare(_ window: DetailPhotoWindow) async {}
    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {}
    func leave(window: UUID) async {}
}

@MainActor
final class EmptyDetailImages: DetailImageSource {
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        .unavailable(.noUsablePreview)
    }
}
