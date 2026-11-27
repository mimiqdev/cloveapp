import CloveCore
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct SaveToPhotosTests {
    @Test func planResolvesOneRasterFilePerVisiblePhotoAndPrefersJpeg() throws {
        let folder = FolderIdentity(rawValue: "save-plan-folder")
        let root = URL(fileURLWithPath: "/tmp/save-plan", isDirectory: true)

        func gridPhoto(_ stem: String, ext: String) -> GridPhoto {
            GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem),
                fileName: "\(stem).\(ext)",
                time: .known(
                    PhotoTime(
                        captureTime: Date(timeIntervalSince1970: 1_760_000_000),
                        hasUTCOffset: true)),
                marks: PhotoMarks())
        }

        func scanned(_ set: PhotoSet) -> ScannedPhotoSet {
            ScannedPhotoSet(
                photoSet: set,
                sidecar: set.sidecarURL.map(SidecarState.resolved) ?? .absent,
                imageFiles: set.imageFiles.map {
                    ScannedImageFile(file: $0, size: 100, modificationDate: nil)
                })
        }

        let standaloneJPEG = gridPhoto("IMG_0001", ext: "JPG")
        let standaloneHEIF = gridPhoto("IMG_0002", ext: "HEIF")
        let rawWithJPEG = gridPhoto("IMG_0003", ext: "ARW")
        let rawWithHEIF = gridPhoto("IMG_0004", ext: "ARW")
        let rawWithBoth = gridPhoto("IMG_0005", ext: "ARW")
        let rawOnly = gridPhoto("IMG_0006", ext: "ARW")
        let missing = gridPhoto("IMG_0007", ext: "ARW")

        let sets: [PhotoIdentity: ScannedPhotoSet] = [
            standaloneJPEG.id: scanned(
                try PhotoSet(
                    folderID: folder, relativeFolderPath: "",
                    jpegURL: root.appendingPathComponent("IMG_0001.JPG"))),
            standaloneHEIF.id: scanned(
                try PhotoSet(
                    folderID: folder, relativeFolderPath: "",
                    heifURL: root.appendingPathComponent("IMG_0002.HEIF"))),
            rawWithJPEG.id: scanned(
                try PhotoSet(
                    folderID: folder, relativeFolderPath: "",
                    rawURL: root.appendingPathComponent("IMG_0003.ARW"),
                    jpegURL: root.appendingPathComponent("IMG_0003.JPG"))),
            rawWithHEIF.id: scanned(
                try PhotoSet(
                    folderID: folder, relativeFolderPath: "",
                    rawURL: root.appendingPathComponent("IMG_0004.ARW"),
                    heifURL: root.appendingPathComponent("IMG_0004.HIF"))),
            rawWithBoth.id: scanned(
                try PhotoSet(
                    folderID: folder, relativeFolderPath: "",
                    rawURL: root.appendingPathComponent("IMG_0005.ARW"),
                    jpegURL: root.appendingPathComponent("IMG_0005.JPG"),
                    heifURL: root.appendingPathComponent("IMG_0005.HIF"))),
            rawOnly.id: scanned(
                try PhotoSet(
                    folderID: folder, relativeFolderPath: "",
                    rawURL: root.appendingPathComponent("IMG_0006.ARW"))),
        ]

        let plan = PhotosSavePlan.resolve(
            targets: [
                standaloneJPEG, standaloneHEIF, rawWithJPEG, rawWithHEIF, rawWithBoth, rawOnly,
                missing,
            ],
            scannedSet: { sets[$0] })

        #expect(plan.eligibleCount == 5)
        #expect(plan.skippedRawCount == 1)
        #expect(plan.missingCount == 1)
        #expect(plan.hasSkippedRawOnly)
        #expect(!plan.hasOnlyRaw)
        #expect(
            plan.fileURLs.map(\.lastPathComponent) == [
                "IMG_0001.JPG",
                "IMG_0002.HEIF",
                "IMG_0003.JPG",
                "IMG_0004.HIF",
                "IMG_0005.JPG",
            ])

        let rawOnlyPlan = PhotosSavePlan.resolve(targets: [rawOnly], scannedSet: { sets[$0] })
        #expect(rawOnlyPlan.eligibleCount == 0)
        #expect(rawOnlyPlan.skippedRawCount == 1)
        #expect(rawOnlyPlan.hasOnlyRaw)
    }

    @Test func saveToPhotosTargetsOnlyVisibleSelectionAndPreservesSelectionAndFilter() async throws
    {
        let library = TestLibrary.sample(includeRasterSamples: true)
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        browsing.setOrder(.fileName)

        // MMQ02679 is rejected, MMQ02680 is RAW+JPEG (unmarked), MMQ02714 is standalone JPG (unmarked).
        let rejectedPhoto = try #require(browsing.photos.first { $0.id.stem == "mmq02679" })
        let rawJpegPhoto = try #require(browsing.photos.first { $0.id.stem == "mmq02680" })
        let jpegPhoto = try #require(browsing.photos.first { $0.id.stem == "mmq02714" })

        browsing.toggleSelection(rejectedPhoto.id)
        browsing.toggleSelection(rawJpegPhoto.id)
        browsing.toggleSelection(jpegPhoto.id)
        #expect(browsing.state.selection.count == 3)

        browsing.setFilter(.unmarked)
        #expect(browsing.batchTargets.map(\.id) == [rawJpegPhoto.id, jpegPhoto.id])
        #expect(browsing.hiddenSelectedCount == 1)

        let plan = browsing.planSaveToPhotos()
        #expect(plan.eligibleCount == 2)
        #expect(plan.skippedRawCount == 0)
        #expect(plan.fileURLs.map(\.lastPathComponent) == ["MMQ02680.JPG", "MMQ02714.JPG"])

        let result = await browsing.saveToPhotos(plan)
        #expect(result == .saved(eligibleCount: 2, skippedRawCount: 0))
        #expect(library.savedPhotoURLs.count == 1)
        #expect(
            library.savedPhotoURLs.first?.map(\.lastPathComponent) == [
                "MMQ02680.JPG", "MMQ02714.JPG",
            ])

        // Selection, hidden count, and active filter remain untouched.
        #expect(browsing.state.selection == [rejectedPhoto.id, rawJpegPhoto.id, jpegPhoto.id])
        #expect(browsing.hiddenSelectedCount == 1)
        #expect(browsing.state.filter == .unmarked)
        #expect(browsing.isPhotosSaveToastVisible)
        #expect(
            browsing.photosSaveToastMessage?.localizedText(language: .english)
                == "Saved 2 photos to Photos")

        await library.closeFolder()
    }

    @Test
    func
        canSaveToPhotosRemainsAvailableWhenMarkingIsGatedButDisablesOnLocationLossOrEmptySelection()
        async throws
    {
        let library = DelayedRenameSampleLibrary()
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        #expect(!browsing.canSaveToPhotos)

        let target = try #require(browsing.photos.first { $0.id.stem == "mmq02680" })
        browsing.toggleSelection(target.id)
        #expect(browsing.canSaveToPhotos)
        #expect(browsing.canMark)

        let flow = BatchRenameFlow(browsing: browsing)
        flow.options.prefix = "Lock_"
        await flow.prepare(rejectsFolderName: .defaultFolderName)
        let renameTask = Task { await flow.rename {} }
        for _ in 0..<100 where !browsing.isRenaming { await Task.yield() }
        #expect(browsing.isRenaming)
        #expect(!browsing.canMark)
        // Save to Photos remains enabled even when canMark is false as long as location is available.
        #expect(browsing.canSaveToPhotos)

        library.releaseRename?.resume()
        library.releaseRename = nil
        await renameTask.value

        library.sample.reportLocationLoss(.externalVolumeDisconnected)
        for _ in 0..<100 where browsing.folderLocationLoss == nil { await Task.yield() }
        #expect(browsing.folderLocationLoss != nil)
        #expect(!browsing.canSaveToPhotos)
    }

    @Test func sessionRequestsAddOnlyAuthorizationAndRunsInsideAdmittedScope() async throws {
        let saver = SpyPhotosSaver(initialAuthorization: .notDetermined)
        let fixture = try await PhotosSessionFixture(photosSaver: saver)
        defer { fixture.cleanup() }

        let target = try #require(fixture.browsing.photos.first { $0.id.stem == "companion" })
        let heifTarget = try #require(fixture.browsing.photos.first { $0.id.stem == "heif_only" })
        fixture.browsing.toggleSelection(target.id)
        fixture.browsing.toggleSelection(heifTarget.id)

        let plan = fixture.browsing.planSaveToPhotos()
        #expect(plan.fileURLs.map(\.lastPathComponent) == ["companion.jpg", "heif_only.heif"])

        let result = await fixture.browsing.saveToPhotos(plan)
        #expect(result == .saved(eligibleCount: 2, skippedRawCount: 0))
        #expect(saver.requestAuthorizationCallCount == 1)
        #expect(
            saver.savedBatches.first?.map(\.lastPathComponent) == [
                "companion.jpg", "heif_only.heif",
            ])

        await fixture.library.closeFolder()
    }

    @Test func sessionAdmittedWorkKeepsScopeOpenUntilSaveFinishesWhenClosingFolder() async throws {
        let saver = SpyPhotosSaver(initialAuthorization: .authorized, suspendsSave: true)
        let fixture = try await PhotosSessionFixture(photosSaver: saver)
        defer { fixture.cleanup() }

        let target = try #require(fixture.browsing.photos.first { $0.id.stem == "heif_only" })
        fixture.browsing.toggleSelection(target.id)
        let plan = fixture.browsing.planSaveToPhotos()

        let saveTask = Task {
            try await fixture.library.saveToPhotos(fileURLs: plan.fileURLs)
        }
        for _ in 0..<100 where saver.releaseSave == nil { await Task.yield() }
        #expect(saver.releaseSave != nil)

        var closeFinished = false
        let closeTask = Task {
            await fixture.library.closeFolder()
            closeFinished = true
        }
        for _ in 0..<20 { await Task.yield() }
        // Close waits for admitted work inside activeSession.withAdmittedWork before ending scope.
        #expect(!closeFinished)

        saver.releaseSave?.resume(returning: ())
        saver.releaseSave = nil
        try await saveTask.value
        await closeTask.value
        #expect(closeFinished)

        // Calling saveToPhotos after the folder has closed throws folderUnavailable.
        await #expect(throws: PhotosSaveError.folderUnavailable) {
            try await fixture.library.saveToPhotos(fileURLs: plan.fileURLs)
        }
    }

    @Test func sessionMapsPermissionDenialAndUnreadableSourceFilesWithoutClearingSelection()
        async throws
    {
        let deniedSaver = SpyPhotosSaver(initialAuthorization: .denied)
        let deniedFixture = try await PhotosSessionFixture(photosSaver: deniedSaver)
        defer { deniedFixture.cleanup() }

        let target = try #require(deniedFixture.browsing.photos.first { $0.id.stem == "heif_only" })
        deniedFixture.browsing.toggleSelection(target.id)
        let deniedPlan = deniedFixture.browsing.planSaveToPhotos()
        let deniedResult = await deniedFixture.browsing.saveToPhotos(deniedPlan)

        #expect(deniedResult == .failed(.permissionDenied))
        #expect(deniedSaver.savedBatches.isEmpty)
        #expect(deniedFixture.browsing.state.selection == [target.id])
        #expect(
            deniedFixture.browsing.photosSaveToastMessage?.localizedText(language: .english)
                == "Allow Photos access in Settings to save photos.")
        await deniedFixture.library.closeFolder()

        let writeSaver = SpyPhotosSaver(initialAuthorization: .authorized)
        let missingFileFixture = try await PhotosSessionFixture(photosSaver: writeSaver)
        defer { missingFileFixture.cleanup() }

        let target2 = try #require(
            missingFileFixture.browsing.photos.first { $0.id.stem == "heif_only" })
        missingFileFixture.browsing.toggleSelection(target2.id)
        let plan2 = missingFileFixture.browsing.planSaveToPhotos()
        let fileURL = try #require(plan2.fileURLs.first)
        try FileManager.default.removeItem(at: fileURL)

        let writeResult = await missingFileFixture.browsing.saveToPhotos(plan2)
        #expect(writeResult == .failed(.writeFailed))
        #expect(writeSaver.savedBatches.isEmpty)
        #expect(missingFileFixture.browsing.state.selection == [target2.id])
        #expect(
            missingFileFixture.browsing.photosSaveToastMessage?.localizedText(language: .english)
                == "Couldn't save to Photos.")
        await missingFileFixture.library.closeFolder()
    }

    @Test func saveToPhotosConfirmationSheetMountsForMixedAndRawOnlyPlansAndExportsOnConfirm()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = TestLibrary.sample(includeRasterSamples: true)
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()

        let eligible = try #require(browsing.photos.first { $0.id.stem == "mmq02680" })
        let rawOnly = try #require(browsing.photos.first { $0.id.stem == "mmq02678" })

        // 1. Mixed plan presents Ready to save, RAW only · skipped, and enabled Save N Photos CTA.
        browsing.toggleSelection(eligible.id)
        browsing.toggleSelection(rawOnly.id)
        let mixedPlan = browsing.planSaveToPhotos()
        #expect(mixedPlan.eligibleCount == 1)
        #expect(mixedPlan.skippedRawCount == 1)
        #expect(
            SaveToPhotosConfirmationSheet.confirmTitle(
                eligibleCount: mixedPlan.eligibleCount, language: .english) == "Save 1 Photo")

        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
            let host = UIHostingController(
                rootView: SaveToPhotosConfirmationSheet(
                    plan: mixedPlan,
                    hiddenSelectedCount: 0,
                    onConfirm: {}
                )
                .environment(\.cloveTheme, .light)
                .environment(\.appLanguage, .english))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitForMountedSheet(host: host, window: window)
            await browsing.saveToPhotos(mixedPlan)
            #expect(
                browsing.photosSaveToastMessage?.localizedText(language: .english)
                    == "Saved 1 photo to Photos · 1 RAW skipped")
        }

        // 2. All RAW-only plan disables Save 0 Photos CTA while keeping Cancel available.
        browsing.clearSelection()
        browsing.toggleSelection(rawOnly.id)
        let rawOnlyPlan = browsing.planSaveToPhotos()
        #expect(rawOnlyPlan.eligibleCount == 0)
        #expect(rawOnlyPlan.skippedRawCount == 1)
        #expect(
            SaveToPhotosConfirmationSheet.confirmTitle(
                eligibleCount: rawOnlyPlan.eligibleCount, language: .english) == "Save 0 Photos")

        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
            let host = UIHostingController(
                rootView: SaveToPhotosConfirmationSheet(plan: rawOnlyPlan) {}
                    .environment(\.cloveTheme, .light)
                    .environment(\.appLanguage, .english))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitForMountedSheet(host: host, window: window)
        }
    }

    private func waitForMountedSheet(host: UIViewController, window: UIWindow) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            if host.view.bounds.size.width > 0, !host.children.isEmpty {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                if image.size.width > 0, image.size.height > 0 {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("Timed out waiting for SaveToPhotosConfirmationSheet to mount")
        throw CancellationError()
    }
}

private final class SpyPhotosSaver: PhotosLibrarySaving, @unchecked Sendable {
    private let lock = NSLock()
    private var authorization: PhotosAuthorizationState
    private let suspendsSave: Bool
    private var batches: [[URL]] = []
    private var requestCount = 0
    var releaseSave: CheckedContinuation<Void, any Error>?

    init(initialAuthorization: PhotosAuthorizationState, suspendsSave: Bool = false) {
        self.authorization = initialAuthorization
        self.suspendsSave = suspendsSave
    }

    var savedBatches: [[URL]] { lock.withLock { batches } }
    var requestAuthorizationCallCount: Int { lock.withLock { requestCount } }

    func authorizationStatus() -> PhotosAuthorizationState {
        lock.withLock { authorization }
    }

    func requestAddOnlyAuthorization() async -> PhotosAuthorizationState {
        lock.withLock {
            requestCount += 1
            if authorization == .notDetermined {
                authorization = .authorized
            }
            return authorization
        }
    }

    func savePhotos(fileURLs: [URL]) async throws {
        if suspendsSave {
            try await withCheckedThrowingContinuation { continuation in
                releaseSave = continuation
            }
        }
        lock.withLock {
            batches.append(fileURLs)
        }
    }
}

@MainActor
private final class PhotosSessionFixture {
    let root: URL
    let photos: URL
    let library: FolderLibrarySession
    let browsing: BrowsingModel

    init(photosSaver: any PhotosLibrarySaving) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)

        try Data("raw".utf8).write(to: photos.appendingPathComponent("companion.arw"))
        try Data("jpg".utf8).write(to: photos.appendingPathComponent("companion.jpg"))
        try Data("heif".utf8).write(to: photos.appendingPathComponent("heif_only.heif"))
        try Data("raw-only".utf8).write(to: photos.appendingPathComponent("raw_only.arw"))

        let marks = CloveMarkStore(directory: root.appendingPathComponent("marks"))
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(store: marks),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")),
            renamer: BatchRenamer(store: marks))
        library = FolderLibrarySession(
            stores: Task { stores },
            photosSaver: photosSaver,
            similarGroupsEnabled: { false })
        browsing = BrowsingModel(library: library)
        await browsing.openPickedFolder(photos)
        browsing.setOrder(.fileName)
        for _ in 0..<1000 {
            if !browsing.isFolderOpening && browsing.photos.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class DelayedRenameSampleLibrary: FolderLibrary {
    let sample = TestLibrary.sample(includeRasterSamples: true)
    var releaseRename: CheckedContinuation<Void, Never>?

    var folder: FolderIdentity { sample.folder }
    var photos: [GridPhoto] { sample.photos }
    var groups: [BrowsingGroup] { sample.groups }
    var updates: AsyncStream<FolderLibraryUpdate> { sample.updates }
    var thumbnails: any GridThumbnailSource { sample.thumbnails }
    var detailImages: any DetailImageSource { sample.detailImages }

    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet? {
        sample.scannedSet(for: photo)
    }

    func planBatchRename(
        order: [PhotoIdentity], template: RenameTemplate, destination: RenameDestination,
        rejectsFolderName: RejectsFolderName
    ) async throws -> BatchRenamePlan {
        try await sample.planBatchRename(
            order: order, template: template, destination: destination,
            rejectsFolderName: rejectsFolderName)
    }

    func runBatchRename(
        _ plan: BatchRenamePlan,
        progress: @escaping @MainActor @Sendable (BatchRenameProgress) -> Void
    ) async throws -> BatchRenameResult {
        await withCheckedContinuation { releaseRename = $0 }
        return try await sample.runBatchRename(plan, progress: progress)
    }

    func rescanAfterRename() async throws {
        try await sample.rescanAfterRename()
    }
}
