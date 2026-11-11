import CloveCore
import CloveImaging
import Foundation
import Testing

@testable import Clove

@MainActor
struct PhotoDisplayTests {
    @Test func explicitChoicePersistsAndResetReturnsToMemoryDefault() {
        let memories: [UInt64] = [4 * 1024 * 1024 * 1024, 5 * 1024 * 1024 * 1024]
        for memory in memories {
            let storage = SampleSettingsStorage()
            let persistence = SettingsPersistence(storage: storage)
            let store = SettingsStore(
                persistence: persistence,
                rememberedAdvanceStorage: storage, physicalMemory: memory)
            let expected: PhotoDisplayMode =
                memory < 5 * 1024 * 1024 * 1024
                ? .cameraPreviewFirst : .rawFirst
            #expect(store.photoDisplayMode == expected)
            let choice: PhotoDisplayMode = expected == .rawFirst ? .cameraPreviewFirst : .rawFirst
            store.update { $0.photoDisplayMode = choice }
            let relaunched = SettingsStore(
                persistence: persistence,
                rememberedAdvanceStorage: storage, physicalMemory: memory)
            #expect(relaunched.photoDisplayMode == choice)
            relaunched.resetToDefaults()
            #expect(relaunched.settings.photoDisplayMode == nil)
            #expect(relaunched.photoDisplayMode == expected)
            let resetLaunch = SettingsStore(
                persistence: persistence,
                rememberedAdvanceStorage: storage, physicalMemory: memory)
            #expect(resetLaunch.photoDisplayMode == expected)
        }
    }

    @Test func sampleSwapsRawPreviewAndCameraModeNeverRendersRaw() async throws {
        let sample = SampleDetailImages()
        let photo = PhotoIdentity(
            folderID: FolderIdentity(rawValue: "display-tests"),
            relativeFolderPath: "", stem: "photo")
        let next = PhotoIdentity(folderID: photo.folderID, relativeFolderPath: "", stem: "next")
        let window = DetailPhotoWindow(
            id: UUID(),
            current: DetailNeighbour(photo: photo, position: 0),
            neighbours: [DetailNeighbour(photo: next, position: 1)], direction: 1,
            mode: .rawFirst, screenPixels: 2000)
        await sample.prepare(window)
        let preview = try image(
            await sample.image(
                for: photo,
                request: window.request(for: window.current)))
        #expect(preview.quality == .preview)
        #expect(sample.rawRenderCount == 0)
        let fit = try image(
            await sample.image(
                for: photo,
                request: window.request(for: window.current, need: .screenRender)))
        #expect(fit.quality == .screenRAW)
        #expect(fit.width == 2000)
        #expect(sample.rawRenderCount == 1)
        await sample.prefetch(window, renderAhead: true)
        #expect(sample.rawRenderCount == 2)
        let held = try image(
            await sample.image(
                for: photo,
                request: window.request(for: window.current)))
        #expect(held.image === fit.image)

        let cameraWindow = DetailPhotoWindow(
            id: UUID(), current: window.current,
            neighbours: window.neighbours, direction: 1, mode: .cameraPreviewFirst,
            screenPixels: 2000)
        await sample.prepare(cameraWindow)
        let cameraFit = try image(
            await sample.image(
                for: photo,
                request: cameraWindow.request(for: cameraWindow.current, need: .screenRender)))
        #expect(cameraFit.quality == .preview)
        let cameraFull = try image(
            await sample.image(
                for: photo,
                request: cameraWindow.request(for: cameraWindow.current, need: .fullResolution)))
        #expect(cameraFull.quality == .raster)
        #expect(cameraFull.source.url.pathExtension == "HIF")
        #expect(sample.cameraDecodeCount == 1)
        await sample.prefetch(cameraWindow, renderAhead: false)
        #expect(sample.rawRenderCount == 2)
        await sample.leave(window: cameraWindow.id)
        _ = await sample.image(
            for: photo,
            request: cameraWindow.request(for: cameraWindow.current, need: .fullResolution))
        #expect(sample.cameraDecodeCount == 2)
    }

    private func image(_ outcome: DetailImageOutcome) throws -> DetailImage {
        guard case .image(let image) = outcome else {
            Issue.record("Expected generated detail pixels")
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }
}
