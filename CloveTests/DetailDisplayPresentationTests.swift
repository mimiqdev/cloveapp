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
    private var reportedMeasurement = false

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

    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        await sample.prefetch(window, renderAhead: renderAhead)
    }

    func leave(window: UUID) async { await sample.leave(window: window) }

    func takeScreenRenderDurations() async -> [Double] {
        guard delivered.contains(.screenRAW), !reportedMeasurement else { return [] }
        reportedMeasurement = true
        return [900]
    }
}

/// Runs the shared SwiftUI detail view in the hosted simulator, with generated
/// camera/RAW pixels and a controlled fifth duration. No folder or device is needed.
@Suite(.serialized)
@MainActor
struct DetailDisplayPresentationTests {
    @Test func rawSwapModeFreezeAndCameraZoomThroughTheSharedView() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let source = ObservedDetailImages()
        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage, physicalMemory: 8 * 1024 * 1024 * 1024)
        store.recordScreenRenderDurations([900, 900, 900, 900])
        let library = TestLibrary.sample()
        let browsing = BrowsingModel(library: library)
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
        try await waitFor {
            source.delivered.contains(.screenRAW) && store.photoDisplayMode == .cameraPreviewFirst
        }
        #expect(source.delivered.first == .preview)
        #expect(source.windows.first?.mode == .rawFirst)
        // The same shared view receives a new order when group filtering changes.
        browsing.setFilter(.unmarked)
        try await waitFor { source.windows.count >= 2 }
        #expect(source.windows.last?.current.photo == first)
        #expect(source.windows.last?.current.position == 0)
        #expect(source.windows.last?.mode == .rawFirst)
        #expect(source.windows.last?.direction == 1)
        #expect(source.windows.last?.neighbours.map(\.photo) == [next])
        let preview = try #require(findPreview(in: window))
        preview.onDoubleTap?(.center)
        try await waitFor {
            source.requests.contains { $0.0 == first && $0.1.need == .fullResolution }
        }
        #expect(source.requests.last(where: { $0.1.need == .fullResolution })?.1.mode == .rawFirst)
        try await waitFor { source.delivered.contains(.nativeRAW) }
        browsing.openPhoto(next)
        try await waitFor {
            source.requests.contains { $0.0 == next && $0.1.need == .screenRender }
        }
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
            "DISPLAY simulator shared view: preview -> screen RAW; fifth sample changes next photo only; camera fit/100% adds zero RAW renders"
        )
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
