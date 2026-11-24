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
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source)
                .environment(store))
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
        try await waitFor { source.delivered.contains(.screenRAW) && !browsing.isFolderOpening }
        #expect(source.delivered.first == .preview)
        #expect(source.windows.first?.mode == .rawFirst)
        let windowsBeforeFilter = source.windows.count
        browsing.setFilter(.unmarked)
        try await waitFor { source.windows.count > windowsBeforeFilter }
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
    func standaloneNavigationReturnsToFitWithoutAskingForPixels(mode: PhotoDisplayMode) async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update { $0.photoDisplayMode = mode }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        // MMQ02682 and MMQ02683 are consecutive standalone photos, so the step leaves any group.
        let first = photos[4].id
        let next = photos[5].id
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
        // Switching to another standalone photo returns to fit, so nothing of the old crop is kept
        // or rendered.
        try await waitFor { !preview.isZoomed && preview.zoomSnapshot == nil }
        #expect(
            !source.requests.contains {
                $0.0 == next && ($0.1.need == .morePixels || $0.1.need == .fullResolution)
            })
        // A person's own pinch still asks for the pixels it needs once the photo is on screen;
        // the pinch has to reach past the screen render's own size to ask for more.
        try await waitFor { source.deliveries.contains { $0.0 == next } }
        preview.onZoomChange?(4)
        try await waitFor { source.requests.contains { $0.0 == next && $0.1.need == .morePixels } }
        if mode == .cameraPreviewFirst { #expect(source.sample.rawRenderCount == 0) }
    }

    @Test func groupNavigationPreservesTheZoomedImagePoint() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        source.prefetchEnabled = false
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let group = try #require(browsing.groups.first)
        browsing.openGroup(group.id, on: group.members[0])
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
        browsing.selectGroupPhoto(group.members[1])
        try await waitFor { source.prefetched.last?.current.photo == group.members[1] }
        let after = try #require(preview.zoomSnapshot)
        #expect(abs(before.scale - after.scale) < 0.02)
        #expect(abs(before.anchor.x - after.anchor.x) < 0.02)
        #expect(abs(before.anchor.y - after.anchor.y) < 0.02)

        // Leaving the group always returns to fit (#302, #304).
        let outside = try #require(browsing.photos.first { !group.members.contains($0.id) }?.id)
        browsing.openPhoto(outside)
        try await waitFor { source.prefetched.last?.current.photo == outside }
        try await waitFor { !preview.isZoomed && preview.zoomSnapshot == nil }
    }

    @Test
    func groupFocusDoubleTapRecentersAcrossAsyncMembersHandlesNoRegionFallbackAndResetsOnExit()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let context = makeGroupFocusTrackingContext()
        let source = context.source
        let browsing = context.browsing
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        store.update { $0.doubleTap = .zoomToFocus }
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        browsing.showsFocusRegions = true
        browsing.openGroup(context.group.id, on: context.g1)

        // Hold g2 and g4 focus analysis so they arrive asynchronously after pixels are shown.
        source.gatedFocusPhotos = [context.g2, context.g4]

        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            source.releaseAll()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("g1 loaded with focus regions") {
            guard let preview = findPreview(in: window) else { return false }
            return source.prefetched.last?.current.photo == context.g1
                && self.findFocusControl(in: preview) != nil
        }
        let preview = try #require(findPreview(in: window))

        // 1. Double-tap Zoom to focus on g1 centers on g1's AF (0.30, 0.35).
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.5)))
        try await waitFor("g1 zoomed to AF") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))
        let g1Snapshot = try #require(preview.zoomSnapshot)
        #expect(abs(g1Snapshot.anchor.x - 0.30) < 0.02)
        #expect(abs(g1Snapshot.anchor.y - 0.35) < 0.02)
        let expectedFullScale = g1Snapshot.scale

        // 2. Step to g2 while g2's focus analysis is still in flight: stays at 100% (no jump to
        //    Fit) using g1's anchor as fallback, then async AF re-centers onto (0.70, 0.64) and
        //    subsequent finish with a shifted eye does not jump a second time.
        browsing.selectGroupPhoto(context.g2)
        try await waitFor("g2 preview shown at retained 100%") {
            source.prefetched.last?.current.photo == context.g2
                && source.isAnalysisWaiting(for: context.g2)
                && preview.isZoomed
        }
        let g2Fallback = try #require(preview.zoomSnapshot)
        #expect(abs(g2Fallback.scale - expectedFullScale) < 0.02)
        #expect(abs(g2Fallback.anchor.x - 0.30) < 0.02)
        #expect(abs(g2Fallback.anchor.y - 0.35) < 0.02)

        source.deliverAutofocus(for: context.g2)
        try await waitFor("g2 recentered onto async AF") {
            guard let snapshot = preview.zoomSnapshot else { return false }
            return abs(snapshot.anchor.x - 0.70) < 0.02
                && abs(snapshot.anchor.y - 0.64) < 0.02
        }
        let g2ControlsAfterAF = findAllFocusControls(in: preview)
        #expect(g2ControlsAfterAF.map(\.region.id) == ["clove.detail.region.af.0"])

        source.finishAnalysis(for: context.g2)
        try await Task.sleep(for: .milliseconds(120))
        let g2Settled = try #require(preview.zoomSnapshot)
        #expect(abs(g2Settled.scale - expectedFullScale) < 0.02)
        #expect(abs(g2Settled.anchor.x - 0.70) < 0.02)
        #expect(abs(g2Settled.anchor.y - 0.64) < 0.02)

        // 3. Step to g3 (no actionable focus regions): retains previous anchor without jumping to
        //    Fit, clears inspected focus region, and keeps focus-point tracking active.
        browsing.selectGroupPhoto(context.g3)
        try await waitFor("g3 settled") {
            source.prefetched.last?.current.photo == context.g3
                && source.finishedAnalysisPhotos.contains(context.g3)
        }
        try await Task.sleep(for: .milliseconds(100))
        let g3Snapshot = try #require(preview.zoomSnapshot)
        #expect(abs(g3Snapshot.scale - expectedFullScale) < 0.02)
        #expect(abs(g3Snapshot.anchor.x - 0.70) < 0.02)
        #expect(abs(g3Snapshot.anchor.y - 0.64) < 0.02)
        #expect(findAllFocusControls(in: preview).isEmpty)

        // 4. Step to g4 (no AF metadata, shifted eye arriving on finish): receiveAutofocus misses,
        //    pending recenter stays active, and finish re-centers onto g4's eye (0.205, 0.685).
        browsing.selectGroupPhoto(context.g4)
        try await waitFor("g4 preview shown and waiting for analysis") {
            source.prefetched.last?.current.photo == context.g4
                && source.isAnalysisWaiting(for: context.g4)
        }
        source.deliverAutofocus(for: context.g4)
        try await Task.sleep(for: .milliseconds(80))
        let g4BeforeFaces = try #require(preview.zoomSnapshot)
        #expect(abs(g4BeforeFaces.anchor.x - 0.70) < 0.02)
        #expect(abs(g4BeforeFaces.anchor.y - 0.64) < 0.02)

        source.finishAnalysis(for: context.g4)
        try await waitFor("g4 recentered onto eye region") {
            guard let snapshot = preview.zoomSnapshot else { return false }
            return abs(snapshot.anchor.x - 0.205) < 0.02
                && abs(snapshot.anchor.y - 0.685) < 0.02
        }
        #expect(
            findAllFocusControls(in: preview).map(\.region.id) == ["clove.detail.region.face.0-0"])

        // 5. Leaving Group Focus to an outside photo resets to Fit and clears tracking.
        browsing.openPhoto(context.outside)
        try await waitFor("outside photo returned to Fit") {
            source.prefetched.last?.current.photo == context.outside
                && !preview.isZoomed && preview.zoomSnapshot == nil
        }
    }

    @Test func groupFocusRegionTapPreloadedAnalysisRapidSteppingAndRawUpgradeWorkCleanly()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let context = makeGroupFocusTrackingContext()
        let source = context.source
        let browsing = context.browsing
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        store.update { $0.doubleTap = .zoomToTapPoint }
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        browsing.showsFocusRegions = true
        browsing.openGroup(context.group.id, on: context.g1)

        // Delay g2's image so focus analysis finishes BEFORE show(image), and omit initial
        // full-resolution size on g2's preview so RAW upgrade runs after recenter.
        source.gatedImagePhotos = [context.g2, context.g3]
        source.previewOmitsFullSize = [context.g2]

        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            source.releaseAll()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("g1 loaded with multiple focus controls") {
            guard let preview = findPreview(in: window) else { return false }
            return source.prefetched.last?.current.photo == context.g1
                && self.findAllFocusControls(in: preview).count >= 2
        }
        let preview = try #require(findPreview(in: window))

        // 1. Tap g1's eye focus control directly (even with doubleTap == .zoomToTapPoint).
        let g1EyeControl = try #require(
            findAllFocusControls(in: preview).first {
                $0.region.id == "clove.detail.region.face.0-0"
            })
        g1EyeControl.sendActions(for: .touchUpInside)
        try await waitFor("g1 zoomed onto tapped eye") {
            guard let snapshot = preview.zoomSnapshot else { return false }
            return abs(snapshot.anchor.x - 0.65) < 0.02
                && abs(snapshot.anchor.y - 0.315) < 0.02
        }

        // 2. Step to g2 while g2's image is held so analysis completes BEFORE show(image).
        browsing.selectGroupPhoto(context.g2)
        try await waitFor("g2 focus analysis finished before image landed") {
            source.finishedAnalysisPhotos.contains(context.g2)
        }
        source.releaseImage(for: context.g2)
        try await waitFor("g2 opened directly on its focus region and upgraded RAW") {
            guard let snapshot = preview.zoomSnapshot else { return false }
            return source.deliveredFullPhotos.contains(context.g2)
                && abs(snapshot.anchor.x - 0.70) < 0.02
                && abs(snapshot.anchor.y - 0.64) < 0.02
        }
        #expect(findAllFocusControls(in: preview).map(\.region.id) == ["clove.detail.region.af.0"])

        // 3. Rapid step g2 -> g3 (held, never loads pixels) -> g4: tracking stays active across g3
        //    and re-centers onto g4's focus region.
        browsing.selectGroupPhoto(context.g3)
        try await Task.sleep(for: .milliseconds(30))
        browsing.selectGroupPhoto(context.g4)
        try await waitFor("g4 settled after rapid stepping") {
            guard let snapshot = preview.zoomSnapshot else { return false }
            return source.prefetched.last?.current.photo == context.g4
                && abs(snapshot.anchor.x - 0.205) < 0.02
                && abs(snapshot.anchor.y - 0.685) < 0.02
        }

        // 4. Collapsing Group Focus onto the Representative Photo (g1 != g4) resets to Fit.
        browsing.collapseGroup()
        try await waitFor("collapse onto different representative returned to Fit") {
            browsing.state.currentPhoto == context.g1 && !preview.isZoomed
        }
    }

    @Test func groupFocusManualPanAndPinchCancelFocusPointTracking() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let context = makeGroupFocusTrackingContext()
        let source = context.source
        let browsing = context.browsing
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        store.update {
            $0.doubleTap = .zoomToFocus
            $0.zoomedGestures = .pan
        }
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        browsing.showsFocusRegions = true
        browsing.openGroup(context.group.id, on: context.g1)

        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            source.releaseAll()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("g1 loaded") {
            guard let preview = findPreview(in: window) else { return false }
            return source.prefetched.last?.current.photo == context.g1
                && self.findFocusControl(in: preview) != nil
        }
        let preview = try #require(findPreview(in: window))
        let scroll = try #require(preview.subviews.first as? UIScrollView)

        // 1. Zoom to focus on g1, simulate an accidental zero-movement touch-down callback, and
        //    verify stepping to g2 still re-centers onto g2's AF.
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.5)))
        try await waitFor("g1 zoomed") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(120))
        let settledG1 = try #require(preview.zoomSnapshot)
        preview.onViewportChanged?(settledG1)

        browsing.selectGroupPhoto(context.g2)
        try await waitFor("g2 still recentered after zero-movement touch") {
            guard let snapshot = preview.zoomSnapshot else { return false }
            return source.prefetched.last?.current.photo == context.g2
                && abs(snapshot.anchor.x - 0.70) < 0.02
                && abs(snapshot.anchor.y - 0.64) < 0.02
        }

        // 2. Manually pan on g2 away from its focus point: inspected region clears and stepping
        //    back to g1 preserves the manual pan anchor instead of snapping to g1's AF.
        scroll.setContentOffset(
            CGPoint(
                x: (scroll.contentSize.width - scroll.bounds.width) * 0.25,
                y: (scroll.contentSize.height - scroll.bounds.height) * 0.50),
            animated: false)
        preview.scrollViewDidEndDragging(scroll, willDecelerate: false)
        let manualPanBefore = try #require(preview.zoomSnapshot)
        try await waitFor("manual pan cleared isolated inspection") {
            self.findAllFocusControls(in: preview).count >= 2
        }

        browsing.selectGroupPhoto(context.g1)
        try await waitFor("g1 kept manual pan anchor") {
            source.prefetched.last?.current.photo == context.g1
        }
        try await Task.sleep(for: .milliseconds(120))
        let afterPanStep = try #require(preview.zoomSnapshot)
        #expect(abs(afterPanStep.anchor.x - manualPanBefore.anchor.x) < 0.02)
        #expect(abs(afterPanStep.anchor.y - manualPanBefore.anchor.y) < 0.02)

        // 3. Return to Fit, re-enter focus tracking on g1, then manually pinch to a custom scale
        //    and verify stepping to g2 preserves the manual scale and anchor.
        preview.onDoubleTap?(.center)
        try await waitFor("returned to Fit") { !preview.isZoomed }
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.5)))
        try await waitFor("g1 re-zoomed to AF") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(120))

        let pinchedScale = max(3.6, (preview.zoomSnapshot?.scale ?? 2.0) + 1.1)
        scroll.setZoomScale(pinchedScale, animated: false)
        preview.scrollViewDidZoom(scroll)
        let pinchedBefore = try #require(preview.zoomSnapshot)

        browsing.selectGroupPhoto(context.g2)
        try await waitFor("g2 settled after manual pinch") {
            source.prefetched.last?.current.photo == context.g2
        }
        try await Task.sleep(for: .milliseconds(120))
        let afterPinchStep = try #require(preview.zoomSnapshot)
        #expect(abs(afterPinchStep.scale - pinchedBefore.scale) < 0.05)
        #expect(abs(afterPinchStep.anchor.x - 0.70) > 0.08)
    }

    @Test func groupFocusTapPointAndNoRegionDoubleTapKeepFixedAnchorAcrossSteps() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let context = makeGroupFocusTrackingContext()
        let source = context.source
        let browsing = context.browsing
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        browsing.showsFocusRegions = true
        browsing.openGroup(context.group.id, on: context.g1)

        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            source.releaseAll()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("g1 loaded") {
            guard let preview = findPreview(in: window) else { return false }
            return source.prefetched.last?.current.photo == context.g1
                && self.findFocusControl(in: preview) != nil
        }
        let preview = try #require(findPreview(in: window))

        // 1. Zoom to tap point keeps fixed tap anchor when stepping to g2 (does not jump to g2 AF).
        store.update { $0.doubleTap = .zoomToTapPoint }
        try await waitFor("setting propagated") {
            store.settings.doubleTap == .zoomToTapPoint
        }
        try await Task.sleep(for: .milliseconds(60))
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.42, y: 0.58)))
        try await waitFor("g1 zoomed to tap point") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(120))

        browsing.selectGroupPhoto(context.g2)
        try await waitFor("g2 settled") {
            source.prefetched.last?.current.photo == context.g2
        }
        try await Task.sleep(for: .milliseconds(120))
        let afterTapPointStep = try #require(preview.zoomSnapshot)
        #expect(abs(afterTapPointStep.anchor.x - 0.42) < 0.02)
        #expect(abs(afterTapPointStep.anchor.y - 0.58) < 0.02)

        // 2. Return to Fit, move to g3 (no focus regions), double-tap in .zoomToFocus mode:
        //    stepping to g2 preserves the tapped anchor without snapping to g2's AF.
        preview.onDoubleTap?(.center)
        try await waitFor("returned to Fit") { !preview.isZoomed }
        store.update { $0.doubleTap = .zoomToFocus }
        browsing.selectGroupPhoto(context.g3)
        try await waitFor("g3 settled") {
            source.prefetched.last?.current.photo == context.g3
                && source.finishedAnalysisPhotos.contains(context.g3)
        }
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.42, y: 0.58)))
        try await waitFor("g3 zoomed to tap point") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(120))

        browsing.selectGroupPhoto(context.g2)
        try await waitFor("g2 kept fixed anchor from no-region double-tap") {
            source.prefetched.last?.current.photo == context.g2
        }
        try await Task.sleep(for: .milliseconds(120))
        let afterNoRegionStep = try #require(preview.zoomSnapshot)
        #expect(abs(afterNoRegionStep.anchor.x - 0.42) < 0.02)
        #expect(abs(afterNoRegionStep.anchor.y - 0.58) < 0.02)
    }

    private func makeGroupFocusTrackingContext() -> (
        browsing: BrowsingModel,
        source: GroupFocusTrackingDetailImages,
        group: BrowsingGroup,
        g1: PhotoIdentity,
        g2: PhotoIdentity,
        g3: PhotoIdentity,
        g4: PhotoIdentity,
        outside: PhotoIdentity
    ) {
        let folder = FolderIdentity(rawValue: "group-focus-tracking-tests")
        func makeID(_ stem: String) -> PhotoIdentity {
            PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: stem)
        }
        let g1ID = makeID("GFT_0001")
        let g2ID = makeID("GFT_0002")
        let g3ID = makeID("GFT_0003")
        let g4ID = makeID("GFT_0004")
        let outsideID = makeID("GFT_0005")
        let base = Date(timeIntervalSince1970: 1_760_100_000)
        let photos = [
            GridPhoto(
                id: g1ID, fileName: "GFT_0001.ARW",
                time: .known(PhotoTime(captureTime: base, hasUTCOffset: true)),
                marks: PhotoMarks(rating: Rating(rawValue: 4)!)),
            GridPhoto(
                id: g2ID, fileName: "GFT_0002.ARW",
                time: .known(
                    PhotoTime(captureTime: base.addingTimeInterval(1), hasUTCOffset: true)),
                marks: PhotoMarks()),
            GridPhoto(
                id: g3ID, fileName: "GFT_0003.ARW",
                time: .known(
                    PhotoTime(captureTime: base.addingTimeInterval(2), hasUTCOffset: true)),
                marks: PhotoMarks()),
            GridPhoto(
                id: g4ID, fileName: "GFT_0004.ARW",
                time: .known(
                    PhotoTime(captureTime: base.addingTimeInterval(3), hasUTCOffset: true)),
                marks: PhotoMarks()),
            GridPhoto(
                id: outsideID, fileName: "GFT_0005.ARW",
                time: .known(
                    PhotoTime(captureTime: base.addingTimeInterval(10), hasUTCOffset: true)),
                marks: PhotoMarks()),
        ]
        let group = BrowsingGroup(
            id: GroupID(rawValue: "burst-gft"), members: [g1ID, g2ID, g3ID, g4ID])
        let source = GroupFocusTrackingDetailImages(
            g1: g1ID, g2: g2ID, g3: g3ID, g4: g4ID, outside: outsideID)
        let library = TestLibrary(photos: photos, groups: [group], detailImages: source)
        let browsing = BrowsingModel(library: library)
        return (browsing, source, group, g1ID, g2ID, g3ID, g4ID, outsideID)
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
        try await waitFor { !browsing.isFolderOpening }
        let photos = browsing.photos
        // MMQ02682, MMQ02683, MMQ02684 are consecutive standalone Timeline slots (#304).
        browsing.openPhoto(photos[4].id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == photos[4].id }
        let preview = try #require(findPreview(in: window))
        let stepTravel = -max(180, preview.bounds.width * 0.3)
        try sendSwipe(to: preview, travel: CGPoint(x: stepTravel, y: 0))
        #expect(browsing.state.currentPhoto == photos[5].id)
        try await Task.sleep(for: .milliseconds(100))
        try sendSwipe(to: preview, travel: CGPoint(x: stepTravel, y: 0))
        #expect(browsing.state.currentPhoto == photos[6].id)
        try await Task.sleep(for: .milliseconds(100))
        try sendSwipe(to: preview, travel: CGPoint(x: 0, y: -130))
        #expect(browsing.shownMarks(for: photos[6].id).rating != .unrated)
        #expect(browsing.shownMarks(for: photos[5].id) == photos[5].marks)
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
        try await waitFor { !browsing.isFolderOpening }
        let photos = browsing.photos
        // MMQ02683 and MMQ02684 are consecutive standalone Timeline slots (#304).
        browsing.openPhoto(photos[5].id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor { source.prefetched.last?.current.photo == photos[5].id }
        let preview = try #require(findPreview(in: window))
        try sendSwipe(to: preview, travel: CGPoint(x: 0, y: -130))
        #expect(browsing.shownMarks(for: photos[5].id).rating != .unrated)
        try await Task.sleep(for: .milliseconds(100))
        let pan = DetailTestPan()
        pan.travel = CGPoint(x: -15, y: 0)
        try #require(preview.gestureRecognizerShouldBegin(pan))
        preview.handleMarkingPan(pan)
        try await Task.sleep(for: .milliseconds(350))
        #expect(browsing.state.currentPhoto == photos[5].id)
        pan.travel = CGPoint(x: -max(180, preview.bounds.width * 0.3), y: 0)
        pan.sampleState = .ended
        preview.handleMarkingPan(pan)
        #expect(browsing.state.currentPhoto == photos[6].id)
        try await Task.sleep(for: .milliseconds(350))
        #expect(browsing.state.currentPhoto == photos[6].id)
    }

    @Test func clearingMarksInDetailScreenStaysWithoutAutoAdvanceWhilePositiveMarksAdvance()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        store.update {
            $0.autoAdvance.destination = .nextPhoto
            $0.autoAdvance.triggers.rating = true
            $0.autoAdvance.triggers.reject = true
            $0.autoAdvance.triggers.colourLabel = true
        }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor { !browsing.isFolderOpening }
        let photos = browsing.photos
        let three = try #require(Rating(rawValue: 3))
        // MMQ02683 (photos[5]) and MMQ02684 (photos[6]) are consecutive standalone Timeline slots.
        browsing.apply(.rating(three), to: photos[5].id)
        browsing.apply(.label(ColourLabel(colour: .red)), to: photos[5].id)
        browsing.openPhoto(photos[5].id)

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
            source.prefetched.last?.current.photo == photos[5].id
                && findPreview(in: window)?.currentRating == three
        }
        let preview = try #require(findPreview(in: window))
        let markingPan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? DetailSingleFingerPanGestureRecognizer }
                .first)

        func sendVerticalSwipe(_ travelY: CGFloat) throws {
            let start = CGPoint(x: 195, y: 300)
            _ = preview.gestureRecognizer(
                markingPan, shouldReceive: DetailMutableTouch(view: preview, location: start))
            let pan = DetailTestPan()
            let initialY: CGFloat = travelY < 0 ? -15 : 15
            pan.travel = CGPoint(x: 0, y: initialY)
            pan.locationPoint = CGPoint(x: start.x, y: start.y + initialY)
            try #require(preview.gestureRecognizerShouldBegin(pan))
            preview.handleMarkingPan(pan)
            pan.sampleState = .changed
            pan.travel = CGPoint(x: 0, y: travelY)
            pan.locationPoint = CGPoint(x: start.x, y: start.y + travelY)
            preview.handleMarkingPan(pan)
            pan.sampleState = .ended
            preview.handleMarkingPan(pan)
        }

        // 1. Swiping down to clear rating to .unrated stays on photos[5] in Timeline.
        try sendVerticalSwipe(50)
        #expect(browsing.shownMarks(for: photos[5].id).rating == .unrated)
        #expect(browsing.shownMarks(for: photos[5].id).label.colour == .red)
        try await Task.sleep(for: .milliseconds(450))
        #expect(browsing.state.currentPhoto == photos[5].id)

        // 2. Swiping up from Rejected to .unrated stays on photos[5].
        browsing.apply(.rating(.rejected), to: photos[5].id)
        try await waitFor { preview.currentRating == .rejected }
        try sendVerticalSwipe(-32)
        #expect(browsing.shownMarks(for: photos[5].id).rating == .unrated)
        try await Task.sleep(for: .milliseconds(450))
        #expect(browsing.state.currentPhoto == photos[5].id)

        // 3. Clearing rating inside Group Focus also stays without advancing or exiting Group Focus.
        let group = try #require(browsing.groups.first)
        let rep = group.members[0]
        browsing.apply(.rating(three), to: rep)
        browsing.openGroup(group.id, on: rep)
        try await waitFor {
            browsing.expandedGroup == group.id && source.prefetched.last?.current.photo == rep
                && preview.currentRating == three
        }
        try sendVerticalSwipe(50)
        #expect(browsing.shownMarks(for: rep).rating == .unrated)
        try await Task.sleep(for: .milliseconds(450))
        #expect(browsing.state.currentPhoto == rep)
        #expect(browsing.expandedGroup == group.id)

        // 4. Positive mark in Timeline still auto-advances after the pause.
        browsing.collapseGroup()
        browsing.openPhoto(photos[5].id)
        try await waitFor {
            browsing.expandedGroup == nil && source.prefetched.last?.current.photo == photos[5].id
                && preview.currentRating == .unrated
        }
        try sendVerticalSwipe(-130)
        #expect(browsing.shownMarks(for: photos[5].id).rating != .unrated)
        try await waitFor { browsing.state.currentPhoto == photos[6].id }
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
        try await waitFor { !browsing.isFolderOpening }
        let first = browsing.photos[4]
        let next = browsing.photos[5]
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
            rootView: DetailScreen(
                browsing: browsing, images: source, initialPresentation: .focus
            )
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

    /// #305: the finishing pill is not part of the filmstrip's layout, so its availability and the
    /// fit–zoom transitions never resize the stage or move the fitted photo. The pill floats over
    /// the stage, above the strip, which is where the chrome already is.
    @Test(arguments: [CloveTheme.light, CloveTheme.dark, CloveTheme.nord])
    func finishingPillNeverResizesTheStageOrMovesTheFit(theme: CloveTheme) async throws {
        for portrait in [false, true] {
            try await expectStageInvariance(theme: theme, portrait: portrait, duo: false)
        }
    }

    /// The same for the Duo cover, whose chrome is a dock below the stage: the pill floats over the
    /// stage's bottom edge, the dock keeps its height, and a marking swipe's star bar is kept above
    /// the pill (#305).
    @Test(arguments: [CloveTheme.light, CloveTheme.dark, CloveTheme.nord])
    func duoPaneFinishingPillNeverResizesTheStage(theme: CloveTheme) async throws {
        guard #available(iOS 27.1, *) else { return }
        for portrait in [false, true] {
            try await expectStageInvariance(theme: theme, portrait: portrait, duo: true)
        }
    }

    /// The star bar's reservation, which the Duo pane used to pass as 0: a low central marking swipe
    /// could then put its bar on the floating pill (#305).
    @Test func duoPaneReservesTheFloatingPillInTheSwipeFeedback() {
        let band: CGFloat = 134
        #expect(
            DetailMarkingView.swipeFeedbackReservation(
                floatingPillInStage: true, pillVisible: true, pillHeight: 38, pillGap: 6,
                measuredBand: band) == 44)
        #expect(
            DetailMarkingView.swipeFeedbackReservation(
                floatingPillInStage: true, pillVisible: false, pillHeight: 38, pillGap: 6,
                measuredBand: band) == 0)
        // The standard layout's chrome floats inside the stage and measures its own band, pill
        // included, so its value passes straight through.
        #expect(
            DetailMarkingView.swipeFeedbackReservation(
                floatingPillInStage: false, pillVisible: true, pillHeight: 38, pillGap: 6,
                measuredBand: band) == band)
    }

    /// Builds one detail host and records the stage, the fitted photo and the strip's band at fit,
    /// at 100% and after the group finishes (#305).
    private func expectStageInvariance(
        theme: CloveTheme, portrait: Bool, duo: Bool
    ) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = PortraitDetailImages(sample: SampleDetailImages(), portrait: portrait)
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let group = try #require(browsing.groups.first)
        browsing.openGroup(group.id, on: group.members[0])
        browsing.apply(.rating(try #require(Rating(rawValue: 2))), to: group.members[0])
        let plan = try #require(
            finishingPlan(for: group, currentPhoto: group.members[0], in: browsing))
        #expect(plan.availability == .available)

        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(
            origin: .zero,
            size: duo ? CGSize(width: 466, height: 678) : CGSize(width: 402, height: 874))
        window.rootViewController = UIHostingController(
            rootView: detailHost(browsing: browsing, images: source, duo: duo)
                .environment(store)
                .environment(\.cloveTheme, theme)
                .environment(\.usesSystemBrowsingToolbar, duo)
                .environment(\.isDuoCover, duo))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("detail did not settle") {
            guard source.delivered, let preview = self.findPreview(in: window),
                let photo = self.fittedPhotoRect(in: preview, window: window)
            else { return false }
            // The placeholder is landscape; wait for the delivered raster so the geometry below is
            // the photo's own shape.
            return portrait ? photo.height > photo.width : photo.width > photo.height
        }
        let preview = try #require(findPreview(in: window))
        let fit = try #require(stageGeometry(in: window))
        let stripAtFit = try #require(fit.strip)
        let photoAtFit = try #require(fit.photo)
        // The strip keeps one band: the pill no longer adds a row to it (#305). The Duo dock's
        // scroll view reaches into the bottom safe area, so its absolute height differs there; its
        // own constancy is checked below.
        if !duo {
            #expect(abs(stripAtFit.height - 70) <= 1)
        }
        if duo {
            // The dock still starts at the stage's bottom edge, so the stage and the dock are both
            // at their full height with the pill floating over the stage.
            #expect(abs(stripAtFit.minY - fit.stage.maxY) <= 1)
        }

        // 100% keeps the stage and the strip's band where they were (#302, #305).
        preview.onDoubleTap?(.center)
        try await waitFor("zoom did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))
        let zoomed = try #require(stageGeometry(in: window))
        #expect(sameFrame(zoomed.stage, fit.stage))
        #expect(sameFrame(zoomed.strip, fit.strip))

        // Returning to fit restores the same stage and the same fitted photo.
        preview.onDoubleTap?(.center)
        try await waitFor("fit did not settle") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))
        let refit = try #require(stageGeometry(in: window))
        #expect(sameFrame(refit.stage, fit.stage))
        #expect(sameFrame(refit.photo, photoAtFit))

        // Finishing the group removes the pill and leaves the stage, the fit and the strip as they
        // were. Before #305 the pill's own row in the filmstrip changed this stage's height.
        browsing.runGroupFinishing(plan)
        try await waitFor("finishing did not settle") {
            guard
                let current = self.finishingPlan(
                    for: group, currentPhoto: group.members[0], in: browsing)
            else { return true }
            return current.isEmpty || !current.availability.isAvailable
        }
        try await Task.sleep(for: .milliseconds(450))
        let finished = try #require(stageGeometry(in: window))
        #expect(sameFrame(finished.stage, fit.stage))
        #expect(sameFrame(finished.photo, photoAtFit))
        #expect(sameFrame(finished.strip, stripAtFit))
    }

    /// The screen for one host: the standard header layout, or the Duo pane's docked filmstrip.
    @ViewBuilder private func detailHost(
        browsing: BrowsingModel, images: any DetailImageSource, duo: Bool
    ) -> some View {
        if duo, #available(iOS 27.1, *) {
            NavigationStack {
                DetailScreen(
                    browsing: browsing, images: images,
                    duo: DuoDetailLayout(
                        presentation: .constant(.focus), filter: AnyView(EmptyView()),
                        more: AnyView(EmptyView()), bottom: AnyView(EmptyView()),
                        showsGrid: true))
            }
        } else {
            NavigationStack {
                DetailScreen(browsing: browsing, images: images, presentation: .constant(.focus))
            }
        }
    }

    /// Whether two rects describe the same place, to within half a point: the fitted photo's rect
    /// comes from the raster's aspect and lands on fractional points.
    private func sameFrame(_ first: CGRect?, _ second: CGRect?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        return abs(first.minX - second.minX) <= 0.5 && abs(first.minY - second.minY) <= 0.5
            && abs(first.width - second.width) <= 0.5 && abs(first.height - second.height) <= 0.5
    }

    /// Where the stage, the fitted photo and the strip's band are, for the checks above.
    private struct StageGeometry {
        let stage: CGRect
        let photo: CGRect?
        let strip: CGRect?
    }

    private func stageGeometry(in window: UIWindow) -> StageGeometry? {
        guard let preview = findPreview(in: window) else { return nil }
        let strip = findFilmstripScrollView(in: window, excluding: preview)
        return StageGeometry(
            stage: preview.convert(preview.bounds, to: window),
            photo: fittedPhotoRect(in: preview, window: window),
            strip: strip.map { $0.convert($0.bounds, to: window) })
    }

    /// #302: the double-tap target follows the setting, and `Off` disables the gesture.
    @Test func doubleTapTargetFollowsTheSetting() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedFocusDetailImages()
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        browsing.showsFocusRegions = true
        let target = try #require(browsing.photos.first { $0.id.stem == "mmq02678" })
        browsing.openPhoto(target.id)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitFor("preview loaded") { source.prefetched.last?.current.photo == target.id }
        let preview = try #require(findPreview(in: window))
        try await waitFor("focus regions presented") { findFocusControl(in: preview) != nil }

        // Zoom to focus (the default) centres 100% on the presented AF region.
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.6)))
        try await waitFor("focus zoom") { preview.isZoomed }
        let focusAnchor = try #require(preview.zoomSnapshot).anchor
        #expect(abs(focusAnchor.x - 0.30) < 0.05)
        #expect(abs(focusAnchor.y - 0.35) < 0.05)
        preview.onDoubleTap?(.center)
        try await waitFor("fit before off") { !preview.isZoomed }

        // Off disables the double tap; its recognizer turning off marks the setting reaching the
        // view, so the tap below is one the screen has already refused.
        store.update { $0.doubleTap = .off }
        try await waitFor("double tap recognizer off") { !preview.doubleTapIsEnabled }
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.6)))
        try await Task.sleep(for: .milliseconds(250))
        #expect(!preview.isZoomed)

        // Zoom to tap point centres the same tap on the tapped image point instead; the recognizer
        // returning marks the setting reaching the view.
        store.update { $0.doubleTap = .zoomToTapPoint }
        try await waitFor("double tap recognizer back") { preview.doubleTapIsEnabled }
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.6)))
        try await waitFor("tap point zoom") { preview.isZoomed }
        let tapAnchor = try #require(preview.zoomSnapshot).anchor
        #expect(abs(tapAnchor.x - 0.5) < 0.02)
        #expect(abs(tapAnchor.y - 0.6) < 0.02)
        preview.onDoubleTap?(.center)
        try await waitFor("fit before region tap") { !preview.isZoomed }

        // An actionable region tap still inspects that region in every mode.
        let control = try #require(findFocusControl(in: preview))
        control.sendActions(for: .touchUpInside)
        try await waitFor("region zoom") { preview.isZoomed }
        let regionAnchor = try #require(preview.zoomSnapshot).anchor
        #expect(abs(regionAnchor.x - 0.30) < 0.05)
        #expect(abs(regionAnchor.y - 0.35) < 0.05)
    }

    @Test func tapsAreUniformAcrossEdgesAndZoomedHorizontalSwipesSwitchPhotos() throws {
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

        // A zoomed one-finger horizontal drag keeps the fit navigation in the default mode.
        var steps = 0
        preview.onStep = { _ in steps += 1 }
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
        let zoomedPan = DetailTestPan()
        zoomedPan.travel = CGPoint(x: -180, y: 0)
        try #require(preview.gestureRecognizerShouldBegin(zoomedPan))
        preview.handleMarkingPan(zoomedPan)
        zoomedPan.sampleState = .ended
        preview.handleMarkingPan(zoomedPan)
        #expect(steps == 1)
    }

    @Test func zoomedGestureAvailabilityFollowsModeZoomAndGesturesEnabled() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.setImage(try testPixels(gray: 0))
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        let scroll = try #require(preview.subviews.first as? UIScrollView)

        func applySettings(mode: ZoomedGestures, gesturesEnabled: Bool) {
            var settings = AppSettings()
            settings.zoomedGestures = mode
            settings.gesturesEnabled = gesturesEnabled
            preview.rules = MarkingInputRules(settings: settings)
        }

        // At fit: 1-finger pan enabled (navigation still lives there), 2-finger zoomed swipe off,
        // chrome tap on, and the scroll view pans with one finger in every zoomed mode.
        for mode in ZoomedGestures.allCases {
            for gesturesEnabled in [true, false] {
                applySettings(mode: mode, gesturesEnabled: gesturesEnabled)
                #expect(!preview.isZoomed)
                #expect(preview.chromeTapIsEnabled)
                #expect(preview.markingPanIsEnabled)
                #expect(!preview.twoFingerMarkingSwipeIsEnabled)
                #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 1)
            }
        }

        // While zoomed: recognizers follow `zoomedGestures` and `gesturesEnabled`, while chrome tap
        // stays on.
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
        #expect(preview.isZoomed)
        #expect(preview.chromeTapIsEnabled)

        applySettings(mode: .rateAndSwitch, gesturesEnabled: true)
        #expect(preview.markingPanIsEnabled)
        #expect(!preview.twoFingerMarkingSwipeIsEnabled)
        // Two-finger drags pan and pinch, so a single-finger drag keeps its culling actions.
        #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 2)
        #expect(
            !preview.gestureRecognizer(
                preview.twoFingerSwipeRecognizer,
                shouldBeRequiredToFailBy: scroll.panGestureRecognizer))

        applySettings(mode: .pan, gesturesEnabled: true)
        #expect(!preview.markingPanIsEnabled)
        #expect(preview.twoFingerMarkingSwipeIsEnabled)
        #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 1)
        #expect(
            preview.gestureRecognizer(
                preview.twoFingerSwipeRecognizer,
                shouldBeRequiredToFailBy: scroll.panGestureRecognizer))

        // Marking gestures off stops vertical input; horizontal switching stays live in
        // `.rateAndSwitch`, exactly as it does at fit.
        applySettings(mode: .rateAndSwitch, gesturesEnabled: false)
        #expect(preview.markingPanIsEnabled)
        #expect(!preview.twoFingerMarkingSwipeIsEnabled)
        let verticalOff = DetailTestPan()
        verticalOff.travel = CGPoint(x: 0, y: -40)
        #expect(!preview.gestureRecognizerShouldBegin(verticalOff))
        let horizontal = DetailTestPan()
        horizontal.travel = CGPoint(x: -60, y: 2)
        #expect(preview.gestureRecognizerShouldBegin(horizontal))

        applySettings(mode: .rateAndSwitch, gesturesEnabled: true)
        let verticalOn = DetailTestPan()
        verticalOn.travel = CGPoint(x: 0, y: -40)
        #expect(preview.gestureRecognizerShouldBegin(verticalOn))
        #expect(preview.gestureRecognizerShouldBegin(horizontal))

        // `.pan` leaves one-finger drags to the scroll view, with or without marking gestures.
        for gesturesEnabled in [true, false] {
            applySettings(mode: .pan, gesturesEnabled: gesturesEnabled)
            #expect(!preview.markingPanIsEnabled)
            #expect(preview.twoFingerMarkingSwipeIsEnabled == gesturesEnabled)
            #expect(
                preview.gestureRecognizerShouldBegin(preview.twoFingerSwipeRecognizer)
                    == gesturesEnabled)
            let vertical = DetailTestPan()
            vertical.travel = CGPoint(x: 0, y: -40)
            #expect(!preview.gestureRecognizerShouldBegin(vertical))
        }

        // Returning to fit restores fit availability.
        applySettings(mode: .pan, gesturesEnabled: true)
        preview.apply(DetailZoomCommand(id: 2, kind: .fit))
        #expect(!preview.isZoomed)
        #expect(preview.chromeTapIsEnabled)
        #expect(preview.markingPanIsEnabled)
        #expect(!preview.twoFingerMarkingSwipeIsEnabled)
        #expect(scroll.panGestureRecognizer.minimumNumberOfTouches == 1)
    }

    @Test func zoomedPanTwoFingerSwipeRatesWithoutPinchAndPinchNeverRates() throws {
        func makeZoomedPreview() throws -> (
            preview: DetailZoomContainerView,
            feedback: DetailSwipeFeedback,
            twoFingerCommits: () -> [Rating],
            singleFingerCommits: () -> [Rating]
        ) {
            let preview = DetailZoomContainerView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 650))
            preview.setImage(try testPixels(gray: 0))
            var settings = AppSettings()
            settings.zoomedGestures = .pan
            preview.rules = MarkingInputRules(settings: settings)
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

            // While zoomed in `.pan`, two-finger marking requires priority over scroll pinch/pan
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

        // Single-finger vertical drag while zoomed in `.pan` fails two-finger swipe so scroll pan runs.
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

    @Test func anchorSymmetricSwipeWorksConsistentlyAtFitAndZoomedTwoFinger() throws {
        // Fit single-finger drag: immediate preview from first movement at H = 650 (rejectTravel = 65pt).
        do {
            let preview = DetailZoomContainerView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 650))
            preview.setImage(try testPixels(gray: 0))
            preview.setNeedsLayout()
            preview.layoutIfNeeded()
            let feedback = DetailSwipeFeedback()
            preview.feedback = feedback
            preview.currentRating = .unrated
            var commits: [Rating] = []
            preview.onMarkingSwipe = { commits.append($0) }

            let pan = try #require(
                preview.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
            let start = CGPoint(x: 195, y: 400)
            _ = preview.gestureRecognizer(
                pan, shouldReceive: DetailMutableTouch(view: preview, location: start))
            let testPan = DetailTestPan()
            testPan.locationPoint = CGPoint(x: 195, y: 470)
            testPan.travel = CGPoint(x: 0, y: 70)
            try #require(preview.gestureRecognizerShouldBegin(testPan))
            preview.handleMarkingPan(testPan)
            #expect(feedback.rating == .rejected)
            testPan.sampleState = .ended
            preview.handleMarkingPan(testPan)
            #expect(commits == [.rejected])
        }

        // Zoomed two-finger drag in `.pan` from 3★ at H = 650 (clear = 32.5pt, reject = 65pt, two-step = 97.5pt, upEntry = 19.5pt).
        do {
            let three = try #require(Rating(rawValue: 3))
            let preview = DetailZoomContainerView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 650))
            preview.setImage(try testPixels(gray: 0))
            var settings = AppSettings()
            settings.zoomedGestures = .pan
            preview.rules = MarkingInputRules(settings: settings)
            preview.setNeedsLayout()
            preview.layoutIfNeeded()
            preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))
            let feedback = DetailSwipeFeedback()
            preview.feedback = feedback
            preview.currentRating = three
            var commits: [Rating] = []
            preview.onTwoFingerMarkingSwipe = { commits.append($0) }

            let twoFinger = preview.twoFingerSwipeRecognizer
            let t1 = DetailMutableTouch(view: preview, location: CGPoint(x: 150, y: 400))
            let t2 = DetailMutableTouch(view: preview, location: CGPoint(x: 230, y: 400))
            let event = UIEvent()
            twoFinger.touchesBegan([t1, t2], with: event)

            t1.locationPoint = CGPoint(x: 150, y: 436)
            t2.locationPoint = CGPoint(x: 230, y: 436)
            twoFinger.touchesMoved([t1, t2], with: event)
            #expect(twoFinger.state == .began)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            #expect(feedback.rating == .unrated)

            t1.locationPoint = CGPoint(x: 150, y: 525)
            t2.locationPoint = CGPoint(x: 230, y: 525)
            twoFinger.touchesMoved([t1, t2], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            #expect(feedback.rating == .rejected)

            t1.locationPoint = CGPoint(x: 150, y: 370)
            t2.locationPoint = CGPoint(x: 230, y: 370)
            twoFinger.touchesMoved([t1, t2], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            #expect(feedback.rating?.rawValue == 4)

            t1.locationPoint = CGPoint(x: 150, y: 400)
            t2.locationPoint = CGPoint(x: 230, y: 400)
            twoFinger.touchesMoved([t1, t2], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            #expect(feedback.rating == three)

            twoFinger.touchesEnded([t1], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            #expect(commits == [three])
        }
    }

    @Test func zoomedRateAndSwitchVerticalRatesAndHorizontalSwitchesWithoutPanning() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        preview.setImage(try testPixels(gray: 0))
        preview.hasPrevious = true
        preview.hasNext = true
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        // The launch default keeps the fit split while zoomed.
        preview.rules = MarkingInputRules(settings: AppSettings())
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: .center)))

        var commits: [Rating] = []
        var steps = 0
        preview.onMarkingSwipe = { commits.append($0) }
        preview.onStep = { steps += $0 }

        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let scrollPan = scroll.panGestureRecognizer
        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? DetailSingleFingerPanGestureRecognizer }
                .first)
        #expect(pan.isEnabled)
        #expect(!preview.twoFingerSwipeRecognizer.isEnabled)
        // The scroll view's own pan waits for a second finger, so a one-finger drag never pans; the
        // marking pan is not made to wait for it either.
        #expect(scrollPan.minimumNumberOfTouches == 2)
        #expect(!preview.gestureRecognizer(pan, shouldBeRequiredToFailBy: scrollPan))
        #expect(!preview.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: scrollPan))

        // Two touches immediately fail DetailSingleFingerPanGestureRecognizer so two-finger pan and
        // pinch do not stall, and they never rate or switch.
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

        // Horizontal single-finger start switches photos on release instead of panning the photo.
        let horizontalStart = CGPoint(x: 300, y: 325)
        let horizontal = DetailTestPan()
        horizontal.locationPoint = horizontalStart
        _ = preview.gestureRecognizer(
            pan, shouldReceive: DetailMutableTouch(view: preview, location: horizontalStart))
        horizontal.travel = CGPoint(x: -20, y: 2)
        try #require(preview.gestureRecognizerShouldBegin(horizontal))
        preview.handleMarkingPan(horizontal)
        horizontal.sampleState = .changed
        horizontal.travel = CGPoint(x: -200, y: 4)
        horizontal.locationPoint = CGPoint(x: 100, y: 325)
        preview.handleMarkingPan(horizontal)
        horizontal.sampleState = .ended
        preview.handleMarkingPan(horizontal)
        #expect(steps == 1)
        #expect(commits.count == 1)
    }

    @Test func zoomedGesturesAutoAdvanceAndReturnToFitInDetailScreen() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        store.update {
            $0.zoomedGestures = .pan
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
        try #require(preview.gestureRecognizerShouldBegin(preview.twoFingerSwipeRecognizer))
        let twoFinger = DetailTestTwoFingerSwipe()
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

        // Switch to rate & switch while zoomed and verify a one-finger vertical drag rates,
        // auto-advances, and returns to fit.
        store.update { $0.zoomedGestures = .rateAndSwitch }
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
        try await waitFor { !browsing.isFolderOpening }
        let photos = browsing.photos
        try #require(photos.count >= 9)
        // MMQ02684 (photos[6]) is standalone with consecutive standalone Timeline slots on both sides.
        let current = photos[6]
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
        #expect(recorded.neighbours.map(\.photo) == [photos[5].id, photos[7].id])
        #expect(
            recorded.previewNeighbours.map(\.photo) == [
                photos[7].id, photos[5].id, photos[8].id, photos[4].id,
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
        try await waitFor { !mappedBrowsing.isFolderOpening }
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
        // MMQ02682 and MMQ02683 are adjacent Timeline slots, so navigating between them hits warmImage.
        mappedBrowsing.openPhoto(photos[4].id)
        directWindow.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: mappedBrowsing, images: spy)
                .environment(SettingsStore.sample))
        directWindow.makeKeyAndVisible()
        defer {
            directWindow.isHidden = true
            directWindow.rootViewController = nil
        }
        try await waitFor { spy.prefetched.last?.current.photo == photos[4].id }
        let preview = try #require(findPreview(in: directWindow))
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let imageView = try #require(scroll.subviews.first as? UIImageView)
        try #require(imageView.image?.cgImage != nil)

        // Swiping to warm neighbour photos[5] hits warmImage synchronously and never flashes nil or requests placeholder.
        mappedBrowsing.openPhoto(photos[5].id)
        #expect(!spy.placeholderPhotos.contains(photos[5].id))
        try await waitFor { spy.warmHits.contains(photos[5].id) && imageView.image?.cgImage != nil }
        #expect(!spy.placeholderPhotos.contains(photos[5].id))
        try await waitFor { spy.prefetched.last?.current.photo == photos[5].id }
    }

    @Test func duoFocusSplitDoubleTapAndRegionTapKeepZoomCentredOnFocusRegion()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
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
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
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

        // 1. Double-tapping the photo body away from the AF region centres 100% on AF, and the
        // chrome stays where it was, so the preview container keeps its size (#302).
        let heightBefore = preview.bounds.height
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.6)))
        try await waitFor { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))
        #expect(preview.bounds.height == heightBefore)
        let doubleTapSnapshot = try #require(preview.zoomSnapshot)
        #expect(abs(doubleTapSnapshot.anchor.x - 0.30) < 0.01)
        #expect(abs(doubleTapSnapshot.anchor.y - 0.35) < 0.01)
        let accessibilityValue = try #require(
            preview.subviews.first(where: {
                $0.accessibilityIdentifier == "clove.detail.preview"
            })?.accessibilityValue)
        #expect(accessibilityValue.contains("centred at 30%, 35%"))

        // 2. Return to fit, then tap the AF control directly and verify it stays centred.
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.5)))
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

    @Test func duoFocusViewAndPortraitFocusResizeKeepFullResolutionScaleAndFocusAnchor()
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
        let presentation = Binding.constant(DetailPresentation.focus)
        let host = UIHostingController(
            rootView: NavigationStack {
                DetailScreen(
                    browsing: browsing,
                    duo: DuoDetailLayout(
                        presentation: presentation,
                        filter: AnyView(EmptyView()),
                        more: AnyView(EmptyView()),
                        bottom: AnyView(EmptyView()),
                        showsGrid: true))
            }
            .environment(store)
            .environment(\.isDuoExpanded, true)
            .environment(\.usesSystemBrowsingToolbar, true))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
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
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.5, y: 0.6)))
        try await waitFor { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(450))

        // Since #273, zooming alone leaves the Duo Focus View filmstrip visible so preview height
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

    @Test func widePadPhotoPreviewDefaultsAndTogglePreserveStateWithoutReloading() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedFocusDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let target = try #require(browsing.photos.first { $0.id.stem == "mmq02678" })
        let next = try #require(browsing.photos.first { $0.id.stem == "mmq02679" })
        browsing.openPhoto(target.id)

        let presentationBox = TestPresentationBox(value: .photoPreview)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let usesSystemToolbar =
            if #available(iOS 27.1, *) {
                true
            } else {
                false
            }
        let host = UIHostingController(
            rootView: TestDetailPresentationHost(
                browsing: browsing, images: source, presentation: presentationBox,
                usesSystemToolbar: usesSystemToolbar))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor {
            self.findCollectionView(in: window) != nil
                && source.prefetched.last?.current.photo == target.id
                && source.delivered.contains(.screenRAW)
                && source.analyzeCalls.count == 1
        }
        let preview = try #require(findPreview(in: window))
        let splitGrid = try #require(findCollectionView(in: window))
        #expect(findFilmstripScrollView(in: window, excluding: preview) == nil)
        #expect(abs(splitGrid.frame.width / 1024 - 0.3) < 0.03)
        #expect(
            DetailPresentationPolicy(
                isRegularWidth: true, isDuoExpanded: false, isDuoCover: false,
                hasFoldRegion: false, availableWidth: 1024, availableHeight: 768
            ).supportsPhotoPreview)

        // The grid toggle is a SwiftUI toolbar item, and a hosted unit test builds no
        // accessibility tree to reach it (#288). Drive the presentation binding the toggle sets;
        // CloveFlowTests covers the button's identifier, labels and values on an iPad destination.

        // Apply a mark and zoom to 100%, then toggle between Photo Preview and Focus View.
        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: target.id)
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.35, y: 0.4)))
        try await waitFor { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(350))
        let windowCountBeforeToggle = source.windows.count
        let requestCountBeforeToggle = source.requests.count
        let analyzeCountBeforeToggle = source.analyzeCalls.count
        let splitPreviewWidth = preview.bounds.width

        presentationBox.value = presentationBox.value.toggled
        try await waitFor {
            self.findCollectionView(in: window) == nil
                && self.findFilmstripScrollView(in: window, excluding: preview) != nil
                && preview.bounds.width > splitPreviewWidth
        }
        #expect(browsing.state.currentPhoto == target.id)
        #expect(browsing.shownMarks(for: target.id).rating == fourStars)
        #expect(browsing.canUndoMark)
        #expect(preview.isZoomed)
        #expect(source.windows.count == windowCountBeforeToggle)
        #expect(source.requests.count == requestCountBeforeToggle)
        #expect(source.analyzeCalls.count == analyzeCountBeforeToggle)

        // Navigating to another photo keeps Focus View.
        browsing.openPhoto(next.id)
        try await waitFor {
            browsing.state.currentPhoto == next.id
                && source.prefetched.last?.current.photo == next.id
        }
        #expect(findCollectionView(in: window) == nil)
        #expect(findFilmstripScrollView(in: window, excluding: preview) != nil)

        // Toggling back restores Photo Preview on the same photo without re-loading pixels.
        let windowCountBeforeRestore = source.windows.count
        let analyzeCountBeforeRestore = source.analyzeCalls.count
        presentationBox.value = presentationBox.value.toggled
        try await waitFor {
            self.findCollectionView(in: window) != nil
                && self.findFilmstripScrollView(in: window, excluding: preview) == nil
        }
        #expect(browsing.state.currentPhoto == next.id)
        #expect(source.windows.count == windowCountBeforeRestore)
        #expect(source.analyzeCalls.count == analyzeCountBeforeRestore)
    }

    @Test func narrowingFallsBackToFocusViewAndWideningRestoresPhotoPreview() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photo = try #require(browsing.photos.first?.id)
        browsing.openPhoto(photo)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let rootView: AnyView
        if #available(iOS 27.1, *) {
            rootView = AnyView(
                NavigationStack {
                    DetailScreen(browsing: browsing, images: source)
                }
                .environment(SettingsStore.sample)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.usesSystemBrowsingToolbar, true))
        } else {
            rootView = AnyView(
                DetailScreen(browsing: browsing, images: source)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveUserInterfaceIdiom, .pad))
        }
        let host = UIHostingController(rootView: rootView)
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor { self.findCollectionView(in: window) != nil }

        // Narrowing below 680 pt falls back to Focus View. The grid toggle hides with
        // `supportsPhotoPreview`; CloveCore's DetailPresentationTests and CloveFlowTests cover that.
        let narrowPolicy = DetailPresentationPolicy(
            isRegularWidth: true, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 600, availableHeight: 768)
        #expect(!narrowPolicy.supportsPhotoPreview)
        #expect(narrowPolicy.effectivePresentation(for: .photoPreview) == .focus)
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 768)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor {
            let preview = self.findPreview(in: window)
            return self.findCollectionView(in: window) == nil
                && preview != nil
                && self.findFilmstripScrollView(in: window, excluding: preview!) != nil
        }

        // Widening back restores Photo Preview.
        let widePolicy = DetailPresentationPolicy(
            isRegularWidth: true, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 1024, availableHeight: 768)
        #expect(widePolicy.supportsPhotoPreview)
        #expect(widePolicy.effectivePresentation(for: .photoPreview) == .photoPreview)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor {
            let preview = self.findPreview(in: window)
            return self.findCollectionView(in: window) != nil
                && preview != nil
                && self.findFilmstripScrollView(in: window, excluding: preview!) == nil
        }
    }

    @Test func expandedDuoToggleSwitchesBetweenPhotoPreviewAndFocusView() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photo = try #require(browsing.photos.first?.id)
        browsing.openPhoto(photo)

        let presentationBox = TestPresentationBox(value: .photoPreview)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let host = UIHostingController(
            rootView: TestDuoDetailHost(
                browsing: browsing, images: source, presentation: presentationBox))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("Expanded Duo Photo Preview did not settle") {
            let preview = self.findPreview(in: window)
            return preview != nil
                && self.findCollectionView(in: window) != nil
                && self.findFilmstripScrollView(in: window, excluding: preview!) == nil
        }

        // Drive the presentation binding the grid toggle sets (#288); CloveFlowTests covers the
        // button itself on a Duo or iPad destination.
        presentationBox.value = presentationBox.value.toggled

        try await waitFor("Expanded Duo Focus View did not settle") {
            let preview = self.findPreview(in: window)
            return presentationBox.value == .focus
                && preview != nil
                && self.findCollectionView(in: window) == nil
                && self.findFilmstripScrollView(in: window, excluding: preview!) != nil
        }
    }

    @Test
    func expandedDuoFocusToggleFloatsInPhotoViewportWithoutDuplicatesAcrossPresentationsAndPoses()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedFocusDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photo = try #require(browsing.photos.first { $0.id.stem == "mmq02678" }?.id)
        browsing.openPhoto(photo)

        let presentationBox = TestPresentationBox(value: .photoPreview)
        let headerFrames = DetailFrameBox()

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let host = UIHostingController(
            rootView: TestDuoPoseDetailHost(
                browsing: browsing,
                images: source,
                presentation: presentationBox,
                isDuoExpanded: true,
                isDuoCover: false,
                usesVerticalToolbar: true,
                hasFoldRegion: true,
                showsGrid: true,
                theme: .light
            )
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                headerFrames.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Photo Preview: expanded Duo reclaims the top header space for the photo viewport and
        // floats the focus toggle beside the viewport-pinned identity badge.
        try await waitFor("Expanded Duo Photo Preview viewport overlay did not settle") {
            let preview = self.findPreview(in: window)
            return preview != nil
                && self.findCollectionView(in: window) != nil
                && source.delivered.contains(.screenRAW)
                && self.findFocusControl(in: preview!) != nil
                && headerFrames.frames["clove.detail.photoCornerOverlay"] != nil
                && headerFrames.frames["clove.detail.focusToggle"] != nil
        }
        let splitGrid = try #require(findCollectionView(in: window))
        let previewInSplit = try #require(findPreview(in: window))
        let splitGridFrame = splitGrid.convert(splitGrid.bounds, to: window)
        let splitPreviewFrame = previewInSplit.convert(previewInSplit.bounds, to: window)
        let splitOverlayFrame = try #require(headerFrames.frames["clove.detail.photoCornerOverlay"])
        let splitFocusFrame = try #require(headerFrames.frames["clove.detail.focusToggle"])
        #expect(headerFrames.frames["clove.detail.photoHeader"] == nil)
        #expect(splitPreviewFrame.minX >= splitGridFrame.maxX - 1)
        #expect(abs(splitPreviewFrame.minY - splitGridFrame.minY) <= 4.0)
        #expect(abs(splitOverlayFrame.minX - (splitPreviewFrame.minX + 16)) <= 1.5)
        #expect(abs(splitOverlayFrame.minY - (splitPreviewFrame.minY + 12)) <= 1.5)
        #expect(splitFocusFrame.minX >= splitOverlayFrame.maxX + 6)
        #expect(abs(splitFocusFrame.minY - (splitPreviewFrame.minY + 12)) <= 1.5)
        #expect(splitFocusFrame.width >= 44 && splitFocusFrame.height >= 44)

        browsing.showsFocusRegions = false
        try await waitFor("Focus controls hid when toggled Off in Photo Preview") {
            guard let preview = self.findPreview(in: window) else { return false }
            return self.findAllFocusControls(in: preview).isEmpty
        }
        #expect(
            sameFrame(previewInSplit.convert(previewInSplit.bounds, to: window), splitPreviewFrame))
        browsing.showsFocusRegions = true
        try await waitFor("Focus controls returned when toggled On in Photo Preview") {
            guard let preview = self.findPreview(in: window) else { return false }
            return self.findFocusControl(in: preview) != nil
        }

        // Focus View: full-width photo viewport keeps the same upper-leading overlay without
        // restarting analysis.
        let analyzesBeforeFocus = source.analyzeCalls.count
        presentationBox.value = .focus
        try await waitFor("Expanded Duo Focus View viewport overlay did not settle") {
            let preview = self.findPreview(in: window)
            return preview != nil
                && self.findCollectionView(in: window) == nil
                && self.findFilmstripScrollView(in: window, excluding: preview!) != nil
                && self.findFocusControl(in: preview!) != nil
                && (headerFrames.frames["clove.detail.photoCornerOverlay"]?.minX
                    ?? .greatestFiniteMagnitude)
                    < splitOverlayFrame.minX - 40
        }
        #expect(source.analyzeCalls.count == analyzesBeforeFocus)
        let previewInFocus = try #require(findPreview(in: window))
        let focusPreviewFrame = previewInFocus.convert(previewInFocus.bounds, to: window)
        let focusOverlayFrame = try #require(headerFrames.frames["clove.detail.photoCornerOverlay"])
        let focusToggleFrame = try #require(headerFrames.frames["clove.detail.focusToggle"])
        #expect(headerFrames.frames["clove.detail.photoHeader"] == nil)
        #expect(abs(focusPreviewFrame.minY - splitPreviewFrame.minY) <= 1.5)
        #expect(focusPreviewFrame.minX < splitPreviewFrame.minX)
        #expect(abs(focusOverlayFrame.minX - (focusPreviewFrame.minX + 16)) <= 1.5)
        #expect(abs(focusOverlayFrame.minY - (focusPreviewFrame.minY + 12)) <= 1.5)
        #expect(focusToggleFrame.minX >= focusOverlayFrame.maxX + 6)
        #expect(abs(focusToggleFrame.minY - (focusPreviewFrame.minY + 12)) <= 1.5)

        // Pose transitions: Half-fold (no vertical toolbar) & Duo Cover remove the expanded
        // viewport overlay cleanly; returning to Expanded Duo Open pose restores it without losing
        // state.
        presentationBox.value = .photoPreview
        host.rootView = TestDuoPoseDetailHost(
            browsing: browsing,
            images: source,
            presentation: presentationBox,
            isDuoExpanded: true,
            isDuoCover: false,
            usesVerticalToolbar: false,
            hasFoldRegion: true,
            showsGrid: true,
            theme: .light
        )
        .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
            headerFrames.frames = $0
        }
        try await waitFor("Half-fold removed expanded viewport overlay") {
            self.findPreview(in: window) != nil
                && self.findCollectionView(in: window) != nil
                && headerFrames.frames["clove.detail.photoCornerOverlay"] == nil
        }

        host.rootView = TestDuoPoseDetailHost(
            browsing: browsing,
            images: source,
            presentation: presentationBox,
            isDuoExpanded: false,
            isDuoCover: true,
            usesVerticalToolbar: true,
            hasFoldRegion: false,
            showsGrid: false,
            theme: .light
        )
        .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
            headerFrames.frames = $0
        }
        host.traitOverrides.horizontalSizeClass = .compact
        try await waitFor("Duo Cover settled cleanly") {
            guard let preview = self.findPreview(in: window) else { return false }
            return self.findCollectionView(in: window) == nil
                && self.findFilmstripScrollView(in: window, excluding: preview) != nil
                && headerFrames.frames["clove.detail.photoCornerOverlay"] == nil
        }

        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        host.rootView = TestDuoPoseDetailHost(
            browsing: browsing,
            images: source,
            presentation: presentationBox,
            isDuoExpanded: true,
            isDuoCover: false,
            usesVerticalToolbar: true,
            hasFoldRegion: true,
            showsGrid: true,
            theme: .light
        )
        .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
            headerFrames.frames = $0
        }
        try await waitFor("Expanded Duo Open pose restored viewport overlay and focus controls") {
            guard let preview = self.findPreview(in: window),
                self.findCollectionView(in: window) != nil,
                headerFrames.frames["clove.detail.photoCornerOverlay"] != nil,
                headerFrames.frames["clove.detail.focusToggle"] != nil
            else { return false }
            return abs(preview.convert(preview.bounds, to: window).minY - splitPreviewFrame.minY)
                <= 1.5
                && self.findFocusControl(in: preview) != nil
        }
        #expect(browsing.showsFocusRegions)
    }

    @Test(arguments: [DetailPresentation.photoPreview, DetailPresentation.focus])
    func expandedDuoPortraitBlankAreaDoubleTapUsesCentreWhilePhotoEdgesUseTapPoint(
        initialPresentation: DetailPresentation
    ) async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = PortraitFocusDetailImages()
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let target = try #require(browsing.photos.first { $0.id.stem == "mmq02678" })
        browsing.openPhoto(target.id)

        let presentationBox = TestPresentationBox(value: initialPresentation)
        let overlayFrames = DetailFrameBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let host = UIHostingController(
            rootView: NavigationStack {
                DetailScreen(
                    browsing: browsing,
                    images: source,
                    duo: DuoDetailLayout(
                        presentation: Binding(
                            get: { presentationBox.value },
                            set: { presentationBox.value = $0 }),
                        filter: AnyView(EmptyView()),
                        more: AnyView(EmptyView()),
                        bottom: AnyView(EmptyView()),
                        showsGrid: true))
            }
            .environment(store)
            .environment(\.isDuoExpanded, true)
            .environment(\.usesSystemBrowsingToolbar, true)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                overlayFrames.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("portrait photo and focus region did not settle") {
            guard let preview = self.findPreview(in: window),
                source.delivered,
                self.findFocusControl(in: preview) != nil
            else { return false }
            let imageRect = preview.imageRectAtFit()
            let layoutMatches =
                initialPresentation == .photoPreview
                ? self.findCollectionView(in: window) != nil
                : self.findFilmstripScrollView(in: window, excluding: preview) != nil
            return layoutMatches
                && imageRect.height > imageRect.width
                && imageRect.minX > 40
                && preview.bounds.maxX - imageRect.maxX > 40
        }

        let preview = try #require(findPreview(in: window))
        let imageRect = preview.imageRectAtFit()
        if let cornerOverlay = overlayFrames.frames["clove.detail.photoCornerOverlay"] {
            let cornerCenterInWindow = CGPoint(x: cornerOverlay.midX, y: cornerOverlay.midY)
            let hitThroughCorner = window.hitTest(cornerCenterInWindow, with: nil)
            #expect(hitThroughCorner?.isDescendant(of: preview) == true)
        }
        let leftBlank = CGPoint(x: imageRect.minX * 0.3, y: preview.bounds.midY)
        let rightBlank = CGPoint(
            x: imageRect.maxX + (preview.bounds.maxX - imageRect.maxX) * 0.7,
            y: preview.bounds.midY)
        let nearLeftEdge = CGPoint(x: imageRect.minX + 4, y: preview.bounds.midY)
        let nearRightEdge = CGPoint(x: imageRect.maxX - 4, y: preview.bounds.midY)
        let topLeftStageEdge = CGPoint(x: 2, y: 2)
        let bottomRightStageEdge = CGPoint(
            x: preview.bounds.maxX - 2, y: preview.bounds.maxY - 2)

        // 1. Focus regions Off + Zoom to focus: blank pillarbox taps zoom to photo centre, while
        // taps inside the portrait near its real edges zoom to those edges; stage-edge double taps
        // return to fit.
        browsing.showsFocusRegions = false
        try await waitFor("focus regions did not hide") {
            self.findAllFocusControls(in: preview).isEmpty
        }

        preview.doubleTap(at: leftBlank)
        try await waitFor("left blank zoom did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let leftBlankAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(leftBlankAnchor.x - 0.5) < 0.05)
        #expect(abs(leftBlankAnchor.y - 0.5) < 0.05)

        preview.doubleTap(at: topLeftStageEdge)
        try await waitFor("return to fit from left blank zoom") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        preview.doubleTap(at: rightBlank)
        try await waitFor("right blank zoom did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let rightBlankAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(rightBlankAnchor.x - 0.5) < 0.05)
        #expect(abs(rightBlankAnchor.y - 0.5) < 0.05)

        preview.doubleTap(at: bottomRightStageEdge)
        try await waitFor("return to fit from right blank zoom") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        preview.doubleTap(at: nearLeftEdge)
        try await waitFor("near-left portrait edge zoom did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let nearLeftAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(nearLeftAnchor.x < 0.15)

        preview.doubleTap(at: topLeftStageEdge)
        try await waitFor("return to fit from near-left edge") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        preview.doubleTap(at: nearRightEdge)
        try await waitFor("near-right portrait edge zoom did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let nearRightAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(nearRightAnchor.x > 0.85)

        preview.doubleTap(at: bottomRightStageEdge)
        try await waitFor("return to fit from near-right edge") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        // 2. Focus regions On + Zoom to focus: blank-area double tap still prioritizes the off-center
        // AF region.
        browsing.showsFocusRegions = true
        try await waitFor("focus regions did not return") {
            self.findFocusControl(in: preview) != nil
        }
        preview.doubleTap(at: leftBlank)
        try await waitFor("focus-target zoom from blank area did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let focusAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(focusAnchor.x - 0.70) < 0.05)
        #expect(abs(focusAnchor.y - 0.30) < 0.05)

        preview.doubleTap(at: topLeftStageEdge)
        try await waitFor("return to fit from focus-target zoom") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        // 3. Off ignores double taps while single-tap chrome and direct region taps remain intact.
        store.update { $0.doubleTap = .off }
        try await waitFor("doubleTap off did not reach preview") { !preview.doubleTapIsEnabled }
        preview.doubleTap(at: leftBlank)
        preview.doubleTap(at: nearLeftEdge)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!preview.isZoomed)

        // 4. Zoom to tap point (even with Focus regions On): blank area uses centre; near-edge tap
        // inside photo uses the tapped edge. Wait for `doubleTapIsEnabled` returning from Off so
        // SwiftUI has delivered the updated setting to DetailMarkingView.
        store.update { $0.doubleTap = .zoomToTapPoint }
        try await waitFor("zoomToTapPoint setting") { preview.doubleTapIsEnabled }
        preview.doubleTap(at: rightBlank)
        try await waitFor("zoomToTapPoint blank area did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let tapPointBlankAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(tapPointBlankAnchor.x - 0.5) < 0.05)

        preview.doubleTap(at: bottomRightStageEdge)
        try await waitFor("return to fit from zoomToTapPoint blank area") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        preview.doubleTap(at: nearLeftEdge)
        try await waitFor("zoomToTapPoint near-left edge did not settle") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let tapPointNearLeftAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(tapPointNearLeftAnchor.x < 0.15)

        preview.doubleTap(at: topLeftStageEdge)
        try await waitFor("return to fit from zoomToTapPoint near-left") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(150))

        #expect(preview.chromeTapIsEnabled)
        if initialPresentation == .focus {
            preview.onChromeToggle?()
            try await waitFor("chrome toggle did not hide filmstrip") {
                self.findFilmstripScrollView(in: window, excluding: preview) == nil
            }
            preview.onChromeToggle?()
            try await waitFor("chrome toggle did not restore filmstrip") {
                self.findFilmstripScrollView(in: window, excluding: preview) != nil
            }
        }

        let afControl = try #require(findFocusControl(in: preview))
        afControl.sendActions(for: .touchUpInside)
        try await waitFor("direct region tap did not zoom") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let directRegionAnchor = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(directRegionAnchor.x - 0.70) < 0.05)
        #expect(abs(directRegionAnchor.y - 0.30) < 0.05)
    }

    @Test func expandedDuoFocusOffSurvivesNavigationPresentationSwitchAndLateCallbacks()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = GatedLateFocusDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let first = try #require(browsing.photos.first { $0.id.stem == "mmq02678" }?.id)
        let second = try #require(browsing.photos.first { $0.id.stem == "mmq02683" }?.id)
        browsing.openPhoto(first)

        let presentationBox = TestPresentationBox(value: .photoPreview)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let host = UIHostingController(
            rootView: TestDuoPoseDetailHost(
                browsing: browsing,
                images: source,
                presentation: presentationBox,
                isDuoExpanded: true,
                isDuoCover: false,
                usesVerticalToolbar: true,
                hasFoldRegion: true,
                showsGrid: true,
                theme: .dark))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            source.releaseAll()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("Gated analysis began for first photo") {
            source.analyzeCalls == [first] && self.findPreview(in: window) != nil
        }

        // Turn Focus regions Off while analysis is still in flight, then deliver late AF & finish.
        browsing.showsFocusRegions = false
        source.deliverLateResults(for: first)
        try await Task.sleep(for: .milliseconds(150))

        #expect(!browsing.showsFocusRegions)
        let previewFirst = try #require(findPreview(in: window))
        #expect(findAllFocusControls(in: previewFirst).isEmpty)

        // Switching Photo Preview -> Focus View keeps Off without restarting analysis.
        let callsBeforeSwitch = source.analyzeCalls.count
        presentationBox.value = .focus
        try await waitFor("Focus View settled while Off") {
            guard let preview = self.findPreview(in: window) else { return false }
            return self.findCollectionView(in: window) == nil
                && self.findFilmstripScrollView(in: window, excluding: preview) != nil
        }
        #expect(!browsing.showsFocusRegions)
        #expect(source.analyzeCalls.count == callsBeforeSwitch)
        let previewFocus = try #require(findPreview(in: window))
        #expect(findAllFocusControls(in: previewFocus).isEmpty)

        // Navigating to the next photo and switching back to Photo Preview keeps Off and runs no
        // new analysis while Off.
        browsing.openPhoto(second)
        try await waitFor("Navigated to second photo while Off") {
            browsing.state.currentPhoto == second
        }
        presentationBox.value = .photoPreview
        try await waitFor("Returned to Photo Preview on second photo while Off") {
            self.findCollectionView(in: window) != nil && self.findPreview(in: window) != nil
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!browsing.showsFocusRegions)
        #expect(source.analyzeCalls.count == callsBeforeSwitch)
        let previewSecond = try #require(findPreview(in: window))
        #expect(findAllFocusControls(in: previewSecond).isEmpty)

        // Turning back On reveals overlays for the current photo cleanly.
        browsing.showsFocusRegions = true
        source.releaseAll()
        try await waitFor("Turning Focus regions back On analyzed and presented second photo") {
            guard let preview = self.findPreview(in: window) else { return false }
            return source.analyzeCalls.contains(second)
                && !self.findAllFocusControls(in: preview).isEmpty
        }
    }

    @Test func programmaticZoomDefersDuringScrollAndLayoutPassesAndCoalescesToLatestTarget()
        async throws
    {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let pixels = try CGContext(
            data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 3000 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ).flatMap { $0.makeImage() }
        preview.setImage(
            try #require(pixels), fullResolutionPixels: CGSize(width: 3000, height: 2000))
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        let scroll = try #require(preview.subviews.first as? UIScrollView)

        // 1. Triggering programmatic zooms during an active scrollViewDidZoom callback must not
        // call setZoomScale synchronously inside the callback, and must coalesce to the newest target.
        var queuedDuringCallback = false
        preview.onZoomChange = { _ in
            guard !queuedDuringCallback else { return }
            queuedDuringCallback = true
            preview.apply(
                DetailZoomCommand(id: 1, kind: .scale(2.0, anchor: UnitPoint(x: 0.2, y: 0.2))))
            preview.apply(
                DetailZoomCommand(id: 2, kind: .scale(3.0, anchor: UnitPoint(x: 0.72, y: 0.64))))
        }
        preview.scrollViewDidZoom(scroll)
        #expect(queuedDuringCallback)
        #expect(!preview.isZoomed)
        #expect(scroll.zoomScale == 1)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(abs(scroll.zoomScale - 3.0) < 0.001)
        let afterCallback = try #require(preview.zoomSnapshot)
        #expect(abs(afterCallback.anchor.x - 0.72) < 0.02)
        #expect(abs(afterCallback.anchor.y - 0.64) < 0.02)

        // 2. Resizing bounds while zoomed defers the #272 retarget off layoutSubviews, and a newer
        // command before the runloop tick supersedes the deferred layout retarget with its own anchor.
        preview.frame = CGRect(x: 0, y: 0, width: 550, height: 480)
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        // Bounds resized synchronously without re-entering setZoomScale inside layoutSubviews;
        // explicit command issued before flush supersedes the pending layout retarget.
        preview.apply(
            DetailZoomCommand(id: 3, kind: .scale(2.4, anchor: UnitPoint(x: 0.30, y: 0.35))))
        #expect(abs(scroll.zoomScale - 3.0) < 0.001)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(abs(scroll.zoomScale - 2.4) < 0.001)
        let afterResize = try #require(preview.zoomSnapshot)
        #expect(abs(afterResize.anchor.x - 0.30) < 0.02)
        #expect(abs(afterResize.anchor.y - 0.35) < 0.02)

        // 3. Pending layout (bounds != laidOutSize) defers and coalesces multiple commands cleanly.
        preview.frame = CGRect(x: 0, y: 0, width: 420, height: 640)
        preview.apply(
            DetailZoomCommand(id: 4, kind: .scale(1.9, anchor: UnitPoint(x: 0.25, y: 0.25))))
        preview.apply(DetailZoomCommand(id: 5, kind: .fit))
        #expect(abs(scroll.zoomScale - 2.4) < 0.001)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!preview.isZoomed)
        #expect(scroll.zoomScale == 1)
    }

    @Test func navigationDetailSurvivesAnimatedPanResizeAndTwoFingerSwipeWithoutReentrancy()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let store = SettingsStore.sample
        store.update {
            $0.doubleTap = .zoomToFocus
            $0.zoomedGestures = .pan
            $0.autoAdvance.destination = .nextPhoto
            $0.autoAdvance.triggers.rating = true
        }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photos = browsing.photos
        try #require(photos.count >= 7)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let shellRoot = BrowseShell(browsing: browsing)
            .environment(store)
            .modifier(DuoLayout())
        let host = UIHostingController(rootView: shellRoot)
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(100))
        browsing.openPhoto(photos[4].id)

        try await waitFor("preview loaded in BrowseShell") {
            guard let preview = findPreview(in: window),
                let scroll = preview.subviews.first as? UIScrollView,
                let imageView = scroll.subviews.first as? UIImageView
            else { return false }
            return (imageView.image?.cgImage?.width ?? 0) >= SampleDetailImages.previewLongEdge
        }

        let preview = try #require(findPreview(in: window))
        let scroll = try #require(preview.subviews.first as? UIScrollView)
        let imageView = try #require(scroll.subviews.first as? UIImageView)
        for round in 0..<2 {
            let expectedNext = photos[5 + round].id
            try await waitFor("detail image loaded for round \(round)") {
                (imageView.image?.cgImage?.width ?? 0) >= SampleDetailImages.previewLongEdge
            }
            if !preview.isZoomed {
                preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.45, y: 0.45)))
            }
            try await waitFor("preview zoomed in round \(round)") {
                preview.isZoomed && preview.twoFingerMarkingSwipeIsEnabled
            }
            scroll.setContentOffset(CGPoint(x: 150, y: 120), animated: true)
            try await Task.sleep(for: .milliseconds(60))
            window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            window.frame = scene.coordinateSpace.bounds
            window.layoutIfNeeded()

            try #require(preview.gestureRecognizerShouldBegin(preview.twoFingerSwipeRecognizer))
            let twoFinger = DetailTestTwoFingerSwipe()
            let t1 = DetailMutableTouch(view: preview, location: CGPoint(x: 140, y: 420))
            let t2 = DetailMutableTouch(view: preview, location: CGPoint(x: 240, y: 420))
            let event = UIEvent()
            twoFinger.touchesBegan([t1, t2], with: event)
            t1.locationPoint = CGPoint(x: 140, y: 380)
            t2.locationPoint = CGPoint(x: 240, y: 380)
            twoFinger.touchesMoved([t1, t2], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            t1.locationPoint = CGPoint(x: 140, y: 240)
            t2.locationPoint = CGPoint(x: 240, y: 240)
            twoFinger.touchesMoved([t1, t2], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            twoFinger.touchesEnded([t1, t2], with: event)
            preview.handleTwoFingerMarkingSwipe(twoFinger)
            try await waitFor("auto-advance settled in round \(round)") {
                browsing.state.currentPhoto == expectedNext && !preview.isZoomed
            }
        }
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

    @Test func collapsedStackIsReadOnlyAndVerticalDragNudgesWithoutMarking() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let group = try #require(browsing.groups.first)
        let rep = try #require(
            BrowsingGroup.representative(
                of: browsing.photos.filter { group.members.contains($0.id) })?.id)
        let marksBefore = browsing.shownMarks(for: rep)
        browsing.openPhoto(rep)

        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(
            rootView: DetailScreen(browsing: browsing, images: source).environment(store))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor { source.prefetched.last?.current.photo == rep }
        let preview = try #require(findPreview(in: window))
        #expect(browsing.expandedGroup == nil)
        #expect(!preview.allowsMarking)
        #expect(preview.onReadOnlyMarkingDrag != nil)

        var nudged = 0
        let originalNudge = preview.onReadOnlyMarkingDrag
        preview.onReadOnlyMarkingDrag = {
            nudged += 1
            originalNudge?()
        }
        try sendSwipe(to: preview, travel: CGPoint(x: 0, y: -120))
        #expect(nudged == 1)
        #expect(browsing.shownMarks(for: rep) == marksBefore)
        #expect(preview.feedback?.rating == nil)

        browsing.openGroup(group.id, on: rep)
        try await waitFor { preview.allowsMarking }
        #expect(browsing.expandedGroup == group.id)

        browsing.collapseGroup()
        try await waitFor { !preview.allowsMarking }
        #expect(browsing.expandedGroup == nil)
        #expect(browsing.state.currentPhoto == rep)
    }

    @Test func splitPhotoPreviewAndFocusViewSyncExpandedGroupMarksAndZoom() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let group = try #require(browsing.groups.first)
        browsing.openGroup(group.id, on: group.members[0])

        let presentationBox = TestPresentationBox(value: .photoPreview)
        let usesSystemToolbar =
            if #available(iOS 27.1, *) {
                true
            } else {
                false
            }
        let host = UIHostingController(
            rootView: TestDetailPresentationHost(
                browsing: browsing, images: source, presentation: presentationBox,
                usesSystemToolbar: usesSystemToolbar))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("Photo Preview did not settle") {
            source.delivered.contains(.screenRAW) && self.findCollectionView(in: window) != nil
        }
        let preview = try #require(findPreview(in: window))
        let collectionView = try #require(findCollectionView(in: window))
        let timeline = DetailTimeline(photos: browsing.photos, groups: browsing.groups)
        let members = try #require(timeline.activeGroup(with: group.id)?.visibleMembers)
        // Photo Preview's split grid isolates the same group the Focus View strip does: one run
        // with its count header, and only the group's visible members (#309).
        try await waitFor("the split grid did not show the focused group") {
            collectionView.numberOfSections == 1
                && collectionView.numberOfItems(inSection: 0) == members.count
                && collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) != nil
        }
        #expect(!collectionView.visibleSupplementaryViews(ofKind: GridGroupHeader.kind).isEmpty)
        #expect(browsing.expandedGroup == group.id)

        // Choosing another member in the split grid changes the open photo, keeps Group Focus and
        // keeps the run scoped to the group (#309).
        let chosenIndex = 2
        let chosen = members[chosenIndex]
        collectionView.delegate?.collectionView?(
            collectionView, didSelectItemAt: IndexPath(item: chosenIndex, section: 0))
        try await waitFor("the split grid did not select the member") {
            browsing.state.currentPhoto == chosen.id
        }
        #expect(browsing.expandedGroup == group.id)
        #expect(collectionView.numberOfSections == 1)
        #expect(collectionView.numberOfItems(inSection: 0) == members.count)

        preview.onDoubleTap?(.center)
        try await waitFor("100% zoom did not settle") {
            source.delivered.contains(.nativeRAW) && preview.zoomSnapshot != nil
        }
        try await Task.sleep(for: .milliseconds(250))
        let zoomBeforeToggle = try #require(preview.zoomSnapshot)
        let requestCountBeforeToggle = source.requests.count

        // Switch from Photo Preview -> Focus View: preserves expandedGroup and zoom anchor without reloading pixels.
        presentationBox.value = presentationBox.value.toggled
        try await waitFor("Focus View did not settle") {
            presentationBox.value == .focus
                && self.findCollectionView(in: window) == nil
                && self.findFilmstripScrollView(in: window, excluding: preview) != nil
                && preview.zoomSnapshot.map {
                    abs($0.anchor.x - zoomBeforeToggle.anchor.x) < 0.05
                        && abs($0.anchor.y - zoomBeforeToggle.anchor.y) < 0.05
                } == true
        }
        #expect(browsing.expandedGroup == group.id)
        let filmstrips = findFilmstripScrollViews(in: window, excluding: preview)
        #expect(filmstrips.count == 2)
        #expect(filmstrips.contains { $0.contentSize.width > 1200 })
        #expect(filmstrips.contains { $0.contentSize.width < 300 })
        #expect(preview.isZoomed)
        let zoomAfterToggle = try #require(preview.zoomSnapshot)
        #expect(abs(zoomAfterToggle.anchor.x - zoomBeforeToggle.anchor.x) < 0.05)
        #expect(abs(zoomAfterToggle.anchor.y - zoomBeforeToggle.anchor.y) < 0.05)
        #expect(source.requests.count == requestCountBeforeToggle)

        // Mark member[1] in Focus View, then return to Photo Preview: expandedGroup and mark stay synced.
        browsing.selectGroupPhoto(group.members[1])
        try await waitFor("member[1] prefetch did not settle") {
            source.prefetched.last?.current.photo == group.members[1]
        }
        let two = try #require(Rating(rawValue: 2))
        browsing.apply(.rating(two), to: group.members[1])

        let requestCountBeforeReturn = source.requests.count
        presentationBox.value = presentationBox.value.toggled
        try await waitFor("Return to Photo Preview did not settle") {
            presentationBox.value == .photoPreview
                && self.findCollectionView(in: window) != nil
                && self.findFilmstripScrollView(in: window, excluding: preview) == nil
        }
        #expect(browsing.expandedGroup == group.id)
        #expect(browsing.state.currentPhoto == group.members[1])
        #expect(browsing.shownMarks(for: group.members[1]).rating == two)
        #expect(source.requests.count == requestCountBeforeReturn)
        let splitAgain = try #require(findCollectionView(in: window))
        try await waitFor("the split grid did not come back scoped to the group") {
            splitAgain.numberOfSections == 1
                && splitAgain.numberOfItems(inSection: 0) == members.count
        }

        // A filter that leaves fewer than two visible members closes Group Focus, and the split
        // grid returns to the folder's own Timeline run (#304, #309).
        browsing.setFilter(.unmarked)
        let folderCellCount =
            GridDisplay(photos: browsing.photos, groups: browsing.groups).cells.count
        try await waitFor("the filter did not return the split grid to Timeline") {
            browsing.expandedGroup == nil
                && splitAgain.numberOfSections == 1
                && splitAgain.numberOfItems(inSection: 0) == folderCellCount
        }
    }

    @Test func timelineNavigationAvailabilitySupportsNonRepresentativePhoto() throws {
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let timeline = DetailTimeline(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: true)
        let group = try #require(
            timeline.slots.compactMap { slot -> ActiveBrowsingGroup? in
                if case .group(let active) = slot { return active }
                return nil
            }.last)
        let nonRepresentative = try #require(
            group.visibleMembers.first { $0.id != group.representative.id })
        let detail = DetailMarkingView(
            browsing: browsing, photo: nonRepresentative,
            settings: AppSettings(),
            images: browsing.detailImages,
            timeline: timeline, expandedGroup: nil,
            order: timeline.stagePhotos,
            actions: DetailMarkingActions(
                apply: { _, _ in },
                marked: { _, _, _ in },
                step: { _ in },
                markingSwipeBegan: {}))
        let availability = detail.navigationAvailability
        #expect(availability.previous)
        #expect(availability.next)
    }

    @Test func fastNavigationFlickUsesTouchStartDistanceWhenPostRecognitionTranslationIsSmall()
        throws
    {
        let preview = DetailZoomContainerView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        preview.hasPrevious = true
        preview.hasNext = true
        var steps: [Int] = []
        preview.onStep = { steps.append($0) }

        // Real UIKit fast flicks eat pre-recognition displacement before `.began` (leaving tiny
        // `translation.x`) and report `numberOfTouches == 0` on `.ended`.
        let start = CGPoint(x: 240, y: 350)
        let markingPan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? DetailSingleFingerPanGestureRecognizer }
                .first)
        let pan = DetailTrackedTouchPan()
        _ = preview.gestureRecognizer(
            markingPan, shouldReceive: DetailMutableTouch(view: preview, location: start))
        pan.trackedNumberOfTouches = 1
        pan.travel = CGPoint(x: -5, y: 0)
        pan.velocityPoint = CGPoint(x: -750, y: 0)
        pan.locationPoint = CGPoint(x: 230, y: 350)
        try #require(preview.gestureRecognizerShouldBegin(pan))
        preview.handleMarkingPan(pan)

        pan.sampleState = .ended
        pan.trackedNumberOfTouches = 0
        pan.travel = CGPoint(x: -6, y: 0)
        pan.locationPoint = CGPoint(x: 222, y: 350)
        preview.handleMarkingPan(pan)

        #expect(steps == [1])
    }

    @Test func ordinaryMaxPhoneLandscapeStaysInFocusViewWithoutPhotoPreviewOrRail() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedFocusDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let photo = try #require(browsing.photos.first?.id)
        browsing.openPhoto(photo)

        let presentationBox = TestPresentationBox(value: .photoPreview)
        let tapFrames = DetailFrameBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 932, height: 430)
        let host = UIHostingController(
            rootView: TestDetailPresentationHost(
                browsing: browsing, images: source, presentation: presentationBox,
                usesSystemToolbar: false, idiom: .phone
            )
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                tapFrames.frames = frames
            })
        // Pro Max iPhone reports regular horizontal / compact vertical in landscape.
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        host.traitOverrides.verticalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("Pro Max iPhone landscape Detail did not settle") {
            guard let preview = self.findPreview(in: window) else { return false }
            return source.delivered.contains(.screenRAW)
                && self.findFilmstripScrollView(in: window, excluding: preview) != nil
                && tapFrames.frames["clove.detail.landscapeBottomRow"] != nil
                && tapFrames.frames["clove.detail.capsule"] != nil
        }
        // Ordinary iPhones must never mount Photo Preview's split grid or iPad's mark rail.
        #expect(findCollectionView(in: window) == nil)
        #expect(tapFrames.frames["clove.detail.gridToggle"] == nil)
        #expect(
            DetailPresentationPolicy(
                isRegularWidth: true, isPhone: true, isDuoExpanded: false, isDuoCover: false,
                hasFoldRegion: false, availableWidth: 932, availableHeight: 430
            ).supportsPhotoPreview == false)
    }

    @Test func ordinaryPhoneLandscapeHeaderBottomRowAndGroupFocusMetricsAcrossSizesAndThemes()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let sizes: [CGSize] = [
            CGSize(width: 667, height: 375),
            CGSize(width: 844, height: 390),
            CGSize(width: 932, height: 430),
        ]
        for theme in [CloveTheme.light, CloveTheme.dark] {
            for size in sizes {
                let source = SampleDetailImages()
                let browsing = BrowsingModel(library: TestLibrary.sample())
                browsing.openFolder()
                try await waitFor("folder did not open") { !browsing.isFolderOpening }
                let group = try #require(browsing.groups.first)
                // Open representative on collapsed stack in Timeline first -> Expand N photos pill.
                browsing.openPhoto(group.members[0])

                let headerFrames = DetailFrameBox()
                let tapFrames = DetailFrameBox()
                let triggerBox = DetailPickerTriggerBox()
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)

                struct HostView: View {
                    let browsing: BrowsingModel
                    let source: SampleDetailImages
                    let theme: CloveTheme
                    @Bindable var triggerBox: DetailPickerTriggerBox
                    var body: some View {
                        DetailScreen(browsing: browsing, images: source)
                            .environment(SettingsStore.sample)
                            .environment(\.cloveTheme, theme)
                            .environment(\.cloveUserInterfaceIdiom, .phone)
                            .environment(\.tapPickerTriggerRequest, triggerBox.trigger)
                            .environment(\.scenePhase, .active)
                    }
                }

                let host = UIHostingController(
                    rootView: HostView(
                        browsing: browsing, source: source, theme: theme, triggerBox: triggerBox
                    )
                    .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                        headerFrames.frames = $0
                    }
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                        tapFrames.frames = $0
                    })
                host.traitOverrides.horizontalSizeClass = size.width >= 900 ? .regular : .compact
                host.traitOverrides.verticalSizeClass = .compact
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }

                try await waitFor("landscape timeline controls did not lay out at \(size)") {
                    headerFrames.frames["clove.nav.back"] != nil
                        && headerFrames.frames["clove.detail.focusToggle"] != nil
                        && headerFrames.frames["clove.detail.fileName"] != nil
                        && headerFrames.frames["clove.detail.expandGroup"] != nil
                        && headerFrames.frames["clove.detail.info"] != nil
                        && headerFrames.frames["clove.detail.undo"] != nil
                        && tapFrames.frames["clove.detail.filmstrip"] != nil
                        && tapFrames.frames["clove.detail.capsule"] != nil
                }

                func expectHeaderOrder(_ pillID: String) throws {
                    let back = try #require(headerFrames.frames["clove.nav.back"])
                    let focus = try #require(headerFrames.frames["clove.detail.focusToggle"])
                    let file = try #require(headerFrames.frames["clove.detail.fileName"])
                    let pill = try #require(headerFrames.frames[pillID])
                    let info = try #require(headerFrames.frames["clove.detail.info"])
                    let undo = try #require(headerFrames.frames["clove.detail.undo"])
                    #expect(back.maxX <= focus.minX + 1)
                    #expect(focus.maxX <= file.minX + 1)
                    #expect(file.maxX <= pill.minX + 1)
                    #expect(pill.maxX <= info.minX + 1)
                    #expect(info.maxX <= undo.minX + 1)
                }

                try expectHeaderOrder("clove.detail.expandGroup")

                let stripFrame = try #require(tapFrames.frames["clove.detail.filmstrip"])
                let capsuleFrame = try #require(tapFrames.frames["clove.detail.capsule"])
                #expect(stripFrame.height <= 58)
                #expect(stripFrame.maxX <= capsuleFrame.minX + 1)
                #expect(abs(capsuleFrame.width - 168) <= 2)
                #expect(abs(capsuleFrame.height - 48) <= 2)

                // Enter Group Focus -> header swaps to Reject N unmarked pill without overlap.
                browsing.openGroup(group.id, on: group.members[0])
                try await waitFor("Group Focus pill did not update in header") {
                    headerFrames.frames["clove.detail.rejectUnmarked"] != nil
                        && headerFrames.frames["clove.detail.expandGroup"] == nil
                }
                try expectHeaderOrder("clove.detail.rejectUnmarked")

                // Horizontal RatingPicker and LabelPicker open cleanly above the bottom capsule.
                for (buttonID, pickerID) in [
                    ("clove.detail.capsule.rating", "clove.detail.capsule.stars"),
                    ("clove.detail.capsule.label", "clove.detail.labels"),
                ] {
                    triggerBox.sendTrigger(buttonID)
                    try await waitFor("horizontal picker \(pickerID) did not open") {
                        tapFrames.frames[pickerID] != nil
                    }
                    let pickerFrame = try #require(tapFrames.frames[pickerID])
                    #expect(pickerFrame.width > pickerFrame.height)
                    #expect(pickerFrame.maxY <= capsuleFrame.minY + 1)
                    triggerBox.sendTrigger(buttonID)
                    try await waitFor("picker \(pickerID) did not dismiss") {
                        tapFrames.frames[pickerID] == nil
                    }
                }
            }
        }
    }

    @Test func ordinaryPhoneRotationAndChromeHidePreserveZoomAndDismissPickers() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedFocusDetailImages()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let group = try #require(browsing.groups.first)
        let rep = group.members[0]
        browsing.openGroup(group.id, on: rep)
        browsing.showsFocusRegions = true
        let four = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(four), to: rep)

        let tapFrames = DetailFrameBox()
        let triggerBox = DetailPickerTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)

        struct HostView: View {
            let browsing: BrowsingModel
            let source: ObservedFocusDetailImages
            @Bindable var triggerBox: DetailPickerTriggerBox
            var body: some View {
                DetailScreen(browsing: browsing, images: source)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.tapPickerTriggerRequest, triggerBox.trigger)
                    .environment(\.scenePhase, .active)
            }
        }

        let host = UIHostingController(
            rootView: HostView(browsing: browsing, source: source, triggerBox: triggerBox)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                    tapFrames.frames = $0
                })
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("portrait phone detail did not settle") {
            guard let preview = self.findPreview(in: window) else { return false }
            return source.delivered.contains(.screenRAW)
                && self.findFilmstripScrollView(in: window, excluding: preview) != nil
        }
        let preview = try #require(findPreview(in: window))
        let portraitStripFrame = try #require(tapFrames.frames["clove.detail.filmstrip"])
        #expect(portraitStripFrame.height >= 68)
        #expect(tapFrames.frames["clove.detail.landscapeBottomRow"] == nil)

        // Zoom to a non-center anchor, open the Label tap picker, and capture pixel request count.
        preview.onDoubleTap?(DetailDoubleTapLocation(UnitPoint(x: 0.35, y: 0.4)))
        try await waitFor("zoom did not settle in portrait") {
            preview.isZoomed && source.delivered.contains(.nativeRAW)
        }
        try await Task.sleep(for: .milliseconds(300))

        triggerBox.sendTrigger("clove.detail.capsule.label")
        try await waitFor("portrait label picker did not open") {
            tapFrames.frames["clove.detail.labels"] != nil
        }

        let requestsBeforeRotate = source.requests.count
        let anchorBeforeRotate = try #require(preview.zoomSnapshot?.anchor)

        // Rotate to Pro Max landscape: open tap picker dismisses, state + zoom stay intact,
        // no redundant image load occurs, and landscapeBottomRow mounts.
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        host.traitOverrides.verticalSizeClass = .compact
        window.frame = CGRect(x: 0, y: 0, width: 932, height: 430)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await waitFor("landscape layout did not settle after rotation") {
            tapFrames.frames["clove.detail.landscapeBottomRow"] != nil
                && tapFrames.frames["clove.detail.labels"] == nil
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(browsing.state.currentPhoto == rep)
        #expect(browsing.expandedGroup == group.id)
        #expect(browsing.shownMarks(for: rep).rating == four)
        #expect(browsing.showsFocusRegions)
        #expect(preview.isZoomed)
        #expect(source.requests.count == requestsBeforeRotate)
        let anchorAfterRotate = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(anchorAfterRotate.x - anchorBeforeRotate.x) < 0.08)
        #expect(abs(anchorAfterRotate.y - anchorBeforeRotate.y) < 0.08)

        // Single tap to hide chrome removes landscapeBottomRow and expands previewArea height cleanly.
        let stageHeightWithChrome = preview.bounds.height
        preview.onChromeToggle?()
        try await waitFor("chrome did not hide and expand stage in landscape") {
            tapFrames.frames["clove.detail.landscapeBottomRow"] == nil
                && preview.bounds.height > stageHeightWithChrome + 30
        }
        try await Task.sleep(for: .milliseconds(350))
        #expect(preview.isZoomed)
        let anchorAfterChromeHide = try #require(preview.zoomSnapshot?.anchor)
        #expect(abs(anchorAfterChromeHide.x - anchorAfterRotate.x) < 0.08)
        #expect(abs(anchorAfterChromeHide.y - anchorAfterRotate.y) < 0.08)

        // Restore chrome, rotate back to portrait -> landscapeBottomRow disappears, portrait strip returns.
        preview.onChromeToggle?()
        try await waitFor("chrome did not restore in landscape") {
            tapFrames.frames["clove.detail.landscapeBottomRow"] != nil
        }
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor("portrait layout did not restore after rotation back") {
            tapFrames.frames["clove.detail.landscapeBottomRow"] == nil
                && (tapFrames.frames["clove.detail.filmstrip"]?.height ?? 0) >= 68
        }
        #expect(browsing.state.currentPhoto == rep)
        #expect(browsing.expandedGroup == group.id)
        #expect(preview.isZoomed)
    }

    @Test
    func duoExpandedPhotoPreviewSingleStagePillMatchesStateAndClearsPriorLayerAcrossTransitions()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)

        struct HostedDuoPane: View {
            let browsing: BrowsingModel
            let store: SettingsStore
            let theme: CloveTheme
            let framesBox: DetailFrameBox

            var body: some View {
                NavigationStack {
                    GridScreen(
                        browsing: browsing,
                        thumbnails: browsing.thumbnails,
                        initialPresentation: .photoPreview)
                }
                .environment(store)
                .environment(\.cloveTheme, theme)
                .environment(\.isDuoExpanded, true)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.scenePhase, .active)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                    framesBox.frames = $0
                }
            }
        }

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let store = SettingsStore.sample
            store.markGestureGuideSeen()
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            try await waitFor("folder open") { !browsing.isFolderOpening }

            let group = try #require(browsing.groups.first)
            let rep = try #require(
                BrowsingGroup.representative(
                    of: browsing.photos.filter { group.members.contains($0.id) })?.id)
            let groupedIDs = Set(browsing.groups.flatMap(\.members))
            let standalone = try #require(browsing.photos.first { !groupedIDs.contains($0.id) }).id

            // Rate the representative so entering Group Focus offers an immediate finishing plan.
            browsing.apply(.rating(try #require(Rating(rawValue: 4))), to: rep)

            let framesBox = DetailFrameBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
            window.overrideUserInterfaceStyle = theme == .light ? .light : .dark
            let host = UIHostingController(
                rootView: HostedDuoPane(
                    browsing: browsing, store: store, theme: theme, framesBox: framesBox))
            host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 89.5)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(100))
            browsing.openPhoto(rep)
            try await waitFor("Duo Photo Preview did not settle") {
                framesBox.frames["clove.duo.photoPreview"] != nil
                    && framesBox.frames["clove.duo.capsule"] != nil
                    && self.findPreview(in: window) != nil
            }
            let preview = try #require(findPreview(in: window))
            let baselinePreviewSize = preview.bounds.size

            func visibleStagePillGlasses() -> [UIView] {
                let previewFrame = preview.convert(preview.bounds, to: window)
                let topY = previewFrame.minY + previewFrame.height * 0.6
                let bottomY = framesBox.frames["clove.duo.capsule"]?.minY ?? previewFrame.maxY
                let band = CGRect(
                    x: previewFrame.minX,
                    y: topY,
                    width: previewFrame.width,
                    height: max(0, bottomY - topY))
                var matches: [UIView] = []
                func walk(_ view: UIView) {
                    let frame = view.convert(view.bounds, to: window)
                    let name = String(describing: type(of: view))
                    if name.contains("GlassInteractionView"),
                        !view.isHidden, view.alpha > 0.01, view.layer.opacity > 0.01,
                        frame.width > 40, frame.height > 20,
                        band.intersects(frame)
                    {
                        matches.append(view)
                    }
                    for subview in view.subviews { walk(subview) }
                }
                walk(window)
                return matches
            }

            func expectSingleCenteredPill(
                expectedWidth: CGFloat? = nil,
                label: String
            ) throws -> CGRect {
                let glasses = visibleStagePillGlasses()
                #expect(glasses.count == 1, Comment(rawValue: "\(label): expected 1 capsule"))
                let glass = try #require(glasses.first)
                let frame = glass.convert(glass.bounds, to: window)
                let previewFrame = preview.convert(preview.bounds, to: window)
                let capsuleFrame = try #require(framesBox.frames["clove.duo.capsule"])

                #expect(
                    (glass.layer.animationKeys() ?? []).isEmpty,
                    Comment(rawValue: "\(label): capsule layer should not hold stale animations"))
                #expect(
                    abs(frame.midX - previewFrame.midX) <= 1.0,
                    Comment(rawValue: "\(label): capsule should be centered in right photo pane"))
                #expect(
                    abs(previewFrame.maxY - frame.maxY - 12.0) <= 1.5,
                    Comment(rawValue: "\(label): capsule should sit 12 pt above stage bottom"))
                #expect(
                    frame.maxY <= capsuleFrame.minY,
                    Comment(rawValue: "\(label): capsule must stay clear of marking dock"))
                if let expectedWidth {
                    #expect(
                        abs(frame.width - expectedWidth) <= 0.5,
                        Comment(rawValue: "\(label): unexpected capsule width \(frame.width)"))
                }
                #expect(
                    preview.bounds.size == baselinePreviewSize,
                    Comment(rawValue: "\(label): pill must not resize photo stage"))
                return frame
            }

            func waitForSinglePillTransition(
                expectedWidth: CGFloat? = nil,
                excludingWidth: CGFloat? = nil,
                label: String
            ) async throws -> CGRect {
                for _ in 0..<15 {
                    let glasses = visibleStagePillGlasses()
                    #expect(
                        glasses.count <= 1,
                        Comment(rawValue: "\(label): duplicate capsules during transition"))
                    if let glass = glasses.first {
                        let frame = glass.convert(glass.bounds, to: window)
                        let matchesExpected =
                            expectedWidth.map { abs(frame.width - $0) <= 0.5 } ?? true
                        let differsFromPrevious =
                            excludingWidth.map { abs(frame.width - $0) > 0.5 } ?? true
                        if matchesExpected && differsFromPrevious {
                            return try expectSingleCenteredPill(
                                expectedWidth: expectedWidth, label: label)
                        }
                    }
                    try await Task.sleep(for: .milliseconds(15))
                }
                return try expectSingleCenteredPill(expectedWidth: expectedWidth, label: label)
            }

            func waitForPillRemoval(label: String) async throws {
                for _ in 0..<15 {
                    let glasses = visibleStagePillGlasses()
                    #expect(
                        glasses.count <= 1,
                        Comment(rawValue: "\(label): duplicate capsules during removal"))
                    if glasses.isEmpty { return }
                    try await Task.sleep(for: .milliseconds(15))
                }
                #expect(
                    visibleStagePillGlasses().isEmpty,
                    Comment(rawValue: "\(label): expected pill removal"))
            }

            // 1. Timeline on collapsed group's representative shows "Expand N photos".
            try await waitFor("Expand pill did not appear") {
                visibleStagePillGlasses().count == 1
            }
            let expandFrame = try expectSingleCenteredPill(label: "Timeline expand pill")

            // 2. Animated transition Expand -> Reject leaves only the single Reject capsule.
            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                browsing.openGroup(group.id, on: rep)
            }
            let midRejectFrame = try await waitForSinglePillTransition(
                excludingWidth: expandFrame.width, label: "Mid Expand->Reject")
            #expect(midRejectFrame.width != expandFrame.width)

            try await Task.sleep(for: .milliseconds(350))
            let rejectFrame = try expectSingleCenteredPill(
                expectedWidth: midRejectFrame.width, label: "Settled Group Focus reject pill")

            // 3. Animated transition Reject -> Expand snaps back to single Expand capsule.
            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                browsing.collapseGroup()
            }
            _ = try await waitForSinglePillTransition(
                expectedWidth: expandFrame.width, label: "Mid Reject->Expand")

            try await Task.sleep(for: .milliseconds(350))
            _ = try expectSingleCenteredPill(
                expectedWidth: expandFrame.width, label: "Settled collapsed Expand pill")

            // 4. Enter Group Focus and finish the group -> Reject disappears with no ghost layer.
            browsing.openGroup(group.id, on: rep)
            try await waitFor("Reject pill did not return") {
                guard let frame = visibleStagePillGlasses().first?.frame else { return false }
                return abs(frame.width - rejectFrame.width) <= 0.5
            }
            let plan = try #require(finishingPlan(for: group, currentPhoto: rep, in: browsing))
            #expect(!plan.isEmpty)
            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                browsing.runGroupFinishing(plan)
            }
            try await waitForPillRemoval(label: "Mid finishing Reject->nil")
            #expect(preview.bounds.size == baselinePreviewSize)
            try await Task.sleep(for: .milliseconds(350))
            #expect(visibleStagePillGlasses().isEmpty)

            // 5. Undo restores the Reject pill cleanly without stale artifacts.
            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                browsing.undoLastMark()
            }
            _ = try await waitForSinglePillTransition(
                expectedWidth: rejectFrame.width, label: "Mid Undo->Reject")

            // 6. Chrome hide/show removes and restores the single pill; stage restores baseline size.
            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                preview.onChromeToggle?()
            }
            try await waitForPillRemoval(label: "Mid chrome hide")

            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                preview.onChromeToggle?()
            }
            try await waitFor("Reject pill did not restore with chrome") {
                visibleStagePillGlasses().count == 1
                    && framesBox.frames["clove.duo.capsule"] != nil
            }
            try await Task.sleep(for: .milliseconds(350))
            _ = try expectSingleCenteredPill(
                expectedWidth: rejectFrame.width, label: "Restored chrome Reject pill")

            // 7. Switching to a standalone photo shows no group action pill.
            browsing.collapseGroup()
            withAnimation(CloveMotion.chrome(reduceMotion: false)) {
                browsing.openPhoto(standalone)
            }
            try await waitForPillRemoval(label: "Mid collapse to standalone")
            #expect(preview.bounds.size == baselinePreviewSize)

            // 8. Resizing the Duo pane re-centers the pill horizontally with the right pane.
            browsing.openPhoto(rep)
            try await waitFor("Expand pill did not return on rep") {
                visibleStagePillGlasses().count == 1
            }
            for width in [CGFloat(880), CGFloat(1180)] {
                window.frame = CGRect(x: 0, y: 0, width: width, height: 703.5)
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let resizedGlass = try #require(visibleStagePillGlasses().first)
                let resizedPill = resizedGlass.convert(resizedGlass.bounds, to: window)
                let resizedPreview = preview.convert(preview.bounds, to: window)
                let resizedCapsule = try #require(framesBox.frames["clove.duo.capsule"])
                #expect(abs(resizedPill.midX - resizedPreview.midX) <= 1.0)
                #expect(resizedPill.maxY <= resizedCapsule.minY)
            }
        }
    }

    @Test func duoExpandedPhotoPreviewStagePillAvailabilityToastClearanceAndFocusViewPreservation()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["rep", "m1", "m2", "standalone"])
        let group = BrowsingGroup(
            id: GroupID(rawValue: "g1"),
            members: ["rep", "m1", "m2"].map { library.identity($0) })
        library.groups = [group]

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder open did not finish") {
            !browsing.isFolderOpening && !browsing.groups.isEmpty
        }
        let rep = library.identity("rep")
        let m1 = library.identity("m1")
        browsing.apply(.rating(try #require(Rating(rawValue: 4))), to: rep)

        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let presentationBox = TestPresentationBox(value: .photoPreview)
        let framesBox = DetailFrameBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)

        struct HostView: View {
            let browsing: BrowsingModel
            let store: SettingsStore
            @Bindable var presentation: TestPresentationBox
            let framesBox: DetailFrameBox

            var body: some View {
                NavigationStack {
                    DetailScreen(
                        browsing: browsing,
                        images: SampleDetailImages(),
                        duo: DuoDetailLayout(
                            presentation: $presentation.value,
                            filter: AnyView(EmptyView()),
                            more: AnyView(EmptyView()),
                            bottom: AnyView(EmptyView()),
                            showsGrid: true))
                }
                .environment(store)
                .environment(\.isDuoExpanded, true)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.scenePhase, .active)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                    framesBox.frames = $0
                }
            }
        }

        let host = UIHostingController(
            rootView: HostView(
                browsing: browsing, store: store, presentation: presentationBox,
                framesBox: framesBox))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 89.5)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        browsing.openPhoto(rep)
        try await waitFor("Photo Preview did not settle") {
            framesBox.frames["clove.duo.photoPreview"] != nil
                && framesBox.frames["clove.duo.capsule"] != nil
                && self.findPreview(in: window) != nil
        }
        func visibleGlassViews(inVerticalBand range: (CGRect) -> ClosedRange<CGFloat>?) -> [UIView]
        {
            guard let currentPreview = findPreview(in: window) else { return [] }
            let previewFrame = currentPreview.convert(currentPreview.bounds, to: window)
            guard let verticalRange = range(previewFrame) else { return [] }
            var matches: [UIView] = []
            func walk(_ view: UIView) {
                let frame = view.convert(view.bounds, to: window)
                if String(describing: type(of: view)).contains("GlassInteractionView"),
                    !view.isHidden, view.alpha > 0.01, view.layer.opacity > 0.01,
                    frame.width > 40, frame.height > 20,
                    frame.midX >= previewFrame.minX, frame.midX <= previewFrame.maxX,
                    frame.midY >= verticalRange.lowerBound, frame.midY <= verticalRange.upperBound
                {
                    matches.append(view)
                }
                for subview in view.subviews { walk(subview) }
            }
            walk(window)
            return matches
        }

        func visiblePillGlasses() -> [UIView] {
            visibleGlassViews { previewFrame in
                let topY = previewFrame.minY + previewFrame.height * 0.55
                return topY...previewFrame.maxY
            }
        }

        func visibleToastGlasses() -> [UIView] {
            visibleGlassViews { previewFrame in
                let capsuleMinY =
                    framesBox.frames["clove.duo.capsule"]?.minY ?? previewFrame.maxY + 200
                guard capsuleMinY > previewFrame.maxY else { return nil }
                return previewFrame.maxY...capsuleMinY
            }
        }

        // Entering Group Focus and triggering a save failure toast keeps the stage pill clear of
        // the toast and marking capsule.
        browsing.openGroup(group.id, on: rep)
        try await waitFor("Group Focus pill did not appear") {
            visiblePillGlasses().count == 1
        }
        library.failNext.insert(m1)
        browsing.apply(.rating(try #require(Rating(rawValue: 3))), to: m1)
        await browsing.drainActions()
        try await waitFor("Save failure toast did not appear") {
            browsing.failureToastMessage != nil && visibleToastGlasses().count == 1
        }
        let pillFrame = try #require(visiblePillGlasses().first).convert(
            try #require(visiblePillGlasses().first).bounds, to: window)
        let toastView = try #require(visibleToastGlasses().first)
        let toastFrame = toastView.convert(toastView.bounds, to: window)
        let capsuleFrame = try #require(framesBox.frames["clove.duo.capsule"])
        #expect(pillFrame.maxY <= toastFrame.minY)
        #expect(toastFrame.maxY <= capsuleFrame.minY)

        // Focus View preserves its filmstrip and group action pill when toggled from Photo Preview.
        presentationBox.value = .focus
        try await waitFor("Focus View did not mount filmstrip") {
            guard let currentPreview = self.findPreview(in: window) else { return false }
            return framesBox.frames["clove.duo.focus"] != nil
                && self.findFilmstripScrollView(in: window, excluding: currentPreview) != nil
                && visiblePillGlasses().count == 1
        }

        // Losing folder location disables marking: Reject hides in Group Focus, while Expand stays
        // available on a collapsed group representative in Timeline.
        presentationBox.value = .photoPreview
        try await waitFor("Photo Preview did not return") {
            guard let currentPreview = self.findPreview(in: window) else { return false }
            return framesBox.frames["clove.duo.photoPreview"] != nil
                && self.findFilmstripScrollView(in: window, excluding: currentPreview) == nil
                && visiblePillGlasses().count == 1
        }
        library.reportDriveLoss()
        try await waitFor("Location loss did not disable marking") { !browsing.canMark }
        try await waitFor("Reject pill did not hide after location loss") {
            visiblePillGlasses().isEmpty
        }

        browsing.collapseGroup()
        try await waitFor("Timeline Expand pill did not appear while location lost") {
            visiblePillGlasses().count == 1
        }
    }

    @Test func detailHeaderFileNamePartsSplitsExtensionWithoutBreakingEdgeCases() {
        let standard = DetailHeaderFileNameParts("MMQ02680.ARW")
        #expect(standard.stem == "MMQ02680")
        #expect(standard.extensionSuffix == ".ARW")

        let dottedStem = DetailHeaderFileNameParts("2026-11-20.Kyoto.Autumn.Session_042.CR3")
        #expect(dottedStem.stem == "2026-11-20.Kyoto.Autumn.Session_042")
        #expect(dottedStem.extensionSuffix == ".CR3")

        let heif = DetailHeaderFileNameParts("DSC00123.HIF")
        #expect(heif.stem == "DSC00123")
        #expect(heif.extensionSuffix == ".HIF")

        let noExtension = DetailHeaderFileNameParts("UntitledShot")
        #expect(noExtension.stem == "UntitledShot")
        #expect(noExtension.extensionSuffix == "")

        let hiddenFile = DetailHeaderFileNameParts(".hidden")
        #expect(hiddenFile.stem == ".hidden")
        #expect(hiddenFile.extensionSuffix == "")

        let trailingDot = DetailHeaderFileNameParts("photo.")
        #expect(trailingDot.stem == "photo.")
        #expect(trailingDot.extensionSuffix == "")
    }

    @Test
    func
        expandedDuoViewportOverlayPreservesExtensionsAdaptsAcrossModesSizesAndRejectGlyph()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)

        let longStem =
            "2026-11-20_Kyoto_Autumn_Morning_Session_Ultra_Wide_Long_Filename_Example_DSC04821"
        let shortStem = "MMQ02680"

        struct HostedCornerDetail: View {
            let browsing: BrowsingModel
            let store: SettingsStore
            let theme: CloveTheme
            let dynamicTypeSize: DynamicTypeSize
            @Bindable var presentation: TestPresentationBox
            let headerFrames: DetailFrameBox
            let headerCounts: DetailCountBox

            var body: some View {
                NavigationStack {
                    DetailScreen(
                        browsing: browsing,
                        images: SampleDetailImages(),
                        duo: DuoDetailLayout(
                            presentation: $presentation.value,
                            filter: AnyView(EmptyView()),
                            more: AnyView(EmptyView()),
                            bottom: AnyView(EmptyView()),
                            showsGrid: true))
                }
                .environment(store)
                .environment(\.cloveTheme, theme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .environment(\.isDuoExpanded, true)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.scenePhase, .active)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    headerFrames.frames = $0
                }
                .onPreferenceChange(HeaderControlCountsPreferenceKey.self) {
                    headerCounts.counts = $0
                }
            }
        }

        let fullLongWidth = ("\(longStem).ARW" as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
        ]).width
        let fullExtensionWidth = (".ARW" as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
        ]).width

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let library = ControlledPhotoLibrary(
                rejected: [],
                stems: [longStem, shortStem, "group_b"])
            library.photos = [
                GridPhoto(
                    id: library.identity(longStem),
                    fileName: "\(longStem).ARW",
                    time: .unavailable,
                    marks: PhotoMarks()),
                GridPhoto(
                    id: library.identity(shortStem),
                    fileName: "\(shortStem).CR3",
                    time: .unavailable,
                    marks: PhotoMarks()),
                GridPhoto(
                    id: library.identity("group_b"),
                    fileName: "group_b.HIF",
                    time: .unavailable,
                    marks: PhotoMarks()),
            ]
            let group = BrowsingGroup(
                id: GroupID(rawValue: "burst-1"),
                members: [library.identity(shortStem), library.identity("group_b")])
            library.groups = [group]

            let store = SettingsStore.sample
            store.markGestureGuideSeen()
            let browsing = BrowsingModel(library: library)
            browsing.openFolder()
            library.reportScanFinished()
            try await waitFor("controlled folder did not finish opening") {
                !browsing.isFolderOpening && browsing.photos.count == 3
            }

            let presentationBox = TestPresentationBox(value: .photoPreview)
            let headerFrames = DetailFrameBox()
            let headerCounts = DetailCountBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 920, height: 680)
            window.overrideUserInterfaceStyle = theme == .light ? .light : .dark

            func mountHost(dynamicTypeSize: DynamicTypeSize) -> UIHostingController<
                HostedCornerDetail
            > {
                let host = UIHostingController(
                    rootView: HostedCornerDetail(
                        browsing: browsing, store: store, theme: theme,
                        dynamicTypeSize: dynamicTypeSize, presentation: presentationBox,
                        headerFrames: headerFrames, headerCounts: headerCounts))
                host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
                host.additionalSafeAreaInsets = UIEdgeInsets(
                    top: 16, left: 0, bottom: 0, right: 89.5)
                window.rootViewController = host
                window.makeKeyAndVisible()
                return host
            }

            let host = mountHost(dynamicTypeSize: .large)
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            // 1. Photo Preview on long filename in Timeline:
            // - No reserved 48 pt top header; previewArea starts at the top safe area
            // - Identity badge pinned at (16, 12) inside viewport, focus toggle floating beside it
            // - Long filename middle-truncates while preserving full .ARW extension width
            // - Top-trailing reject glyph stays clear of the floating controls
            browsing.openPhoto(library.identity(longStem))
            browsing.apply(.rating(.rejected), to: library.identity(longStem))
            try await waitFor("Photo Preview viewport overlay did not lay out") {
                headerFrames.frames["clove.detail.focusToggle"] != nil
                    && headerFrames.frames["clove.detail.photoCornerOverlay"] != nil
                    && headerFrames.frames["clove.detail.fileName"] != nil
                    && headerFrames.frames["clove.detail.fileName.extension"] != nil
                    && headerFrames.frames["clove.detail.zoom"] != nil
                    && headerFrames.frames["clove.detail.rejectGlyph"] != nil
                    && self.findPreview(in: window) != nil
                    && self.findCollectionView(in: window) != nil
            }

            let previewPhotoPreview = try #require(findPreview(in: window))
            let splitGrid = try #require(findCollectionView(in: window))
            let focusPP = try #require(headerFrames.frames["clove.detail.focusToggle"])
            let overlayPP = try #require(headerFrames.frames["clove.detail.photoCornerOverlay"])
            let filePP = try #require(headerFrames.frames["clove.detail.fileName"])
            let extPP = try #require(headerFrames.frames["clove.detail.fileName.extension"])
            let zoomPP = try #require(headerFrames.frames["clove.detail.zoom"])
            let rejectPP = try #require(headerFrames.frames["clove.detail.rejectGlyph"])
            let stagePreviewRect = previewPhotoPreview.convert(
                previewPhotoPreview.bounds, to: window)
            let splitGridRect = splitGrid.convert(splitGrid.bounds, to: window)

            #expect(headerFrames.frames["clove.detail.photoHeader"] == nil)
            #expect(stagePreviewRect.minX >= splitGridRect.maxX - 1)
            #expect(stagePreviewRect.minY >= 15.5)
            #expect(abs(overlayPP.minX - (stagePreviewRect.minX + 16)) <= 1.5)
            #expect(abs(overlayPP.minY - (stagePreviewRect.minY + 12)) <= 1.5)
            #expect(focusPP.width >= 44 && focusPP.height >= 44)
            #expect(focusPP.minX >= overlayPP.maxX + 6)
            #expect(abs(focusPP.minY - (stagePreviewRect.minY + 12)) <= 1.5)
            #expect(!focusPP.intersects(rejectPP))
            #expect(focusPP.maxX <= rejectPP.minX - 4)
            #expect(headerFrames.frames["clove.detail.saveState"] == nil)
            #expect(filePP.maxY <= zoomPP.minY + 1)
            #expect(filePP.width < fullLongWidth)
            #expect(extPP.width >= fullExtensionWidth - 2)
            #expect(extPP.maxX <= filePP.maxX + 1)
            #expect(headerCounts.counts["clove.detail.fileName"] == 1)
            #expect(headerCounts.counts["clove.detail.zoom"] == 1)
            if let fileAccessibility = findAccessibilityElement(
                withIdentifier: "clove.detail.fileName", in: window)
            {
                #expect(fileAccessibility.accessibilityLabel == "\(longStem).ARW")
            }

            // 2. Narrower Photo Preview width + drive loss:
            // - SaveStatusIndicator floats beside focusToggle inside the viewport
            // - FolderSaveBanner appears above previewArea while overlay stays pinned at (16, 12)
            window.frame = CGRect(x: 0, y: 0, width: 760, height: 680)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            library.reportDriveLoss()
            try await waitFor("SaveStatusIndicator did not appear in viewport overlay") {
                guard let preview = self.findPreview(in: window),
                    let overlay = headerFrames.frames["clove.detail.photoCornerOverlay"]
                else { return false }
                let stageRect = preview.convert(preview.bounds, to: window)
                return headerFrames.frames["clove.detail.saveState"] != nil
                    && headerFrames.frames["clove.detail.saveStatus.failure"] != nil
                    && abs(overlay.minX - (stageRect.minX + 16)) <= 1.5
                    && abs(overlay.minY - (stageRect.minY + 12)) <= 1.5
            }
            let narrowFocus = try #require(headerFrames.frames["clove.detail.focusToggle"])
            let narrowSave = try #require(headerFrames.frames["clove.detail.saveState"])
            let narrowBanner = try #require(
                headerFrames.frames["clove.detail.saveStatus.failure"])
            let narrowOverlay = try #require(headerFrames.frames["clove.detail.photoCornerOverlay"])
            let narrowExt = try #require(headerFrames.frames["clove.detail.fileName.extension"])
            let narrowReject = try #require(headerFrames.frames["clove.detail.rejectGlyph"])
            let narrowPreview = try #require(findPreview(in: window))
            let narrowStageRect = narrowPreview.convert(narrowPreview.bounds, to: window)
            #expect(headerFrames.frames["clove.detail.photoHeader"] == nil)
            #expect(narrowFocus.minX >= narrowOverlay.maxX + 6)
            #expect(narrowFocus.maxX < narrowSave.minX)
            #expect(!narrowSave.intersects(narrowReject))
            #expect(narrowSave.maxX <= narrowReject.minX - 4)
            #expect(narrowStageRect.minY >= narrowBanner.maxY - 1)
            #expect(abs(narrowOverlay.minX - (narrowStageRect.minX + 16)) <= 1.5)
            #expect(abs(narrowOverlay.minY - (narrowStageRect.minY + 12)) <= 1.5)
            #expect(narrowExt.width >= fullExtensionWidth - 2)

            // 3. Switch to Focus View + Group Focus on shorter filename:
            // - Overlay stays pinned to (16, 12) of the full-width viewport
            window.frame = CGRect(x: 0, y: 0, width: 920, height: 680)
            browsing.openGroup(group.id, on: library.identity(shortStem))
            presentationBox.value = .focus
            try await waitFor("Focus View viewport overlay did not settle") {
                guard let preview = self.findPreview(in: window),
                    let overlay = headerFrames.frames["clove.detail.photoCornerOverlay"]
                else { return false }
                let stageRect = preview.convert(preview.bounds, to: window)
                return self.findCollectionView(in: window) == nil
                    && self.findFilmstripScrollView(in: window, excluding: preview) != nil
                    && overlay.minX < overlayPP.minX - 40
                    && abs(overlay.minX - (stageRect.minX + 16)) <= 1.5
                    && abs(overlay.minY - (stageRect.minY + 12)) <= 1.5
            }
            let focusToggleInFocus = try #require(headerFrames.frames["clove.detail.focusToggle"])
            let focusSave = try #require(headerFrames.frames["clove.detail.saveState"])
            let focusOverlay = try #require(headerFrames.frames["clove.detail.photoCornerOverlay"])
            let focusPreview = try #require(findPreview(in: window))
            let focusStageRect = focusPreview.convert(focusPreview.bounds, to: window)
            #expect(headerFrames.frames["clove.detail.photoHeader"] == nil)
            #expect(focusOverlay.minX < overlayPP.minX - 40)
            #expect(focusToggleInFocus.minX >= focusOverlay.maxX + 6)
            #expect(focusToggleInFocus.maxX < focusSave.minX)
            #expect(focusSave.maxX < focusStageRect.maxX - 120)
            #expect(abs(focusOverlay.minX - (focusStageRect.minX + 16)) <= 1.5)
            #expect(abs(focusOverlay.minY - (focusStageRect.minY + 12)) <= 1.5)
            #expect(headerCounts.counts["clove.detail.fileName"] == 1)
            #expect(headerCounts.counts["clove.detail.zoom"] == 1)

            // 4. Accessibility Dynamic Type size: viewport identity badge scales cleanly without
            // clipping while keeping >= 44×44 focus toggle and viewport insets intact.
            let standardOverlayHeight = focusOverlay.height
            _ = mountHost(dynamicTypeSize: .accessibility2)
            presentationBox.value = .photoPreview
            try await waitFor("Accessibility Dynamic Type viewport overlay did not scale") {
                guard let overlay = headerFrames.frames["clove.detail.photoCornerOverlay"] else {
                    return false
                }
                return overlay.height > standardOverlayHeight + 6
                    && self.findCollectionView(in: window) != nil
            }
            let a11yFocus = try #require(headerFrames.frames["clove.detail.focusToggle"])
            let a11yOverlay = try #require(headerFrames.frames["clove.detail.photoCornerOverlay"])
            let a11yFile = try #require(headerFrames.frames["clove.detail.fileName"])
            let a11yZoom = try #require(headerFrames.frames["clove.detail.zoom"])
            let a11yPreview = try #require(findPreview(in: window))
            let a11yStageRect = a11yPreview.convert(a11yPreview.bounds, to: window)
            #expect(headerFrames.frames["clove.detail.photoHeader"] == nil)
            #expect(abs(a11yOverlay.minX - (a11yStageRect.minX + 16)) <= 1.5)
            #expect(abs(a11yOverlay.minY - (a11yStageRect.minY + 12)) <= 1.5)
            #expect(a11yFocus.width >= 44 && a11yFocus.height >= 44)
            #expect(a11yFocus.minX >= a11yOverlay.maxX + 6)
            #expect(abs(a11yFocus.minY - (a11yStageRect.minY + 12)) <= 1.5)
            #expect(a11yFocus.maxX <= a11yStageRect.maxX - 40)
            #expect(a11yFile.maxY <= a11yZoom.minY + 1)
            #expect(a11yZoom.maxY <= a11yOverlay.maxY)
        }
    }

    @Test
    func expandedDuoCornerOverlayCountGroupGlyphNoCompanionsAndThemes() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let store = SettingsStore.sample
            store.markGestureGuideSeen()
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            try await waitFor("sample folder open") { !browsing.isFolderOpening }

            // MMQ02680 has + JPG and MMQ02695 has + JPG · + HIF in TestLibrary.sample();
            // the expanded Duo corner overlay must omit companion suffixes in both Timeline and
            // Group Focus.
            let companionPhoto = try #require(
                browsing.photos.first { $0.id.stem == "mmq02695" })
            let group = try #require(browsing.groups.first)
            browsing.openPhoto(companionPhoto.id)

            let timeline = DetailTimeline(
                photos: browsing.photos, groups: browsing.groups, groupsEnabled: true)
            let timelineDescriptor = DetailMarkingView.cornerPositionDescriptor(
                photo: companionPhoto, timeline: timeline, expandedGroup: nil, language: .english)
            let timelineStrings = DetailPhotoCornerOverlay.metadataStrings(
                positionText: timelineDescriptor.positionText,
                isGroupFocus: timelineDescriptor.isGroupFocus,
                zoomText: nil,
                language: .english)
            #expect(!timelineDescriptor.isGroupFocus)
            let timelineVisible = try #require(timelineStrings.visible)
            #expect(!timelineVisible.contains("+ JPG"))
            #expect(!timelineVisible.contains("+ HIF"))
            #expect(!timelineStrings.accessible.contains("Group"))

            let presentationBox = TestPresentationBox(value: .photoPreview)
            let framesBox = DetailFrameBox()
            let countsBox = DetailCountBox()
            let source = ObservedDetailImages()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
            window.overrideUserInterfaceStyle = theme == .light ? .light : .dark

            let host = UIHostingController(
                rootView: TestDuoPoseDetailHost(
                    browsing: browsing,
                    images: source,
                    presentation: presentationBox,
                    isDuoExpanded: true,
                    isDuoCover: false,
                    usesVerticalToolbar: true,
                    hasFoldRegion: true,
                    showsGrid: true,
                    theme: theme,
                    settingsStore: store
                )
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                }
                .onPreferenceChange(HeaderControlCountsPreferenceKey.self) {
                    countsBox.counts = $0
                })
            host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("Timeline corner overlay settled") {
                framesBox.frames["clove.detail.photoCornerOverlay"] != nil
                    && self.findPreview(in: window) != nil
                    && source.deliveries.contains { $0.0 == companionPhoto.id }
            }

            #expect(countsBox.counts["clove.detail.fileName"] == 1)
            #expect(countsBox.counts["clove.detail.zoom"] == 1)
            let timelineZoomWidth = try #require(framesBox.frames["clove.detail.zoom"]).width

            // Enter Group Focus in Focus View -> square.stack glyph renders, VoiceOver label uses
            // "Group · ...", + JPG/+ HIF stays omitted, and 100% zoom appends magnification.
            let groupMemberID = group.members[0]
            let groupMember = try #require(browsing.photos.first { $0.id == groupMemberID })
            browsing.openGroup(group.id, on: groupMemberID)
            presentationBox.value = .focus
            let expandedGroup = try #require(timeline.activeGroup(with: group.id))
            let groupDescriptor = DetailMarkingView.cornerPositionDescriptor(
                photo: groupMember, timeline: timeline, expandedGroup: expandedGroup,
                language: .english)
            let groupFitStrings = DetailPhotoCornerOverlay.metadataStrings(
                positionText: groupDescriptor.positionText,
                isGroupFocus: groupDescriptor.isGroupFocus,
                zoomText: nil,
                language: .english)
            let groupZoomedStrings = DetailPhotoCornerOverlay.metadataStrings(
                positionText: groupDescriptor.positionText,
                isGroupFocus: groupDescriptor.isGroupFocus,
                zoomText: "100%",
                language: .english)
            #expect(groupDescriptor.isGroupFocus)
            #expect(groupFitStrings.visible == "1 / \(expandedGroup.visibleMembers.count)")
            #expect(
                groupFitStrings.accessible == "Group · 1 / \(expandedGroup.visibleMembers.count)")
            #expect(
                groupZoomedStrings.accessible
                    == "Group · 1 / \(expandedGroup.visibleMembers.count) · 100%")

            try await waitFor("Group Focus corner overlay settled") {
                guard let preview = self.findPreview(in: window),
                    self.findFilmstripScrollView(in: window, excluding: preview) != nil,
                    let zoomFrame = framesBox.frames["clove.detail.zoom"]
                else { return false }
                return source.deliveries.contains { $0.0 == groupMemberID }
                    && zoomFrame.width > 0
            }

            #expect(countsBox.counts["clove.detail.fileName"] == 1)
            #expect(countsBox.counts["clove.detail.zoom"] == 1)
            let groupZoomWidth = try #require(framesBox.frames["clove.detail.zoom"]).width

            // Verify zoomed magnification appends cleanly in Group Focus, growing the zoom row width.
            let preview = try #require(findPreview(in: window))
            preview.onDoubleTap?(.center)
            try await waitFor("Group Focus zoom magnification appeared in corner overlay") {
                guard let zoomFrame = framesBox.frames["clove.detail.zoom"] else { return false }
                return preview.isZoomed && zoomFrame.width > groupZoomWidth + 12
            }

            #expect(UIImage(systemName: "square.stack") != nil)
            let timelineRender = ImageRenderer(
                content: DetailPhotoCornerOverlay(
                    fileName: "a",
                    positionText: "100 / 999",
                    isGroupFocus: false,
                    zoomText: nil,
                    language: .english
                )
                .environment(\.cloveTheme, theme))
            timelineRender.scale = 2
            let groupRender = ImageRenderer(
                content: DetailPhotoCornerOverlay(
                    fileName: "a",
                    positionText: "100 / 999",
                    isGroupFocus: true,
                    zoomText: nil,
                    language: .english
                )
                .environment(\.cloveTheme, theme))
            groupRender.scale = 2
            let timelineImage = try #require(timelineRender.cgImage)
            let groupImage = try #require(groupRender.cgImage)
            #expect(groupImage.width > timelineImage.width)
            #expect(
                UIImage(cgImage: groupImage).pngData() != UIImage(cgImage: timelineImage).pngData())
            #expect(timelineZoomWidth > 0)
        }
    }

    @Test(arguments: [DetailPresentation.photoPreview, DetailPresentation.focus])
    func expandedDuoViewportOverlayStaysPinnedAcrossAspectSwitchesZoomPanAndReclaimsTopSpace(
        initialPresentation: DetailPresentation
    ) async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder open") { !browsing.isFolderOpening }
        let landscapeID = try #require(browsing.photos.first { $0.id.stem == "mmq02680" }?.id)
        let portraitID = try #require(browsing.photos.first { $0.id.stem == "mmq02681" }?.id)
        let source = AspectByPhotoDetailImages(portraitPhotos: [portraitID])
        browsing.openPhoto(landscapeID)

        let presentationBox = TestPresentationBox(value: initialPresentation)
        let framesBox = DetailFrameBox()
        let paneFramesBox = DetailFrameBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 920, height: 700)
        let host = UIHostingController(
            rootView: TestDuoPoseDetailHost(
                browsing: browsing,
                images: source,
                presentation: presentationBox,
                isDuoExpanded: true,
                isDuoCover: false,
                usesVerticalToolbar: true,
                hasFoldRegion: true,
                showsGrid: true,
                theme: .light,
                settingsStore: store
            )
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                framesBox.frames = $0
            }
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                paneFramesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let paneKey =
            initialPresentation == .photoPreview ? "clove.duo.photoPreview" : "clove.duo.focus"
        try await waitFor("Landscape photo and viewport overlay settled") {
            guard source.deliveredPhotos.contains(landscapeID),
                let preview = self.findPreview(in: window),
                let overlay = framesBox.frames["clove.detail.photoCornerOverlay"],
                framesBox.frames["clove.detail.focusToggle"] != nil,
                paneFramesBox.frames[paneKey] != nil
            else { return false }
            let fit = preview.imageRectAtFit()
            let stageInWindow = preview.convert(preview.bounds, to: window)
            let layoutMatches =
                initialPresentation == .photoPreview
                ? self.findCollectionView(in: window) != nil
                : self.findFilmstripScrollView(in: window, excluding: preview) != nil
            return layoutMatches
                && fit.width > fit.height
                && abs(overlay.minX - (stageInWindow.minX + 16)) <= 1.5
                && abs(overlay.minY - (stageInWindow.minY + 12)) <= 1.5
        }

        let preview = try #require(findPreview(in: window))
        let duoPaneFrame = try #require(paneFramesBox.frames[paneKey])
        let stageAtLandscape = preview.convert(preview.bounds, to: window)
        let landscapeFit = preview.imageRectAtFit()
        let landscapeOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        let landscapeFocus = try #require(framesBox.frames["clove.detail.focusToggle"])

        // No reserved 48 pt top header: usable stage starts at the top of the Duo photo pane and
        // takes the full usable height above the 70 pt bottom review/capsule band.
        #expect(framesBox.frames["clove.detail.photoHeader"] == nil)
        #expect(abs(stageAtLandscape.minY - duoPaneFrame.minY) <= 1.5)
        #expect(abs(stageAtLandscape.height - (duoPaneFrame.height - 70)) <= 1.5)
        // Wide landscape maximizes usable width without cropping and still keeps the badge pinned
        // to the viewport corner rather than the letterboxed image top.
        #expect(landscapeFit.minY > 30)
        #expect(abs(landscapeFit.width - stageAtLandscape.width) <= 1.5)
        #expect(abs(landscapeOverlay.minX - (stageAtLandscape.minX + 16)) <= 1.5)
        #expect(abs(landscapeOverlay.minY - (stageAtLandscape.minY + 12)) <= 1.5)
        #expect(landscapeOverlay.minY < stageAtLandscape.minY + landscapeFit.minY)
        #expect(landscapeFocus.minX >= landscapeOverlay.maxX + 6)
        #expect(abs(landscapeFocus.minY - (stageAtLandscape.minY + 12)) <= 1.5)

        // Switch to portrait photo: portrait fills the full recovered stage height while the
        // identity badge and focus toggle remain pinned at the exact same viewport coordinates.
        browsing.openPhoto(portraitID)
        try await waitFor("Portrait photo settled") {
            guard source.deliveredPhotos.contains(portraitID) else { return false }
            let fit = preview.imageRectAtFit()
            return fit.height > fit.width && abs(fit.height - preview.bounds.height) <= 1.5
        }
        let stageAtPortrait = preview.convert(preview.bounds, to: window)
        let portraitFit = preview.imageRectAtFit()
        let portraitOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        let portraitFocus = try #require(framesBox.frames["clove.detail.focusToggle"])

        #expect(sameFrame(stageAtPortrait, stageAtLandscape))
        #expect(portraitFit.minX > 30)
        #expect(abs(portraitFit.height - stageAtPortrait.height) <= 1.5)
        #expect(abs(portraitFit.height - (duoPaneFrame.height - 70)) <= 1.5)
        #expect(abs(portraitOverlay.minX - landscapeOverlay.minX) <= 1.0)
        #expect(abs(portraitOverlay.minY - landscapeOverlay.minY) <= 1.0)
        #expect(abs(portraitFocus.minX - landscapeFocus.minX) <= 2.0)
        #expect(abs(portraitFocus.minY - landscapeFocus.minY) <= 1.0)

        // Zoom to 100%, pan, and simulate rubber-band overscroll: viewport coordinates never drift.
        let zoomWidthAtFit = try #require(framesBox.frames["clove.detail.zoom"]).width
        preview.onDoubleTap?(.center)
        try await waitFor("zoom to 100% settled") {
            guard let zoomFrame = framesBox.frames["clove.detail.zoom"] else { return false }
            return preview.isZoomed && zoomFrame.width > zoomWidthAtFit + 12
        }
        try await Task.sleep(for: .milliseconds(250))

        let scroll = try #require(preview.subviews.first as? UIScrollView)
        scroll.setContentOffset(CGPoint(x: -28, y: -36), animated: false)
        try await Task.sleep(for: .milliseconds(150))

        let zoomedOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        let zoomedFocus = try #require(framesBox.frames["clove.detail.focusToggle"])
        #expect(abs(zoomedOverlay.minX - portraitOverlay.minX) <= 1.0)
        #expect(abs(zoomedOverlay.minY - portraitOverlay.minY) <= 1.0)
        #expect(abs(zoomedFocus.minX - portraitFocus.minX) <= 1.0)
        #expect(abs(zoomedFocus.minY - portraitFocus.minY) <= 1.0)

        // Return to fit and toggle top overlay status: fitted photo and stage stay invariant.
        preview.onDoubleTap?(.center)
        try await waitFor("returned to fit") { !preview.isZoomed }
        try await Task.sleep(for: .milliseconds(200))

        let fitBeforeToggle = preview.imageRectAtFit()
        browsing.showsFocusRegions = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(sameFrame(preview.imageRectAtFit(), fitBeforeToggle))
        browsing.showsFocusRegions = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(sameFrame(preview.imageRectAtFit(), fitBeforeToggle))

        // Chrome toggle hides the identity badge and restores it at the exact same coordinates
        // without changing the fitted photo on restore.
        preview.onChromeToggle?()
        try await waitFor("identity overlay hid with chrome") {
            framesBox.frames["clove.detail.photoCornerOverlay"] == nil
                && framesBox.frames["clove.detail.fileName"] == nil
                && framesBox.frames["clove.detail.zoom"] == nil
                && framesBox.frames["clove.detail.focusToggle"] != nil
        }

        preview.onChromeToggle?()
        try await waitFor("identity overlay restored with chrome") {
            let currentFit = preview.imageRectAtFit()
            return framesBox.frames["clove.detail.photoCornerOverlay"] != nil
                && framesBox.frames["clove.detail.fileName"] != nil
                && framesBox.frames["clove.detail.zoom"] != nil
                && abs(currentFit.height - fitBeforeToggle.height) <= 1.0
        }
        let restoredOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        #expect(abs(restoredOverlay.minX - portraitOverlay.minX) <= 1.0)
        #expect(abs(restoredOverlay.minY - portraitOverlay.minY) <= 1.0)
        let fitAfterRestore = preview.imageRectAtFit()
        #expect(abs(fitAfterRestore.minX - fitBeforeToggle.minX) <= 1.0)
        #expect(abs(fitAfterRestore.minY - fitBeforeToggle.minY) <= 1.0)
        #expect(abs(fitAfterRestore.width - fitBeforeToggle.width) <= 1.0)
        #expect(abs(fitAfterRestore.height - fitBeforeToggle.height) <= 1.0)
    }

    @Test
    func expandedDuoViewportOverlayRemainsStableAcrossLoadingPlaceholderErrorAndContrast()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder open") { !browsing.isFolderOpening }
        let loadingID = browsing.photos[2].id
        let unavailableID = browsing.photos[3].id
        let deferredID = browsing.photos[4].id
        let source = StateControlledDetailImages(
            heldPhoto: loadingID,
            unavailablePhoto: unavailableID,
            deferredPhoto: deferredID)
        browsing.openPhoto(loadingID)

        let presentationBox = TestPresentationBox(value: .photoPreview)
        let framesBox = DetailFrameBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 920, height: 680)
        let host = UIHostingController(
            rootView: TestDuoPoseDetailHost(
                browsing: browsing,
                images: source,
                presentation: presentationBox,
                isDuoExpanded: true,
                isDuoCover: false,
                usesVerticalToolbar: true,
                hasFoldRegion: true,
                showsGrid: true,
                theme: .dark,
                settingsStore: store
            )
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            source.releaseHeld()
            window.isHidden = true
            window.rootViewController = nil
        }

        // 1. Loading state (before placeholder or image arrives): badge & focus toggle already sit
        // at the exact viewport inset.
        try await waitFor("loading state viewport overlay did not appear") {
            self.findPreview(in: window) != nil
                && framesBox.frames["clove.detail.photoCornerOverlay"] != nil
                && framesBox.frames["clove.detail.focusToggle"] != nil
        }
        let preview = try #require(findPreview(in: window))
        let stageRect = preview.convert(preview.bounds, to: window)
        let loadingOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        let loadingFocus = try #require(framesBox.frames["clove.detail.focusToggle"])
        #expect(abs(loadingOverlay.minX - (stageRect.minX + 16)) <= 1.5)
        #expect(abs(loadingOverlay.minY - (stageRect.minY + 12)) <= 1.5)
        #expect(loadingFocus.minX >= loadingOverlay.maxX + 6)

        // 2. Loaded state: coordinates remain identical.
        source.releaseHeld()
        try await waitFor("loaded image did not arrive") {
            source.deliveredPhotos.contains(loadingID)
        }
        let loadedOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        let loadedFocus = try #require(framesBox.frames["clove.detail.focusToggle"])
        #expect(abs(loadedOverlay.minX - loadingOverlay.minX) <= 1.0)
        #expect(abs(loadedOverlay.minY - loadingOverlay.minY) <= 1.0)
        #expect(abs(loadedFocus.minX - loadingFocus.minX) <= 1.0)
        #expect(abs(loadedFocus.minY - loadingFocus.minY) <= 1.0)

        // 3. Unavailable & deferred error states: overlay remains pinned and clear of error copy.
        for errorID in [unavailableID, deferredID] {
            browsing.openPhoto(errorID)
            try await waitFor("error state did not appear") {
                framesBox.frames["clove.detail.unavailable"] != nil
            }
            let errorFrame = try #require(framesBox.frames["clove.detail.unavailable"])
            let errorOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
            let errorFocus = try #require(framesBox.frames["clove.detail.focusToggle"])
            #expect(abs(errorOverlay.minX - loadingOverlay.minX) <= 1.0)
            #expect(abs(errorOverlay.minY - loadingOverlay.minY) <= 1.0)
            #expect(abs(errorFocus.minY - loadingFocus.minY) <= 1.0)
            #expect(!errorFrame.intersects(errorOverlay))
            #expect(!errorFrame.intersects(errorFocus))
        }

        // 4. Contrast check across Light & Dark themes on bright white, pure black, and stage.
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "preparing",
            ])
        let contrastBrowsing = BrowsingModel(library: library)
        contrastBrowsing.openFolder()
        let lostLibrary = ControlledPhotoLibrary(rejected: [], stems: ["MMQ02680"])
        let lostBrowsing = BrowsingModel(library: lostLibrary)
        lostBrowsing.openFolder()
        lostLibrary.reportScanFinished()
        lostLibrary.reportDriveLoss()
        try await waitFor("lost browsing situation did not report") {
            lostBrowsing.folderSituation != nil
        }

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let backgrounds: [Color] = [.white, .black, theme.tokens.stage.color]
            for bg in backgrounds {
                let blank = ImageRenderer(
                    content: bg.frame(width: 220, height: 64)
                )
                blank.scale = 1
                let rendered = ImageRenderer(
                    content: ZStack(alignment: .leading) {
                        bg
                        HStack(spacing: 8) {
                            DetailPhotoCornerOverlay(
                                fileName: "MMQ02680.ARW",
                                positionText: "1 / 36",
                                isGroupFocus: false,
                                zoomText: nil,
                                language: .english)
                            SaveStatusIndicator(
                                browsing: lostBrowsing,
                                identifierPrefix: "clove.detail.saveState",
                                usesFloatingBackdrop: true)
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(width: 220, height: 64)
                    .environment(\.cloveTheme, theme)
                )
                rendered.scale = 1
                let blankImage = try #require(blank.cgImage)
                let overlayImage = try #require(rendered.cgImage)
                #expect(
                    UIImage(cgImage: overlayImage).pngData()
                        != UIImage(cgImage: blankImage).pngData())
            }
        }
    }

    @Test
    func expandedDuoCornerOverlayStacksAboveIndicatorsAndPassesThroughGesturesAndFocusRegions()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = CornerRegionAndLimitationImages()
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        store.update { $0.autoAdvance.destination = .stay }
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder open") { !browsing.isFolderOpening }
        let first = browsing.photos[4]
        let next = browsing.photos[5]
        browsing.openPhoto(first.id)

        let presentationBox = TestPresentationBox(value: .focus)
        let framesBox = DetailFrameBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 920, height: 700)
        let host = UIHostingController(
            rootView: TestDuoPoseDetailHost(
                browsing: browsing,
                images: source,
                presentation: presentationBox,
                isDuoExpanded: true,
                isDuoCover: false,
                usesVerticalToolbar: true,
                hasFoldRegion: true,
                showsGrid: false,
                theme: .dark,
                settingsStore: store
            )
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("corner overlay, focus region, indicators, and limitation settled") {
            guard let preview = self.findPreview(in: window) else { return false }
            return framesBox.frames["clove.detail.photoCornerOverlay"] != nil
                && framesBox.frames["clove.detail.focusToggle"] != nil
                && self.findFocusControl(in: preview) != nil
                && framesBox.frames["clove.detail.focusIndicators"] != nil
                && framesBox.frames["clove.detail.limitation"] != nil
        }

        let preview = try #require(findPreview(in: window))
        let cornerOverlay = try #require(framesBox.frames["clove.detail.photoCornerOverlay"])
        let focusToggleFrame = try #require(framesBox.frames["clove.detail.focusToggle"])
        let indicatorsFrame = try #require(framesBox.frames["clove.detail.focusIndicators"])
        let limitationFrame = try #require(framesBox.frames["clove.detail.limitation"])

        // Passive indicators and limitation note stack cleanly below the top row without overlap.
        #expect(!cornerOverlay.intersects(focusToggleFrame))
        #expect(!cornerOverlay.intersects(indicatorsFrame))
        #expect(!focusToggleFrame.intersects(indicatorsFrame))
        #expect(indicatorsFrame.minY >= max(cornerOverlay.maxY, focusToggleFrame.maxY) + 4)
        #expect(!indicatorsFrame.intersects(limitationFrame))
        #expect(limitationFrame.minY >= indicatorsFrame.maxY + 4)

        // Focus region placed under the upper-leading corner (x=0.08, y=0.08) still receives hits
        // right through the passive corner overlay, while passive indicators, limitation note, and
        // empty area pass through to the preview and the floating focus toggle receives its own tap.
        let cornerRegion = try #require(findFocusControl(in: preview))
        let regionCenterInWindow = cornerRegion.convert(
            CGPoint(x: cornerRegion.bounds.midX, y: cornerRegion.bounds.midY), to: window)
        let hitView = window.hitTest(regionCenterInWindow, with: nil)
        #expect(hitView === cornerRegion)

        let indicatorHit = window.hitTest(
            CGPoint(x: indicatorsFrame.midX, y: indicatorsFrame.midY), with: nil)
        #expect(indicatorHit?.isDescendant(of: preview) == true)
        let limitationHit = window.hitTest(
            CGPoint(x: limitationFrame.midX, y: limitationFrame.midY), with: nil)
        #expect(limitationHit?.isDescendant(of: preview) == true)
        let trailingControlsEdge = max(
            focusToggleFrame.maxX,
            framesBox.frames["clove.detail.preparation"]?.maxX ?? 0)
        let emptyAreaHit = window.hitTest(
            CGPoint(x: trailingControlsEdge + 40, y: focusToggleFrame.midY), with: nil)
        #expect(emptyAreaHit?.isDescendant(of: preview) == true)
        let toggleHit = window.hitTest(
            CGPoint(x: focusToggleFrame.midX, y: focusToggleFrame.midY), with: nil)
        #expect(toggleHit != nil)
        #expect(toggleHit?.isDescendant(of: preview) == false)

        // Double-tap through the corner overlay area zooms to 100% and returns to fit.
        let overlayCenterInPreview = window.convert(
            CGPoint(x: cornerOverlay.midX, y: cornerOverlay.midY), to: preview)
        preview.doubleTap(at: overlayCenterInPreview)
        try await waitFor("double tap through corner overlay zoomed") { preview.isZoomed }
        preview.doubleTap(at: overlayCenterInPreview)
        try await waitFor("double tap through corner overlay returned to fit") { !preview.isZoomed }

        // Tapping the corner focus region through the corner area enters 100% inspection on it.
        cornerRegion.sendActions(for: .touchUpInside)
        try await waitFor("corner focus region tap zoomed") { preview.isZoomed }
        try await Task.sleep(for: .milliseconds(250))
        let regionSnapshot = try #require(preview.zoomSnapshot)
        #expect(regionSnapshot.anchor.x < 0.25)
        #expect(regionSnapshot.anchor.y < 0.25)
        preview.doubleTap(at: overlayCenterInPreview)
        try await waitFor("returned to fit after region tap") { !preview.isZoomed }

        // Vertical marking swipe and horizontal navigation swipe starting inside the corner overlay
        // work normally through the passive overlay.
        try sendSwipe(
            to: preview,
            start: overlayCenterInPreview,
            travel: CGPoint(x: 0, y: -130))
        #expect(browsing.shownMarks(for: first.id).rating != .unrated)

        let stepTravel = -max(180, preview.bounds.width * 0.3)
        try sendSwipe(
            to: preview,
            start: overlayCenterInPreview,
            travel: CGPoint(x: stepTravel, y: 0))
        #expect(browsing.state.currentPhoto == next.id)
        #expect(preview.chromeTapIsEnabled)
    }

    @Test
    func nonExpandedDuoCoverHalfFoldIPhoneAndIPadKeepToolbarHeadersWithCompanions() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder open") { !browsing.isFolderOpening }
        let photoWithJPEG = try #require(
            browsing.photos.first { $0.id.stem == "mmq02680" }?.id)
        browsing.openPhoto(photoWithJPEG)

        struct StandardPoseCase {
            let name: String
            let size: CGSize
            let horizontal: UIUserInterfaceSizeClass
            let vertical: UIUserInterfaceSizeClass
            let idiom: UIUserInterfaceIdiom
            let usesSystemToolbar: Bool
            let isDuoCover: Bool
            let isDuoExpanded: Bool
            let usesVerticalToolbar: Bool
            let hasFoldRegion: Bool
        }

        let cases: [StandardPoseCase] = [
            StandardPoseCase(
                name: "Duo Cover",
                size: CGSize(width: 466, height: 678),
                horizontal: .compact, vertical: .regular, idiom: .phone,
                usesSystemToolbar: true, isDuoCover: true, isDuoExpanded: false,
                usesVerticalToolbar: true, hasFoldRegion: false),
            StandardPoseCase(
                name: "iPhone Portrait",
                size: CGSize(width: 393, height: 852),
                horizontal: .compact, vertical: .regular, idiom: .phone,
                usesSystemToolbar: false, isDuoCover: false, isDuoExpanded: false,
                usesVerticalToolbar: false, hasFoldRegion: false),
            StandardPoseCase(
                name: "iPhone Landscape",
                size: CGSize(width: 852, height: 393),
                horizontal: .compact, vertical: .compact, idiom: .phone,
                usesSystemToolbar: false, isDuoCover: false, isDuoExpanded: false,
                usesVerticalToolbar: false, hasFoldRegion: false),
            StandardPoseCase(
                name: "iPad Regular",
                size: CGSize(width: 1024, height: 768),
                horizontal: .regular, vertical: .regular, idiom: .pad,
                usesSystemToolbar: false, isDuoCover: false, isDuoExpanded: false,
                usesVerticalToolbar: false, hasFoldRegion: false),
        ]

        for pose in cases {
            let presentationBox = TestPresentationBox(value: .focus)
            let framesBox = DetailFrameBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: pose.size)

            let rootView = Group {
                if pose.usesSystemToolbar {
                    NavigationStack {
                        DetailScreen(
                            browsing: browsing,
                            images: SampleDetailImages(),
                            duo: DuoDetailLayout(
                                presentation: Binding(
                                    get: { presentationBox.value },
                                    set: { presentationBox.value = $0 }),
                                filter: AnyView(EmptyView()),
                                more: AnyView(EmptyView()),
                                bottom: AnyView(EmptyView()),
                                showsGrid: false))
                    }
                } else {
                    DetailScreen(
                        browsing: browsing,
                        images: SampleDetailImages(),
                        presentation: Binding(
                            get: { presentationBox.value },
                            set: { presentationBox.value = $0 }))
                }
            }
            .environment(SettingsStore.sample)
            .environment(\.cloveUserInterfaceIdiom, pose.idiom)
            .environment(\.usesSystemBrowsingToolbar, pose.usesSystemToolbar)
            .environment(\.isDuoCover, pose.isDuoCover)
            .environment(\.isDuoExpanded, pose.isDuoExpanded)
            .environment(\.usesVerticalBrowsingToolbar, pose.usesVerticalToolbar)
            .environment(\.hasFoldRegion, pose.hasFoldRegion)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                framesBox.frames = $0
            }

            let host = UIHostingController(rootView: rootView)
            host.traitOverrides.horizontalSizeClass = pose.horizontal
            host.traitOverrides.verticalSizeClass = pose.vertical
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("\(pose.name) header did not settle") {
                self.findPreview(in: window) != nil
                    && framesBox.frames["clove.detail.fileName"] != nil
                    && framesBox.frames["clove.detail.zoom"] != nil
            }

            #expect(
                framesBox.frames["clove.detail.photoCornerOverlay"] == nil,
                Comment(rawValue: "\(pose.name) must not render expanded Duo corner overlay"))
            if let zoomLabel = findAccessibilityElement(
                withIdentifier: "clove.detail.zoom", in: window)?.accessibilityLabel
            {
                #expect(
                    zoomLabel.contains("+ JPG"),
                    Comment(rawValue: "\(pose.name) must preserve + JPG in header subtitle"))
            }
        }

        // Half Fold: neither expanded Duo header nor corner overlay renders.
        let halfFoldPresentation = TestPresentationBox(value: .photoPreview)
        let halfFoldFrames = DetailFrameBox()
        let halfFoldWindow = UIWindow(windowScene: scene)
        halfFoldWindow.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        let halfFoldHost = UIHostingController(
            rootView: TestDuoPoseDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                presentation: halfFoldPresentation,
                isDuoExpanded: true,
                isDuoCover: false,
                usesVerticalToolbar: false,
                hasFoldRegion: true,
                showsGrid: true,
                theme: .light
            )
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                halfFoldFrames.frames = $0
            })
        halfFoldHost.traitOverrides.horizontalSizeClass = .regular
        halfFoldWindow.rootViewController = halfFoldHost
        halfFoldWindow.makeKeyAndVisible()
        defer {
            halfFoldWindow.isHidden = true
            halfFoldWindow.rootViewController = nil
        }

        try await waitFor("Half Fold settled") {
            self.findPreview(in: halfFoldWindow) != nil
                && self.findCollectionView(in: halfFoldWindow) != nil
        }
        #expect(halfFoldFrames.frames["clove.detail.photoHeader"] == nil)
        #expect(halfFoldFrames.frames["clove.detail.photoCornerOverlay"] == nil)
    }

    @Test func expandedFilmstripEndCapsStaySymmetricalHighContrastAndKeepTimelineClean()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let folder = FolderIdentity(rawValue: "filmstrip-caps-test")
        let photos = (1...5).map { index in
            GridPhoto(
                id: PhotoIdentity(
                    folderID: folder, relativeFolderPath: "", stem: "CAP00\(index)"),
                fileName: "CAP00\(index).ARW",
                time: .unavailable,
                marks: PhotoMarks())
        }
        let groupID = GroupID(rawValue: "caps-group")
        let groups = [
            BrowsingGroup(id: groupID, members: [photos[1].id, photos[2].id, photos[3].id])
        ]
        let timeline = DetailTimeline(photos: photos, groups: groups, groupsEnabled: true)
        let expanded = try #require(timeline.activeGroup(with: groupID))

        for metrics in [DetailFilmstrip.Metrics.standard, .compact] {
            for theme in [CloveTheme.light, CloveTheme.dark, CloveTheme.nord] {
                for backdrop in [Color.white, Color.black] {
                    let state = FilmstripCapTestState(
                        timeline: timeline,
                        expandedGroup: nil,
                        current: photos[1].id)
                    let framesBox = DetailFrameBox()

                    struct HostView: View {
                        @Bindable var state: FilmstripCapTestState
                        let metrics: DetailFilmstrip.Metrics
                        let theme: CloveTheme
                        let backdrop: Color

                        var body: some View {
                            ZStack {
                                backdrop
                                DetailFilmstrip(
                                    timeline: state.timeline,
                                    expandedGroup: state.expandedGroup,
                                    current: state.current,
                                    thumbnails: TestLibrary.sampleThumbnails,
                                    metrics: metrics,
                                    openPhoto: { _ in },
                                    selectGroupPhoto: { state.current = $0 },
                                    expandGroup: { _ in },
                                    collapseGroup: { state.expandedGroup = nil }
                                )
                            }
                            .frame(width: 402, height: 120)
                            .environment(\.cloveTheme, theme)
                            .environment(\.scenePhase, .active)
                        }
                    }

                    let host = UIHostingController(
                        rootView: HostView(
                            state: state, metrics: metrics, theme: theme, backdrop: backdrop
                        )
                        .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                            framesBox.frames = frames
                        })
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: 402, height: 120)
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    defer {
                        window.isHidden = true
                        window.rootViewController = nil
                    }

                    try await waitFor("Timeline filmstrip did not lay out") {
                        framesBox.frames["clove.detail.filmstrip"] != nil
                            && framesBox.frames["clove.detail.filmstrip.timeline"] != nil
                    }
                    let timelineStripFrame = try #require(
                        framesBox.frames["clove.detail.filmstrip"])
                    #expect(abs(timelineStripFrame.height - metrics.bandHeight) <= 0.5)
                    #expect(framesBox.frames["clove.detail.filmstrip.group.gridPicker"] == nil)
                    #expect(framesBox.frames["clove.detail.filmstrip.group.fold"] == nil)
                    #expect(framesBox.frames["clove.detail.filmstrip.expandedGroup"] == nil)

                    state.expandedGroup = expanded
                    try await waitFor("Expanded group caps did not lay out") {
                        framesBox.frames["clove.detail.filmstrip.group.gridPicker"] != nil
                            && framesBox.frames["clove.detail.filmstrip.group.fold"] != nil
                            && framesBox.frames["clove.detail.filmstrip.expandedGroup"] != nil
                    }
                    try await Task.sleep(for: .milliseconds(320))

                    let expandedStripFrame = try #require(
                        framesBox.frames["clove.detail.filmstrip"])
                    let trayFrame = try #require(
                        framesBox.frames["clove.detail.filmstrip.expandedGroup"])
                    let gridPickerFrame = try #require(
                        framesBox.frames["clove.detail.filmstrip.group.gridPicker"])
                    let foldFrame = try #require(
                        framesBox.frames["clove.detail.filmstrip.group.fold"])

                    #expect(abs(expandedStripFrame.height - metrics.bandHeight) <= 0.5)
                    #expect(abs(gridPickerFrame.width - metrics.collapseCapWidth) <= 0.5)
                    #expect(abs(foldFrame.width - metrics.collapseCapWidth) <= 0.5)
                    #expect(abs(gridPickerFrame.height - metrics.thumbnailHeight) <= 0.5)
                    #expect(abs(foldFrame.height - metrics.thumbnailHeight) <= 0.5)
                    #expect(gridPickerFrame.maxX < foldFrame.minX)
                    #expect(abs(gridPickerFrame.midY - foldFrame.midY) <= 0.5)
                    #expect(gridPickerFrame.minX >= trayFrame.minX - 0.5)
                    #expect(foldFrame.maxX <= trayFrame.maxX + 0.5)

                    // Sample the solid top-interior corner of each end cap to confirm both render
                    // the opaque inverted primaryText backing over both white and black backdrops.
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let snapshot = UIGraphicsImageRenderer(
                        size: window.bounds.size, format: format
                    ).image { _ in
                        _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let cgImage = try #require(snapshot.cgImage)
                    let expectedBacking = theme.tokens.primaryText
                    for capFrame in [gridPickerFrame, foldFrame] {
                        let sample = try rgbaPixel(
                            in: cgImage,
                            at: CGPoint(x: capFrame.minX + 5, y: capFrame.minY + 5))
                        #expect(abs(sample.r - expectedBacking.red) < 0.08)
                        #expect(abs(sample.g - expectedBacking.green) < 0.08)
                        #expect(abs(sample.b - expectedBacking.blue) < 0.08)
                    }
                }
            }
        }
    }

    @Test func groupPhotoGridPickerAdaptsPresentationAndDismissesSafely() async throws {
        #expect(
            GroupPhotoGridPickerPresentationMode.resolved(horizontalSizeClass: .regular)
                == .popover)
        #expect(
            GroupPhotoGridPickerPresentationMode.resolved(horizontalSizeClass: .compact) == .sheet)
        #expect(GroupPhotoGridPickerPresentationMode.resolved(horizontalSizeClass: nil) == .sheet)
        #expect(GroupPhotoGridPicker.popoverHeight(memberCount: 3, compactHeight: false) < 200)
        #expect(GroupPhotoGridPicker.popoverHeight(memberCount: 40, compactHeight: false) <= 400)
        #expect(GroupPhotoGridPicker.popoverHeight(memberCount: 40, compactHeight: true) <= 240)

        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let folder = FolderIdentity(rawValue: "grid-picker-presentation")
        let photos = (1...8).map { index in
            GridPhoto(
                id: PhotoIdentity(
                    folderID: folder, relativeFolderPath: "", stem: "GRP00\(index)"),
                fileName: "GRP00\(index).ARW",
                time: .unavailable,
                marks: PhotoMarks())
        }
        let firstGroupID = GroupID(rawValue: "group-a")
        let secondGroupID = GroupID(rawValue: "group-b")
        let groups = [
            BrowsingGroup(id: firstGroupID, members: Array(photos[0..<4].map(\.id))),
            BrowsingGroup(id: secondGroupID, members: Array(photos[4..<8].map(\.id))),
        ]
        let timeline = DetailTimeline(photos: photos, groups: groups, groupsEnabled: true)
        let firstGroup = try #require(timeline.activeGroup(with: firstGroupID))
        let secondGroup = try #require(timeline.activeGroup(with: secondGroupID))

        let state = FilmstripCapTestState(
            timeline: timeline,
            expandedGroup: firstGroup,
            current: photos[0].id)
        let triggerBox = DetailPickerTriggerBox()

        struct HostView: View {
            @Bindable var state: FilmstripCapTestState
            @Bindable var triggerBox: DetailPickerTriggerBox

            var body: some View {
                VStack {
                    Spacer()
                    DetailFilmstrip(
                        timeline: state.timeline,
                        expandedGroup: state.expandedGroup,
                        current: state.current,
                        thumbnails: TestLibrary.sampleThumbnails,
                        gridPickerDismissToken: state.dismissToken,
                        openPhoto: { _ in },
                        selectGroupPhoto: { state.current = $0 },
                        expandGroup: { _ in },
                        collapseGroup: { state.expandedGroup = nil }
                    )
                }
                .environment(\.cloveTheme, .light)
                .environment(\.scenePhase, state.scenePhase)
                .environment(\.tapPickerTriggerRequest, triggerBox.trigger)
            }
        }

        let host = UIHostingController(rootView: HostView(state: state, triggerBox: triggerBox))
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(100))

        // 1. Compact width presents a sheet.
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("compact sheet did not present") {
            self.topPresentedViewController(from: host)?.sheetPresentationController != nil
        }

        // 2. Flipping size class (compact -> regular) auto-dismisses cleanly.
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor("sheet did not dismiss on horizontalSizeClass change") {
            self.topPresentedViewController(from: host) == nil
        }

        // 3. Regular width presents a popover anchored to the grid picker button.
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("regular popover did not present") {
            self.topPresentedViewController(from: host)?.popoverPresentationController != nil
        }

        // 4. Collapsing Group Focus dismisses the popover.
        state.expandedGroup = nil
        try await waitFor("popover did not dismiss when expandedGroup became nil") {
            self.topPresentedViewController(from: host) == nil
        }

        // 5. Switching to a different expanded group ID dismisses the popover.
        state.expandedGroup = firstGroup
        try await Task.sleep(for: .milliseconds(100))
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("popover did not re-present") {
            self.topPresentedViewController(from: host) != nil
        }
        state.expandedGroup = secondGroup
        state.current = photos[4].id
        try await waitFor("popover did not dismiss on group ID change") {
            self.topPresentedViewController(from: host) == nil
        }

        // 6. Scene backgrounding / inactivation dismisses the popover.
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("popover did not re-present before scenePhase change") {
            self.topPresentedViewController(from: host) != nil
        }
        state.scenePhase = .inactive
        UIView.performWithoutAnimation {
            _ = window.snapshotView(afterScreenUpdates: true)
        }
        try await waitFor("popover did not dismiss on inactive scenePhase") {
            self.topPresentedViewController(from: host) == nil
        }

        // 7. External dismiss token (chrome hide / marking key) dismisses the popover.
        state.scenePhase = .active
        try await Task.sleep(for: .milliseconds(80))
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("popover did not re-present before dismissToken") {
            self.topPresentedViewController(from: host) != nil
        }
        state.dismissToken += 1
        try await waitFor("popover did not dismiss on dismissToken change") {
            self.topPresentedViewController(from: host) == nil
        }
    }

    @Test func groupPhotoGridPickerListsVisibleMembersMarksCurrentAndSelectsPhoto() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let folder = FolderIdentity(rawValue: "grid-picker-members")
        let allPhotos = try (1...24).map { index in
            let stem = String(format: "GRP%03d", index)
            let marks: PhotoMarks =
                switch index {
                case 1: PhotoMarks(rating: try #require(Rating(rawValue: 4)))
                case 2: PhotoMarks(label: ColourLabel(colour: .green))
                case 3: PhotoMarks(rating: .rejected)
                default: PhotoMarks()
                }
            return GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem),
                fileName: "\(stem).ARW",
                time: .unavailable,
                marks: marks)
        }
        let outsidePhoto = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "OUT001"),
            fileName: "OUT001.ARW",
            time: .unavailable,
            marks: PhotoMarks())
        let groupID = GroupID(rawValue: "grid-picker-burst")
        let groups = [BrowsingGroup(id: groupID, members: allPhotos.map(\.id))]

        // 1. Respects active filters: filtered-out members drop from visibleMembers & shrink height.
        let fullTimeline = DetailTimeline(
            photos: allPhotos + [outsidePhoto], groups: groups, groupsEnabled: true)
        let fullGroup = try #require(fullTimeline.activeGroup(with: groupID))
        #expect(fullGroup.visibleMembers.count == 24)
        #expect(!fullGroup.visibleMembers.contains(where: { $0.id == outsidePhoto.id }))

        let smallPhotos = Array(allPhotos.prefix(8))
        let smallGroups = [BrowsingGroup(id: groupID, members: smallPhotos.map(\.id))]
        let unfilteredSmall = DetailTimeline(
            photos: smallPhotos, groups: smallGroups, groupsEnabled: true)
        let filteredSmallPhotos = smallPhotos.enumerated().compactMap { offset, photo in
            offset < 4 ? photo : nil
        }
        let filteredSmall = DetailTimeline(
            photos: filteredSmallPhotos, groups: smallGroups, groupsEnabled: true)
        let filteredGroup = try #require(filteredSmall.activeGroup(with: groupID))
        #expect(filteredGroup.visibleMembers.count == 4)
        #expect(
            GroupPhotoGridPicker.popoverHeight(
                memberCount: filteredGroup.visibleMembers.count, compactHeight: false)
                < GroupPhotoGridPicker.popoverHeight(
                    memberCount: try #require(unfilteredSmall.activeGroup(with: groupID))
                        .visibleMembers.count,
                    compactHeight: false))

        // 2. Long burst auto-scrolls the picker to `current` when presented from DetailFilmstrip.
        let targetCurrent = allPhotos[21].id
        let triggerBox = DetailPickerTriggerBox()
        struct FilmstripPopoverHost: View {
            let timeline: DetailTimeline
            let expandedGroup: ActiveBrowsingGroup
            let current: PhotoIdentity
            let thumbnails: any GridThumbnailSource
            @Bindable var triggerBox: DetailPickerTriggerBox

            var body: some View {
                VStack {
                    Spacer()
                    DetailFilmstrip(
                        timeline: timeline,
                        expandedGroup: expandedGroup,
                        current: current,
                        thumbnails: thumbnails,
                        openPhoto: { _ in },
                        selectGroupPhoto: { _ in },
                        expandGroup: { _ in },
                        collapseGroup: {}
                    )
                }
                .environment(\.cloveTheme, .dark)
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, triggerBox.trigger)
            }
        }

        let solidThumbnails = SolidWhiteThumbnails()
        let host = UIHostingController(
            rootView: FilmstripPopoverHost(
                timeline: fullTimeline,
                expandedGroup: fullGroup,
                current: targetCurrent,
                thumbnails: solidThumbnails,
                triggerBox: triggerBox))
        host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(100))
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("group picker popover did not scroll to current photo") {
            guard let presented = self.topPresentedViewController(from: host),
                let scrollView = self.findFirstScrollView(in: presented.view)
            else { return false }
            return scrollView.contentSize.height > scrollView.bounds.height + 1
                && scrollView.contentOffset.y > 0
        }

        host.dismiss(animated: false)

        // 3. Visual indicators inside GroupPhotoGridPicker: current ring, green label, reject dim.
        let fourGroup = try #require(filteredSmall.activeGroup(with: groupID))
        let pickerHeight = GroupPhotoGridPicker.popoverHeight(
            memberCount: fourGroup.visibleMembers.count, compactHeight: false)
        let pickerHost = UIHostingController(
            rootView: GroupPhotoGridPicker(
                group: fourGroup,
                current: smallPhotos[0].id,
                thumbnails: solidThumbnails,
                showsDoneButton: false,
                onSelect: { _ in }
            )
            .ignoresSafeArea()
            .environment(\.cloveTheme, .dark))
        pickerHost.safeAreaRegions = []
        let pickerWindow = UIWindow(windowScene: scene)
        pickerWindow.frame = CGRect(x: 0, y: 120, width: 340, height: pickerHeight)
        pickerWindow.rootViewController = pickerHost
        pickerWindow.makeKeyAndVisible()
        defer {
            pickerWindow.isHidden = true
            pickerWindow.rootViewController = nil
        }

        pickerWindow.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        pickerWindow.layoutIfNeeded()

        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pickerWindow.bounds.size, format: format)
        let image = renderer.image { _ in
            pickerWindow.drawHierarchy(in: pickerWindow.bounds, afterScreenUpdates: true)
        }
        let cgImage = try #require(image.cgImage)

        // Locate exact pixel bounds of the unmarked white thumbnail (cell index 3).
        let cellSide: CGFloat = (340 - 24 - 18) / 4
        let stepX: CGFloat = cellSide + 6
        func cellMinX(_ index: Int) -> CGFloat { (12 + CGFloat(index) * stepX) * scale }
        let normalCenterX = cellMinX(3) + (cellSide * scale) / 2
        var whiteRowYs: [Int] = []
        for y in 0..<cgImage.height {
            let probe = try rgbaPixel(in: cgImage, at: CGPoint(x: normalCenterX, y: CGFloat(y)))
            if probe.r > 0.9, probe.g > 0.9, probe.b > 0.9 {
                whiteRowYs.append(y)
            }
        }
        let cellTopY = CGFloat(try #require(whiteRowYs.first))
        let cellBottomY = CGFloat(try #require(whiteRowYs.last))
        let cellCenterY = (cellTopY + cellBottomY) / 2
        #expect(cellBottomY - cellTopY >= 130)

        // Rejected photo (index 2) renders noticeably dimmer than normal photo (index 3).
        let rejectedCenter = try rgbaPixel(
            in: cgImage, at: CGPoint(x: cellMinX(2) + (cellSide * scale) / 2, y: cellCenterY))
        let normalCenter = try rgbaPixel(
            in: cgImage, at: CGPoint(x: normalCenterX, y: cellCenterY))
        #expect(normalCenter.r > 0.9)
        #expect(rejectedCenter.r < normalCenter.r - 0.35)

        // CurrentPhotoIndicator accent ring renders on cell 0's left edge and not on cell 3's.
        let accent = CloveTheme.dark.tokens.accent
        let hasAccentOnCell0 = try (0...10).contains { dx in
            let sample = try rgbaPixel(
                in: cgImage, at: CGPoint(x: cellMinX(0) - 2 + CGFloat(dx), y: cellCenterY))
            return abs(sample.r - accent.red) < 0.15
                && abs(sample.g - accent.green) < 0.15
                && abs(sample.b - accent.blue) < 0.15
        }
        let hasAccentOnCell3 = try (0...10).contains { dx in
            let sample = try rgbaPixel(
                in: cgImage, at: CGPoint(x: cellMinX(3) - 2 + CGFloat(dx), y: cellCenterY))
            return abs(sample.r - accent.red) < 0.15
                && abs(sample.g - accent.green) < 0.15
                && abs(sample.b - accent.blue) < 0.15
        }
        #expect(hasAccentOnCell0)
        #expect(!hasAccentOnCell3)

        // Green label dot appears in the bottom-trailing corner of cell 1 (index 1).
        var foundGreenDot = false
        for dy in 2...36 {
            for dx in 2...36 {
                let sample = try rgbaPixel(
                    in: cgImage,
                    at: CGPoint(
                        x: cellMinX(1) + cellSide * scale - CGFloat(dx),
                        y: cellBottomY - CGFloat(dy)))
                if sample.g > sample.r + 0.12, sample.g > sample.b + 0.12 {
                    foundGreenDot = true
                    break
                }
            }
            if foundGreenDot { break }
        }
        #expect(foundGreenDot)
    }

    private func rgbaPixel(in image: CGImage, at point: CGPoint) throws -> (
        r: Double, g: Double, b: Double, a: Double
    ) {
        let x = max(0, min(image.width - 1, Int(point.x.rounded())))
        let y = max(0, min(image.height - 1, Int(point.y.rounded())))
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: &bytes,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(x),
                y: -CGFloat(image.height - 1 - y),
                width: CGFloat(image.width),
                height: CGFloat(image.height)))
        return (
            Double(bytes[0]) / 255.0,
            Double(bytes[1]) / 255.0,
            Double(bytes[2]) / 255.0,
            Double(bytes[3]) / 255.0
        )
    }

    private func topPresentedViewController(from controller: UIViewController) -> UIViewController?
    {
        if let presented = controller.presentedViewController { return presented }
        for child in controller.children {
            if let presented = topPresentedViewController(from: child) { return presented }
        }
        return nil
    }

    private func sendSwipe(
        to preview: DetailZoomContainerView,
        start: CGPoint = CGPoint(x: 195, y: 300),
        travel: CGPoint
    ) throws {
        let pan = DetailTestPan()
        _ = preview.gestureRecognizer(
            pan, shouldReceive: DetailMutableTouch(view: preview, location: start))
        let initial = CGPoint(
            x: travel.x == 0 ? 0 : (travel.x < 0 ? -15 : 15),
            y: travel.y == 0 ? 0 : (travel.y < 0 ? -15 : 15))
        pan.travel = initial
        pan.locationPoint = CGPoint(x: start.x + initial.x, y: start.y + initial.y)
        try #require(preview.gestureRecognizerShouldBegin(pan))
        preview.handleMarkingPan(pan)
        pan.sampleState = .changed
        pan.travel = travel
        pan.locationPoint = CGPoint(x: start.x + travel.x, y: start.y + travel.y)
        preview.handleMarkingPan(pan)
        pan.sampleState = .ended
        preview.handleMarkingPan(pan)
    }

    private func waitFor(
        _ message: String = "Detail presentation did not settle within five seconds",
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), Comment(rawValue: message))
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

    private func findAccessibilityElement(
        withIdentifier identifier: String, in view: UIView
    ) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews {
            if let found = findAccessibilityElement(withIdentifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    private func findFirstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, !(view is UICollectionView) {
            return scrollView
        }
        for child in view.subviews {
            if let found = findFirstScrollView(in: child) { return found }
        }
        return nil
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collectionView = view as? UICollectionView { return collectionView }
        for child in view.subviews {
            if let found = findCollectionView(in: child) { return found }
        }
        return nil
    }

    private func findFilmstripScrollView(
        in view: UIView, excluding preview: DetailZoomContainerView
    ) -> UIScrollView? {
        findFilmstripScrollViews(in: view, excluding: preview).first
    }

    private func findFilmstripScrollViews(
        in view: UIView, excluding preview: DetailZoomContainerView
    ) -> [UIScrollView] {
        if view === preview { return [] }
        var matches: [UIScrollView] = []
        if let scrollView = view as? UIScrollView, !(view is UICollectionView) {
            matches.append(scrollView)
        }
        for child in view.subviews {
            matches.append(contentsOf: findFilmstripScrollViews(in: child, excluding: preview))
        }
        return matches
    }

    /// The finishing action the screen offers for `group` right now, from the model's marks, so a
    /// test can tell when the pill is available and when it is not (#304, #305).
    private func finishingPlan(
        for group: BrowsingGroup, currentPhoto: PhotoIdentity, in browsing: BrowsingModel
    ) -> GroupFinishingPlan? {
        let timeline = DetailTimeline(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: true)
        guard let expanded = timeline.activeGroup(with: group.id) else { return nil }
        return GroupFinishingPlan(
            group: expanded, action: .rejectUnmarked, currentPhoto: currentPhoto)
    }

    /// The rect the photo's pixels occupy at fit: the stage, less the letterbox the aspect fit
    /// leaves around them. The chrome floats over the stage, so a test can tell whether a floating
    /// control reaches the photo.
    private func fittedPhotoRect(
        in preview: DetailZoomContainerView, window: UIWindow
    ) -> CGRect? {
        guard
            let imageView = preview.subviews.compactMap({ $0 as? UIScrollView })
                .first?.subviews.compactMap({ $0 as? UIImageView }).first,
            let image = imageView.image,
            image.size.width > 0, image.size.height > 0
        else { return nil }
        let bounds = imageView.bounds
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height)
        return imageView.convert(rect, to: window)
    }
}

/// The sample's photos with a portrait raster, so the fitted band fills the stage's height the way
/// a camera's portrait photograph does. Everything else is the sample's behaviour (#305).
@MainActor
private final class PortraitDetailImages: DetailImageSource {
    private let sample: SampleDetailImages
    private let portrait: Bool
    private(set) var delivered = false

    init(sample: SampleDetailImages, portrait: Bool) {
        self.sample = sample
        self.portrait = portrait
    }

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        await sample.placeholder(for: photo, gridThumbnails: gridThumbnails)
    }

    func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        let outcome = await sample.image(for: photo, request: request)
        guard case .image(let image) = outcome else { return outcome }
        delivered = true
        guard portrait, let pixels = Self.portraitPixels else { return outcome }
        return .image(
            DetailImage(
                image: pixels, source: image.source, quality: image.quality,
                hasRAW: image.hasRAW,
                fullResolutionSize: CGSize(width: 2_000, height: 3_000)))
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    /// One 800 × 1200 raster, drawn once: tall enough that the fit is height-limited.
    private static let portraitPixels: CGImage? = {
        guard
            let context = CGContext(
                data: nil, width: 800, height: 1_200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 0.42, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 1_200))
        context.setFillColor(gray: 0.72, alpha: 1)
        context.fill(CGRect(x: 0, y: 800, width: 800, height: 400))
        return context.makeImage()
    }()
}

@MainActor
private final class PortraitFocusDetailImages: DetailImageSource, DetailRegionSharpnessSource {
    private let sample = SampleDetailImages()
    private(set) var delivered = false

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        await sample.placeholder(for: photo, gridThumbnails: gridThumbnails)
    }

    func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        let outcome = await sample.image(for: photo, request: request)
        guard case .image(let image) = outcome else { return outcome }
        delivered = true
        guard let pixels = Self.portraitPixels else { return outcome }
        return .image(
            DetailImage(
                image: pixels, source: image.source, quality: image.quality,
                hasRAW: image.hasRAW,
                fullResolutionSize: CGSize(width: 2_400, height: 3_600)))
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis? {
        let offCentreAF = RegionSharpnessEvidence(
            kind: .cameraAutofocus,
            groupIndex: nil,
            region: NormalizedRegion(x: 0.65, y: 0.25, width: 0.10, height: 0.10),
            score: nil,
            unavailableBecause: nil)
        onAutofocus(.regions([offCentreAF]))
        return RegionSharpnessAnalysis(
            autofocus: .regions([offCentreAF]),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())
    }

    private static let portraitPixels: CGImage? = {
        guard
            let context = CGContext(
                data: nil, width: 800, height: 1_200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 0.42, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 1_200))
        return context.makeImage()
    }()
}

@MainActor
private final class ObservedFocusDetailImages: DetailImageSource, DetailRegionSharpnessSource {
    let sample = SampleDetailImages()
    private(set) var requests: [(PhotoIdentity, DetailPixelRequest)] = []
    private(set) var delivered: [DetailQuality] = []
    private(set) var windows: [DetailPhotoWindow] = []
    private(set) var prefetched: [DetailPhotoWindow] = []
    private(set) var analyzeCalls: [PhotoIdentity] = []

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
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
        let outcome = await sample.image(for: photo, request: request)
        if case .image(let image) = outcome { delivered.append(image.quality) }
        return outcome
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
        prefetched.append(window)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis? {
        analyzeCalls.append(photo)
        return await sample.analyzeRegions(
            for: photo, group: group, nearby: nearby, onAutofocus: onAutofocus)
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
private final class DetailTrackedTouchPan: UIPanGestureRecognizer {
    var trackedNumberOfTouches = 0
    var travel: CGPoint = .zero
    var velocityPoint: CGPoint = .zero
    var locationPoint: CGPoint?
    var sampleState: UIGestureRecognizer.State = .began

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override var numberOfTouches: Int { trackedNumberOfTouches }
    override func translation(in view: UIView?) -> CGPoint { travel }
    override func location(in view: UIView?) -> CGPoint {
        locationPoint ?? super.location(in: view)
    }
    override func velocity(in view: UIView?) -> CGPoint { velocityPoint }
}

@MainActor
private final class DetailTestTwoFingerSwipe: TwoFingerMarkingSwipeGestureRecognizer {
    var sampleState: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }
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

@MainActor
@Observable
private final class TestPresentationBox {
    var value: DetailPresentation

    init(value: DetailPresentation) {
        self.value = value
    }
}

private struct TestDuoDetailHost: View {
    let browsing: BrowsingModel
    let images: any DetailImageSource
    @Bindable var presentation: TestPresentationBox
    @State private var settingsStore: SettingsStore = {
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        return store
    }()

    var body: some View {
        NavigationStack {
            DetailScreen(
                browsing: browsing, images: images,
                duo: DuoDetailLayout(
                    presentation: $presentation.value,
                    filter: AnyView(EmptyView()),
                    more: AnyView(EmptyView()),
                    bottom: AnyView(EmptyView()),
                    showsGrid: true))
        }
        .environment(settingsStore)
        .environment(\.isDuoExpanded, true)
        .environment(\.usesSystemBrowsingToolbar, true)
    }
}

private struct TestDetailPresentationHost: View {
    let browsing: BrowsingModel
    let images: any DetailImageSource
    @Bindable var presentation: TestPresentationBox
    let usesSystemToolbar: Bool
    var idiom: UIUserInterfaceIdiom = .pad
    @State private var settingsStore: SettingsStore = {
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        return store
    }()

    var body: some View {
        Group {
            if usesSystemToolbar {
                NavigationStack {
                    DetailScreen(
                        browsing: browsing, images: images, presentation: $presentation.value)
                }
                .environment(\.usesSystemBrowsingToolbar, true)
            } else {
                DetailScreen(
                    browsing: browsing, images: images, presentation: $presentation.value)
            }
        }
        .environment(settingsStore)
        .environment(\.cloveUserInterfaceIdiom, idiom)
    }
}

private struct TestDuoPoseDetailHost: View {
    let browsing: BrowsingModel
    let images: any DetailImageSource
    @Bindable var presentation: TestPresentationBox
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let usesVerticalToolbar: Bool
    let hasFoldRegion: Bool
    let showsGrid: Bool
    let theme: CloveTheme
    var settingsStore: SettingsStore? = nil
    @State private var fallbackStore: SettingsStore = {
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        return store
    }()

    var body: some View {
        NavigationStack {
            DetailScreen(
                browsing: browsing, images: images,
                duo: DuoDetailLayout(
                    presentation: $presentation.value,
                    filter: AnyView(EmptyView()),
                    more: AnyView(EmptyView()),
                    bottom: AnyView(EmptyView()),
                    showsGrid: showsGrid))
        }
        .environment(settingsStore ?? fallbackStore)
        .environment(\.cloveTheme, theme)
        .environment(\.isDuoExpanded, isDuoExpanded)
        .environment(\.isDuoCover, isDuoCover)
        .environment(\.usesSystemBrowsingToolbar, true)
        .environment(\.usesVerticalBrowsingToolbar, usesVerticalToolbar)
        .environment(\.hasFoldRegion, hasFoldRegion)
    }
}

@MainActor
private final class GatedLateFocusDetailImages: DetailImageSource, DetailRegionSharpnessSource {
    private let sample = SampleDetailImages()
    private(set) var analyzeCalls: [PhotoIdentity] = []
    private var pendingAutofocus: [PhotoIdentity: @Sendable (RegionSharpnessPathResult) -> Void] =
        [:]
    private var pendingFinish:
        [PhotoIdentity: CheckedContinuation<RegionSharpnessAnalysis?, Never>] =
            [:]
    private var heldPhotos: Set<PhotoIdentity> = []

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        if case .image(let pixels) = await gridThumbnails.thumbnail(for: photo, priority: .visible)
        {
            return pixels
        }
        return nil
    }

    func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        await sample.image(for: photo, request: request)
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis? {
        analyzeCalls.append(photo)
        if heldPhotos.isEmpty && pendingFinish[photo] == nil {
            heldPhotos.insert(photo)
            pendingAutofocus[photo] = onAutofocus
            return await withCheckedContinuation { continuation in
                pendingFinish[photo] = continuation
            }
        }
        return await sample.analyzeRegions(
            for: photo, group: group, nearby: nearby, onAutofocus: onAutofocus)
    }

    func deliverLateResults(for photo: PhotoIdentity) {
        let af = RegionSharpnessEvidence(
            kind: .cameraAutofocus, groupIndex: nil,
            region: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16),
            score: nil, unavailableBecause: nil)
        let eye = RegionSharpnessEvidence(
            kind: .eye, groupIndex: 0,
            region: NormalizedRegion(x: 0.62, y: 0.29, width: 0.04, height: 0.04),
            score: RegionSharpnessScore(
                tenengradMeanSquare: 42, sampledPixels: 64, sampledWidth: 8, sampledHeight: 8),
            unavailableBecause: nil)
        pendingAutofocus.removeValue(forKey: photo)?(.regions([af]))
        let analysis = RegionSharpnessAnalysis(
            autofocus: .regions([af]),
            faces: .regions([eye]),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())
        pendingFinish.removeValue(forKey: photo)?.resume(returning: analysis)
    }

    func releaseAll() {
        for photo in Array(pendingFinish.keys) {
            deliverLateResults(for: photo)
        }
    }
}

@MainActor
private final class AspectByPhotoDetailImages: DetailImageSource {
    private let sample = SampleDetailImages()
    private let portraitPhotos: Set<PhotoIdentity>
    private(set) var deliveredPhotos: Set<PhotoIdentity> = []

    init(portraitPhotos: Set<PhotoIdentity>) {
        self.portraitPhotos = portraitPhotos
    }

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        nil
    }

    func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        let outcome = await sample.image(for: photo, request: request)
        guard case .image(let image) = outcome else { return outcome }
        deliveredPhotos.insert(photo)
        let isPortrait = portraitPhotos.contains(photo)
        let pixels = isPortrait ? Self.portraitPixels : Self.wideLandscapePixels
        guard let pixels else { return outcome }
        return .image(
            DetailImage(
                image: pixels, source: image.source, quality: image.quality,
                hasRAW: image.hasRAW,
                fullResolutionSize: isPortrait
                    ? CGSize(width: 2_000, height: 3_000)
                    : CGSize(width: 3_600, height: 1_500)))
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    private static let portraitPixels: CGImage? = makeSolidPixels(width: 800, height: 1_200)
    private static let wideLandscapePixels: CGImage? = makeSolidPixels(width: 1_200, height: 500)

    private static func makeSolidPixels(width: Int, height: Int) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 0.48, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

@MainActor
private final class StateControlledDetailImages: DetailImageSource {
    private let sample = SampleDetailImages()
    private let heldPhoto: PhotoIdentity
    private let unavailablePhoto: PhotoIdentity
    private let deferredPhoto: PhotoIdentity
    private var released = false
    private(set) var deliveredPhotos: Set<PhotoIdentity> = []

    init(
        heldPhoto: PhotoIdentity,
        unavailablePhoto: PhotoIdentity,
        deferredPhoto: PhotoIdentity
    ) {
        self.heldPhoto = heldPhoto
        self.unavailablePhoto = unavailablePhoto
        self.deferredPhoto = deferredPhoto
    }

    func releaseHeld() {
        released = true
    }

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        nil
    }

    func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        if photo == unavailablePhoto {
            return .unavailable(.cannotOpen)
        }
        if photo == deferredPhoto {
            return .deferred
        }
        if photo == heldPhoto {
            for _ in 0..<250 {
                guard !Task.isCancelled else { return .deferred }
                if released { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        let outcome = await sample.image(for: photo, request: request)
        if case .image = outcome {
            deliveredPhotos.insert(photo)
        }
        return outcome
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }
}

@MainActor
private final class CornerRegionAndLimitationImages: DetailImageSource,
    DetailRegionSharpnessSource
{
    private let sample = SampleDetailImages()

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        await sample.placeholder(for: photo, gridThumbnails: gridThumbnails)
    }

    func prepare(_ window: DetailPhotoWindow) async { await sample.prepare(window) }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        let outcome = await sample.image(for: photo, request: request)
        guard case .image(let image) = outcome else { return outcome }
        return .image(
            DetailImage(
                image: image.image,
                source: image.source,
                quality: image.quality,
                hasRAW: image.hasRAW,
                limitation: .noHigherResolution,
                fullResolutionSize: CGSize(width: 9_000, height: 6_000)))
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis? {
        let cornerAF = RegionSharpnessEvidence(
            kind: .cameraAutofocus,
            groupIndex: nil,
            region: NormalizedRegion(x: 0.04, y: 0.04, width: 0.08, height: 0.08),
            score: nil,
            unavailableBecause: nil)
        onAutofocus(.regions([cornerAF]))
        return RegionSharpnessAnalysis(
            autofocus: .regions([cornerAF]),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings())
    }
}

@MainActor
private final class DetailFrameBox {
    var frames: [String: CGRect] = [:]
}

@MainActor
private final class DetailCountBox {
    var counts: [String: Int] = [:]
}

@MainActor
@Observable
private final class DetailPickerTriggerBox {
    var trigger: TapPickerTriggerRequest?
    private var nonce = 0

    func sendTrigger(_ id: String) {
        nonce += 1
        trigger = TapPickerTriggerRequest(id: id, nonce: nonce)
    }
}

@MainActor
@Observable
private final class FilmstripCapTestState {
    let timeline: DetailTimeline
    var expandedGroup: ActiveBrowsingGroup?
    var current: PhotoIdentity?
    var scenePhase: ScenePhase = .active
    var dismissToken = 0

    init(
        timeline: DetailTimeline,
        expandedGroup: ActiveBrowsingGroup?,
        current: PhotoIdentity?
    ) {
        self.timeline = timeline
        self.expandedGroup = expandedGroup
        self.current = current
    }
}

@MainActor
private final class SolidWhiteThumbnails: GridThumbnailSource {
    private let whiteImage: CGImage = {
        let context = CGContext(
            data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        return context.makeImage()!
    }()

    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? {
        .image(whiteImage)
    }

    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority)
        async -> GridThumbnailOutcome
    {
        .image(whiteImage)
    }

    func companions(for photo: PhotoIdentity) -> GridCompanions {
        GridCompanions()
    }
}

@MainActor
private final class GroupFocusTrackingDetailImages: DetailImageSource, DetailRegionSharpnessSource {
    private let sample = SampleDetailImages()
    let g1: PhotoIdentity
    let g2: PhotoIdentity
    let g3: PhotoIdentity
    let g4: PhotoIdentity
    let outside: PhotoIdentity

    var gatedFocusPhotos: Set<PhotoIdentity> = []
    var gatedImagePhotos: Set<PhotoIdentity> = []
    var previewOmitsFullSize: Set<PhotoIdentity> = []

    private(set) var prefetched: [DetailPhotoWindow] = []
    private(set) var finishedAnalysisPhotos: Set<PhotoIdentity> = []
    private(set) var deliveredFullPhotos: Set<PhotoIdentity> = []

    private var pendingAutofocus: [PhotoIdentity: @Sendable (RegionSharpnessPathResult) -> Void] =
        [:]
    private var pendingFocusFinish:
        [PhotoIdentity: CheckedContinuation<RegionSharpnessAnalysis?, Never>] = [:]
    private var pendingImages: [PhotoIdentity: [CheckedContinuation<Void, Never>]] = [:]

    init(
        g1: PhotoIdentity,
        g2: PhotoIdentity,
        g3: PhotoIdentity,
        g4: PhotoIdentity,
        outside: PhotoIdentity
    ) {
        self.g1 = g1
        self.g2 = g2
        self.g3 = g3
        self.g4 = g4
        self.outside = outside
    }

    func isAnalysisWaiting(for photo: PhotoIdentity) -> Bool {
        pendingFocusFinish[photo] != nil
    }

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        nil
    }

    func prepare(_ window: DetailPhotoWindow) async {
        await sample.prepare(window)
    }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        if gatedImagePhotos.contains(photo), request.need == .preview {
            await withCheckedContinuation { continuation in
                pendingImages[photo, default: []].append(continuation)
            }
        }
        let outcome = await sample.image(for: photo, request: request)
        guard case .image(let image) = outcome else { return outcome }
        if request.need == .fullResolution || image.quality == .nativeRAW {
            deliveredFullPhotos.insert(photo)
        }
        if previewOmitsFullSize.contains(photo), image.quality == .preview {
            return .image(
                DetailImage(
                    image: image.image,
                    source: image.source,
                    quality: image.quality,
                    hasRAW: image.hasRAW,
                    limitation: image.limitation,
                    fullResolutionSize: nil))
        }
        return outcome
    }

    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        await sample.prefetchPreviews(window)
    }

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
        prefetched.append(window)
    }

    func leave(window: UUID) async {
        await sample.leave(window: window)
    }

    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis? {
        if gatedFocusPhotos.contains(photo) {
            pendingAutofocus[photo] = onAutofocus
            let result = await withCheckedContinuation { continuation in
                pendingFocusFinish[photo] = continuation
            }
            finishedAnalysisPhotos.insert(photo)
            return result
        }
        let analysis = analysisFor(photo)
        onAutofocus(analysis.autofocus)
        await Task.yield()
        finishedAnalysisPhotos.insert(photo)
        return analysis
    }

    func deliverAutofocus(for photo: PhotoIdentity) {
        let af = analysisFor(photo).autofocus
        pendingAutofocus.removeValue(forKey: photo)?(af)
    }

    func finishAnalysis(for photo: PhotoIdentity) {
        finishedAnalysisPhotos.insert(photo)
        pendingFocusFinish.removeValue(forKey: photo)?.resume(returning: analysisFor(photo))
    }

    func releaseImage(for photo: PhotoIdentity) {
        gatedImagePhotos.remove(photo)
        let waiting = pendingImages.removeValue(forKey: photo) ?? []
        for continuation in waiting {
            continuation.resume()
        }
    }

    func releaseAll() {
        for photo in Array(pendingAutofocus.keys) {
            deliverAutofocus(for: photo)
        }
        for photo in Array(pendingFocusFinish.keys) {
            finishAnalysis(for: photo)
        }
        for photo in Array(pendingImages.keys) {
            releaseImage(for: photo)
        }
    }

    private func analysisFor(_ photo: PhotoIdentity) -> RegionSharpnessAnalysis {
        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Sample", exifOrientation: 1)))
        let score = RegionSharpnessScore(
            tenengradMeanSquare: 12, sampledPixels: 64, sampledWidth: 8, sampledHeight: 8)
        switch photo {
        case g1:
            let af = RegionSharpnessEvidence(
                kind: .cameraAutofocus, groupIndex: nil,
                region: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16),
                score: nil, unavailableBecause: nil)
            let eye = RegionSharpnessEvidence(
                kind: .eye, groupIndex: 0,
                region: NormalizedRegion(x: 0.625, y: 0.29, width: 0.05, height: 0.05),
                score: score, unavailableBecause: nil)
            return RegionSharpnessAnalysis(
                autofocus: .regions([af]), faces: .regions([eye]),
                acquisitionFailure: nil, timings: RegionSharpnessTimings())
        case g2:
            let af = RegionSharpnessEvidence(
                kind: .cameraAutofocus, groupIndex: nil,
                region: NormalizedRegion(x: 0.64, y: 0.56, width: 0.12, height: 0.16),
                score: nil, unavailableBecause: nil)
            let eye = RegionSharpnessEvidence(
                kind: .eye, groupIndex: 0,
                region: NormalizedRegion(x: 0.15, y: 0.20, width: 0.05, height: 0.05),
                score: score, unavailableBecause: nil)
            return RegionSharpnessAnalysis(
                autofocus: .regions([af]), faces: .regions([eye]),
                acquisitionFailure: nil, timings: RegionSharpnessTimings())
        case g3:
            return RegionSharpnessAnalysis(
                autofocus: noAF, faces: .unavailable(.noFacesDetected),
                acquisitionFailure: nil, timings: RegionSharpnessTimings())
        case g4:
            let eye = RegionSharpnessEvidence(
                kind: .eye, groupIndex: 0,
                region: NormalizedRegion(x: 0.18, y: 0.66, width: 0.05, height: 0.05),
                score: score, unavailableBecause: nil)
            return RegionSharpnessAnalysis(
                autofocus: noAF, faces: .regions([eye]),
                acquisitionFailure: nil, timings: RegionSharpnessTimings())
        default:
            let af = RegionSharpnessEvidence(
                kind: .cameraAutofocus, groupIndex: nil,
                region: NormalizedRegion(x: 0.44, y: 0.44, width: 0.12, height: 0.12),
                score: nil, unavailableBecause: nil)
            return RegionSharpnessAnalysis(
                autofocus: .regions([af]), faces: .unavailable(.noFacesDetected),
                acquisitionFailure: nil, timings: RegionSharpnessTimings())
        }
    }
}
