import Foundation
import Testing

@testable import CloveCore

@Suite("Folder metadata cache")
struct FolderMetadataCacheTests {
    @Test func roundTripPersistencePreservesPrimaryAndMarksPayloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = FolderMetadataCache(directory: root.appendingPathComponent("FolderMetadata"))
        let folderID = FolderIdentity(rawValue: "sd-card-travel-2026")

        let wallTime = Date(timeIntervalSinceReferenceDate: 789_012_345.125)
        let creationDate = Date(timeIntervalSinceReferenceDate: 789_012_400.5)
        let modificationDate = Date(timeIntervalSinceReferenceDate: 789_012_500.25)

        let rawKey = FolderMetadataCache.Key(relativeFolderPath: "DCIM/100SONY", stem: "DSC00001")
        let rawPrimaryFP = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "DSC00001.ARW",
                size: 42_000_000,
                modificationDate: modificationDate))
        let rawSidecarFP = try #require(
            FolderMetadataCache.SidecarFingerprint.resolved(
                fileName: "DSC00001.XMP",
                size: 1_280,
                modificationDate: creationDate))
        let rawMarks = XMPMarks(
            rating: .rated(try #require(Rating(rawValue: 4))),
            label: ColourLabel(rawValue: "CustomBlue"),
            keywords: ["kyoto", "temple", "dawn"])
        let rawEntry = FolderMetadataCache.Entry(
            primaryFingerprint: rawPrimaryFP,
            primary: FolderMetadataCache.PrimaryPayload(
                timeSource: .captureMetadata(wallTime: wallTime, utcOffsetSeconds: 32_400),
                cameraBody: CameraBody(model: "ILCE-1M2", serial: "00112233"),
                filterMetadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2",
                    lens: "FE 35mm F1.4 GM",
                    focalLengthMillimetres: 35.0)),
            marks: .raw(sidecar: rawSidecarFP, xmp: rawMarks))

        let jpegKey = FolderMetadataCache.Key(relativeFolderPath: "", stem: "IMG_9999")
        let jpegPrimaryFP = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "IMG_9999.JPG",
                size: 4_500_000,
                modificationDate: modificationDate))
        let jpegEntry = FolderMetadataCache.Entry(
            primaryFingerprint: jpegPrimaryFP,
            primary: FolderMetadataCache.PrimaryPayload(
                timeSource: .fileCreation(creationDate),
                cameraBody: CameraBody(model: "X100VI", serial: nil),
                filterMetadata: PhotoFilterMetadata(
                    camera: "X100VI",
                    lens: nil,
                    focalLengthMillimetres: 35.0)),
            marks: .standalone(
                embedded: XMPMarks(
                    rating: .external(7),
                    label: ColourLabel(colour: .green),
                    keywords: ["street"])))

        let ambiguousKey = FolderMetadataCache.Key(relativeFolderPath: "Sub", stem: "ambig")
        let ambiguousFP = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "ambig.RAF",
                size: 100,
                modificationDate: modificationDate))
        let ambiguousEntry = FolderMetadataCache.Entry(
            primaryFingerprint: ambiguousFP,
            primary: FolderMetadataCache.PrimaryPayload(
                timeSource: .unavailable,
                cameraBody: nil,
                filterMetadata: .empty),
            marks: .raw(sidecar: .ambiguous, xmp: nil))

        let entries = [
            rawKey: rawEntry,
            jpegKey: jpegEntry,
            ambiguousKey: ambiguousEntry,
        ]
        cache.save(entries, folderID: folderID)

        let outcome = cache.loadWithOutcome(folderID: folderID)
        guard case .loaded(let loaded) = outcome else {
            Issue.record("Expected loaded cache outcome, got \(outcome)")
            return
        }
        #expect(loaded == entries)
        #expect(cache.fileURL(for: folderID).lastPathComponent.hasPrefix("metadata-v1-"))
        #expect(
            try cache.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true)
    }

    @Test func corruptVersionMismatchAndForeignFolderFallbackCleanly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = FolderMetadataCache(directory: root)
        let folderA = FolderIdentity(rawValue: "folder-a")
        let folderB = FolderIdentity(rawValue: "folder-b")

        #expect(cache.loadWithOutcome(folderID: folderA) == .missing)
        #expect(cache.load(folderID: folderA).isEmpty)

        // Corrupt JSON.
        try Data("{not json".utf8).write(to: cache.fileURL(for: folderA))
        #expect(cache.loadWithOutcome(folderID: folderA) == .unusable)
        #expect(cache.load(folderID: folderA).isEmpty)

        // Schema version mismatch.
        let wrongVersion = """
            {"version":999,"folder":"folder-a","entries":[]}
            """
        try Data(wrongVersion.utf8).write(to: cache.fileURL(for: folderA))
        #expect(cache.loadWithOutcome(folderID: folderA) == .unusable)
        #expect(cache.load(folderID: folderA).isEmpty)

        // Foreign folder identity copied into folderA's cache slot.
        let fp = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "A.ARW", size: 10, modificationDate: Date()))
        cache.save(
            [
                FolderMetadataCache.Key(relativeFolderPath: "", stem: "a"):
                    FolderMetadataCache.Entry(
                        primaryFingerprint: fp,
                        primary: FolderMetadataCache.PrimaryPayload(
                            timeSource: .unavailable, cameraBody: nil, filterMetadata: .empty))
            ],
            folderID: folderB)
        let foreignData = try Data(contentsOf: cache.fileURL(for: folderB))
        try foreignData.write(to: cache.fileURL(for: folderA))
        #expect(cache.loadWithOutcome(folderID: folderA) == .unusable)
        #expect(cache.load(folderID: folderA).isEmpty)
    }

    @Test func primaryFingerprintRequiresStrictMatchAndInvalidatesOnChange() throws {
        let folderID = FolderIdentity(rawValue: "fingerprint-test")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rawURL = root.appendingPathComponent("IMG_0001.ARW")
        let jpegURL = root.appendingPathComponent("IMG_0001.JPG")
        let modDate = Date(timeIntervalSinceReferenceDate: 780_000_000.5)

        let rawSet = try PhotoSet(folderID: folderID, relativeFolderPath: "", rawURL: rawURL)
        let primaryFP = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "IMG_0001.ARW", size: 2048, modificationDate: modDate))
        let payload = FolderMetadataCache.PrimaryPayload(
            timeSource: .fileModification(modDate),
            cameraBody: CameraBody(model: "A7RV", serial: nil),
            filterMetadata: PhotoFilterMetadata(camera: "A7RV"))
        let entry = FolderMetadataCache.Entry(
            primaryFingerprint: primaryFP,
            primary: payload,
            marks: .raw(sidecar: .absent, xmp: nil))

        // Exact match hits.
        let exact = ScannedPhotoSet(
            photoSet: rawSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(file: rawSet.primary, size: 2048, modificationDate: modDate)
            ])
        #expect(entry.cachedPrimary(for: exact) == payload)

        // Missing size or missing modificationDate never hits.
        let nilSize = ScannedPhotoSet(
            photoSet: rawSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(file: rawSet.primary, size: nil, modificationDate: modDate)
            ])
        let nilDate = ScannedPhotoSet(
            photoSet: rawSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(file: rawSet.primary, size: 2048, modificationDate: nil)
            ])
        #expect(entry.cachedPrimary(for: nilSize) == nil)
        #expect(entry.cachedPrimary(for: nilDate) == nil)

        // Changed size or subsecond modificationDate invalidates.
        let changedSize = ScannedPhotoSet(
            photoSet: rawSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(file: rawSet.primary, size: 2049, modificationDate: modDate)
            ])
        let changedDate = ScannedPhotoSet(
            photoSet: rawSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(
                    file: rawSet.primary,
                    size: 2048,
                    modificationDate: modDate.addingTimeInterval(0.001))
            ])
        #expect(entry.cachedPrimary(for: changedSize) == nil)
        #expect(entry.cachedPrimary(for: changedDate) == nil)

        // Primary extension/filename switch (e.g. RAW removed leaving standalone JPEG) invalidates.
        let standaloneSet = try PhotoSet(
            folderID: folderID, relativeFolderPath: "", jpegURL: jpegURL)
        let standaloneScanned = ScannedPhotoSet(
            photoSet: standaloneSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(
                    file: standaloneSet.primary, size: 2048, modificationDate: modDate)
            ])
        #expect(entry.cachedPrimary(for: standaloneScanned) == nil)
        #expect(entry.cachedMarks(for: standaloneScanned) == .miss)
    }

    @Test func sidecarFingerprintInvalidatesOnAddModifyDeleteAndFormatChange() throws {
        let folderID = FolderIdentity(rawValue: "sidecar-fp-test")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rawURL = root.appendingPathComponent("IMG_0002.ARW")
        let xmpURL = root.appendingPathComponent("IMG_0002.xmp")
        let upperXmpURL = root.appendingPathComponent("IMG_0002.XMP")
        let rawDate = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let xmpDate = Date(timeIntervalSinceReferenceDate: 780_000_100)

        let rawSetNoSidecar = try PhotoSet(
            folderID: folderID, relativeFolderPath: "", rawURL: rawURL)
        let rawSetWithSidecar = try PhotoSet(
            folderID: folderID, relativeFolderPath: "", rawURL: rawURL, sidecarURL: xmpURL)
        let primaryFP = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "IMG_0002.ARW", size: 5000, modificationDate: rawDate))
        let primaryPayload = FolderMetadataCache.PrimaryPayload(
            timeSource: .fileCreation(rawDate),
            cameraBody: nil,
            filterMetadata: .empty)

        // Cached as absent sidecar.
        let absentEntry = FolderMetadataCache.Entry(
            primaryFingerprint: primaryFP,
            primary: primaryPayload,
            marks: .raw(sidecar: .absent, xmp: nil))
        let scannedAbsent = ScannedPhotoSet(
            photoSet: rawSetNoSidecar,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(
                    file: rawSetNoSidecar.primary, size: 5000, modificationDate: rawDate)
            ])
        #expect(absentEntry.cachedMarks(for: scannedAbsent) == .hit(embedded: nil, xmp: nil))

        // Sidecar added on disk -> primary still hits, marks miss.
        let scannedAdded = ScannedPhotoSet(
            photoSet: rawSetWithSidecar,
            sidecar: .resolved(xmpURL),
            imageFiles: [
                ScannedImageFile(
                    file: rawSetWithSidecar.primary, size: 5000, modificationDate: rawDate)
            ],
            sidecarRevision: ScannedFileRevision(size: 512, modificationDate: xmpDate))
        #expect(absentEntry.cachedPrimary(for: scannedAdded) == primaryPayload)
        #expect(absentEntry.cachedMarks(for: scannedAdded) == .miss)

        // Cached as resolved sidecar.
        let five = try #require(Rating(rawValue: 5))
        let cachedXMP = XMPMarks(rating: .rated(five), label: ColourLabel(colour: .red))
        let resolvedFP = try #require(
            FolderMetadataCache.SidecarFingerprint.resolved(
                fileName: "IMG_0002.xmp", size: 512, modificationDate: xmpDate))
        let resolvedEntry = FolderMetadataCache.Entry(
            primaryFingerprint: primaryFP,
            primary: primaryPayload,
            marks: .raw(sidecar: resolvedFP, xmp: cachedXMP))

        #expect(resolvedEntry.cachedMarks(for: scannedAdded) == .hit(embedded: nil, xmp: cachedXMP))

        // Modified sidecar size or mtime or spelling invalidates marks while keeping primary.
        let modifiedSidecar = ScannedPhotoSet(
            photoSet: rawSetWithSidecar,
            sidecar: .resolved(xmpURL),
            imageFiles: scannedAdded.imageFiles,
            sidecarRevision: ScannedFileRevision(size: 513, modificationDate: xmpDate))
        #expect(resolvedEntry.cachedPrimary(for: modifiedSidecar) == primaryPayload)
        #expect(resolvedEntry.cachedMarks(for: modifiedSidecar) == .miss)

        let renamedSidecar = ScannedPhotoSet(
            photoSet: try PhotoSet(
                folderID: folderID, relativeFolderPath: "", rawURL: rawURL,
                sidecarURL: upperXmpURL),
            sidecar: .resolved(upperXmpURL),
            imageFiles: scannedAdded.imageFiles,
            sidecarRevision: ScannedFileRevision(size: 512, modificationDate: xmpDate))
        #expect(resolvedEntry.cachedMarks(for: renamedSidecar) == .miss)

        // Missing sidecarRevision (e.g. non-regular file or synthetic without revision) misses.
        let missingRevision = ScannedPhotoSet(
            photoSet: rawSetWithSidecar,
            sidecar: .resolved(xmpURL),
            imageFiles: scannedAdded.imageFiles,
            sidecarRevision: nil)
        #expect(resolvedEntry.cachedMarks(for: missingRevision) == .miss)

        // Deleted sidecar or ambiguous sidecar misses.
        #expect(resolvedEntry.cachedMarks(for: scannedAbsent) == .miss)
        let ambiguousScanned = ScannedPhotoSet(
            photoSet: rawSetNoSidecar,
            sidecar: .ambiguous([xmpURL]),
            imageFiles: scannedAbsent.imageFiles)
        #expect(resolvedEntry.cachedMarks(for: ambiguousScanned) == .miss)
    }

    @Test func timezoneSafeCaptureWallTimeReconstructsAgainstCurrentZone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let wallTime = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026, month: 6, day: 15, hour: 14, minute: 30, second: 0,
                    nanosecond: 250_000_000)))

        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

        let cache = FolderMetadataCache(directory: root)
        let folderID = FolderIdentity(rawValue: "tz-folder")
        let fp = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "A.ARW", size: 100, modificationDate: Date()))
        let noOffsetKey = FolderMetadataCache.Key(relativeFolderPath: "", stem: "no_offset")
        let withOffsetKey = FolderMetadataCache.Key(relativeFolderPath: "", stem: "with_offset")

        cache.save(
            [
                noOffsetKey: FolderMetadataCache.Entry(
                    primaryFingerprint: fp,
                    primary: FolderMetadataCache.PrimaryPayload(
                        timeSource: .captureMetadata(wallTime: wallTime, utcOffsetSeconds: nil),
                        cameraBody: nil,
                        filterMetadata: .empty)),
                withOffsetKey: FolderMetadataCache.Entry(
                    primaryFingerprint: fp,
                    primary: FolderMetadataCache.PrimaryPayload(
                        timeSource: .captureMetadata(wallTime: wallTime, utcOffsetSeconds: 32_400),
                        cameraBody: nil,
                        filterMetadata: .empty)),
            ],
            folderID: folderID)

        let loaded = cache.load(folderID: folderID)
        let noOffsetSource = try #require(loaded[noOffsetKey]?.primary?.timeSource)
        let withOffsetSource = try #require(loaded[withOffsetKey]?.primary?.timeSource)

        // Without offset: wall clock resolves against the supplied zone.
        #expect(
            noOffsetSource.photoTimeState(in: tokyo)
                == .known(PhotoTime(captureWallTime: wallTime, utcOffsetSeconds: nil, in: tokyo)))
        #expect(
            noOffsetSource.photoTimeState(in: losAngeles)
                == .known(
                    PhotoTime(captureWallTime: wallTime, utcOffsetSeconds: nil, in: losAngeles)))
        #expect(
            noOffsetSource.photoTimeState(in: tokyo)
                != noOffsetSource.photoTimeState(in: losAngeles))

        // With explicit offset: instant is invariant across zones.
        #expect(
            withOffsetSource.photoTimeState(in: tokyo)
                == withOffsetSource.photoTimeState(in: losAngeles))
    }

    @Test func savePrunesRemovedEntriesAndApplicationSupportPathIsAppPrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = FolderMetadataCache(directory: root)
        let folderID = FolderIdentity(rawValue: "prune-test")
        let fp = try #require(
            FolderMetadataCache.PrimaryFingerprint(
                fileName: "A.ARW", size: 100, modificationDate: Date()))
        let payload = FolderMetadataCache.PrimaryPayload(
            timeSource: .unavailable, cameraBody: nil, filterMetadata: .empty)

        let keepKey = FolderMetadataCache.Key(relativeFolderPath: "", stem: "keep")
        let removedKey = FolderMetadataCache.Key(relativeFolderPath: "", stem: "removed")
        cache.save(
            [
                keepKey: FolderMetadataCache.Entry(primaryFingerprint: fp, primary: payload),
                removedKey: FolderMetadataCache.Entry(primaryFingerprint: fp, primary: payload),
            ],
            folderID: folderID)
        #expect(cache.load(folderID: folderID).count == 2)

        cache.save(
            [keepKey: FolderMetadataCache.Entry(primaryFingerprint: fp, primary: payload)],
            folderID: folderID)
        let reloaded = cache.load(folderID: folderID)
        #expect(Array(reloaded.keys) == [keepKey])

        let appSupport = try FolderMetadataCache.applicationSupportDirectory()
        #expect(appSupport.lastPathComponent == "FolderMetadata")
        #expect(appSupport.deletingLastPathComponent().lastPathComponent == "Clove")
    }

    @Test func photoFolderWalkPrefetchesResolvedSidecarRevision() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }

        try folder.file("Resolved.ARW")
        let resolvedXMP = try folder.file("Resolved.xmp", bytes: 321)
        try folder.file("Absent.ARW")
        try folder.file("Ambiguous.ARW")
        try folder.file("Ambiguous.ARW.xmp", bytes: 99)
        try folder.file("DirectorySidecar.ARW")
        try folder.directory("DirectorySidecar.xmp")

        let outcome = try await scanFolder(folder)
        let photos = outcome.photosByStem

        let resolved = try #require(photos["resolved"])
        let expectedAttrs = try resolvedXMP.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey,
        ])
        #expect(resolved.sidecar == .resolved(resolvedXMP))
        #expect(resolved.sidecarRevision?.size == 321)
        #expect(resolved.sidecarRevision?.size == expectedAttrs.fileSize)
        #expect(
            resolved.sidecarRevision?.modificationDate == expectedAttrs.contentModificationDate)

        #expect(photos["absent"]?.sidecarRevision == nil)
        #expect(photos["ambiguous"]?.sidecarRevision == nil)
        #expect(photos["directorysidecar"]?.sidecarRevision == nil)
    }
}
