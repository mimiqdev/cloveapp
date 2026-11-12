import CloveImaging
import CoreGraphics
import Observation

/// One consumer serializes fit and native requests. A zoom made during the fit read is
/// fulfilled immediately after it, so a late fit image can never replace native pixels.
@MainActor
@Observable
final class RenameCheckImages {
    private(set) var shown: DetailImage?
    private(set) var placeholder: CGImage?
    private(set) var unavailable = false
    private let source: any DetailImageSource
    private var window: DetailPhotoWindow?
    private var isLoadingFit = false
    private var isZoomed = false
    private var nativeTask: Task<Void, Never>?

    init(source: any DetailImageSource) { self.source = source }

    func load(_ window: DetailPhotoWindow, thumbnails: any GridThumbnailSource) async {
        nativeTask?.cancel()
        self.window = window
        shown = nil
        placeholder = nil
        unavailable = false
        isLoadingFit = true
        isZoomed = false
        placeholder = await source.placeholder(
            for: window.current.photo, gridThumbnails: thumbnails)
        guard !Task.isCancelled else { return }
        await source.prepare(window)
        guard !Task.isCancelled else { return }
        let preview = await source.image(for: window.current.photo, request: window.request())
        guard !Task.isCancelled else { return }
        if case .image(let image) = preview {
            shown = image
        } else {
            unavailable = placeholder == nil
        }
        if !isZoomed {
            let screen = await source.image(
                for: window.current.photo, request: window.request(need: .screenRender))
            guard !Task.isCancelled else { return }
            if case .image(let image) = screen, shown?.isBestAvailable != true {
                shown = image
                unavailable = false
            }
        }
        isLoadingFit = false
        if isZoomed { await loadNative(window) }
        guard !Task.isCancelled else { return }
        await source.prefetch(window, renderAhead: true)
    }

    func setZoomed(_ zoomed: Bool) {
        isZoomed = zoomed
        guard zoomed, !isLoadingFit, let window else { return }
        nativeTask?.cancel()
        nativeTask = Task { await loadNative(window) }
    }

    private func loadNative(_ window: DetailPhotoWindow) async {
        guard shown?.isBestAvailable != true else { return }
        let native = await source.image(
            for: window.current.photo, request: window.request(need: .fullResolution))
        guard !Task.isCancelled, self.window?.current.photo == window.current.photo else { return }
        if case .image(let image) = native {
            shown = image
            unavailable = false
        }
    }

    func close() {
        nativeTask?.cancel()
        shown = nil
        placeholder = nil
        if let window { Task { await source.leave(window: window.id) } }
        window = nil
    }
}
