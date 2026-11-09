import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// PRD P0-11 keeps grouping working when Vision is unavailable, and G1 "Grouping (C9/I3)" adds
/// the rules this file checks: a failure falls back to the hash, the reason is kept, and a
/// session stops asking after repeated failures. Every Vision outcome here is injected, so these
/// tests behave the same whether or not the host can run Vision (S5: the iOS Simulator cannot).
@Suite(.serialized)
struct ImageFeatureVisionFailureTests {
    private static let espressoFailure = FeatureFailure(
        domain: "NSOSStatusErrorDomain", code: -1,
        message: "Failed to create espresso context.")

    @Test func failureFallsBackToTheHashAndKeepsTheReason() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let one = try directory.jpeg("one.jpg", FeatureScene.identical())
        let two = try directory.jpeg("two.jpg", FeatureScene.unrelated())
        let previews = PreviewReadRecorder()
        let prints = PrintReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(
                recorder: previews,
                images: [
                    "one.jpg": FeatureScene.identical(), "two.jpg": FeatureScene.unrelated(),
                ]),
            prints: StubFeaturePrintReader(
                behaviour: .fail(Self.espressoFailure), recorder: prints))
        let results = await collect(
            await pipeline.run([try featureRequest(one), try featureRequest(two)]))
        #expect(results.count == 2)
        var settled: [ImageFeatures] = []
        for result in results {
            let features = try features(of: result)
            #expect(features.print == nil)
            #expect(features.differenceHash != nil)
            #expect(features.visionFailure == Self.espressoFailure)
            #expect(features.kinds == [.differenceHash])
            settled.append(features)
        }
        // G1: the fallback answers the boundary, marked as the fallback kind.
        let distance = try #require(settled[0].distance(to: settled[1]))
        #expect(distance.kind == .differenceHash)
        let status = await pipeline.featurePrintStatus
        #expect(status == .failing(Self.espressoFailure))
        await pipeline.close()
    }

    @Test func sessionGivesUpAfterRepeatedFailures() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let names = (0..<5).map { "photo-\($0).jpg" }
        var images: [String: CGImage] = [:]
        for (index, name) in names.enumerated() {
            let image =
                index.isMultiple(of: 2) ? FeatureScene.identical() : FeatureScene.unrelated()
            images[name] = image
            try directory.jpeg(name, image)
        }
        let previews = PreviewReadRecorder()
        let prints = PrintReadRecorder()
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(recorder: previews, images: images),
            prints: StubFeaturePrintReader(
                behaviour: .fail(Self.espressoFailure), recorder: prints),
            workers: 1)
        let requests = try names.map { try featureRequest(directory.path($0)) }
        let results = await collect(await pipeline.run(requests))
        let attempts = await prints.count
        // Three attempts for five photos: the session stops asking instead of retrying per photo.
        #expect(attempts == FeaturePrintSession.defaultFailureLimit)
        #expect(results.count == 5)
        for result in results {
            let features = try features(of: result)
            #expect(features.print == nil)
            #expect(features.differenceHash != nil)
            #expect(features.visionFailure == Self.espressoFailure)
        }
        let status = await pipeline.featurePrintStatus
        #expect(
            status
                == .givenUp(
                    Self.espressoFailure,
                    consecutiveFailures: FeaturePrintSession.defaultFailureLimit))
        await pipeline.close()
    }

    @Test func successResetsTheFailureCount() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let names = (0..<7).map { "photo-\($0).jpg" }
        var images: [String: CGImage] = [:]
        for name in names {
            images[name] = FeatureScene.identical()
            try directory.jpeg(name, images[name] ?? FeatureScene.identical())
        }
        let outcomes = ScriptedPrintOutcomes([
            .fail(Self.espressoFailure), .fail(Self.espressoFailure), .succeed,
            .fail(Self.espressoFailure), .fail(Self.espressoFailure), .succeed, .succeed,
        ])
        let pipeline = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(
                recorder: PreviewReadRecorder(), images: images),
            prints: ScriptedFeaturePrintReader(outcomes: outcomes),
            workers: 1)
        let results = await collect(
            await pipeline.run(try names.map { try featureRequest(directory.path($0)) }))
        let settled = try results.map { try features(of: $0) }
        #expect(settled.filter { $0.print != nil }.count == 3)
        #expect(settled.allSatisfy { $0.differenceHash != nil })
        // Two failures in a row never reach the limit, so the session keeps asking.
        let status = await pipeline.featurePrintStatus
        #expect(status == .available)
        await pipeline.close()
    }

    @Test func relaunchRetriesVisionInsteadOfTrustingTheFallback() async throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let image = FeatureScene.identical()
        let file = try directory.jpeg("scene.jpg", image)
        let request = try featureRequest(file)

        let failing = ImageFeaturePipeline(
            cache: try directory.cache(),
            previews: StubFeaturePreviewReader(
                recorder: PreviewReadRecorder(), images: ["scene.jpg": image]),
            prints: StubFeaturePrintReader(behaviour: .fail(Self.espressoFailure)))
        let first = try #require(await failing.features(for: request))
        #expect(try features(of: first).print == nil)
        await failing.close()

        // The failure is not persisted, so a relaunch reads the preview again and stores the
        // print; only the hash came from disk.
        let previews = PreviewReadRecorder()
        let cache = try directory.cache()
        let recovered = ImageFeaturePipeline(
            cache: cache,
            previews: StubFeaturePreviewReader(recorder: previews, images: ["scene.jpg": image]),
            prints: StubFeaturePrintReader())
        let second = try #require(await recovered.features(for: request))
        let settled = try features(of: second)
        #expect(settled.print != nil)
        #expect(settled.differenceHash != nil)
        #expect(settled.visionFailure == nil)
        let reads = await previews.count
        #expect(reads == 1)
        await recovered.close()

        // Now the record is complete, so a third session reads nothing at all.
        let untouched = PreviewReadRecorder()
        let cached = ImageFeaturePipeline(
            cache: cache,
            previews: StubFeaturePreviewReader(recorder: untouched, images: ["scene.jpg": image]),
            prints: StubFeaturePrintReader())
        let third = try #require(await cached.features(for: request))
        #expect(try features(of: third).print != nil)
        let cachedReads = await untouched.count
        #expect(cachedReads == 0)
        await cached.close()
    }
}

/// Plays a fixed sequence of Vision outcomes, so the session's reset rule is observable.
actor ScriptedPrintOutcomes {
    private var pending: [StubFeaturePrintReader.Behaviour]

    init(_ pending: [StubFeaturePrintReader.Behaviour]) {
        self.pending = pending
    }

    var remaining: Int { pending.count }

    func next() -> StubFeaturePrintReader.Behaviour {
        pending.isEmpty ? .succeed : pending.removeFirst()
    }
}

struct ScriptedFeaturePrintReader: FeaturePrintReading {
    var revision = VisionFeaturePrintReader.requestRevision
    let outcomes: ScriptedPrintOutcomes

    func featurePrint(of image: CGImage) async -> Result<VisionFeaturePrint, FeatureFailure> {
        switch await outcomes.next() {
        case .succeed: return .success(StubFeaturePrintReader.print(for: image))
        case .fail(let failure): return .failure(failure)
        }
    }
}
