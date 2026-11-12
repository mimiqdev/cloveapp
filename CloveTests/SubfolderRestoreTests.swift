import CloveCore
import Foundation
import Testing

@testable import Clove

@MainActor
struct SubfolderRestoreTests {
    @Test func settingsRestoreKeepsASubfolderWhileTheScanDeliversIt() async throws {
        let library = StreamingSubfolderLibrary()
        let saved = BrowsingState(
            folder: library.folder, filter: .subfolder("DCIM/101CAM"), route: .settings)
        let model = BrowsingModel(library: library)
        await model.restore(from: saved.encoded())
        #expect(model.state.filter == saved.filter)
        library.deliverPhoto()
        try await waitFor { model.allPlacedPhotos.count == 1 }
        #expect(model.state.filter == saved.filter)
        #expect(model.state.route == .settings)
        model.back()
        #expect(model.state.route == .grid)
        #expect(model.photos.count == 1)
    }

    @Test func missingSettingsSubfolderFallsBackOnlyAtScanEnd() async throws {
        let library = StreamingSubfolderLibrary()
        let saved = BrowsingState(
            folder: library.folder, filter: .subfolder("gone"), route: .settings)
        let model = BrowsingModel(library: library)
        await model.restore(from: saved.encoded())
        #expect(model.state.filter == saved.filter)
        library.finishScan()
        try await waitFor { model.state.filter == .all }
        #expect(model.state.route == .settings)
    }

    @Test func openingWhileASubfolderIsStillBeingScannedKeepsItsFilter() async throws {
        let library = StreamingSubfolderLibrary()
        let saved = BrowsingState(
            folder: library.folder, filter: .subfolder("DCIM/101CAM"), route: .grid)
        let model = BrowsingModel(library: library, state: saved)
        model.openFolder()
        #expect(model.state.filter == saved.filter)
        library.deliverPhoto()
        library.finishScan()
        try await waitFor { !model.isFolderOpening }
        #expect(model.photos.count == 1)
        #expect(model.state.filter == saved.filter)
    }

    @Test func leavingSettingsBeforeRestoreFinishesStillDropsAMissingSubfolder() async throws {
        let library = StreamingSubfolderLibrary()
        let saved = BrowsingState(
            folder: library.folder, filter: .subfolder("gone"), route: .settings)
        let model = BrowsingModel(library: library)
        await model.restore(from: saved.encoded())
        model.back()
        library.finishScan()
        try await waitFor { model.state.filter == .all }
        #expect(model.state.route == .grid)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The browsing model did not consume the scan update")
    }
}

@MainActor
private final class StreamingSubfolderLibrary: FolderLibrary {
    let folder = FolderIdentity(rawValue: "streaming-subfolders")
    var photos: [GridPhoto] = []
    let groups: [BrowsingGroup] = []
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func deliverPhoto() {
        photos = [
            GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/101CAM", stem: "a"),
                fileName: "a.ARW", time: .unavailable)
        ]
        continuation.yield(.photos(photos))
    }

    func finishScan() {
        continuation.yield(
            .scanFinished(FolderScanSummary(photoCount: photos.count, status: .complete)))
    }
}
