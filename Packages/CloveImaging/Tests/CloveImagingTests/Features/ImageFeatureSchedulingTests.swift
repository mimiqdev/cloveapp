import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// PRD P0-11 shows groups while analysis continues, and G1 "Grouping (C9/I3)" bounds the work:
/// low priority, one or two workers, pausable, cancellable by folder or photo, and streaming
/// results as each photo finishes.
@Suite(.serialized)
struct ImageFeatureSchedulingTests {
    private struct Fixture {
        let directory: FeatureTestDirectory
        let files: [URL]
        let images: [String: CGImage]

        init(count: Int) throws {
            directory = try FeatureTestDirectory()
            var files: [URL] = []
            var images: [String: CGImage] = [:]
            for index in 0..<count {
                let name = "photo-\(index).jpg"
                let image =
                    index.isMultiple(of: 2) ? FeatureScene.identical() : FeatureScene.unrelated()
                images[name] = image
                files.append(try directory.jpeg(name, image))
            }
            self.files = files
            self.images = images
        }

        func requests() throws -> [ImageFeatureRequest] {
            try files.map { try featureRequest($0) }
        }

        func remove() { directory.remove() }
    }

    @Test func pausedPipelineStartsNoWork() async throws {
        let fixture = try Fixture(count: 3)
        defer { fixture.remove() }
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        await pipeline.pause()
        let stream = await pipeline.run(try fixture.requests())
        let queued = await pipeline.queuedCount
        #expect(queued == 3)
        // A paused pipeline must not start feature work, not even a cached lookup that reads.
        try await Task.sleep(for: .milliseconds(50))
        let readsWhilePaused = await previews.count
        #expect(readsWhilePaused == 0)
        let active = await pipeline.activeCount
        #expect(active == 0)
        await pipeline.resume()
        let results = await collect(stream)
        #expect(results.count == 3)
        let reads = await previews.count
        #expect(reads == 3)
        await pipeline.close()
    }

    @Test func pauseLetsRunningWorkFinish() async throws {
        let fixture = try Fixture(count: 1)
        defer { fixture.remove() }
        let previews = PreviewReadRecorder()
        await previews.setHolds(true)
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        let stream = await pipeline.run(try fixture.requests())
        try await awaitCondition("one read starts") { await previews.count == 1 }
        await pipeline.pause()
        let releaser = releaseHeldReads(previews)
        defer { releaser.cancel() }
        let results = await collect(stream)
        // A read that already started is not thrown away; its result is delivered.
        #expect(results.count == 1)
        let settled = try features(of: #require(results.first))
        #expect(settled.print != nil)
        await pipeline.close()
    }

    @Test func cancelFolderDropsOnlyThatFolder() async throws {
        let fixture = try Fixture(count: 3)
        defer { fixture.remove() }
        let requests = try fixture.requests()
        let firstFolder = requests.prefix(2).map {
            ImageFeatureRequest(
                source: $0.source, revision: $0.preview.revision, locationIdentity: "folder-a")
        }
        let secondFolder = requests.suffix(1).map {
            ImageFeatureRequest(
                source: $0.source, revision: $0.preview.revision, locationIdentity: "folder-b")
        }
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        await pipeline.pause()
        let cancelled = await pipeline.run(firstFolder)
        let kept = await pipeline.run(secondFolder)
        await pipeline.cancel(folder: "folder-a")
        #expect(await pipeline.queuedCount == 1)
        await pipeline.resume()
        let cancelledResults = await collect(cancelled)
        let keptResults = await collect(kept)
        #expect(cancelledResults.isEmpty)
        #expect(keptResults.count == 1)
        let reads = await previews.entries
        #expect(reads.count == 1)
        #expect(reads.first == secondFolder[0].source.lastPathComponent)
        await pipeline.close()
    }

    @Test func cancelPhotoDropsOnlyThatPhoto() async throws {
        let fixture = try Fixture(count: 3)
        defer { fixture.remove() }
        let requests = try fixture.requests()
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        await pipeline.pause()
        let stream = await pipeline.run(requests)
        await pipeline.cancel(photo: requests[1].source, in: requests[1].folderIdentity)
        await pipeline.resume()
        let results = await collect(stream)
        #expect(results.count == 2)
        let names = Set(results.map { $0.request.source.lastPathComponent })
        #expect(names == ["photo-0.jpg", "photo-2.jpg"])
        let reads = Set(await previews.entries)
        #expect(reads == ["photo-0.jpg", "photo-2.jpg"])
        await pipeline.close()
    }

    @Test func resultsStreamWhileWorkContinues() async throws {
        let fixture = try Fixture(count: 3)
        defer { fixture.remove() }
        let previews = PreviewReadRecorder()
        await previews.setHolds(true)
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader(), workers: 1)
        let stream = await pipeline.run(try fixture.requests())
        var iterator = stream.makeAsyncIterator()
        try await awaitCondition("the first read starts") { await previews.count == 1 }
        await previews.release()
        let first = try #require(await iterator.next())
        // One photo is delivered while the rest of the folder is still queued.
        #expect(try features(of: first).differenceHash != nil)
        let queued = await pipeline.queuedCount
        #expect(queued >= 1)
        let releaser = releaseHeldReads(previews)
        defer { releaser.cancel() }
        var rest: [ImageFeatureResult] = []
        while let next = await iterator.next() { rest.append(next) }
        #expect(rest.count == 2)
        await pipeline.close()
    }

    @Test func workersStayBounded() async throws {
        let fixture = try Fixture(count: 5)
        defer { fixture.remove() }
        let previews = PreviewReadRecorder()
        await previews.setHolds(true)
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader(), workers: 2)
        let stream = await pipeline.run(try fixture.requests())
        try await awaitCondition("both workers are busy") { await previews.count == 2 }
        let concurrent = await previews.maximumConcurrent
        #expect(concurrent <= 2)
        let releaser = releaseHeldReads(previews)
        defer { releaser.cancel() }
        let results = await collect(stream)
        #expect(results.count == 5)
        let peak = await previews.maximumConcurrent
        #expect(peak == 2)
        await pipeline.close()
    }

    @Test func cachedFeaturesNeedNoSecondRead() async throws {
        let fixture = try Fixture(count: 1)
        defer { fixture.remove() }
        let request = try #require(try fixture.requests().first)
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        let first = try #require(await pipeline.features(for: request))
        let firstFeatures = try features(of: first)
        #expect(firstFeatures.kinds == [.visionPrint, .differenceHash])
        let second = try #require(await pipeline.features(for: request))
        #expect(try features(of: second) == firstFeatures)
        let reads = await previews.count
        #expect(reads == 1)
        await pipeline.close()
    }

    @Test func duplicateRequestsAreComputedOnce() async throws {
        let fixture = try Fixture(count: 1)
        defer { fixture.remove() }
        let request = try #require(try fixture.requests().first)
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        let results = await collect(await pipeline.run([request, request]))
        #expect(results.count == 1)
        let reads = await previews.count
        #expect(reads == 1)
        await pipeline.close()
    }

    @Test func closeFinishesStreamsAndRefusesNewWork() async throws {
        let fixture = try Fixture(count: 3)
        defer { fixture.remove() }
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try fixture.directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: fixture.images),
            prints: StubFeaturePrintReader())
        await pipeline.pause()
        let stream = await pipeline.run(try fixture.requests())
        await pipeline.close()
        let results = await collect(stream)
        #expect(results.isEmpty)
        #expect(await pipeline.queuedCount == 0)
        let reads = await previews.count
        #expect(reads == 0)
        // After a folder closes the pipeline takes no more work; the app builds a new one.
        let afterClose = await collect(await pipeline.run(try fixture.requests()))
        #expect(afterClose.isEmpty)
    }
}
