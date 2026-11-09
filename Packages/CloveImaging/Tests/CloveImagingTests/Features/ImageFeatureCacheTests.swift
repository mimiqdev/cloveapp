import Foundation
import Testing

@testable import CloveImaging

/// G1 "Grouping (C9/I3)" asks similar-group features to be cached, and "Scheduling and cache"
/// asks for a memory tier, an app-private disk tier and keys that name everything the numbers
/// depend on. These tests exercise the cache directly, so they need no pixels.
@Suite(.serialized)
struct ImageFeatureCacheTests {
    private static let revision = ThumbnailRevision(
        size: 1_000, modificationTime: Date(timeIntervalSince1970: 1_000_000))

    private func makeRequest(
        _ name: String = "MMQ05184.ARW", pixels: Int = 400, location: String = "folder"
    ) -> ImageFeatureRequest {
        featureRequest(
            URL(fileURLWithPath: "/photos/\(name)"), revision: Self.revision, pixels: pixels,
            location: location)
    }

    private func features(base: Float = 1, bits: UInt64 = 0) -> ImageFeatures {
        ImageFeatures(
            print: samplePrint(base: base), differenceHash: DifferenceHash(bits: bits))
    }

    @Test func diskSurvivesANewInstance() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let request = makeRequest()
        let stored = features(bits: 0b1010)
        try directory.cache().store(
            stored, route: .embeddedOnly, visionRevision: 2, for: request)

        // A relaunch: new instance, empty memory tier, same directory.
        let reopened = try directory.cache()
        let read = try #require(
            reopened.features(for: request, route: .embeddedOnly, visionRevision: 2))
        #expect(read.print == stored.print)
        #expect(read.differenceHash == stored.differenceHash)
        #expect(read.visionFailure == nil)
    }

    @Test func memoryAnswersBeforeDisk() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let request = makeRequest()
        let cache = try directory.cache()
        try cache.store(features(), route: .embeddedOnly, visionRevision: 2, for: request)
        // Remove every file: a memory hit must not need one.
        for file in try FileManager.default.contentsOfDirectory(
            at: directory.path("features"), includingPropertiesForKeys: nil)
        {
            try FileManager.default.removeItem(at: file)
        }
        #expect(cache.features(for: request, route: .embeddedOnly, visionRevision: 2) != nil)
        cache.releaseMemory()
        #expect(cache.features(for: request, route: .embeddedOnly, visionRevision: 2) == nil)
    }

    @Test func revisionChangeIsAMiss() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let cache = try directory.cache()
        let request = makeRequest()
        try cache.store(features(), route: .embeddedOnly, visionRevision: 2, for: request)
        let newerSize = featureRequest(
            request.source,
            revision: .init(
                size: Self.revision.size + 1,
                modificationTime: Self.revision.modificationTime), location: "folder")
        let newerDate = featureRequest(
            request.source,
            revision: .init(
                size: Self.revision.size,
                modificationTime: Self.revision.modificationTime.addingTimeInterval(0.5)),
            location: "folder")
        #expect(cache.features(for: newerSize, route: .embeddedOnly, visionRevision: 2) == nil)
        #expect(cache.features(for: newerDate, route: .embeddedOnly, visionRevision: 2) == nil)
    }

    @Test func previewSizeRouteLocationAndVisionRevisionAreInTheKey() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let cache = try directory.cache()
        let request = makeRequest()
        try cache.store(features(), route: .embeddedOnly, visionRevision: 2, for: request)
        #expect(cache.features(for: request, route: .embeddedOnly, visionRevision: 2) != nil)
        #expect(cache.features(for: request, route: .embeddedOnly, visionRevision: 3) == nil)
        #expect(cache.features(for: request, route: .ifAbsent, visionRevision: 2) == nil)
        #expect(
            cache.features(for: makeRequest(pixels: 200), route: .embeddedOnly, visionRevision: 2)
                == nil)
        #expect(
            cache.features(
                for: makeRequest(location: "other-card"), route: .embeddedOnly, visionRevision: 2)
                == nil)
    }

    @Test func eachKindIsItsOwnEntry() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let request = makeRequest()
        let first = try directory.cache()
        try first.store(
            ImageFeatures(differenceHash: DifferenceHash(bits: 0b11)), route: .embeddedOnly,
            visionRevision: 2, for: request)
        let hashOnly = try #require(
            first.features(for: request, route: .embeddedOnly, visionRevision: 2))
        #expect(hashOnly.print == nil)
        #expect(hashOnly.differenceHash?.bits == 0b11)
        try first.store(features(bits: 0b11), route: .embeddedOnly, visionRevision: 2, for: request)
        let complete = try #require(
            first.features(for: request, route: .embeddedOnly, visionRevision: 2))
        #expect(complete.print != nil)
        #expect(complete.differenceHash?.bits == 0b11)
    }

    @Test func corruptEntryIsIgnoredAndReplaced() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let request = makeRequest()
        let cache = try directory.cache()
        let stored = features(bits: 0b0101)
        try cache.store(stored, route: .embeddedOnly, visionRevision: 2, for: request)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory.path("features"), includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        // A damaged entry must be a miss, not a decode failure or a wrong feature.
        for file in files {
            try Data("not a feature entry".utf8).write(to: file)
        }
        cache.releaseMemory()
        #expect(cache.features(for: request, route: .embeddedOnly, visionRevision: 2) == nil)
        #expect(cache.diskByteCount == 0)
        try cache.store(stored, route: .embeddedOnly, visionRevision: 2, for: request)
        let replaced = try #require(
            cache.features(for: request, route: .embeddedOnly, visionRevision: 2))
        #expect(replaced.print == stored.print)
        #expect(replaced.differenceHash == stored.differenceHash)
    }

    @Test func clearRemovesBothTiers() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let request = makeRequest()
        let cache = try directory.cache()
        try cache.store(features(), route: .embeddedOnly, visionRevision: 2, for: request)
        #expect(cache.diskByteCount > 0)
        try cache.clear()
        #expect(cache.diskByteCount == 0)
        #expect(cache.features(for: request, route: .embeddedOnly, visionRevision: 2) == nil)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: directory.path("features"), includingPropertiesForKeys: nil
            ).isEmpty)
    }

    @Test func diskBudgetEvictsTheOldestEntry() throws {
        let directory = try FeatureTestDirectory()
        defer { directory.remove() }
        let first = makeRequest("first.ARW")
        let second = makeRequest("second.ARW")
        let payload = ImageFeatures(
            print: VisionFeaturePrint(
                revision: 2, elements: (0..<768).map { Float($0) }),
            differenceHash: DifferenceHash(bits: 0b1))
        let probe = try directory.cache()
        try probe.store(payload, route: .embeddedOnly, visionRevision: 2, for: first)
        let perPhoto = probe.diskByteCount
        // A print, its hash and the payload wrapper: small enough for thousands of photos.
        #expect(perPhoto > 3_000)
        #expect(perPhoto < 4_096)

        var configuration = ImageFeatureCache.Configuration()
        configuration.diskBytes = perPhoto + 64
        let budgeted = try ImageFeatureCache(
            directory: directory.path("budgeted"), configuration: configuration)
        try budgeted.store(payload, route: .embeddedOnly, visionRevision: 2, for: first)
        try budgeted.store(payload, route: .embeddedOnly, visionRevision: 2, for: second)
        budgeted.releaseMemory()
        #expect(budgeted.diskByteCount <= perPhoto + 64)
        #expect(budgeted.features(for: first, route: .embeddedOnly, visionRevision: 2) == nil)
        #expect(budgeted.features(for: second, route: .embeddedOnly, visionRevision: 2) != nil)
    }
}
