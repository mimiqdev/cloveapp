import Foundation
import Testing

@testable import CloveImaging

@Suite("Compare 2-RAW native retention")
struct CompareRetentionTests {
    @Test(
        "Raising limit retains two full-resolution decodes and restoring immediately evicts excess")
    func retainsTwoFullResolutionRendersWhileActiveAndEvictsOnExit() async throws {
        let dir = try DetailTestDirectory()
        defer { dir.remove() }
        let fileA = try dir.image(name: "A.ARW", width: 1200, height: 800)
        let fileB = try dir.image(name: "B.ARW", width: 1200, height: 800)
        let fileC = try dir.image(name: "C.ARW", width: 1200, height: 800)

        let cache = dir.cache()
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(
            cache: cache,
            reader: GatedDetailReader(gate: gate),
            sizes: StubDetailNativeSizeReader(size: CGSize(width: 1200, height: 800))
        )

        let reqA = try rawRequest(fileA, native: true, location: "loc-a")
        let reqB = try rawRequest(fileB, native: true, location: "loc-b")
        let reqC = try rawRequest(fileC, native: true, location: "loc-c")

        #expect(await pipeline.nativeRetentionLimit == 1)

        // Activate Compare 2-RAW retention budget.
        await pipeline.setNativeRetentionLimit(2)
        #expect(await pipeline.nativeRetentionLimit == 2)

        _ = try availableDetail(await pipeline.image(for: reqA, consumer: UUID()))
        _ = try availableDetail(await pipeline.image(for: reqB, consumer: UUID()))
        #expect(await pipeline.heldNativeCount == 2)

        // Re-reading both A and B serves directly from cache without additional native RAW renders.
        let decodesBeforeCacheHits = await gate.finishedNatives
        _ = try availableDetail(await pipeline.image(for: reqA, consumer: UUID()))
        _ = try availableDetail(await pipeline.image(for: reqB, consumer: UUID()))
        #expect(await gate.finishedNatives == decodesBeforeCacheHits)
        #expect(await pipeline.heldNativeCount == 2)

        // Decoding a 3rd photo never exceeds the 2-entry ceiling.
        _ = try availableDetail(await pipeline.image(for: reqC, consumer: UUID()))
        #expect(await pipeline.heldNativeCount == 2)

        // Leaving Compare restores limit to 1 and keeps only the preferred active photo when held.
        await pipeline.setNativeRetentionLimit(1, keepingLocation: "loc-c")
        #expect(await pipeline.nativeRetentionLimit == 1)
        #expect(await pipeline.heldNativeCount == 1)

        let decodesAfterExit = await gate.finishedNatives
        _ = try availableDetail(await pipeline.image(for: reqC, consumer: UUID()))
        #expect(await gate.finishedNatives == decodesAfterExit)

        // Memory pressure releases all native buffers back to zero.
        await pipeline.releaseCachedImages()
        #expect(await pipeline.heldNativeCount == 0)
    }

    @Test("Distinct Compare panes decode full-resolution RAW serially on one bounded render lane")
    func concurrentComparePanesDecodeSeriallyWithoutCancelling() async throws {
        let dir = try DetailTestDirectory()
        defer { dir.remove() }
        let fileA = try dir.image(name: "PaneA.ARW", width: 1200, height: 800)
        let fileB = try dir.image(name: "PaneB.ARW", width: 1200, height: 800)

        let cache = dir.cache()
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(
            cache: cache,
            reader: GatedDetailReader(gate: gate),
            sizes: StubDetailNativeSizeReader(size: CGSize(width: 1200, height: 800))
        )

        await pipeline.setNativeRetentionLimit(2)

        let reqA = try rawRequest(fileA, native: true, location: "pane-a")
        let reqB = try rawRequest(fileB, native: true, location: "pane-b")
        let consumerA = UUID()
        let consumerB = UUID()

        async let outcomeA = pipeline.image(for: reqA, consumer: consumerA)
        async let outcomeB = pipeline.image(for: reqB, consumer: consumerB)

        let resultA = try availableDetail(await outcomeA)
        let resultB = try availableDetail(await outcomeB)

        #expect(resultA.quality == .nativeRAW)
        #expect(resultB.quality == .nativeRAW)
        #expect(await gate.maximumNativeEntries == 1)
        #expect(await pipeline.heldNativeCount == 2)

        await pipeline.close()
    }
}
