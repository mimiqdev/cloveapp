import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit

@testable import Clove
@testable import CloveImaging

@MainActor
struct MainActorPerformanceTests {
    @Test func filmstripPlanGroupsContiguousAndNonContiguousMembersInOrder() {
        let folder = FolderIdentity(rawValue: "filmstrip-plan-test")
        let s1 = gridPhoto(folder: folder, stem: "s1", seconds: 1)
        let g1a = gridPhoto(folder: folder, stem: "g1a", seconds: 2)
        let g1b = gridPhoto(folder: folder, stem: "g1b", seconds: 3)
        let s2 = gridPhoto(folder: folder, stem: "s2", seconds: 4)
        let g2a = gridPhoto(folder: folder, stem: "g2a", seconds: 5)
        let s3 = gridPhoto(folder: folder, stem: "s3", seconds: 6)
        let g2b = gridPhoto(folder: folder, stem: "g2b", seconds: 7)
        let g2c = gridPhoto(folder: folder, stem: "g2c", seconds: 8)

        let group1 = BrowsingGroup(
            id: GroupID(rawValue: "g1"), members: [g1a.id, g1b.id])
        let group2 = BrowsingGroup(
            id: GroupID(rawValue: "g2"), members: [g2a.id, g2b.id, g2c.id])
        let photos = [s1, g1a, g1b, s2, g2a, s3, g2b, g2c]

        let expanded = DetailFilmstrip.makePlan(
            photos: photos, groups: [group1, group2], current: g1b.id, isFolded: false)
        #expect(expanded.entries.map(\.id) == [s1.id, g1a.id, s2.id, g2a.id, s3.id])
        #expect(expanded.entries[1].expands)
        #expect(expanded.entries[1].holdsCurrent)
        #expect(expanded.entries[1].photos.map(\.id) == [g1a.id, g1b.id])
        #expect(!expanded.entries[3].expands)
        #expect(!expanded.entries[3].holdsCurrent)
        #expect(expanded.entries[3].photos.map(\.id) == [g2a.id, g2b.id, g2c.id])
        #expect(expanded.scrollTarget(for: g1a.id) == g1a.id)
        #expect(expanded.scrollTarget(for: g1b.id) == g1b.id)
        #expect(expanded.scrollTarget(for: g2a.id) == g2a.id)
        #expect(expanded.scrollTarget(for: g2b.id) == g2a.id)
        #expect(expanded.scrollTarget(for: g2c.id) == g2a.id)
        #expect(expanded.scrollTarget(for: s2.id) == s2.id)

        let folded = DetailFilmstrip.makePlan(
            photos: photos, groups: [group1, group2], current: g1b.id, isFolded: true)
        #expect(folded.entries[1].holdsCurrent)
        #expect(!folded.entries[1].expands)
        #expect(folded.scrollTarget(for: g1b.id) == g1a.id)
    }

    @Test func browsingModelIncrementalOrderingMatchesPhotoOrderingAcrossScanAndEdits() async throws
    {
        let library = StreamingOrderingLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()

        let batch1 = [
            gridPhoto(folder: library.folder, stem: "p03", seconds: 30),
            gridPhoto(folder: library.folder, stem: "p01", seconds: 10),
            gridPhoto(folder: library.folder, stem: "p05", seconds: nil),
        ]
        library.emitScanBatch(batch1)
        try await waitUntil { model.allPlacedPhotos.count == 3 }
        assertMatchesPhotoOrdering(model: model, source: library.photos)

        // Interleave earlier and later timestamps in a second scan batch.
        let batch2 = [
            gridPhoto(folder: library.folder, stem: "p00", seconds: 5),
            gridPhoto(folder: library.folder, stem: "p02", seconds: 20),
            gridPhoto(
                folder: library.folder, stem: "p04", seconds: 40,
                marks: PhotoMarks(rating: .rejected)),
        ]
        library.emitScanBatch(batch2)
        library.emitScanFinished(total: 6)
        try await waitUntil { !model.isFolderOpening && model.allPlacedPhotos.count == 6 }
        assertMatchesPhotoOrdering(model: model, source: library.photos)

        // Mark-only edits preserve order and update filtered views cleanly.
        let two = try #require(Rating(rawValue: 2))
        let p02 = library.identity("p02")
        let p00 = library.identity("p00")
        model.setFilter(.unmarked)
        model.apply(.rating(two), to: p02)
        await model.drainActions()
        assertMatchesPhotoOrdering(model: model, source: library.photos)

        model.openPhoto(p00)
        model.apply(.label(ColourLabel(colour: .green)), to: p00)
        assertMatchesPhotoOrdering(
            model: model,
            source: applying(
                PhotoMarks(label: ColourLabel(colour: .green)), to: p00, in: library.photos))
        model.undoLastMark()
        await model.drainActions()
        assertMatchesPhotoOrdering(model: model, source: library.photos)

        // Confirmed mark updates via `.reads(times: [:], marks: ...)` and filter/order changes.
        let three = try #require(Rating(rawValue: 3))
        library.emitConfirmedMark(
            PhotoMarks(rating: three, label: ColourLabel(colour: .red)), for: p00)
        try await waitUntil { model.shownMarks(for: p00).rating == three }
        model.setLabelFilter(.red)
        #expect(model.photos.map(\.id) == [p00])
        model.setFilter(.rejected)
        assertMatchesPhotoOrdering(model: model, source: library.photos)
        model.setFilter(.all)
        model.setOrder(.fileName)
        assertMatchesPhotoOrdering(model: model, source: library.photos)
        model.setOrder(.captureTime)
        assertMatchesPhotoOrdering(model: model, source: library.photos)

        // Removal reconciles allPlacedPhotos, ordering, and currentPhoto.
        library.removePhoto(p00)
        try await waitUntil { model.allPlacedPhotos.count == 5 }
        assertMatchesPhotoOrdering(model: model, source: library.photos)
        #expect(model.state.currentPhoto == nil)
    }

    @Test func pipelineDetailImagesReadsSourcesOffMainActorDuringPrefetchAndRegionAnalysis()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let folder = FolderIdentity(rawValue: "off-main-actor-test")
        let currentURL = directory.appendingPathComponent("current.jpg")
        let nextURL = directory.appendingPathComponent("next.jpg")
        try writeJPEG(to: currentURL, width: 1200, height: 800, subjectArea: [600, 400, 200, 200])

        let currentSet = try PhotoSet(folderID: folder, relativeFolderPath: "", jpegURL: currentURL)
        let nextSet = try PhotoSet(folderID: folder, relativeFolderPath: "", jpegURL: nextURL)
        let sets: [PhotoIdentity: PhotoSet] = [currentSet.id: currentSet, nextSet.id: nextSet]

        let reader = OffMainTestReader()
        let pipeline = DetailPipeline(
            cache: DetailCache(),
            reader: reader,
            sizes: OffMainNativeSizeReader())
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(
                reader: DetailRegionSharpnessReading(details: pipeline),
                faces: OffMainEmptyFaceDetector()),
            results: RegionSharpnessResultStore(capacity: 16))

        let tracker = OffMainExecutionTracker()
        let admissionActor = OffMainAdmissionActor(
            tracker: tracker,
            createNext: {
                try? writeJPEG(
                    to: nextURL, width: 1200, height: 800,
                    subjectArea: [600, 400, 200, 200])
            })
        let admission = DetailWorkAdmission(
            image: { work in await admissionActor.runImage(work) },
            prefetch: { work in await admissionActor.runPrefetch(work) },
            sharpness: { work in await admissionActor.runSharpness(work) })

        let source = PipelineDetailImages(
            pipeline: pipeline,
            set: { sets[$0] },
            admitted: admission,
            regionScheduler: scheduler)

        let window = DetailPhotoWindow(
            id: UUID(),
            current: DetailNeighbour(photo: currentSet.id, position: 0),
            neighbours: [DetailNeighbour(photo: nextSet.id, position: 1)],
            direction: 1,
            mode: .rawFirst,
            screenPixels: 1200)

        // `nextURL` does not exist on disk yet when `prefetch` is called on `@MainActor`.
        // Because `DetailSource.read` runs inside `admitted.prefetch` off `@MainActor`, creating
        // `nextURL` inside `admitted.prefetch` still lets `pipeline.prefetch` warm `next.jpg`.
        await source.prepare(window)
        await source.prefetch(window, renderAhead: false)
        #expect(tracker.prefetchWasOffMain)
        let prefetchedCount = await reader.prefetchedURLs.count
        #expect(prefetchedCount == 1)

        let firstAnalysis = await source.analyzeRegions(
            for: currentSet.id, group: [], nearby: [nextSet.id], onAutofocus: { _ in })
        #expect(tracker.sharpnessWasOffMain)
        #expect(firstAnalysis != nil)

        // Updating `current.jpg` changes its revision; the second `analyzeRegions` call detects the
        // changed `RegionSharpnessRequest` off `@MainActor` and invalidates the old result.
        let beforeSecondCount = await reader.prefetchedURLs.count
        try writeJPEG(to: currentURL, width: 1400, height: 900, subjectArea: [700, 450, 220, 220])
        let secondAnalysis = await source.analyzeRegions(
            for: currentSet.id, group: [], nearby: [], onAutofocus: { _ in })
        #expect(secondAnalysis != nil)
        let afterSecondCount = await reader.prefetchedURLs.count
        #expect(afterSecondCount > beforeSecondCount)
        #expect(await reader.fullRasterReads == 0)

        await source.closeRegionAnalysis()
        await pipeline.close()
    }

    @Test func readMarksSkipsAbsentSidecarsWhenTrustedAndReadsWhenRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rawURL = directory.appendingPathComponent("shot.ARW")
        try Data("raw".utf8).write(to: rawURL)
        let set = try PhotoSet(
            folderID: FolderIdentity(rawValue: "absent-sidecar-test"),
            relativeFolderPath: "",
            rawURL: rawURL)
        let scanned = ScannedPhotoSet(photoSet: set, sidecar: .absent, imageFiles: [])

        // Write a sidecar on disk while `ScannedPhotoSet.sidecar` stays `.absent`.
        let three = try #require(Rating(rawValue: 3))
        let sidecarURL = directory.appendingPathComponent("shot.xmp")
        try XMPCodec().write(.rating(three), into: nil).write(to: sidecarURL)

        let trusted = try FolderLibrarySession.readMarks(
            for: [scanned], storedMarks: [:], codec: XMPCodec(), trustAbsentSidecar: true)
        #expect(trusted[scanned.id] == PhotoMarks())

        let retried = try FolderLibrarySession.readMarks(
            for: [scanned], storedMarks: [:], codec: XMPCodec(), trustAbsentSidecar: false)
        #expect(retried[scanned.id] == PhotoMarks(rating: three))
    }

    @Test func folderSessionScanCoalescesBatchUpdatesWithoutIntermediatePendingPhotos() async throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photosDir = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let four = try #require(Rating(rawValue: 4))
        let codec = XMPCodec()
        // Exceed the 64-item scan batch size so multiple batches stream in.
        for index in 1...70 {
            let stem = String(format: "img_%03d", index)
            try Data("raw".utf8).write(to: photosDir.appendingPathComponent("\(stem).ARW"))
            if index == 1 || index == 70 {
                try codec.write(.rating(four), into: nil).write(
                    to: photosDir.appendingPathComponent("\(stem).xmp"))
            }
        }

        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks")),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")))
        let session = FolderLibrarySession(stores: Task { stores }, similarGroupsEnabled: { false })

        var observedUpdates: [FolderLibraryUpdate] = []
        let collector = Task {
            for await update in session.updates {
                observedUpdates.append(update)
                if case .scanFinished = update { break }
            }
        }

        let failure = await session.pick(photosDir)
        #expect(failure == nil)
        await collector.value

        let nonEmptyPhotoUpdates = observedUpdates.filter { update in
            if case .photos(let batch) = update { return !batch.isEmpty }
            return false
        }
        #expect(nonEmptyPhotoUpdates.isEmpty)

        let readBatchUpdates = observedUpdates.filter { update in
            if case .reads(let times, _) = update { return !times.isEmpty }
            return false
        }
        #expect(readBatchUpdates.count >= 2)
        #expect(session.photos.count == 70)
        #expect(session.photos.filter { $0.marks.rating == four }.count == 2)

        await session.closeFolder()
    }

    private func assertMatchesPhotoOrdering(
        model: BrowsingModel, source: [GridPhoto],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ordering = PhotoOrdering(photos: source)
        let expectedPlaced = ordering.photos(order: model.state.order, matching: .all)
        let expectedFiltered = ordering.photos(
            order: model.state.order, matching: model.state.filter)
        #expect(model.allPlacedPhotos == expectedPlaced)
        #expect(model.photos == expectedFiltered)
    }

    private func applying(_ marks: PhotoMarks, to id: PhotoIdentity, in photos: [GridPhoto])
        -> [GridPhoto]
    {
        photos.map { photo in
            guard photo.id == id else { return photo }
            var copy = photo
            copy.marks = marks
            return copy
        }
    }

    private func gridPhoto(
        folder: FolderIdentity, stem: String, seconds: TimeInterval?,
        marks: PhotoMarks = PhotoMarks()
    ) -> GridPhoto {
        let time: PhotoTimeState =
            seconds.map {
                .known(PhotoTime(fileCreation: Date(timeIntervalSince1970: 1_700_000_000 + $0)))
            } ?? .unavailable
        return GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem),
            fileName: "\(stem).ARW", time: time, marks: marks)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw MainActorPerformanceWaitError()
    }
}

private struct MainActorPerformanceWaitError: Error {}

private func writeJPEG(to url: URL, width: Int, height: Int, subjectArea: [Int]) throws {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = context.makeImage()!
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(
        destination, pixels,
        [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifPixelXDimension: width,
                kCGImagePropertyExifPixelYDimension: height,
                kCGImagePropertyExifSubjectArea: subjectArea,
            ]
        ] as CFDictionary)
    try #require(CGImageDestinationFinalize(destination))
}

private actor OffMainTestReader: DetailReading {
    private(set) var prefetchedURLs: [URL] = []
    private(set) var fullRasterReads = 0

    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome {
        prefetchedURLs.append(step.source.url)
        return .image(makePixels(width: 800, height: 600))
    }

    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome {
        fullRasterReads += 1
        return .image(makePixels(width: 1200, height: 800))
    }

    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        makePixels(width: 1200, height: 800)
    }

    func screenRAW(_ source: DetailSource, longEdge: Int) async -> CGImage? {
        makePixels(width: longEdge, height: max(1, longEdge * 2 / 3))
    }

    private func makePixels(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

private struct OffMainNativeSizeReader: DetailNativeSizeReading {
    func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize? {
        CGSize(width: 1200, height: 800)
    }
}

private struct OffMainEmptyFaceDetector: FaceRegionDetecting {
    func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
        .faces([])
    }
}

private final class OffMainExecutionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _prefetchWasOffMain = false
    private var _sharpnessWasOffMain = false
    private var _shouldCreateNext = true

    var prefetchWasOffMain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _prefetchWasOffMain
    }

    var sharpnessWasOffMain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _sharpnessWasOffMain
    }

    func recordPrefetch(offMain: Bool) {
        lock.lock()
        _prefetchWasOffMain = offMain
        lock.unlock()
    }

    func recordSharpness(offMain: Bool) {
        lock.lock()
        _sharpnessWasOffMain = offMain
        lock.unlock()
    }

    func takeCreateNext() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let current = _shouldCreateNext
        _shouldCreateNext = false
        return current
    }
}

private actor OffMainAdmissionActor {
    private let tracker: OffMainExecutionTracker
    private let createNext: @Sendable () -> Void

    init(tracker: OffMainExecutionTracker, createNext: @escaping @Sendable () -> Void) {
        self.tracker = tracker
        self.createNext = createNext
    }

    func runImage(_ work: @Sendable () async -> DetailImageOutcome) async -> DetailImageOutcome {
        await work()
    }

    func runPrefetch(_ work: @Sendable () async -> Void) async {
        tracker.recordPrefetch(offMain: isOffMainThread())
        if tracker.takeCreateNext() {
            createNext()
        }
        await work()
    }

    func runSharpness(_ work: @Sendable () async -> RegionSharpnessAnalysis?) async
        -> RegionSharpnessAnalysis?
    {
        tracker.recordSharpness(offMain: isOffMainThread())
        return await work()
    }

    private nonisolated func isOffMainThread() -> Bool {
        !Thread.isMainThread
    }
}

@MainActor
private final class StreamingOrderingLibrary: FolderLibrary {
    let folder = FolderIdentity(rawValue: "streaming-ordering-test")
    var photos: [GridPhoto] = []
    var groups: [BrowsingGroup] = []
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation
    var openGeneration = 1

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func identity(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem)
    }

    func emitScanBatch(_ batch: [GridPhoto]) {
        photos.append(contentsOf: batch)
        let times = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0.time) })
        let marks = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0.marks) })
        continuation.yield(.reads(times: times, marks: marks))
    }

    func emitScanFinished(total: Int) {
        continuation.yield(.scanFinished(FolderScanSummary(photoCount: total, status: .complete)))
    }

    func emitConfirmedMark(_ marks: PhotoMarks, for id: PhotoIdentity) {
        if let index = photos.firstIndex(where: { $0.id == id }) {
            photos[index].marks = marks
        }
        continuation.yield(.reads(times: [:], marks: [id: marks]))
    }

    func removePhoto(_ id: PhotoIdentity) {
        photos.removeAll { $0.id == id }
        continuation.yield(.photos([]))
    }

    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        var outcomes: [MarkChangeStatus] = []
        var confirmedMarks: [PhotoIdentity: PhotoMarks] = [:]
        for item in items {
            if let index = photos.firstIndex(where: { $0.id == item.photo }) {
                photos[index].marks = photos[index].marks.applying(item.change)
                confirmedMarks[item.photo] = photos[index].marks
            }
            outcomes.append(
                MarkChangeStatus(
                    id: MarkChangeID(), identity: item.photo, requested: item.change,
                    state: .savedInSidecar))
        }
        continuation.yield(.reads(times: [:], marks: confirmedMarks))
        return MarkBatchResult(
            id: MarkBatchID(), change: items.first?.change ?? MarkChange(), outcomes: outcomes)
    }
}
