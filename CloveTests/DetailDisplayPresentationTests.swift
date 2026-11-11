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
    var prefetchEnabled = true

    func prepare(_ window: DetailPhotoWindow) async {
        windows.append(window)
        await sample.prepare(window)
    }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        requests.append((photo, request))
        let outcome = await sample.image(for: photo, request: request)
        if case .image(let image) = outcome {
            delivered.append(image.quality)
            deliveries.append((photo, request.need, image.quality))
        }
        return outcome
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
        preview.onZoomChange?(4)
        try await waitFor { source.requests.contains { $0.0 == next && $0.1.need == .morePixels } }
        if mode == .cameraPreviewFirst { #expect(source.sample.rawRenderCount == 0) }
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
        try sendSwipe(to: preview, travel: CGPoint(x: -180, y: 0))
        #expect(browsing.state.currentPhoto == photos[3].id)
        try await Task.sleep(for: .milliseconds(100))
        try sendSwipe(to: preview, travel: CGPoint(x: -180, y: 0))
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
        pan.travel = CGPoint(x: -180, y: 0)
        pan.sampleState = .ended
        preview.handleMarkingPan(pan)
        #expect(browsing.state.currentPhoto == photos[3].id)
        try await Task.sleep(for: .milliseconds(350))
        #expect(browsing.state.currentPhoto == photos[3].id)
    }

    @Test func zoomBeginningCancelsAnInProgressNavigationPan() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.hasNext = true
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
        var navigations = 0
        preview.onEdgeTap = { _ in navigations += 1 }
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
        #expect(scroll.transform.tx == -180)
        preview.scrollViewWillBeginZooming(scroll, with: scroll.subviews.first)
        #expect(pan.state == .cancelled || pan.state == .failed)
        // Without physical touches UIKit does not dispatch the terminal action; deliver it here.
        preview.handleMarkingPan(pan)
        #expect(scroll.transform == .identity)
        #expect(pan.isEnabled)
        #expect(navigations == 0)
    }

    @Test func navigationOffsetResetsOnlyAfterReplacementPixelsAreInstalled() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.hasNext = true
        let old = try testPixels(gray: 0)
        let replacement = try testPixels(gray: 1)
        preview.setImage(old)
        try sendSwipe(to: preview, travel: CGPoint(x: -180, y: 0))
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let image = try #require(scroll.subviews.first as? UIImageView)
        #expect(scroll.transform.tx == -180)
        #expect(image.image?.cgImage === old)
        preview.setImage(replacement)
        #expect(scroll.transform == .identity)
        #expect(image.image?.cgImage === replacement)
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
}

@MainActor
private final class DetailTestPan: UIPanGestureRecognizer {
    var travel: CGPoint = .zero
    var sampleState: UIGestureRecognizer.State = .began

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { travel }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}
