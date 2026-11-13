import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// The compact per-photo result store (#216): full-identity keys, LRU eviction, invalidation
/// by source file, and no image buffers in any record.
@Suite struct RegionSharpnessResultStoreTests {
    private func key(
        _ name: String, revision: Int64 = 1, session: String = "folder", version: Int = 1
    ) -> SharpnessResultKey {
        SharpnessResultKey(
            folderSession: session, photo: URL(fileURLWithPath: "/tmp/\(session)/\(name).arw"),
            revision: ThumbnailRevision(
                size: revision,
                modificationTime: Date(timeIntervalSince1970: TimeInterval(revision))),
            parametersVersion: version)
    }

    private func record(
        _ key: SharpnessResultKey, name: String = "a",
        acquisitionFailure: RegionImageFailure? = nil
    ) -> RegionSharpnessRecord {
        RegionSharpnessRecord(
            key: key,
            request: RegionSharpnessRequest(
                raw: DetailSource(
                    url: key.photo,
                    revision: ThumbnailRevision(
                        size: key.revision.size,
                        modificationTime: key.revision.modificationTime)),
                locationIdentity: key.folderSession),
            analysis: RegionSharpnessAnalysis(
                autofocus: .unavailable(
                    .noAutofocusMetadata(
                        AutofocusMetadataEvidence(
                            inspected: [], cameraMake: nil, exifOrientation: 1))),
                faces: .unavailable(.noFacesDetected),
                acquisitionFailure: acquisitionFailure,
                timings: RegionSharpnessTimings()))
    }

    @Test func servesOnlyTheExactIdentity() {
        let store = RegionSharpnessResultStore(capacity: 4)
        let original = key("a", revision: 1)
        store.store(record(original))
        #expect(store.result(for: original) != nil)
        // Another revision of the same photo: a different identity, never served.
        #expect(store.result(for: key("a", revision: 2)) == nil)
        // Another folder session at the same path: never served.
        #expect(store.result(for: key("a", session: "other")) == nil)
        // Another parameters version: never served.
        #expect(store.result(for: key("a", version: 2)) == nil)
        // Another photo: never served.
        #expect(store.result(for: key("b")) == nil)
    }

    @Test func evictsLeastRecentlyUsedFirst() {
        let store = RegionSharpnessResultStore(capacity: 2)
        let first = key("a")
        let second = key("b")
        let third = key("c")
        store.store(record(first))
        store.store(record(second))
        // Touch the first so the second becomes the least recently used.
        _ = store.result(for: first)
        store.store(record(third))
        #expect(store.result(for: first) != nil)
        #expect(store.result(for: second) == nil, "the untouched entry is evicted first")
        #expect(store.result(for: third) != nil)
        #expect(store.count == 2)
    }

    @Test func invalidateDropsEveryRecordTouchingTheFile() {
        let store = RegionSharpnessResultStore(capacity: 8)
        let gone = key("gone")
        // A RAW set whose companion shares the store's invalidation scope.
        let companion = RegionSharpnessRecord(
            key: key("other"),
            request: RegionSharpnessRequest(
                raw: DetailSource(
                    url: URL(fileURLWithPath: "/tmp/folder/other.arw"),
                    revision: ThumbnailRevision(size: 1, modificationTime: Date())),
                jpeg: DetailSource(
                    url: URL(fileURLWithPath: "/tmp/folder/gone.jpg"),
                    revision: ThumbnailRevision(size: 1, modificationTime: Date())),
                locationIdentity: "folder"),
            analysis: record(key("other")).analysis)
        store.store(record(gone))
        store.store(record(key("kept")))
        store.store(companion)
        #expect(store.count == 3)
        // The photo set changed: the app invalidates with every file of the set, which
        // drops the photo's own record and the other set that carries its JPEG as a
        // companion; the untouched record stays.
        store.invalidate(sources: [
            URL(fileURLWithPath: "/tmp/folder/gone.arw"),
            URL(fileURLWithPath: "/tmp/folder/gone.jpg"),
        ])
        #expect(store.result(for: gone) == nil)
        #expect(store.result(for: key("other")) == nil)
        #expect(store.result(for: key("kept")) != nil)
    }

    @Test func neverStoresContentionOrIdentityFailures() {
        let store = RegionSharpnessResultStore(capacity: 4)
        // A stale source: the answer belongs to no revision the caller can ask for again.
        store.store(record(key("stale"), acquisitionFailure: .staleSource))
        // Contention: the photo was never analysed; a later request must run real work.
        store.store(record(key("full"), acquisitionFailure: .queueFull))
        store.store(record(key("closed"), acquisitionFailure: .closed))
        #expect(store.count == 0)
        // Every other explicit answer is a fact about the photo and is kept.
        store.store(record(key("unreadable"), acquisitionFailure: .cannotOpen))
        store.store(record(key("nopreview"), acquisitionFailure: .noUsablePreview))
        store.store(record(key("analysed")))
        #expect(store.count == 3)
    }

    @Test func removeAllDropsEverything() {
        let store = RegionSharpnessResultStore(capacity: 4)
        store.store(record(key("a")))
        store.store(record(key("b")))
        store.removeAll()
        #expect(store.count == 0)
        #expect(store.result(for: key("a")) == nil)
    }
}
