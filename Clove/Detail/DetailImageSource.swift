import CloveCore
import CloveImaging
import Foundation

enum DetailImageOutcome: Sendable {
    case image(DetailImage)
    case unavailable(DetailFailure)
    case deferred
}

/// The display mode is frozen at arrival, even if the fifth timing changes the
/// device default while this photo is still on screen.
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
    let position: Int

    init(
        displayPixels: Int, need: Need, mode: PhotoDisplayMode = .rawFirst,
        screenPixels: Int? = nil, position: Int = 0
    ) {
        self.displayPixels = min(max(displayPixels, 1), DetailPixelLimit.maximumEdge)
        self.need = need
        self.mode = mode
        self.screenPixels = min(max(screenPixels ?? displayPixels, 1), DetailPixelLimit.maximumEdge)
        self.position = position
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

    func request(for photo: DetailNeighbour, need: DetailPixelRequest.Need = .preview)
        -> DetailPixelRequest
    {
        DetailPixelRequest(
            displayPixels: screenPixels, need: need, mode: mode,
            screenPixels: screenPixels, position: photo.position)
    }
}

/// The shared detail/group view asks only for photo identities and display needs.
/// Folder reads remain admitted through the folder session; the test library
/// generates its own pixels. Leaving cancels work and releases the full image.
@MainActor
protocol DetailImageSource: AnyObject {
    func prepare(_ window: DetailPhotoWindow) async
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome
    func prefetch(_ window: DetailPhotoWindow) async
    func leave(window: UUID) async
    func takeScreenRenderDurations() async -> [Double]
}

extension DetailImageSource {
    func prepare(_ window: DetailPhotoWindow) async {}
    func prefetch(_ window: DetailPhotoWindow) async {}
    func leave(window: UUID) async {}
    func takeScreenRenderDurations() async -> [Double] { [] }
}

@MainActor
final class EmptyDetailImages: DetailImageSource {
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        .unavailable(.noUsablePreview)
    }
}
