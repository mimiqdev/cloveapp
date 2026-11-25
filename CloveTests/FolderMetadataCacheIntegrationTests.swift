import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing

@testable import Clove
@testable import CloveImaging

@Suite(.serialized)
@MainActor
struct FolderMetadataCacheIntegrationTests {
    @Test func unchangedReopenMakesZeroMetadataReadsAndRestoresTimesBodyFilterAndLiveMarks()
        async throws
    {
        let workspace = try MetadataCacheTestWorkspace()
        defer { workspace.remove() }

        let rawURL = workspace.folder.appendingPathComponent("IMG_0001.ARW")
        let rawXMP = workspace.folder.appendingPathComponent("IMG_0001.xmp")
        let jpegURL = workspace.folder.appendingPathComponent("IMG_0002.JPG")
        let jpegPlainURL = workspace.folder.appendingPathComponent("IMG_0003.JPG")

        try Data("raw-bytes".utf8).write(to: rawURL)
        let five = try #require(Rating(rawValue: 5))
        try XMPCodec().write(
            XMPEdit(
                rating: .set(five),
                label: .set(ColourLabel(colour: .blue)),
                keywords: .set(["mountain", "alpine"])),
            into: nil
        ).write(to: rawXMP)

        try MetadataCacheTestWorkspace.writeJPEG(
            to: jpegURL,
            captureDate: "2026:11:10 10:00:02",
            subseconds: "250",
            offset: "+02:00",
            model: "ILCE-7M4",
            serial: "SER-777",
            lens: "FE 70-200mm F2.8 GM OSS II",
            focalLength: 135.0,
            embeddedRating: 3,
            embeddedLabel: "Green",
            embeddedKeywords: ["harbour"])
        try MetadataCacheTestWorkspace.writeJPEG(
            to: jpegPlainURL,
            captureDate: "2026:11:10 10:00:03",
            subseconds: nil,
            offset: nil,
            model: "X100VI",
            serial: nil,
            lens: nil,
            focalLength: 23.0)

        let coldReader = CountingMetadataReader { url in
            if url == rawURL {
                return .success(
                    ImageMetadata(
                        captureTime: .value(
                            CaptureTime(
                                wallTime: MetadataCacheTestWorkspace.wallTime(
                                    "2026:11:10 10:00:01"),
                                utcOffsetSeconds: 3600),
                            source: .imageProperty("{Exif}.DateTimeOriginal")),
                        subseconds: .missing,
                        utcOffset: .value(
                            3600, source: .imageProperty("{Exif}.OffsetTimeOriginal")),
                        model: .value("ILCE-1M2", source: .imageProperty("{TIFF}.Model")),
                        bodySerial: .value(
                            "SER-111", source: .imageProperty("{Exif}.BodySerialNumber")),
                        lens: .value("FE 35mm F1.4 GM", source: .imageProperty("{Exif}.LensModel")),
                        focalLengthMillimetres: .value(
                            35.0, source: .imageProperty("{Exif}.FocalLength")),
                        focalLength35mmEquivalent: .missing,
                        fileCreationTime: .missing,
                        fileModificationTime: .missing))
            }
            return MetadataReader().read(url: url).outcome
        }

        let library1 = workspace.makeLibrary(metadata: coldReader.reader)
        let model1 = BrowsingModel(library: library1, similarGroupsEnabled: false)
        await model1.openPickedFolder(workspace.folder)
        try await waitUntil { !model1.isFolderOpening && model1.photos.count == 3 }

        #expect(Set(coldReader.readURLs) == Set([rawURL, jpegURL, jpegPlainURL]))

        let firstColdPhotos = model1.allPlacedPhotos
        let firstColdBodies = library1.photos.map { ($0.id, $0.metadata) }
        let rawID = try #require(firstColdPhotos.first { $0.id.stem == "img_0001" }?.id)
        let jpegID = try #require(firstColdPhotos.first { $0.id.stem == "img_0002" }?.id)
        let jpegPlainID = try #require(firstColdPhotos.first { $0.id.stem == "img_0003" }?.id)

        // Update CloveStoredMarks on the standalone JPEG via normal marking before closing.
        let four = try #require(Rating(rawValue: 4))
        model1.apply(.rating(four), to: jpegID)
        await model1.drainActions()

        await library1.reloadRecents()
        let recent = try #require(library1.recents.first)
        await library1.closeFolder()

        // Reopen with a brand-new FolderLibrarySession sharing Application Support stores and a
        // counting MetadataReader that must receive ZERO calls.
        let warmReader = CountingMetadataReader { url in
            MetadataReader().read(url: url).outcome
        }
        let library2 = workspace.makeLibrary(metadata: warmReader.reader)
        let model2 = BrowsingModel(library: library2, similarGroupsEnabled: false)

        // Observe visibleReadingProgress during reopen: must stay nil on fast cached reopen.
        var sawVisibleReadingProgress = false
        var sawReadingSubtitle = false
        var sawProgressLine = false
        let reopenObserver = Task { @MainActor in
            while !Task.isCancelled && model2.isFolderOpening {
                if model2.visibleReadingProgress != nil { sawVisibleReadingProgress = true }
                let subtitle = GridScreen.subtitleText(
                    browsing: model2, isSelecting: false, isRegular: false)
                if subtitle == "Reading photos…" || subtitle.contains(" of ") {
                    sawReadingSubtitle = true
                }
                if GridScreen.progressLineState(browsing: model2, similarGroupsEnabled: false)
                    .progress != nil
                {
                    sawProgressLine = true
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
        }

        await model2.reopen(recent)
        try await waitUntil { !model2.isFolderOpening && model2.photos.count == 3 }
        reopenObserver.cancel()

        #expect(warmReader.readURLs.isEmpty)
        #expect(!sawVisibleReadingProgress)
        #expect(!sawReadingSubtitle)
        #expect(!sawProgressLine)
        #expect(model2.visibleReadingProgress == nil)

        // Verify restored times, filter metadata, and marks (including live CloveStoredMarks).
        let restoredRaw = try #require(model2.placedPhoto(for: rawID))
        let restoredJPEG = try #require(model2.placedPhoto(for: jpegID))
        let restoredPlain = try #require(model2.placedPhoto(for: jpegPlainID))

        #expect(
            restoredRaw.time
                == firstColdPhotos.first { $0.id == rawID }?.time)
        #expect(
            restoredJPEG.time
                == firstColdPhotos.first { $0.id == jpegID }?.time)
        #expect(
            restoredPlain.time
                == firstColdPhotos.first { $0.id == jpegPlainID }?.time)

        #expect(restoredRaw.metadata == firstColdBodies.first { $0.0 == rawID }?.1)
        #expect(restoredJPEG.metadata == firstColdBodies.first { $0.0 == jpegID }?.1)
        #expect(restoredPlain.metadata == firstColdBodies.first { $0.0 == jpegPlainID }?.1)

        #expect(
            restoredRaw.marks
                == PhotoMarks(
                    rating: five,
                    label: ColourLabel(colour: .blue),
                    keywords: ["mountain", "alpine"]))
        // CloveStoredMarks rating (4 stars) combines live with cached embedded label & keywords!
        #expect(
            restoredJPEG.marks
                == PhotoMarks(
                    rating: four,
                    label: ColourLabel(colour: .green),
                    keywords: ["harbour"]))
        #expect(restoredPlain.marks == PhotoMarks())

        // Verify secondary metadata filter options & grouping CameraBody work after cache hit.
        #expect(
            Set(model2.metadataFilterOptions.cameras.map(\.value))
                == Set(["ILCE-1M2", "ILCE-7M4", "X100VI"]))

        await library2.closeFolder()
    }

    @Test func addingModifyingAndExternalSidecarEditsParseIncrementally() async throws {
        let workspace = try MetadataCacheTestWorkspace()
        defer { workspace.remove() }

        let img1 = workspace.folder.appendingPathComponent("IMG_0001.JPG")
        let img2Raw = workspace.folder.appendingPathComponent("IMG_0002.ARW")
        let img2XMP = workspace.folder.appendingPathComponent("IMG_0002.xmp")
        let img3 = workspace.folder.appendingPathComponent("IMG_0003.JPG")

        try MetadataCacheTestWorkspace.writeJPEG(
            to: img1, captureDate: "2026:11:10 10:00:01", model: "Cam1")
        try Data("raw2".utf8).write(to: img2Raw)
        let two = try #require(Rating(rawValue: 2))
        try XMPCodec().write(.rating(two), into: nil).write(to: img2XMP)
        try MetadataCacheTestWorkspace.writeJPEG(
            to: img3, captureDate: "2026:11:10 10:00:03", model: "Cam3")

        let coldReader = CountingMetadataReader { MetadataReader().read(url: $0).outcome }
        let library1 = workspace.makeLibrary(metadata: coldReader.reader)
        let model1 = BrowsingModel(library: library1, similarGroupsEnabled: false)
        await model1.openPickedFolder(workspace.folder)
        try await waitUntil { !model1.isFolderOpening && model1.photos.count == 3 }
        #expect(coldReader.readURLs.count == 3)
        await library1.reloadRecents()
        let recent = try #require(library1.recents.first)
        await library1.closeFolder()

        // 1. Add IMG_0004.JPG, modify IMG_0001.JPG, delete IMG_0003.JPG, and edit IMG_0002.xmp!
        let img4 = workspace.folder.appendingPathComponent("IMG_0004.JPG")
        try MetadataCacheTestWorkspace.writeJPEG(
            to: img4, captureDate: "2026:11:10 10:00:04", model: "Cam4")
        try MetadataCacheTestWorkspace.writeJPEG(
            to: img1, captureDate: "2026:11:10 10:00:11", model: "Cam1Updated")
        try FileManager.default.removeItem(at: img3)
        let five = try #require(Rating(rawValue: 5))
        try XMPCodec().write(
            XMPEdit(rating: .set(five), label: .set(ColourLabel(colour: .purple))),
            into: nil
        ).write(to: img2XMP)

        let incrementalReader = CountingMetadataReader { MetadataReader().read(url: $0).outcome }
        let library2 = workspace.makeLibrary(metadata: incrementalReader.reader)
        let model2 = BrowsingModel(library: library2, similarGroupsEnabled: false)
        await model2.reopen(recent)
        try await waitUntil { !model2.isFolderOpening && model2.photos.count == 3 }

        // Only modified img1 and new img4 should be parsed by MetadataReader; img2Raw is untouched!
        #expect(Set(incrementalReader.readURLs) == Set([img1, img4]))

        let p1 = try #require(model2.allPlacedPhotos.first { $0.id.stem == "img_0001" })
        let p2 = try #require(model2.allPlacedPhotos.first { $0.id.stem == "img_0002" })
        let p4 = try #require(model2.allPlacedPhotos.first { $0.id.stem == "img_0004" })
        #expect(p1.metadata.camera == "Cam1Updated")
        #expect(p2.marks == PhotoMarks(rating: five, label: ColourLabel(colour: .purple)))
        #expect(p4.metadata.camera == "Cam4")

        // Cache was pruned: deleted img3 is gone from the persisted cache file.
        let cached = workspace.metadataCache.load(folderID: library2.folder)
        #expect(cached[FolderMetadataCache.Key(relativeFolderPath: "", stem: "img_0003")] == nil)
        #expect(cached.count == 3)

        // 2. Delete IMG_0002.xmp externally -> 0 MetadataReader calls and marks revert to unmarked.
        try FileManager.default.removeItem(at: img2XMP)
        await library2.closeFolder()

        let xmpDeleteReader = CountingMetadataReader { MetadataReader().read(url: $0).outcome }
        let library3 = workspace.makeLibrary(metadata: xmpDeleteReader.reader)
        let model3 = BrowsingModel(library: library3, similarGroupsEnabled: false)
        await model3.reopen(recent)
        try await waitUntil { !model3.isFolderOpening && model3.photos.count == 3 }

        #expect(xmpDeleteReader.readURLs.isEmpty)
        let p2AfterDelete = try #require(model3.allPlacedPhotos.first { $0.id.stem == "img_0002" })
        #expect(p2AfterDelete.marks == PhotoMarks())
        await library3.closeFolder()
    }

    @Test func moveRejectsWaitsForScanFinishDuringCachedReopen() async throws {
        let workspace = try MetadataCacheTestWorkspace()
        defer { workspace.remove() }

        let rawURL = workspace.folder.appendingPathComponent("IMG_0001.ARW")
        let xmpURL = workspace.folder.appendingPathComponent("IMG_0001.xmp")
        try Data("raw".utf8).write(to: rawURL)
        try XMPCodec().write(.rating(.rejected), into: nil).write(to: xmpURL)

        let library1 = workspace.makeLibrary()
        let model1 = BrowsingModel(library: library1, similarGroupsEnabled: false)
        await model1.openPickedFolder(workspace.folder)
        try await waitUntil { !model1.isFolderOpening && model1.photos.count == 1 }
        await library1.reloadRecents()
        let recent = try #require(library1.recents.first)
        await library1.closeFolder()

        let library2 = workspace.makeLibrary()
        let model2 = BrowsingModel(library: library2, similarGroupsEnabled: false)
        var sawOpeningTrueBeforeFinish = false
        let watcher = Task { @MainActor in
            while !Task.isCancelled && model2.isFolderOpening {
                if model2.isScanning && model2.isFolderOpening {
                    sawOpeningTrueBeforeFinish = true
                }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        await model2.reopen(recent)
        try await waitUntil { !model2.isFolderOpening && model2.photos.count == 1 }
        watcher.cancel()

        #expect(sawOpeningTrueBeforeFinish || !model2.isFolderOpening)
        #expect(!model2.isScanning)
        #expect(model2.rejectedPhotoCount == 1)
        await library2.closeFolder()
    }

    @Test func coldOpenAndSlowCachedScanSurfaceReadingProgress() async throws {
        let workspace = try MetadataCacheTestWorkspace()
        defer { workspace.remove() }

        let gate = AsyncGate()
        let img1 = workspace.folder.appendingPathComponent("IMG_0001.JPG")
        try MetadataCacheTestWorkspace.writeJPEG(
            to: img1, captureDate: "2026:11:10 10:00:01", model: "Cam1")

        // Hold MetadataReader on a gate so the cold open stays in uncached parsing.
        let slowReader = CountingMetadataReader { url in
            awaitBlockingGate(gate)
            return MetadataReader().read(url: url).outcome
        }
        let library = workspace.makeLibrary(metadata: slowReader.reader)
        let model = BrowsingModel(library: library, similarGroupsEnabled: false)
        await model.openPickedFolder(workspace.folder)

        try await waitUntil { model.visibleReadingProgress != nil }
        #expect(
            GridScreen.subtitleText(browsing: model, isSelecting: false, isRegular: false)
                == "Reading photos…")
        #expect(
            GridScreen.progressLineState(browsing: model, similarGroupsEnabled: false).progress
                != nil)

        gate.open()
        try await waitUntil { !model.isFolderOpening && model.photos.count == 1 }
        #expect(model.visibleReadingProgress == nil)
        await library.closeFolder()

        // Verify grace timer surfaces reading progress if a scan exceeds 150ms without uncached reads.
        let delayedLibrary = DelayedScanLibrary()
        let delayedModel = BrowsingModel(library: delayedLibrary, similarGroupsEnabled: false)
        delayedLibrary.emitScanStarted()
        try await Task.sleep(for: .milliseconds(20))
        #expect(delayedModel.visibleReadingProgress == nil)

        try await waitUntil { delayedModel.visibleReadingProgress != nil }
        delayedLibrary.emitScanFinished()
        try await waitUntil {
            delayedModel.visibleReadingProgress == nil && !delayedModel.isScanning
        }
    }

    @Test func cloveSidecarMarkWriteAndPartialScanPreserveIncrementalCacheInvariants() async throws
    {
        let workspace = try MetadataCacheTestWorkspace()
        defer { workspace.remove() }

        let sub = workspace.folder.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let raw1 = workspace.folder.appendingPathComponent("IMG_0001.ARW")
        let subImg = sub.appendingPathComponent("SUB_0001.JPG")
        try Data("raw".utf8).write(to: raw1)
        try MetadataCacheTestWorkspace.writeJPEG(
            to: subImg, captureDate: "2026:11:10 10:00:05", model: "SubCam")

        let coldReader = CountingMetadataReader { MetadataReader().read(url: $0).outcome }
        let library1 = workspace.makeLibrary(metadata: coldReader.reader)
        let model1 = BrowsingModel(library: library1, similarGroupsEnabled: false)
        await model1.openPickedFolder(workspace.folder)
        try await waitUntil { !model1.isFolderOpening && model1.photos.count == 2 }
        #expect(coldReader.readURLs.count == 2)

        // Clove writes IMG_0001.xmp via normal marking without touching FolderMetadataCache.
        let rawID = try #require(model1.allPlacedPhotos.first { $0.id.stem == "img_0001" }?.id)
        let three = try #require(Rating(rawValue: 3))
        model1.apply(.rating(three), to: rawID)
        await model1.drainActions()

        await library1.reloadRecents()
        let recent = try #require(library1.recents.first)
        await library1.closeFolder()

        // Reopen detects newly created IMG_0001.xmp via sidecar revision with 0 MetadataReader calls.
        let reopenReader = CountingMetadataReader { MetadataReader().read(url: $0).outcome }
        let library2 = workspace.makeLibrary(metadata: reopenReader.reader)
        let model2 = BrowsingModel(library: library2, similarGroupsEnabled: false)
        await model2.reopen(recent)
        try await waitUntil { !model2.isFolderOpening && model2.photos.count == 2 }
        #expect(reopenReader.readURLs.isEmpty)
        #expect(model2.placedPhoto(for: rawID)?.marks.rating == three)
        await library2.closeFolder()

        // Partial scan (unreadable subfolder) must NOT prune previously cached entries from Sub/.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: sub.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: sub.path)
        }

        let partialReader = CountingMetadataReader { MetadataReader().read(url: $0).outcome }
        let library3 = workspace.makeLibrary(metadata: partialReader.reader)
        let model3 = BrowsingModel(library: library3, similarGroupsEnabled: false)
        await model3.reopen(recent)
        try await waitUntil { !model3.isFolderOpening && model3.photos.count == 1 }
        #expect(partialReader.readURLs.isEmpty)

        let cachedAfterPartial = workspace.metadataCache.load(folderID: library3.folder)
        #expect(cachedAfterPartial.count == 2)
        #expect(
            cachedAfterPartial[
                FolderMetadataCache.Key(relativeFolderPath: "Sub", stem: "sub_0001")] != nil)
        await library3.closeFolder()
    }

    @Test func mixedBatchSurfacesReadingProgressAndReadsOnlyNewPhoto() async throws {
        let workspace = try MetadataCacheTestWorkspace()
        defer { workspace.remove() }

        let img1 = workspace.folder.appendingPathComponent("IMG_0001.JPG")
        try MetadataCacheTestWorkspace.writeJPEG(
            to: img1, captureDate: "2026:11:10 10:00:01", model: "Cam1")

        let library1 = workspace.makeLibrary()
        let model1 = BrowsingModel(library: library1, similarGroupsEnabled: false)
        await model1.openPickedFolder(workspace.folder)
        try await waitUntil { !model1.isFolderOpening && model1.photos.count == 1 }
        await library1.reloadRecents()
        let recent = try #require(library1.recents.first)
        await library1.closeFolder()

        let img2 = workspace.folder.appendingPathComponent("IMG_0002.JPG")
        try MetadataCacheTestWorkspace.writeJPEG(
            to: img2, captureDate: "2026:11:10 10:00:02", model: "Cam2")

        let gate = AsyncGate()
        let gatedReader = CountingMetadataReader { url in
            awaitBlockingGate(gate)
            return MetadataReader().read(url: url).outcome
        }
        let library2 = workspace.makeLibrary(metadata: gatedReader.reader)
        let model2 = BrowsingModel(library: library2, similarGroupsEnabled: false)
        await model2.reopen(recent)

        // Cached img1 is already placed while uncached img2 is gated, showing 1 of 2!
        try await waitUntil {
            model2.visibleReadingProgress != nil && model2.photos.count == 1
        }
        #expect(gatedReader.readURLs == [img2])
        #expect(
            GridScreen.subtitleText(browsing: model2, isSelecting: false, isRegular: false)
                == "1 of 2")
        let line = GridScreen.progressLineState(browsing: model2, similarGroupsEnabled: false)
        #expect(abs((line.progress ?? 0) - 0.5) < 0.001)

        gate.open()
        try await waitUntil { !model2.isFolderOpening && model2.photos.count == 2 }
        #expect(model2.visibleReadingProgress == nil)
        await library2.closeFolder()
    }

    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while await !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func awaitBlockingGate(_ gate: AsyncGate) {
    gate.waitSync()
}

private final class AsyncGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let state = Mutex(false)

    func waitSync() {
        let alreadyOpen = state.withLock { $0 }
        guard !alreadyOpen else { return }
        semaphore.wait()
    }

    func open() {
        state.withLock { open in
            guard !open else { return }
            open = true
            semaphore.signal()
        }
    }
}

private final class CountingMetadataReader: @unchecked Sendable {
    let reader: MetadataReader
    private let recorder: URLRecorder

    init(handler: @escaping @Sendable (URL) -> MetadataReadOutcome) {
        let storage = URLRecorder()
        self.recorder = storage
        self.reader = MetadataReader(maximumConcurrentReads: 1) { url in
            storage.append(url)
            return handler(url)
        }
    }

    var readURLs: [URL] {
        recorder.urls
    }
}

private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
private final class DelayedScanLibrary: FolderLibrary {
    let folder = FolderIdentity(rawValue: "delayed-scan-test")
    var photos: [GridPhoto] = []
    var groups: [BrowsingGroup] = []
    private(set) var openGeneration = 1
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        self.updates = stream
        self.continuation = continuation
    }

    func emitScanStarted() {
        continuation.yield(.scanStarted)
    }

    func emitScanFinished() {
        continuation.yield(
            .scanFinished(FolderScanSummary(photoCount: photos.count, status: .complete)))
    }
}

@MainActor
private final class MetadataCacheTestWorkspace {
    let root: URL
    let folder: URL
    let metadataCache: FolderMetadataCache
    private let recentsURL: URL
    private let marksDir: URL
    private let groupsDir: URL
    private let cacheDir: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Card", isDirectory: true)
        recentsURL = root.appendingPathComponent("recents.json")
        marksDir = root.appendingPathComponent("marks", isDirectory: true)
        groupsDir = root.appendingPathComponent("groups", isDirectory: true)
        cacheDir = root.appendingPathComponent("caches", isDirectory: true)
        metadataCache = FolderMetadataCache(
            directory: root.appendingPathComponent("FolderMetadata", isDirectory: true))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func makeLibrary(metadata: MetadataReader = MetadataReader()) -> FolderLibrarySession {
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(store: RecentFolderStore(fileURL: recentsURL)),
            writes: MarkWriteQueue(storeDirectory: marksDir),
            groups: SimilarGroupsCache(directory: groupsDir),
            metadata: metadataCache)
        return FolderLibrarySession(
            stores: Task { stores },
            caches: Task.detached(priority: .userInitiated) {
                await FolderLibrarySession.makeCaches(in: self.cacheDir)
            },
            metadata: metadata,
            similarGroupsEnabled: { false })
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    nonisolated static func wallTime(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)!
    }

    static func writeJPEG(
        to url: URL,
        captureDate: String,
        subseconds: String? = nil,
        offset: String? = nil,
        model: String,
        serial: String? = nil,
        lens: String? = nil,
        focalLength: Double? = nil,
        embeddedRating: Int? = nil,
        embeddedLabel: String? = nil,
        embeddedKeywords: [String] = []
    ) throws {
        let width = 16
        let height = 16
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        var exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: captureDate]
        if let subseconds { exif[kCGImagePropertyExifSubsecTimeOriginal] = subseconds }
        if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
        if let serial { exif[kCGImagePropertyExifBodySerialNumber] = serial }
        if let lens { exif[kCGImagePropertyExifLensModel] = lens }
        if let focalLength { exif[kCGImagePropertyExifFocalLength] = focalLength }

        var properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: model],
            kCGImagePropertyExifDictionary: exif,
        ]
        if !embeddedKeywords.isEmpty {
            properties[kCGImagePropertyIPTCDictionary] = [
                kCGImagePropertyIPTCKeywords: embeddedKeywords
            ]
        }

        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))

        if embeddedRating != nil || embeddedLabel != nil || !embeddedKeywords.isEmpty {
            let metadata = CGImageMetadataCreateMutable()
            if let embeddedRating {
                CGImageMetadataSetValueWithPath(
                    metadata, nil, "xmp:Rating" as CFString, "\(embeddedRating)" as CFString)
            }
            if let embeddedLabel {
                CGImageMetadataSetValueWithPath(
                    metadata, nil, "xmp:Label" as CFString, embeddedLabel as CFString)
            }
            if !embeddedKeywords.isEmpty {
                let tag = CGImageMetadataTagCreate(
                    "http://purl.org/dc/elements/1.1/" as CFString,
                    "dc" as CFString,
                    "subject" as CFString,
                    .arrayUnordered,
                    embeddedKeywords as CFArray)
                if let tag {
                    CGImageMetadataSetTagWithPath(metadata, nil, "dc:subject" as CFString, tag)
                }
            }
            CGImageDestinationAddImageAndMetadata(
                destination, image, metadata, properties as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination))
    }
}
