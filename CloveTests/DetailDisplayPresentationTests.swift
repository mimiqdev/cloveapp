import CloveCore
import CloveImaging
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
private final class ObservedDetailImages: DetailImageSource {
    let sample = SampleDetailImages()
    private(set) var requests: [(PhotoIdentity, DetailPixelRequest)] = []
    private(set) var delivered: [DetailQuality] = []
    private(set) var windows: [DetailPhotoWindow] = []
    private(set) var deliveries: [(PhotoIdentity, DetailPixelRequest.Need, DetailQuality)] = []
    private(set) var prefetched: [DetailPhotoWindow] = []
    private(set) var previewPrefetched: [DetailPhotoWindow] = []
    var prefetchEnabled = true
    var heldPhoto: PhotoIdentity?
    var heldScreenRenderPhoto: PhotoIdentity?
    var releasesScreenRender = false
    var heldPlaceholder: PhotoIdentity?
    var releasesPlaceholder = false
    private(set) var placeholderRequests: [PhotoIdentity] = []

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        placeholderRequests.append(photo)
        if photo == heldPlaceholder {
            for _ in 0..<250 {
                guard !Task.isCancelled else { return nil }
                if releasesPlaceholder { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        if case .image(let pixels) = await gridThumbnails.thumbnail(for: photo, priority: .visible)
        {
            return pixels
        }
        return nil
    }

    func prepare(_ window: DetailPhotoWindow) async {
        windows.append(window)
        await sample.prepare(window)
    }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        requests.append((photo, request))
        if photo == heldPhoto {
            do { try await Task.sleep(for: .seconds(5)) } catch { return .deferred }
        }
        if photo == heldScreenRenderPhoto && request.need == .screenRender {
            for _ in 0..<250 {
                guard !Task.isCancelled else { return .deferred }
                if releasesScreenRender { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        let outcome = await sample.image(for: photo, request: request)
        if case .image(let image) = outcome {
            delivered.append(image.quality)
            deliveries.append((photo, request.need, image.quality))
        }
        return outcome
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        if prefetchEnabled { await sample.prefetchPreviews(window) }
        previewPrefetched.append(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        if prefetchEnabled { await sample.prefetch(window, renderAhead: renderAhead) }
        prefetched.append(window)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }
}

/// Runs the shared SwiftUI detail view with generated camera/RAW pixels.
@Suite(.serialized)
@MainActor
struct DetailDisplayPresentationTests {
    @Test func productionPlaceholderReadsTheGridCacheWithoutRequestingGridWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pixels = try testPixels(gray: 0.4)
        let file = directory.appendingPathComponent("photo.JPG")
        let data = try #require(UIImage(cgImage: pixels).jpegData(compressionQuality: 0.9))
        try data.write(to: file)
        let set = try PhotoSet(
            folderID: FolderIdentity(rawValue: "placeholder"), relativeFolderPath: "", jpegURL: file
        )
        let cache = try ThumbnailCache(directory: directory.appendingPathComponent("cache"))
        let request = ThumbnailRequest(
            source: file, revision: try ThumbnailRevision.read(from: file),
            locationIdentity: set.id.folderID.rawValue)
        try cache.store(.available(Thumbnail(image: pixels, route: .always)), for: request)
        let grid = RefusedPlaceholderThumbnails()
        let pipeline = DetailPipeline()
        let source = PipelineDetailImages(pipeline: pipeline, thumbnails: cache, set: { _ in set })
        let placeholder = await source.placeholder(for: set.id, gridThumbnails: grid)
        #expect(placeholder === pixels)
        #expect(grid.requests == 0)
        await pipeline.close()
    }

    @Test func uncachedPhotoShowsItsGridThumbnailWhileDetailIsPending() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        source.prefetchEnabled = false
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let first = browsing.photos[2]
        let next = browsing.photos[3]
        source.heldPhoto = next.id
        source.heldPlaceholder = next.id
        guard
            case .image(let thumbnail) = await browsing.thumbnails.thumbnail(
                for: next.id, priority: .visible)
        else { throw CocoaError(.fileReadUnknown) }
        browsing.openPhoto(first.id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source)
                .environment(SettingsStore.sample))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == first.id }
        let preview = try #require(findPreview(in: window))
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let image = try #require(scroll.subviews.first as? UIImageView)
        try #require(image.image?.cgImage != nil)
        browsing.openPhoto(next.id)
        try await waitFor { source.placeholderRequests.contains(next.id) }
        try await waitFor { image.image == nil }
        #expect(!source.releasesPlaceholder)
        #expect(!source.requests.contains { $0.0 == next.id })
        source.releasesPlaceholder = true
        try await waitFor { source.requests.contains { $0.0 == next.id } }
        try await waitFor { image.image?.cgImage === thumbnail }
        #expect(!source.deliveries.contains { $0.0 == next.id })
        #expect(!(preview.accessibilityValue ?? "").localizedCaseInsensitiveContains("loading"))
        func hasLoadingCue(_ view: UIView) -> Bool {
            if view is UIActivityIndicatorView { return true }
            if (view.accessibilityValue ?? "").localizedCaseInsensitiveContains("loading") {
                return true
            }
            if let text = (view as? UILabel)?.text, text.localizedCaseInsensitiveContains("loading")
            {
                return true
            }
            return view.subviews.contains(where: hasLoadingCue)
        }
        #expect(!hasLoadingCue(window))
    }

    @Test func rejectedDetailKeepsTheRenderedPhotoAtFullBrightness() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photo = browsing.photos[2]
        browsing.openPhoto(photo.id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source)
                .environment(SettingsStore.sample))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == photo.id }
        let preview = try #require(findPreview(in: window))
        let frame = preview.convert(preview.bounds, to: window)
        let centre = CGRect(x: frame.midX - 20, y: frame.midY - 20, width: 40, height: 40)
        let corner = CGRect(x: frame.maxX - 25, y: frame.minY + 13, width: 12, height: 12)
        let before = try displayedPixels(in: centre, window: window)
        let unmarkedCorner = try displayedPixels(in: corner, window: window)
        browsing.apply(.rating(.rejected), to: photo.id)
        try await waitFor {
            guard let pixels = try? displayedPixels(in: corner, window: window) else {
                return false
            }
            return pixels != unmarkedCorner
        }
        #expect(try displayedPixels(in: centre, window: window) == before)
        browsing.apply(.rating(.unrated), to: photo.id)
        try await waitFor {
            (try? displayedPixels(in: corner, window: window)) == unmarkedCorner
        }
        #expect(try displayedPixels(in: centre, window: window) == before)
    }

    /// Compare displayed photo pixels, including opacity applied by any SwiftUI ancestor.
    private func displayedPixels(in region: CGRect, window: UIWindow) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: region.size, format: format)
            .image { context in
                context.cgContext.translateBy(x: -region.minX, y: -region.minY)
                didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        try #require(didDraw)
        return try #require(image.pngData())
    }

    @Test func rawSwapOrderRefreshAndCameraZoomThroughTheSharedView() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update { $0.photoDisplayMode = .rawFirst }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        try #require(photos.count >= 4)
        let first = photos[2].id
        let next = photos[3].id
        browsing.openPhoto(first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.delivered.contains(.screenRAW) }
        #expect(source.delivered.first == .preview)
        #expect(source.windows.first?.mode == .rawFirst)
        browsing.setFilter(.unmarked)
        try await waitFor { source.windows.count >= 2 }
        #expect(source.windows.last?.current.photo == first)
        #expect(source.windows.last?.current.position == 0)
        #expect(source.windows.last?.mode == .rawFirst)
        #expect(source.windows.last?.direction == 1)
        #expect(source.windows.last?.neighbours.map(\.photo) == [next])
        let preview = try #require(findPreview(in: window))
        preview.onDoubleTap?(.center)
        try await waitFor { source.delivered.contains(.nativeRAW) }
        #expect(source.requests.last(where: { $0.1.need == .fullResolution })?.1.mode == .rawFirst)
        store.update { $0.photoDisplayMode = .cameraPreviewFirst }
        browsing.openPhoto(next)
        try await waitFor { source.prefetched.last?.current.photo == next }
        #expect(source.windows.last?.mode == .cameraPreviewFirst)
        let rawCount = source.sample.rawRenderCount
        let cameraPreview = try #require(findPreview(in: window))
        cameraPreview.onDoubleTap?(.center)
        try await waitFor { source.delivered.contains(.raster) }
        #expect(
            source.requests.last(where: { $0.1.need == .fullResolution })?.1.mode
                == .cameraPreviewFirst)
        #expect(source.sample.rawRenderCount == rawCount)
        #expect(source.sample.cameraDecodeCount == 1)
        print(
            "DISPLAY simulator shared view: preview -> screen RAW; camera fit/100% adds zero RAW renders"
        )
    }

    @Test(arguments: PhotoDisplayMode.allCases)
    func regularKeptZoomWaitsForOwnGestureBeforeUpgrading(mode: PhotoDisplayMode) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update {
            $0.photoDisplayMode = mode
            $0.keepZoom.inDetail = true
        }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        let first = photos[2].id
        let next = photos[3].id
        browsing.openPhoto(first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == first }
        let preview = try #require(findPreview(in: window))
        preview.onDoubleTap?(.center)
        try await waitFor {
            source.deliveries.contains { $0.0 == first && $0.1 == .fullResolution }
                && preview.zoomSnapshot != nil
        }
        browsing.openPhoto(next)
        try await waitFor { source.prefetched.last?.current.photo == next }
        try await waitFor { preview.zoomSnapshot != nil }
        #expect(
            !source.requests.contains {
                $0.0 == next && ($0.1.need == .morePixels || $0.1.need == .fullResolution)
            })
        // Retaining zoom did not decode; a person's own pinch still does.
        let pinchScale = try #require(preview.zoomSnapshot).scale + 1
        preview.onZoomChange?(pinchScale)
        try await waitFor { source.requests.contains { $0.0 == next && $0.1.need == .morePixels } }
        if mode == .cameraPreviewFirst { #expect(source.sample.rawRenderCount == 0) }
    }

    @Test func groupNavigationPreservesTheZoomedImagePoint() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        source.prefetchEnabled = false
        let store = SettingsStore.sample
        store.update { $0.keepZoom.inDetail = false }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let group = try #require(browsing.groups.first)
        browsing.openPhoto(group.members[0])
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitFor { source.prefetched.last?.current.photo == group.members[0] }
        let preview = try #require(findPreview(in: window))
        preview.onDoubleTap?(.center)
        try await waitFor { source.delivered.contains(.nativeRAW) && preview.zoomSnapshot != nil }
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        scroll.setContentOffset(
            CGPoint(
                x: (scroll.contentSize.width - scroll.bounds.width) * 0.7,
                y: scroll.contentOffset.y), animated: false)
        let before = try #require(preview.zoomSnapshot)
        browsing.openPhoto(group.members[1])
        try await waitFor { source.prefetched.last?.current.photo == group.members[1] }
        let after = try #require(preview.zoomSnapshot)
        #expect(abs(before.scale - after.scale) < 0.02)
        #expect(abs(before.anchor.x - after.anchor.x) < 0.02)
        #expect(abs(before.anchor.y - after.anchor.y) < 0.02)
    }

    @Test func attachmentUsesStableDisplayEdgeAndReturningToFirstUsesHeldRaw() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        source.prefetchEnabled = false
        let store = SettingsStore.sample
        store.update { $0.photoDisplayMode = .rawFirst }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        let first = photos[2].id
        let next = photos[3].id
        browsing.openPhoto(first)
        let host = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 500, height: 300)
        host.beginAppearanceTransition(true, animated: false)
        host.endAppearanceTransition()
        try await Task.sleep(for: .milliseconds(40))
        #expect(source.windows.isEmpty)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == first }
        let expectedEdge = Int(
            max(scene.screen.nativeBounds.width, scene.screen.nativeBounds.height))
        #expect(source.windows.first?.screenPixels == expectedEdge)
        browsing.openPhoto(next)
        try await waitFor { source.prefetched.last?.current.photo == next }
        #expect(source.sample.rawRenderCount == 2)
        let beforeReturn = source.prefetched.count
        browsing.openPhoto(first)
        try await waitFor {
            source.prefetched.count > beforeReturn && source.prefetched.last?.current.photo == first
        }
        #expect(source.windows.allSatisfy { $0.screenPixels == expectedEdge })
        #expect(
            source.deliveries.last(where: { $0.0 == first && $0.1 == .preview })?.2 == .screenRAW)
        #expect(source.sample.rawRenderCount == 2)
    }

    @Test func rapidNavigationAndRatingUseTheNewPhoto() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update { $0.autoAdvance.destination = .stay }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        browsing.openPhoto(photos[2].id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == photos[2].id }
        let preview = try #require(findPreview(in: window))
        let stepTravel = -max(180, preview.bounds.width * 0.3)
        try sendSwipe(to: preview, travel: CGPoint(x: stepTravel, y: 0))
        #expect(browsing.state.currentPhoto == photos[3].id)
        try await Task.sleep(for: .milliseconds(100))
        try sendSwipe(to: preview, travel: CGPoint(x: stepTravel, y: 0))
        #expect(browsing.state.currentPhoto == photos[4].id)
        try await Task.sleep(for: .milliseconds(100))
        try sendSwipe(to: preview, travel: CGPoint(x: 0, y: -130))
        #expect(browsing.shownMarks(for: photos[4].id).rating != .unrated)
        #expect(browsing.shownMarks(for: photos[3].id) == photos[3].marks)
    }

    @Test func navigationStartedAfterRatingCancelsAutoAdvanceAndMovesExactlyOnePhoto() async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update {
            $0.autoAdvance.destination = .nextPhoto
            $0.autoAdvance.triggers.rating = true
        }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        browsing.openPhoto(photos[2].id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == photos[2].id }
        let preview = try #require(findPreview(in: window))
        try sendSwipe(to: preview, travel: CGPoint(x: 0, y: -130))
        #expect(browsing.shownMarks(for: photos[2].id).rating != .unrated)
        try await Task.sleep(for: .milliseconds(100))
        let pan = DetailTestPan()
        pan.travel = CGPoint(x: -15, y: 0)
        try #require(preview.gestureRecognizerShouldBegin(pan))
        preview.handleMarkingPan(pan)
        try await Task.sleep(for: .milliseconds(350))
        #expect(browsing.state.currentPhoto == photos[2].id)
        pan.travel = CGPoint(x: -max(180, preview.bounds.width * 0.3), y: 0)
        pan.sampleState = .ended
        preview.handleMarkingPan(pan)
        #expect(browsing.state.currentPhoto == photos[3].id)
        try await Task.sleep(for: .milliseconds(350))
        #expect(browsing.state.currentPhoto == photos[3].id)
    }

    @Test func zoomBeginningCancelsAnInProgressNavigationPan() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.hasNext = true
        preview.layoutIfNeeded()
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
        var navigations = 0
        preview.onStep = { _ in navigations += 1 }
        // No physical touches exist here: feed travel separately, but cancel the real recognizer.
        pan.delegate = nil
        pan.setValue(UIGestureRecognizer.State.began.rawValue, forKey: "state")
        try #require(pan.state == .began)
        pan.delegate = preview
        let sample = DetailTestPan()
        sample.travel = CGPoint(x: -15, y: 0)
        try #require(preview.gestureRecognizerShouldBegin(sample))
        preview.handleMarkingPan(sample)
        sample.travel = CGPoint(x: -180, y: 0)
        sample.sampleState = .changed
        preview.handleMarkingPan(sample)
        #expect(scroll.transform == .identity)
        #expect(scroll.frame == preview.bounds)
        preview.scrollViewWillBeginZooming(scroll, with: scroll.subviews.first)
        #expect(pan.state == .cancelled || pan.state == .failed)
        // Without physical touches UIKit does not dispatch the terminal action; deliver it here.
        preview.handleMarkingPan(pan)
        #expect(scroll.transform == .identity)
        #expect(pan.isEnabled)
        #expect(navigations == 0)
    }

    /// At fit, horizontal drags keep the photo stationary and step only on release (#244).
    @Test func fitNavigationKeepsThePhotoStationaryDuringDragAndStillNavigates() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.hasPrevious = true
        preview.hasNext = true
        let old = try testPixels(gray: 0)
        let replacement = try testPixels(gray: 1)
        preview.setImage(old)
        preview.layoutIfNeeded()
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let image = try #require(scroll.subviews.first as? UIImageView)
        var steps: [Int] = []
        preview.onStep = { steps.append($0) }
        #expect(preview.clipsToBounds)

        for (travelX, expected) in [(-180.0, 1), (180.0, -1)] {
            let pan = DetailTestPan()
            pan.travel = CGPoint(x: travelX < 0 ? -15 : 15, y: 0)
            try #require(preview.gestureRecognizerShouldBegin(pan))
            preview.handleMarkingPan(pan)
            #expect(scroll.transform == .identity)
            #expect(image.frame == preview.bounds)
            pan.sampleState = .changed
            pan.travel = CGPoint(x: travelX, y: 0)
            preview.handleMarkingPan(pan)
            #expect(scroll.transform == .identity)
            #expect(scroll.frame == preview.bounds)
            #expect(image.frame == preview.bounds)
            let countBeforeRelease = steps.count
            pan.sampleState = .ended
            preview.handleMarkingPan(pan)
            #expect(steps.count == countBeforeRelease + 1)
            #expect(steps.last == expected)
            #expect(scroll.transform == .identity)
        }

        // Below-threshold release keeps the photo stationary and does not navigate.
        let shortPan = DetailTestPan()
        shortPan.travel = CGPoint(x: -15, y: 0)
        try #require(preview.gestureRecognizerShouldBegin(shortPan))
        preview.handleMarkingPan(shortPan)
        shortPan.sampleState = .changed
        shortPan.travel = CGPoint(x: -40, y: 0)
        preview.handleMarkingPan(shortPan)
        #expect(scroll.transform == .identity)
        shortPan.sampleState = .ended
        preview.handleMarkingPan(shortPan)
        #expect(steps == [1, -1])
        #expect(scroll.transform == .identity)

        preview.setImage(replacement)
        #expect(scroll.transform == .identity)
        #expect(image.image?.cgImage === replacement)
    }

    @Test func fitHorizontalDragInDetailScreenDoesNotTranslatePhotoFrameAndStepsOnRelease()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let first = browsing.photos[2]
        let next = browsing.photos[3]
        browsing.openPhoto(first.id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor {
            source.prefetched.last?.current.photo == first.id
                && source.delivered.contains(.screenRAW)
        }
        let preview = try #require(findPreview(in: window))
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let image = try #require(scroll.subviews.first as? UIImageView)
        let initialFrame = image.convert(image.bounds, to: window)
        let photoBand = CGRect(
            x: initialFrame.minX, y: initialFrame.midY - 60,
            width: initialFrame.width, height: 120)
        let initialPixels = try displayedPixels(in: photoBand, window: window)

        let pan = DetailTestPan()
        pan.travel = CGPoint(x: -15, y: 0)
        try #require(preview.gestureRecognizerShouldBegin(pan))
        preview.handleMarkingPan(pan)
        pan.sampleState = .changed
        pan.travel = CGPoint(x: -max(140, preview.bounds.width * 0.3), y: 0)
        preview.handleMarkingPan(pan)

        #expect(scroll.transform == .identity)
        #expect(image.convert(image.bounds, to: window) == initialFrame)
        #expect(try displayedPixels(in: photoBand, window: window) == initialPixels)
        #expect(browsing.state.currentPhoto == first.id)

        pan.sampleState = .ended
        preview.handleMarkingPan(pan)
        #expect(browsing.state.currentPhoto == next.id)
        #expect(scroll.transform == .identity)
        #expect(image.convert(image.bounds, to: window) == initialFrame)
    }

    /// A single tap toggles chrome at both fit and zoomed scales, waiting on double-tap first
    /// so returning to fit never toggles chrome (#273).
    @Test func chromeTapIsLiveAtFitAndZoomed() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.setImage(try testPixels(gray: 0))
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        var chromeToggles = 0
        preview.onChromeToggle = { chromeToggles += 1 }
        #expect(preview.chromeTapIsEnabled)
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
        #expect(preview.chromeTapIsEnabled)
        let toggleAction = try #require(
            preview.subviews.compactMap { $0.accessibilityCustomActions }.flatMap { $0 }.first)
        #expect(toggleAction.name == "Show or hide controls")
        #expect((preview as NSObject).perform(toggleAction.selector) != nil)
        #expect(chromeToggles == 1)
        preview.apply(DetailZoomCommand(id: 2, kind: .fit))
        #expect(preview.chromeTapIsEnabled)
    }

    @Test func filmstripStaysVisibleWhileZoomedAndChromeToggleHidesItInDetailScreen() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photo = browsing.photos[2]
        browsing.openPhoto(photo.id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source)
                .environment(SettingsStore.sample))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor {
            source.prefetched.last?.current.photo == photo.id
                && source.delivered.contains(.screenRAW)
        }
        let preview = try #require(findPreview(in: window))
        try await waitFor { self.findFilmstripScrollView(in: window, excluding: preview) != nil }

        // Double-tapping to 100% keeps the filmstrip mounted.
        preview.onDoubleTap?(.center)
        try await waitFor { preview.isZoomed }
        #expect(findFilmstripScrollView(in: window, excluding: preview) != nil)

        // Single-tapping chrome toggle while zoomed hides the filmstrip, then shows it again.
        preview.onChromeToggle?()
        try await waitFor { self.findFilmstripScrollView(in: window, excluding: preview) == nil }
        preview.onChromeToggle?()
        try await waitFor { self.findFilmstripScrollView(in: window, excluding: preview) != nil }
    }

    @Test func tapsAreUniformAcrossEdgesAndZoomedHorizontalSwipesDoNotNavigate() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.hasPrevious = true
        preview.hasNext = true
        preview.setImage(try testPixels(gray: 0))
        preview.layoutIfNeeded()
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let taps = (scroll.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
        #expect(taps.count == 2)
        #expect(taps.map(\.numberOfTapsRequired).sorted() == [1, 2])
        for tap in taps {
            #expect(preview.gestureRecognizerShouldBegin(tap))
        }

        var steps = 0
        preview.onStep = { _ in steps += 1 }
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
        let zoomedPan = DetailTestPan()
        zoomedPan.travel = CGPoint(x: -180, y: 0)
        #expect(!preview.gestureRecognizerShouldBegin(zoomedPan))
        #expect(steps == 0)
    }

    @Test func zoomedRatingRecognizerAvailabilityFollowsModeZoomAndGesturesEnabled() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.setImage(try testPixels(gray: 0))
        preview.setNeedsLayout()
        preview.layoutIfNeeded()

        func applySettings(mode: ZoomedRatingSwipe, gesturesEnabled: Bool) {
            var settings = AppSettings()
            settings.zoomedRatingSwipe = mode
            settings.gesturesEnabled = gesturesEnabled
            preview.rules = MarkingInputRules(settings: settings)
        }

        // At fit: 1-finger pan enabled (navigation still lives there), 2-finger zoomed swipe off, chrome tap on.
        for mode in ZoomedRatingSwipe.allCases {
            for gesturesEnabled in [true, false] {
                applySettings(mode: mode, gesturesEnabled: gesturesEnabled)
                #expect(!preview.isZoomed)
                #expect(preview.chromeTapIsEnabled)
                #expect(preview.markingPanIsEnabled)
                #expect(!preview.twoFingerMarkingSwipeIsEnabled)
            }
        }

        // While zoomed: recognizers follow `zoomedRatingSwipe` and `gesturesEnabled`, while chrome tap stays on.
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
        #expect(preview.isZoomed)
        #expect(preview.chromeTapIsEnabled)

        applySettings(mode: .twoFinger, gesturesEnabled: true)
        #expect(!preview.markingPanIsEnabled)
        #expect(preview.twoFingerMarkingSwipeIsEnabled)

        applySettings(mode: .singleFingerAxisLock, gesturesEnabled: true)
        #expect(preview.markingPanIsEnabled)
        #expect(!preview.twoFingerMarkingSwipeIsEnabled)

        for mode in ZoomedRatingSwipe.allCases {
            applySettings(mode: mode, gesturesEnabled: false)
            #expect(!preview.markingPanIsEnabled)
            #expect(!preview.twoFingerMarkingSwipeIsEnabled)
            #expect(!preview.gestureRecognizerShouldBegin(preview.twoFingerSwipeRecognizer))
            let pan = DetailTestPan()
            pan.travel = CGPoint(x: 0, y: -40)
            #expect(!preview.gestureRecognizerShouldBegin(pan))
        }

        // Returning to fit restores fit availability.
        applySettings(mode: .twoFinger, gesturesEnabled: true)
        preview.apply(DetailZoomCommand(id: 2, kind: .fit))
        #expect(!preview.isZoomed)
        #expect(preview.chromeTapIsEnabled)
        #expect(preview.markingPanIsEnabled)
        #expect(!preview.twoFingerMarkingSwipeIsEnabled)
    }

    @Test func zoomedTwoFingerSwipeRatesWithoutPinchAndPinchNeverRates() throws {
        func makeZoomedPreview() throws -> (
            preview: DetailZoomContainerView,
            feedback: DetailSwipeFeedback,
            twoFingerCommits: () -> [Rating],
            singleFingerCommits: () -> [Rating]
        ) {
            let preview = DetailZoomContainerView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 650))
            preview.setImage(try testPixels(gray: 0))
            let region = DetailFocusRegion(
                id: "clove.detail.region.af.0",
                evidence: RegionSharpnessEvidence(
                    kind: .cameraAutofocus, groupIndex: nil,
                    region: NormalizedRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                    score: RegionSharpnessScore(
                        tenengradMeanSquare: 1, sampledPixels: 64, sampledWidth: 8, sampledHeight: 8
                    ),
                    unavailableBecause: nil))
            preview.setFocusRegions([region])
            preview.setNeedsLayout()
            preview.layoutIfNeeded()
            preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
            let feedback = DetailSwipeFeedback()
            preview.feedback = feedback
            preview.currentRating = .unrated
            var twoFinger: [Rating] = []
            var singleFinger: [Rating] = []
            preview.onTwoFingerMarkingSwipe = { twoFinger.append($0) }
            preview.onMarkingSwipe = { singleFinger.append($0) }
            return (preview, feedback, { twoFinger }, { singleFinger })
        }

        // Parallel two-finger upward swipe recognizes, previews, and commits on first finger lift.
        do {
            let context = try makeZoomedPreview()
            let preview = context.preview
            let feedback = context.feedback
            let scroll = try #require(preview.subviews.first as? UIScrollView)
            let scrollPan = scroll.panGestureRecognizer
            let scrollPinch = try #require(scroll.pinchGestureRecognizer)
            let twoFingerSwipe = preview.twoFingerSwipeRecognizer
            #expect(twoFingerSwipe.isEnabled)

            // While zoomed in default mode, two-finger marking requires priority over scroll pinch/pan
            // and never runs simultaneously with them.
            #expect(
                preview.gestureRecognizer(twoFingerSwipe, shouldBeRequiredToFailBy: scrollPinch))
            #expect(preview.gestureRecognizer(twoFingerSwipe, shouldBeRequiredToFailBy: scrollPan))
            #expect(
                !preview.gestureRecognizer(
                    twoFingerSwipe, shouldRecognizeSimultaneouslyWith: scrollPinch))
            #expect(
                !preview.gestureRecognizer(
                    twoFingerSwipe, shouldRecognizeSimultaneouslyWith: scrollPan))

            // Focus region controls allow the zoomed two-finger swipe to start over them.
            if let control = findFocusControl(in: preview) {
                let regionTouch = DetailMutableTouch(view: control, location: control.center)
                #expect(preview.gestureRecognizer(twoFingerSwipe, shouldReceive: regionTouch))
            }

            let touch1 = DetailMutableTouch(view: preview, location: CGPoint(x: 150, y: 400))
            let touch2 = DetailMutableTouch(view: preview, location: CGPoint(x: 230, y: 400))
            let event = UIEvent()
            twoFingerSwipe.touchesBegan([touch1, touch2], with: event)
            #expect(twoFingerSwipe.state == .possible)

            touch1.locationPoint = CGPoint(x: 150, y: 380)
            touch2.locationPoint = CGPoint(x: 230, y: 380)
            twoFingerSwipe.touchesMoved([touch1, touch2], with: event)
            #expect(twoFingerSwipe.state == .began)
            #expect(preview.gestureRecognizerShouldBegin(twoFingerSwipe))
            preview.handleTwoFingerMarkingSwipe(twoFingerSwipe)
            #expect(feedback.isShowing)

            touch1.locationPoint = CGPoint(x: 150, y: 200)
            touch2.locationPoint = CGPoint(x: 230, y: 200)
            twoFingerSwipe.touchesMoved([touch1, touch2], with: event)
            #expect(twoFingerSwipe.state == .changed)
            preview.handleTwoFingerMarkingSwipe(twoFingerSwipe)

            // First finger lift immediately finishes the gesture without waiting for the second.
            twoFingerSwipe.touchesEnded([touch1], with: event)
            #expect(twoFingerSwipe.state == .ended)
            preview.handleTwoFingerMarkingSwipe(twoFingerSwipe)
            #expect(context.twoFingerCommits().count == 1)
            #expect(context.twoFingerCommits().first != .unrated)
            #expect(context.singleFingerCommits().isEmpty)
            #expect(!feedback.isShowing)
        }

        // Pinch (opposite / diverging touches) immediately fails and never rates.
        do {
            let context = try makeZoomedPreview()
            let twoFingerSwipe = context.preview.twoFingerSwipeRecognizer
            let pinch1 = DetailMutableTouch(
                view: context.preview, location: CGPoint(x: 160, y: 300))
            let pinch2 = DetailMutableTouch(
                view: context.preview, location: CGPoint(x: 220, y: 300))
            let event = UIEvent()
            twoFingerSwipe.touchesBegan([pinch1, pinch2], with: event)
            pinch1.locationPoint = CGPoint(x: 140, y: 315)
            pinch2.locationPoint = CGPoint(x: 240, y: 285)
            twoFingerSwipe.touchesMoved([pinch1, pinch2], with: event)
            #expect(twoFingerSwipe.didFailInCurrentSequence)
            #expect(twoFingerSwipe.state == .failed || twoFingerSwipe.state == .possible)
            context.preview.handleTwoFingerMarkingSwipe(twoFingerSwipe)
            #expect(context.twoFingerCommits().isEmpty)
            #expect(!context.feedback.isShowing)
        }

        // Two-finger horizontal pan fails and never rates.
        do {
            let context = try makeZoomedPreview()
            let twoFingerSwipe = context.preview.twoFingerSwipeRecognizer
            let pan1 = DetailMutableTouch(view: context.preview, location: CGPoint(x: 160, y: 300))
            let pan2 = DetailMutableTouch(view: context.preview, location: CGPoint(x: 220, y: 300))
            let event = UIEvent()
            twoFingerSwipe.touchesBegan([pan1, pan2], with: event)
            pan1.locationPoint = CGPoint(x: 190, y: 302)
            pan2.locationPoint = CGPoint(x: 250, y: 302)
            twoFingerSwipe.touchesMoved([pan1, pan2], with: event)
            #expect(twoFingerSwipe.didFailInCurrentSequence)
            #expect(twoFingerSwipe.state == .failed || twoFingerSwipe.state == .possible)
            #expect(context.twoFingerCommits().isEmpty)
        }

        // Single-finger vertical drag while zoomed in default mode fails two-finger swipe so scroll pan runs.
        do {
            let context = try makeZoomedPreview()
            let twoFingerSwipe = context.preview.twoFingerSwipeRecognizer
            let single = DetailMutableTouch(
                view: context.preview, location: CGPoint(x: 190, y: 300))
            let event = UIEvent()
            twoFingerSwipe.touchesBegan([single], with: event)
            single.locationPoint = CGPoint(x: 190, y: 280)
            twoFingerSwipe.touchesMoved([single], with: event)
            #expect(twoFingerSwipe.didFailInCurrentSequence)
            #expect(twoFingerSwipe.state == .failed || twoFingerSwipe.state == .possible)
            #expect(context.twoFingerCommits().isEmpty)
        }
    }

    @Test func zoomedSingleFingerAxisLockVerticalRatesAndHorizontalPansWithoutNavigating() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.setImage(try testPixels(gray: 0))
        preview.hasPrevious = true
        preview.hasNext = true
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        var settings = AppSettings()
        settings.zoomedRatingSwipe = .singleFingerAxisLock
        preview.rules = MarkingInputRules(settings: settings)
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))

        var commits: [Rating] = []
        var steps = 0
        preview.onMarkingSwipe = { commits.append($0) }
        preview.onStep = { _ in steps += 1 }

        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let scrollPan = scroll.panGestureRecognizer
        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? DetailSingleFingerPanGestureRecognizer }
                .first)
        #expect(pan.isEnabled)
        #expect(!preview.twoFingerSwipeRecognizer.isEnabled)
        #expect(preview.gestureRecognizer(pan, shouldBeRequiredToFailBy: scrollPan))
        #expect(!preview.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: scrollPan))

        // Horizontal single-finger start does not begin marking or navigation; yields to scrollView pan.
        let horizontal = DetailTestPan()
        horizontal.travel = CGPoint(x: -20, y: 4)
        #expect(!preview.gestureRecognizerShouldBegin(horizontal))
        #expect(steps == 0)

        // Two touches immediately fail DetailSingleFingerPanGestureRecognizer so pinch does not stall.
        let t1 = DetailMutableTouch(view: preview, location: CGPoint(x: 150, y: 300))
        let t2 = DetailMutableTouch(view: preview, location: CGPoint(x: 230, y: 300))
        pan.touchesBegan([t1, t2], with: UIEvent())
        #expect(pan.didFailForMultiTouch)
        #expect(pan.state == .failed || pan.state == .possible)

        // Vertical single-finger start begins marking and commits rating on release.
        let verticalStart = CGPoint(x: 195, y: 380)
        let vertical = DetailTestPan()
        vertical.locationPoint = verticalStart
        _ = preview.gestureRecognizer(
            pan, shouldReceive: DetailMutableTouch(view: preview, location: verticalStart))
        vertical.travel = CGPoint(x: 2, y: -20)
        #expect(preview.gestureRecognizerShouldBegin(vertical))
        preview.handleMarkingPan(vertical)
        vertical.sampleState = .changed
        vertical.locationPoint = CGPoint(x: 195, y: 240)
        vertical.travel = CGPoint(x: 2, y: -140)
        preview.handleMarkingPan(vertical)
        vertical.sampleState = .ended
        preview.handleMarkingPan(vertical)
        #expect(commits.count == 1)
        #expect(commits.first != .unrated)
        #expect(steps == 0)
    }

    @Test func zoomedRatingSwipeAutoAdvancesAndReturnsToFitInDetailScreen() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update {
            $0.zoomedRatingSwipe = .twoFinger
            $0.keepZoom.inDetail = false
            $0.autoAdvance.destination = .nextPhoto
            $0.autoAdvance.triggers.rating = true
        }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        // Use standalone consecutive photos (MMQ02682, MMQ02683, MMQ02684) so auto-advance steps
        // cleanly forward outside burst-2678.
        let first = photos[4].id
        let second = photos[5].id
        let third = photos[6].id
        browsing.openPhoto(first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor {
            source.prefetched.last?.current.photo == first && source.delivered.contains(.screenRAW)
        }
        let preview = try #require(findPreview(in: window))
        preview.onDoubleTap?(.center)
        try await waitFor { preview.isZoomed && preview.twoFingerMarkingSwipeIsEnabled }

        // Zoomed two-finger rating swipe commits rating, auto-advances, and returns to fit.
        let twoFinger = preview.twoFingerSwipeRecognizer
        let t1 = DetailMutableTouch(view: preview, location: CGPoint(x: 140, y: 420))
        let t2 = DetailMutableTouch(view: preview, location: CGPoint(x: 240, y: 420))
        let event = UIEvent()
        twoFinger.touchesBegan([t1, t2], with: event)
        t1.locationPoint = CGPoint(x: 140, y: 390)
        t2.locationPoint = CGPoint(x: 240, y: 390)
        twoFinger.touchesMoved([t1, t2], with: event)
        preview.handleTwoFingerMarkingSwipe(twoFinger)
        t1.locationPoint = CGPoint(x: 140, y: 240)
        t2.locationPoint = CGPoint(x: 240, y: 240)
        twoFinger.touchesMoved([t1, t2], with: event)
        preview.handleTwoFingerMarkingSwipe(twoFinger)
        twoFinger.touchesEnded([t1, t2], with: event)
        preview.handleTwoFingerMarkingSwipe(twoFinger)

        #expect(browsing.shownMarks(for: first).rating != .unrated)
        try await waitFor { browsing.state.currentPhoto == second && !preview.isZoomed }

        // Switch to single-finger axis lock while zoomed and verify rating + auto-advance + fit reset.
        store.update { $0.zoomedRatingSwipe = .singleFingerAxisLock }
        try await waitFor { source.prefetched.last?.current.photo == second }
        preview.onDoubleTap?(.center)
        try await waitFor { preview.isZoomed && preview.markingPanIsEnabled }

        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? DetailSingleFingerPanGestureRecognizer }
                .first)
        let singleTouch = DetailMutableTouch(view: preview, location: CGPoint(x: 195, y: 420))
        _ = preview.gestureRecognizer(pan, shouldReceive: singleTouch)
        let testPan = DetailTestPan()
        testPan.locationPoint = CGPoint(x: 195, y: 400)
        testPan.travel = CGPoint(x: 0, y: -20)
        try #require(preview.gestureRecognizerShouldBegin(testPan))
        preview.handleMarkingPan(testPan)
        testPan.sampleState = .changed
        testPan.locationPoint = CGPoint(x: 195, y: 240)
        testPan.travel = CGPoint(x: 0, y: -180)
        preview.handleMarkingPan(testPan)
        testPan.sampleState = .ended
        preview.handleMarkingPan(testPan)

        #expect(browsing.shownMarks(for: second).rating != .unrated)
        try await waitFor { browsing.state.currentPhoto == third && !preview.isZoomed }
    }

    @Test func previewPrefetchStartsImmediatelyOnArrivalBeforeScreenRenderFinishes() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        try #require(photos.count >= 6)
        let current = photos[2]
        source.heldScreenRenderPhoto = current.id
        browsing.openPhoto(current.id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source)
                .environment(SettingsStore.sample))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        // +/-2 preview prefetch fires on arrival before screenRender finishes.
        try await waitFor { source.previewPrefetched.last?.current.photo == current.id }
        let recorded = try #require(source.previewPrefetched.last)
        #expect(recorded.neighbours.map(\.photo) == [photos[1].id, photos[3].id])
        #expect(
            recorded.previewNeighbours.map(\.photo) == [
                photos[3].id, photos[1].id, photos[4].id, photos[0].id,
            ])
        #expect(source.prefetched.isEmpty)

        source.releasesScreenRender = true
        try await waitFor { source.prefetched.last?.current.photo == current.id }
    }

    @Test func warmArrivalShowsCachedBitmapSynchronouslyWithoutFlashingNil() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        try #require(photos.count >= 6)
        let targetIndices = 2...5
        var sets: [PhotoIdentity: PhotoSet] = [:]
        for index in targetIndices {
            let photo = photos[index]
            let file = directory.appendingPathComponent("photo-\(index).JPG")
            let context = try #require(
                CGContext(
                    data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 1200 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(
                red: CGFloat(index) * 0.15 + 0.1, green: 0.4, blue: 0.6, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            let cg = try #require(context.makeImage())
            let data = try #require(UIImage(cgImage: cg).jpegData(compressionQuality: 0.9))
            try data.write(to: file)
            let generatedSet = try PhotoSet(
                folderID: photo.id.folderID, relativeFolderPath: photo.id.relativeFolderPath,
                jpegURL: file)
            // Key the lookup by the browsing photo identity so DetailScreen resolves real files.
            sets[photo.id] = generatedSet
        }

        let directWindow = UIWindow(windowScene: scene)
        directWindow.frame = scene.coordinateSpace.bounds
        let mappedBrowsing = BrowsingModel(library: TestLibrary.sample())
        mappedBrowsing.openFolder()
        let screenPixels = Int(
            max(scene.screen.nativeBounds.width, scene.screen.nativeBounds.height))
        let directSets = Dictionary(
            uniqueKeysWithValues: sets.values.map { ($0.id, $0) })
        let directPipeline = DetailPipeline()
        let directSource = PipelineDetailImages(
            pipeline: directPipeline, set: { directSets[$0] })
        let sortedDirectIDs = sets.values.sorted {
            $0.primary.url.lastPathComponent < $1.primary.url.lastPathComponent
        }.map(\.id)
        let firstWindow = DetailPhotoWindow(
            id: UUID(),
            current: DetailNeighbour(photo: sortedDirectIDs[0], position: 0),
            neighbours: [DetailNeighbour(photo: sortedDirectIDs[1], position: 1)],
            previewNeighbours: [
                DetailNeighbour(photo: sortedDirectIDs[1], position: 1),
                DetailNeighbour(photo: sortedDirectIDs[2], position: 2),
            ],
            direction: 1, mode: .rawFirst, screenPixels: screenPixels)
        await directSource.prepare(firstWindow)
        _ = await directSource.image(for: sortedDirectIDs[0], request: firstWindow.request())
        await directSource.prefetchPreviews(firstWindow)
        let warmHit = directSource.warmImage(
            for: sortedDirectIDs[1], request: firstWindow.request())
        #expect(warmHit != nil)
        #expect(warmHit?.image != nil)
        await directPipeline.close()

        // Also exercise DetailScreen view-level synchronous warm path without nil flash or placeholder request.
        let sampleSource = SampleDetailImages()
        @MainActor final class WarmSampleObserver: DetailImageSource {
            let sample: SampleDetailImages
            var warmed: [PhotoIdentity: DetailImage] = [:]
            var placeholderPhotos: [PhotoIdentity] = []
            var warmHits: [PhotoIdentity] = []
            var prefetched: [DetailPhotoWindow] = []
            init(_ sample: SampleDetailImages) { self.sample = sample }
            func warmImage(for photo: PhotoIdentity, request: DetailPixelRequest) -> DetailImage? {
                if let hit = warmed[photo] {
                    warmHits.append(photo)
                    return hit
                }
                return nil
            }
            func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource)
                async
                -> CGImage?
            {
                placeholderPhotos.append(photo)
                return await sample.placeholder(for: photo, gridThumbnails: gridThumbnails)
            }
            func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }
            func image(for photo: PhotoIdentity, request: DetailPixelRequest) async
                -> DetailImageOutcome
            {
                let outcome = await sample.image(for: photo, request: request)
                if case .image(let img) = outcome { warmed[photo] = img }
                return outcome
            }
            func prefetchPreviews(_ window: DetailPhotoWindow) async {
                await sample.prefetchPreviews(window)
                for n in window.previewNeighbours {
                    if case .image(let img) = await sample.image(
                        for: n.photo, request: window.request())
                    {
                        warmed[n.photo] = img
                    }
                }
            }
            func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
                await sample.prefetch(window, renderAhead: renderAhead)
                prefetched.append(window)
            }
            func leave(window: UUID) async { await sample.leave(window: window) }
        }

        let spy = WarmSampleObserver(sampleSource)
        mappedBrowsing.openPhoto(photos[2].id)
        directWindow.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: mappedBrowsing, images: spy)
                .environment(SettingsStore.sample))
        directWindow.makeKeyAndVisible()
        defer {
            directWindow.isHidden = true
            directWindow.rootViewController = nil
        }
        try await waitFor { spy.prefetched.last?.current.photo == photos[2].id }
        let preview = try #require(findPreview(in: directWindow))
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let imageView = try #require(scroll.subviews.first as? UIImageView)
        try #require(imageView.image?.cgImage != nil)

        // Swiping to warm neighbour photos[3] hits warmImage synchronously and never flashes nil or requests placeholder.
        mappedBrowsing.openPhoto(photos[3].id)
        #expect(!spy.placeholderPhotos.contains(photos[3].id))
        try await waitFor { spy.warmHits.contains(photos[3].id) && imageView.image?.cgImage != nil }
        #expect(!spy.placeholderPhotos.contains(photos[3].id))
        try await waitFor { spy.prefetched.last?.current.photo == photos[3].id }
    }

    @Test func duoFocusSplitDoubleTapAndRegionTapKeepZoomCentredOnFocusRegionAfterChromeHides()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let target = try #require(browsing.photos.first { $0.id.stem == "mmq02678" })

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 600)
        let rootView = GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
            .environment(store)
            .environment(\.isDuoExpanded, true)
            .environment(\.usesSystemBrowsingToolbar, true)
        let host = UIHostingController(rootView: NavigationStack { rootView })
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Open photo from the expanded Duo grid into Focus split.
        try await Task.sleep(for: .milliseconds(100))
        browsing.openPhoto(target.id)

        try await waitFor {
            if let preview = findPreview(in: window),
                let value = preview.subviews.first(where: {
                    $0.accessibilityIdentifier == "clove.detail.preview"
                })?.accessibilityValue
            {
                return value.contains("Loaded") && findFocusControl(in: preview) != nil
            }
            return false
        }

        let preview = try #require(findPreview(in: window))
        let previewFrameInWindow = preview.convert(preview.bounds, to: window)
        // Verify the preview inside PhotoArrangement receives touches across the photo body.
        let hitCenter = window.hitTest(
            CGPoint(x: previewFrameInWindow.midX, y: previewFrameInWindow.midY), with: nil)
        #expect(hitCenter is UIImageView)

        // 1. Double-tapping the photo body away from the AF region centres 100% on AF and keeps it
        // centred after Duo chrome hides and resizes the preview container (#272).
        let heightBefore = preview.bounds.height
        preview.onDoubleTap?(UnitPoint(x: 0.5, y: 0.6))
        try await waitFor { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))
        #expect(preview.bounds.height > heightBefore)
        let doubleTapSnapshot = try #require(preview.zoomSnapshot)
        #expect(abs(doubleTapSnapshot.anchor.x - 0.30) < 0.01)
        #expect(abs(doubleTapSnapshot.anchor.y - 0.35) < 0.01)
        let accessibilityValue = try #require(
            preview.subviews.first(where: {
                $0.accessibilityIdentifier == "clove.detail.preview"
            })?.accessibilityValue)
        #expect(accessibilityValue.contains("centred at 30%, 35%"))

        // 2. Return to fit, then tap the AF control directly and verify it stays centred after chrome hides.
        preview.onDoubleTap?(UnitPoint(x: 0.5, y: 0.5))
        try await waitFor { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(350))
        let afControl = try #require(
            findAllFocusControls(in: preview).first { $0.region.id == "clove.detail.region.af.0" })
        afControl.sendActions(for: .touchUpInside)
        try await waitFor { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))
        let regionTapSnapshot = try #require(preview.zoomSnapshot)
        #expect(abs(regionTapSnapshot.anchor.x - 0.30) < 0.05)
        #expect(abs(regionTapSnapshot.anchor.y - 0.35) < 0.05)
    }

    @Test func duoPhotoOnlyAndPortraitFocusResizeKeepFullResolutionScaleAndFocusAnchor()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let target = try #require(browsing.photos.first { $0.id.stem == "mmq02678" })

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let split = Binding.constant(DuoSplit.photoOnly)
        let host = UIHostingController(
            rootView: NavigationStack {
                DetailScreen(
                    browsing: browsing,
                    duo: DuoDetailLayout(
                        split: split,
                        grid: AnyView(EmptyView()),
                        filter: AnyView(EmptyView()),
                        more: AnyView(EmptyView()),
                        bottom: AnyView(EmptyView()),
                        showsGrid: true,
                        foldedGroup: nil))
            }
            .environment(store)
            .environment(\.isDuoExpanded, true)
            .environment(\.usesSystemBrowsingToolbar, true))
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        browsing.openPhoto(target.id)
        try await waitFor {
            if let preview = findPreview(in: window),
                let value = preview.subviews.first(where: {
                    $0.accessibilityIdentifier == "clove.detail.preview"
                })?.accessibilityValue
            {
                return value.contains("Loaded") && findFocusControl(in: preview) != nil
            }
            return false
        }

        let preview = try #require(findPreview(in: window))
        let heightBefore = preview.bounds.height
        preview.onDoubleTap?(UnitPoint(x: 0.5, y: 0.6))
        try await waitFor { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))

        // Since #273, zooming alone leaves the Duo photo-only filmstrip visible so preview height
        // stays unchanged while zoom scale and focus anchor settle cleanly.
        #expect(preview.bounds.height == heightBefore)
        let zoomedSnapshot = try #require(preview.zoomSnapshot)
        #expect(zoomedSnapshot.anchor.x < 0.42)
        #expect(zoomedSnapshot.anchor.y < 0.42)
        let expectedZoomedScale = DetailZoom.fullResolutionScale(
            nativePixels: CGSize(width: 3000, height: 2000),
            shownPixels: CGSize(width: 1616, height: 1078),
            viewSize: preview.bounds.size,
            screenScale: host.traitCollection.displayScale)
        #expect(abs(zoomedSnapshot.scale - expectedZoomedScale) < 0.02)

        // Toggling chrome hides the filmstrip and grows the pane height; both the native 100%
        // scale and focus-region anchor must re-settle cleanly for the enlarged bounds.
        preview.onChromeToggle?()
        try await waitFor { preview.bounds.height > heightBefore }
        try await Task.sleep(for: .milliseconds(450))
        #expect(preview.bounds.height > heightBefore)
        let settled = try #require(preview.zoomSnapshot)
        #expect(settled.anchor.x < 0.42)
        #expect(settled.anchor.y < 0.42)
        let expectedScale = DetailZoom.fullResolutionScale(
            nativePixels: CGSize(width: 3000, height: 2000),
            shownPixels: CGSize(width: 1616, height: 1078),
            viewSize: preview.bounds.size,
            screenScale: host.traitCollection.displayScale)
        #expect(abs(settled.scale - expectedScale) < 0.02)
    }

    private func findAllFocusControls(in view: UIView) -> [DetailFocusRegionControl] {
        var found: [DetailFocusRegionControl] = []
        if let control = view as? DetailFocusRegionControl { found.append(control) }
        for child in view.subviews {
            found.append(contentsOf: findAllFocusControls(in: child))
        }
        return found
    }

    private func testPixels(gray: CGFloat) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try #require(context.makeImage())
    }

    private func sendSwipe(to preview: DetailZoomContainerView, travel: CGPoint) throws {
        let pan = DetailTestPan()
        pan.travel = CGPoint(x: travel.x == 0 ? 0 : -15, y: travel.y == 0 ? 0 : -15)
        try #require(preview.gestureRecognizerShouldBegin(pan))
        preview.handleMarkingPan(pan)
        pan.sampleState = .changed
        pan.travel = travel
        preview.handleMarkingPan(pan)
        pan.sampleState = .ended
        preview.handleMarkingPan(pan)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Detail presentation did not settle within five seconds")
    }

    private func findPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let preview = findPreview(in: child) { return preview }
        }
        return nil
    }

    private func findFocusControl(in view: UIView) -> DetailFocusRegionControl? {
        if let control = view as? DetailFocusRegionControl { return control }
        for child in view.subviews {
            if let control = findFocusControl(in: child) { return control }
        }
        return nil
    }

    private func findFilmstripScrollView(
        in view: UIView, excluding preview: DetailZoomContainerView
    ) -> UIScrollView? {
        if view === preview { return nil }
        if let scrollView = view as? UIScrollView { return scrollView }
        for child in view.subviews {
            if let found = findFilmstripScrollView(in: child, excluding: preview) {
                return found
            }
        }
        return nil
    }
}

@MainActor
private final class RefusedPlaceholderThumbnails: GridThumbnailSource {
    private(set) var requests = 0
    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority) async
        -> GridThumbnailOutcome
    {
        requests += 1
        return .deferred
    }
    func companions(for photo: PhotoIdentity) -> GridCompanions { GridCompanions() }
}

@MainActor
private final class DetailTestPan: UIPanGestureRecognizer {
    var travel: CGPoint = .zero
    var locationPoint: CGPoint?
    var sampleState: UIGestureRecognizer.State = .began

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { travel }
    override func location(in view: UIView?) -> CGPoint {
        locationPoint ?? super.location(in: view)
    }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}

@MainActor
private final class DetailMutableTouch: UITouch {
    private weak var targetView: UIView?
    var locationPoint: CGPoint

    init(view: UIView, location: CGPoint) {
        self.targetView = view
        self.locationPoint = location
        super.init()
    }

    override var view: UIView? { targetView }

    override func location(in view: UIView?) -> CGPoint {
        guard let targetView, let view, view !== targetView else { return locationPoint }
        return targetView.convert(locationPoint, to: view)
    }
}
