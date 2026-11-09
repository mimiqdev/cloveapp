import CoreGraphics
import Foundation
import Testing
import Vision

@testable import CloveImaging

/// PRD P0-11 refines groups with features computed from the grid's previews, and G1 "Grouping
/// (C9/I3)" wants both kinds from one read of roughly 400 px. These tests use generated scenes, so
/// they never depend on the shared fixture cache.
@Suite(.serialized)
struct ImageFeatureExtractionTests {
    @Test func computesBothKindsFromOnePreviewRead() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let image = FeatureScene.identical()
        let file = try directory.jpeg("scene.jpg", image)
        let request = try featureRequest(file)
        let previews = PreviewReadRecorder()
        let prints = PrintReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(
                recorder: previews, images: ["scene.jpg": image]),
            prints: StubFeaturePrintReader(recorder: prints))

        let result = try #require(await pipeline.features(for: request))
        let settled = try features(of: result)
        let previewCount = await previews.count
        let printCount = await prints.count
        let previewDigests = await previews.digests
        let printDigests = await prints.digests
        #expect(settled.kinds == [.visionPrint, .differenceHash])
        // One preview read for both kinds, and Vision saw exactly those pixels.
        #expect(previewCount == 1)
        #expect(printCount == 1)
        #expect(previewDigests == printDigests)
        #expect(settled.differenceHash == DifferenceHashReader().hash(of: image))
        await pipeline.close()
    }

    @Test func nearIdenticalIsCloserThanUnrelatedForBothKinds() async throws {
        let identical = FeatureScene.identical()
        let shifted = FeatureScene.shifted()
        let unrelated = FeatureScene.unrelated()
        let reader = VisionFeaturePrintReader()
        let nearVision = try await printDistance(identical, shifted, reader: reader)
        let farVision = try await printDistance(identical, unrelated, reader: reader)
        #expect(nearVision < farVision)
        let nearHash = hashDistance(identical, shifted)
        let farHash = hashDistance(identical, unrelated)
        #expect(nearHash < farHash)
        print(
            "FEATURE generated-pair near_vision=\(nearVision) far_vision=\(farVision)"
                + " near_hash_bits=\(nearHash) far_hash_bits=\(farHash)")
    }

    @Test func identicalSceneHasAZeroDistanceForBothKinds() async throws {
        let image = FeatureScene.identical()
        let featurePrint = try await featurePrint(of: image, reader: VisionFeaturePrintReader())
        #expect(featurePrint.distance(to: featurePrint) == 0)
        let hash = try #require(DifferenceHashReader().hash(of: image))
        #expect(hash.distance(to: hash) == 0)
    }

    @Test func reusesTheGridPreviewWhenTheSharedCacheHasOne() async throws {
        // The shared cache holds a different image for this file, so a matching hash proves the
        // feature used the grid's preview instead of reading the file (G1 "Preview, grid (I1)").
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let file = try directory.jpeg("photo.jpg", FeatureScene.unrelated())
        let request = try featureRequest(file)
        let thumbnails = try ThumbnailCache(directory: directory.path("thumbnails"))
        try thumbnails.store(
            .available(Thumbnail(image: FeatureScene.identical(), route: .ifAbsent)),
            for: request.preview)
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(), sharedPreviewCache: thumbnails)
        let result = try #require(await pipeline.features(for: request))
        let settled = try features(of: result)
        #expect(settled.differenceHash == DifferenceHashReader().hash(of: FeatureScene.identical()))
        #expect(settled.differenceHash != DifferenceHashReader().hash(of: FeatureScene.unrelated()))
        await pipeline.close()
    }

    @Test func leavesItsPreviewForTheGrid() async throws {
        // The other direction: a feature read that missed stores the thumbnail the grid wants.
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let file = try directory.jpeg("photo.jpg", FeatureScene.identical())
        let request = try featureRequest(file)
        let thumbnails = try ThumbnailCache(directory: directory.path("thumbnails"))
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(), sharedPreviewCache: thumbnails)
        _ = try #require(await pipeline.features(for: request))
        #expect(thumbnails.result(for: request.preview) != nil)
        await pipeline.close()
    }

    @Test func unavailablePreviewIsReported() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let file = try directory.jpeg("broken.jpg", FeatureScene.identical())
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(
                recorder: PreviewReadRecorder(), images: [:], unavailable: ["broken.jpg"]),
            prints: StubFeaturePrintReader())
        let result = try #require(await pipeline.features(for: try featureRequest(file)))
        guard case .unavailable(let reason) = result.outcome else {
            Issue.record("Expected no preview, got \(result.outcome)")
            return
        }
        // P0-11 splits a boundary without a usable feature, so the reason is explicit.
        #expect(reason == .noUsablePreview)
        await pipeline.close()
    }

    @Test func staleRequestIsSourceChangedAndNeverRead() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let image = FeatureScene.identical()
        let file = try directory.jpeg("scene.jpg", image)
        let fresh = try featureRequest(file)
        let stale = featureRequest(
            file,
            revision: ThumbnailRevision(
                size: fresh.preview.revision.size + 1,
                modificationTime: fresh.preview.revision.modificationTime))
        let previews = PreviewReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(
                recorder: previews, images: ["scene.jpg": image]),
            prints: StubFeaturePrintReader())
        let result = try #require(await pipeline.features(for: stale))
        guard case .unavailable(let reason) = result.outcome else {
            Issue.record("Expected a stale source, got \(result.outcome)")
            return
        }
        #expect(reason == .sourceChanged)
        let reads = await previews.count
        #expect(reads == 0)
        await pipeline.close()
    }

    private func hashDistance(_ left: CGImage, _ right: CGImage) -> Int {
        let reader = DifferenceHashReader()
        guard let one = reader.hash(of: left), let two = reader.hash(of: right) else { return 0 }
        return one.distance(to: two)
    }

    private func featurePrint(of image: CGImage, reader: VisionFeaturePrintReader) async throws
        -> VisionFeaturePrint
    {
        switch await reader.featurePrint(of: image) {
        case .success(let print): return print
        case .failure(let failure):
            Issue.record("Vision could not run on this host: \(failure)")
            throw CocoaError(.featureUnsupported)
        }
    }

    private func printDistance(
        _ left: CGImage, _ right: CGImage, reader: VisionFeaturePrintReader
    ) async throws -> Double {
        let first = try await featurePrint(of: left, reader: reader)
        let second = try await featurePrint(of: right, reader: reader)
        return try #require(first.distance(to: second))
    }
}

/// Fixture coverage: one RAW and one raster, each read once for both kinds.
@Suite(.enabled(if: FeatureFixtures.hasFormats))
struct ImageFeatureFixtureTests {
    @Test(arguments: ["sony-ilce-7s.ARW", "canon-eos-6d.JPG"])
    func onePreviewReadServesBothKinds(_ name: String) async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let request = try featureRequest(FeatureFixtures.file(name))
        let previews = PreviewReadRecorder()
        let prints = PrintReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: RecordingThumbnailReader(recorder: previews),
            prints: RecordingVisionReader(recorder: prints))
        let result = try #require(await pipeline.features(for: request))
        let settled = try features(of: result)
        let previewCount = await previews.count
        let printCount = await prints.count
        let previewDigests = await previews.digests
        let printDigests = await prints.digests
        let status = await pipeline.featurePrintStatus
        #expect(previewCount == 1)
        #expect(printCount == 1)
        #expect(previewDigests == printDigests)
        #expect(settled.print != nil, "Vision failed: \(String(describing: settled.visionFailure))")
        #expect(settled.differenceHash != nil)
        #expect(status == .available)

        // The hash is the one the same preview answers, so both kinds share one read.
        let read = await ThumbnailPreviewReader().preview(for: request.preview)
        guard case .preview(let preview) = read else {
            Issue.record("No preview for \(name)")
            return
        }
        #expect(preview.longEdge == 400)
        #expect(settled.differenceHash == DifferenceHashReader().hash(of: preview.image))
        await pipeline.close()
    }

    @Test func visionDistanceMatchesTheFramework() async throws {
        // The stored elements must say what Vision's own computeDistance says, because the cached
        // print replaces the observation and C9 compares it with S5's 0.5 starting value.
        let left = try #require(
            await preview(of: FeatureFixtures.file("canon-eos-6d.JPG")))
        let right = try #require(await preview(of: FeatureFixtures.file("nikon-d500.NEF")))
        let reader = VisionFeaturePrintReader()
        let first = try #require(await success(reader.featurePrint(of: left)))
        let second = try #require(await success(reader.featurePrint(of: right)))
        let expected = try #require(frameworkDistance(left, right))
        let actual = try #require(first.distance(to: second))
        #expect(abs(actual - expected) < 1e-4, "vision=\(actual) framework=\(expected)")
        print("FEATURE framework-check vision=\(actual) computeDistance=\(expected)")
    }

    private func preview(of file: URL) async throws -> CGImage? {
        let request = try featureRequest(file)
        guard
            case .preview(let preview) = await ThumbnailPreviewReader().preview(
                for: request.preview)
        else { return nil }
        return preview.image
    }

    private func success(
        _ result: Result<VisionFeaturePrint, FeatureFailure>
    ) -> VisionFeaturePrint? {
        switch result {
        case .success(let print): return print
        case .failure(let failure):
            Issue.record("Vision could not run on this host: \(failure)")
            return nil
        }
    }

    /// The reference answer, straight from a live observation.
    private func frameworkDistance(_ left: CGImage, _ right: CGImage) -> Double? {
        guard let first = observation(left), let second = observation(right) else { return nil }
        var distance: Float = 0
        do {
            try first.computeDistance(&distance, to: second)
        } catch {
            return nil
        }
        return Double(distance)
    }

    private func observation(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VisionFeaturePrintReader.requestRevision
        request.imageCropAndScaleOption = .scaleFit
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }
}
