import Foundation
import Testing

@testable import CloveCore

private let testFolderID = FolderIdentity(rawValue: "scan-test-folder")

@Suite(.serialized)
struct FolderScanTests {
    // MARK: - Pairing

    @Test func everyPairingCombinationFormsOneSetWithMixedCase() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("DCIM/100CAM/Standalone.ARW")
        try folder.file("DCIM/100CAM/Pair.ARW")
        try folder.file("DCIM/100CAM/pair.JpEg")
        try folder.file("DCIM/100CAM/RawHeif.NEF")
        try folder.file("DCIM/100CAM/rawheif.hIf")
        try folder.file("DCIM/100CAM/Triple.CR3")
        try folder.file("DCIM/100CAM/Triple.JPG")
        try folder.file("DCIM/100CAM/triple.hif")
        try folder.file("DCIM/100CAM/OnlyJpeg.JpEg")
        try folder.file("DCIM/100CAM/OnlyHeif.HeIc")
        try folder.file("DCIM/100CAM/NoRaw.JPEG")
        try folder.file("DCIM/100CAM/NoRaw.HIF")

        let outcome = try await scanFolder(folder, folderID: testFolderID)
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 7)
        #expect(summary.status == .complete)
        #expect(outcome.itemsMatchLogicalPhotoCount)
        #expect(outcome.items.count == 7)

        let photos = outcome.photosByStem
        #expect(photos["standalone"]?.photoSet.primary.format == .raw)
        #expect(photos["standalone"]?.photoSet.jpegCompanion == nil)
        #expect(photos["standalone"]?.photoSet.heifCompanion == nil)

        let pair = try #require(photos["pair"]?.photoSet)
        #expect(pair.primary.url.lastPathComponent == "Pair.ARW")
        #expect(pair.jpegCompanion?.url.lastPathComponent == "pair.JpEg")
        #expect(pair.heifCompanion == nil)

        let rawHeif = try #require(photos["rawheif"]?.photoSet)
        #expect(rawHeif.primary.format == .raw)
        #expect(rawHeif.jpegCompanion == nil)
        #expect(rawHeif.heifCompanion?.url.lastPathComponent == "rawheif.hIf")

        // G1 decision 1: RAW + JPEG + HIF is one photo with three files, RAW primary.
        let triple = try #require(photos["triple"]?.photoSet)
        #expect(triple.primary.url.lastPathComponent == "Triple.CR3")
        #expect(triple.jpegCompanion?.url.lastPathComponent == "Triple.JPG")
        #expect(triple.heifCompanion?.url.lastPathComponent == "triple.hif")
        #expect(triple.imageFiles.count == 3)

        #expect(photos["onlyjpeg"]?.photoSet.primary.format == .jpeg)
        #expect(photos["onlyheif"]?.photoSet.primary.format == .heif)

        // JPEG + HIF without RAW follows the generic rule: JPEG primary, HIF companion.
        let noRaw = try #require(photos["noraw"]?.photoSet)
        #expect(noRaw.primary.url.lastPathComponent == "NoRaw.JPEG")
        #expect(noRaw.jpegCompanion == nil)
        #expect(noRaw.heifCompanion?.url.lastPathComponent == "NoRaw.HIF")

        for photo in outcome.photos {
            #expect(photo.photoSet.id.folderID == testFolderID)
            #expect(photo.photoSet.id.relativeFolderPath == "DCIM/100CAM")
            #expect(photo.sidecar == .absent)
            // Member metadata follows the set's own member order for I1's cache revision.
            #expect(photo.imageFiles.map(\.file.url) == photo.photoSet.imageFiles.map(\.url))
            #expect(photo.imageFiles.allSatisfy { $0.size == 16 })
            #expect(photo.imageFiles.allSatisfy { $0.modificationDate != nil })
        }
        #expect(summary.unsupportedFileCount == 0)
        #expect(summary.ambiguousCount == 0)
        #expect(summary.orphanSidecarCount == 0)
        #expect(summary.skippedFolderCount == 0)
    }

    @Test func nestedCameraFoldersPairWithinTheirOwnFolder() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("DCIM/100XXXXX/MMQ0001.ARW")
        try folder.file("DCIM/100XXXXX/MMQ0001.HIF")
        try folder.file("DCIM/101XXXXX/MMQ0001.ARW")
        try folder.file("DCIM/101XXXXX/MMQ0002.DNG")
        try folder.file("DCIM/101XXXXX/MMQ0002.JPG")

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 3)
        #expect(summary.status == .complete)

        let first = try #require(
            outcome.photos.first { $0.photoSet.id.relativeFolderPath == "DCIM/100XXXXX" })
        #expect(first.photoSet.primary.url.lastPathComponent == "MMQ0001.ARW")
        #expect(first.photoSet.heifCompanion?.url.lastPathComponent == "MMQ0001.HIF")
        #expect(first.photoSet.id.relativeFolderPath == "DCIM/100XXXXX")

        let second = try #require(
            outcome.photos.first {
                $0.photoSet.id.relativeFolderPath == "DCIM/101XXXXX"
                    && $0.photoSet.primary.format == .raw
                    && $0.photoSet.primary.url.pathExtension == "ARW"
            })
        #expect(second.photoSet.heifCompanion == nil)

        // The same stem in another folder is a different photo (PRD P0-01, scan scope).
        #expect(first.photoSet.id != second.photoSet.id)
        #expect(first.photoSet.id.stem == second.photoSet.id.stem)

        let pair = try #require(
            outcome.photos.first { $0.photoSet.id.stem == "mmq0002" })
        #expect(pair.photoSet.primary.url.lastPathComponent == "MMQ0002.DNG")
        #expect(pair.photoSet.jpegCompanion?.url.lastPathComponent == "MMQ0002.JPG")
    }

    @Test func rootFilesUseAnEmptyRelativeFolderPathAndKeepTheirSpelling() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("Root.ARW")
        try folder.file("DCIM/MiXeD Case/Inner.JPG")

        let outcome = try await scanFolder(folder)
        let photos = outcome.photos
        #expect(photos.count == 2)
        let root = try #require(photos.first { $0.photoSet.id.stem == "root" })
        #expect(root.photoSet.id.relativeFolderPath == "")
        let inner = try #require(photos.first { $0.photoSet.id.stem == "inner" })
        #expect(inner.photoSet.id.relativeFolderPath == "DCIM/MiXeD Case")
    }

    @Test func setSeparatedByASubfolderStaysOneItemInOneBatch() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        let raw = try folder.file("A.ARW")
        let subfolder = try folder.directory("sub")
        let inner = try folder.file("sub/B.JPG")
        let jpeg = try folder.file("A.JPG")

        // No generated folder can guarantee that a subfolder is walked between two files of
        // one stem, so the exact walk order is fed in (PRD scan scope: no split across batches).
        var walk = FolderWalk(
            folderID: testFolderID, configuration: ScanConfiguration(batchSize: 1))
        var batches: [ScanBatch] = []
        func emit(_ batch: ScanBatch) { batches.append(batch) }
        _ = try walk.receive(WalkEntry(url: raw, isDirectory: false), emit: emit)
        _ = try walk.receive(WalkEntry(url: subfolder, isDirectory: true), emit: emit)
        _ = try walk.receive(WalkEntry(url: inner, isDirectory: false), emit: emit)
        _ = try walk.receive(WalkEntry(url: jpeg, isDirectory: false), emit: emit)
        let summary = try walk.finish(emit: emit)

        #expect(summary.logicalPhotoCount == 2)
        #expect(batches.count == 2)
        let pairItems = batches.flatMap(\.items).filter { item in
            item.imageFiles.contains { $0.file.url.lastPathComponent == "A.ARW" }
        }
        #expect(pairItems.count == 1)
        let pair = try #require(pairItems.first)
        #expect(
            Set(pair.imageFiles.map(\.file.url.lastPathComponent))
                == Set(["A.ARW", "A.JPG"]))
        guard case .photo(let photo) = pair else {
            Issue.record("A.ARW and A.JPG must form one set")
            return
        }
        #expect(photo.photoSet.primary.url == raw)
        #expect(photo.photoSet.jpegCompanion?.url == jpeg)
    }

    // MARK: - Skipping

    @Test func skipsHiddenAppleDoublePackagesAndTheRejectsFolder() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("DCIM/100CAM/Keep.ARW")
        try folder.file("DCIM/100CAM/._Keep.ARW")
        try folder.file("DCIM/100CAM/.DS_Store")
        try folder.file(".Hidden/Inside.ARW")
        try folder.file("DCIM/.Hidden/Inside.ARW")
        try folder.file("Holiday.photoslibrary/DCIM/Inside.ARW")
        try folder.file("DCIM/100CAM/_Rejected/Moved.ARW")
        try folder.file("DCIM/101CAM/_rejected/Lower.ARW")
        try folder.file("DCIM/100CAM/_Rejected2/Kept.ARW")
        try folder.file("DCIM/100CAM/MVI_0001.MOV")

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 2)
        #expect(Set(outcome.photos.map { $0.photoSet.id.stem }) == Set(["keep", "kept"]))
        #expect(summary.unsupportedFileCount == 1)
        #expect(summary.unsupportedFiles.map(\.lastPathComponent) == ["MVI_0001.MOV"])
        // `_Rejected` in either case and the package are skipped; hidden folders are skipped
        // by the enumeration itself.
        #expect(summary.skippedFolderCount == 3)
        #expect(summary.status == .complete)
        #expect(
            !outcome.items.contains { item in
                item.imageFiles.contains { $0.file.url.path.contains("/_Rejected/") }
            })
        #expect(
            !outcome.items.contains { item in
                item.imageFiles.contains { $0.file.url.path.contains("Holiday.photoslibrary") }
            })
    }

    @Test func customRejectsFolderNameReplacesTheDefault() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("Keep.ARW")
        try folder.file("Archive/Photo.ARW")
        try folder.file("_Rejected/Kept.ARW")

        let outcome = try await scanFolder(
            folder, configuration: ScanConfiguration(rejectsFolderName: "archive"))
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 2)
        #expect(Set(outcome.photos.map { $0.photoSet.id.stem }) == Set(["keep", "kept"]))
        #expect(summary.skippedFolderCount == 1)
    }

    // MARK: - Sidecars

    @Test func sidecarStatesCoverFoundMissingSpellingAppendedAndOrphan() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("DCIM/100CAM/Found.ARW")
        try folder.file("DCIM/100CAM/Found.xmp")
        try folder.file("DCIM/100CAM/Missing.ARW")
        try folder.file("DCIM/100CAM/Spelling.ARW")
        try folder.file("DCIM/100CAM/SpellING.XMP")
        try folder.file("DCIM/100CAM/Appended.ARW")
        try folder.file("DCIM/100CAM/Appended.ARW.xmp")
        try folder.file("DCIM/100CAM/Orphan.JPG")
        try folder.file("DCIM/100CAM/Orphan.xmp")
        try folder.file("DCIM/100CAM/Loose.xmp")

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        let photos = outcome.photosByStem
        #expect(summary.logicalPhotoCount == 5)

        #expect(
            photos["found"]?.sidecar
                == .resolved(folder.fileURL("DCIM/100CAM/Found.xmp")))
        #expect(photos["found"]?.photoSet.sidecarURL == folder.fileURL("DCIM/100CAM/Found.xmp"))
        #expect(
            photos["found"]?.photoSet.markPersistence.rating
                == .xmpSidecar(folder.fileURL("DCIM/100CAM/Found.xmp")))

        #expect(photos["missing"]?.sidecar == .absent)
        #expect(photos["missing"]?.photoSet.sidecarURL == nil)

        // The actual spelling reaches the set, so C1 reuses it instead of inventing `Spelling.xmp`.
        #expect(
            photos["spelling"]?.sidecar
                == .resolved(folder.fileURL("DCIM/100CAM/SpellING.XMP")))
        #expect(
            photos["spelling"]?.photoSet.markPersistence.rating
                == .xmpSidecar(folder.fileURL("DCIM/100CAM/SpellING.XMP")))

        // `Appended.ARW.xmp` would make C1 propose a second packet, so the set is produced
        // but its sidecar is ambiguous and no destination is offered.
        let appended = try #require(photos["appended"])
        #expect(
            appended.sidecar
                == .ambiguous([folder.fileURL("DCIM/100CAM/Appended.ARW.xmp")]))
        #expect(appended.photoSet.sidecarURL == nil)

        // A JPEG without RAW has no sidecar (G1 decision 6); the packet is an orphan.
        #expect(photos["orphan"]?.sidecar == .absent)
        #expect(photos["orphan"]?.photoSet.sidecarURL == nil)
        #expect(summary.orphanSidecarCount == 2)
        #expect(summary.ambiguousSidecarCount == 1)
        #expect(summary.ambiguousMemberCount == 0)
        #expect(summary.status == .complete)
    }

    @Test func sidecarStateReusesOnePacketAndReportsAnyCompetingChoice() {
        let directory = URL(fileURLWithPath: "/Photos/DCIM/100CAM", isDirectory: true)
        let plain = DirectoryContents.PacketMatch(
            url: directory.appendingPathComponent("A.xmp"), isAppendedExtension: false)
        let otherCase = DirectoryContents.PacketMatch(
            url: directory.appendingPathComponent("A.XMP"), isAppendedExtension: false)
        let appended = DirectoryContents.PacketMatch(
            url: directory.appendingPathComponent("A.ARW.xmp"), isAppendedExtension: true)

        #expect(PhotoFolderWalk.sidecarState(from: []) == .absent)
        #expect(PhotoFolderWalk.sidecarState(from: [plain]) == .resolved(plain.url))
        #expect(
            PhotoFolderWalk.sidecarState(from: [plain, otherCase])
                == .ambiguous([plain.url, otherCase.url]))
        #expect(
            PhotoFolderWalk.sidecarState(from: [appended])
                == .ambiguous([appended.url]))
        #expect(
            PhotoFolderWalk.sidecarState(from: [plain, appended])
                == .ambiguous([plain.url, appended.url]))
        #expect(SidecarState.ambiguous([plain.url]).resolvedURL == nil)
        #expect(SidecarState.resolved(plain.url).resolvedURL == plain.url)
        #expect(SidecarState.absent.candidates.isEmpty)
    }

    // MARK: - Ambiguity

    @Test func duplicateFamilyMembersMakeOneAmbiguousItemWithoutASet() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("DCIM/100CAM/TwoRaw.ARW")
        try folder.file("DCIM/100CAM/TwoRaw.DNG")
        try folder.file("DCIM/100CAM/TwoJpeg.JPG")
        try folder.file("DCIM/100CAM/TwoJpeg.JPEG")
        try folder.file("DCIM/100CAM/TwoHeif.HIF")
        try folder.file("DCIM/100CAM/TwoHeif.HEIC")
        try folder.file("DCIM/100CAM/Mixed.ARW")
        try folder.file("DCIM/100CAM/Mixed.NEF")
        try folder.file("DCIM/100CAM/Mixed.JPG")
        try folder.file("DCIM/100CAM/Mixed.xmp")
        try folder.file("DCIM/100CAM/Fine.ARW")

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 1)
        #expect(summary.ambiguousMemberCount == 4)
        #expect(summary.ambiguousCount == 4)
        #expect(outcome.photos.map { $0.photoSet.id.stem } == ["fine"])

        let ambiguous = Dictionary(
            outcome.ambiguousStems.map { ($0.stem.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        #expect(Set(ambiguous.keys) == Set(["tworaw", "twojpeg", "twoheif", "mixed"]))
        #expect(
            Set(ambiguous["tworaw"]?.urls.map(\.lastPathComponent) ?? [])
                == Set(["TwoRaw.ARW", "TwoRaw.DNG"]))
        #expect(
            Set(ambiguous["twojpeg"]?.urls.map(\.lastPathComponent) ?? [])
                == Set(["TwoJpeg.JPG", "TwoJpeg.JPEG"]))
        #expect(
            Set(ambiguous["twoheif"]?.urls.map(\.lastPathComponent) ?? [])
                == Set(["TwoHeif.HIF", "TwoHeif.HEIC"]))
        #expect(ambiguous["mixed"]?.imageFiles.count == 3)
        #expect(ambiguous["mixed"]?.sidecar == .resolved(folder.fileURL("DCIM/100CAM/Mixed.xmp")))
        #expect(ambiguous["mixed"]?.relativeFolderPath == "DCIM/100CAM")
        #expect(summary.status == .complete)
    }

    @Test func competingPacketsAreAmbiguousWhenTheVolumeKeepsBothNames() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("DCIM/100CAM/Competing.ARW")
        try folder.file("DCIM/100CAM/Competing.xmp")
        guard try acceptsCaseDistinctNames(folder.fileURL("DCIM/100CAM")) else { return }
        try folder.file("DCIM/100CAM/Competing.XMP")

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        let photo = try #require(outcome.photos.first)
        #expect(summary.logicalPhotoCount == 1)
        #expect(summary.ambiguousSidecarCount == 1)
        #expect(photo.photoSet.sidecarURL == nil)
        #expect(
            Set(photo.sidecar.candidates.map(\.lastPathComponent))
                == Set(["Competing.xmp", "Competing.XMP"]))
    }

    // MARK: - Unsupported files

    @Test func unsupportedFilesAreCountedWithTheirURLs() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("MVI_0001.MOV")
        try folder.file("NOTES.txt")
        try folder.file("README")
        try folder.file("Photo.ARW")
        try folder.file("Photo.xmp")

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        #expect(summary.unsupportedFileCount == 3)
        #expect(
            Set(summary.unsupportedFiles.map(\.lastPathComponent))
                == Set(["MVI_0001.MOV", "NOTES.txt", "README"]))
        #expect(summary.logicalPhotoCount == 1)
        // A packet that matches a RAW is no orphan and never an unsupported file.
        #expect(summary.orphanSidecarCount == 0)
        #expect(outcome.photos.first?.sidecar == .resolved(folder.fileURL("Photo.xmp")))
    }

    // MARK: - Streaming

    @Test func batchesHoldAtMost64ItemsAndEverySetIsWhole() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        for index in 0..<130 {
            try folder.file(String(format: "DCIM/100CAM/IMG_%04d.ARW", index))
        }
        for index in 0..<50 {
            try folder.file(String(format: "DCIM/101CAM/PAIR_%04d.ARW", index))
            try folder.file(String(format: "DCIM/101CAM/PAIR_%04d.JPG", index))
        }
        for index in 0..<30 {
            try folder.file(String(format: "DCIM/102CAM/HEIF_%04d.HIF", index))
        }

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 210)
        #expect(outcome.itemsMatchLogicalPhotoCount)
        #expect(!outcome.batches.isEmpty)
        #expect(outcome.batches.allSatisfy { $0.items.count <= ScanConfiguration.maximumBatchSize })
        #expect(outcome.batches.contains { $0.items.count == ScanConfiguration.maximumBatchSize })
        let numbers = outcome.batches.map(\.number)
        #expect(numbers == Array(1...outcome.batches.count))

        // Every pair is one item with both files, so no batch boundary can split it.
        let pairs = outcome.photos.filter { $0.photoSet.jpegCompanion != nil }
        #expect(pairs.count == 50)
        for pair in pairs {
            #expect(pair.imageFiles.count == 2)
            #expect(pair.photoSet.id.relativeFolderPath == "DCIM/101CAM")
        }
        // 130 items in one folder give 64 + 64 + 2 once it completes, then one batch per folder.
        #expect(outcome.batches.count == 5)
    }

    @Test func batchSizeIsClampedToOneThrough64() {
        #expect(ScanConfiguration().batchSize == 64)
        #expect(ScanConfiguration().rejectsFolderName == "_Rejected")
        #expect(ScanConfiguration(batchSize: 0).batchSize == 1)
        #expect(ScanConfiguration(batchSize: 500).batchSize == 64)
        #expect(ScanConfiguration(batchSize: 7).batchSize == 7)
    }

    // MARK: - Cancellation

    @Test func cancellingTheConsumerTaskStopsTheBatchSequence() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        for index in 0..<200 {
            try folder.file(String(format: "DCIM/100CAM/IMG_%04d.ARW", index))
        }
        let scan = FolderScan(folderURL: folder.url, folderID: testFolderID)
        let gate = TestGate()
        let consumer = Task { () -> Int in
            await gate.wait()
            var received = 0
            do {
                for try await _ in scan {
                    // The sequence's cancellation contract is cooperative at batch
                    // boundaries: a cancelled consumer stops admitting batches, including
                    // ones the walk already buffered (the app's scan loop checks the same way).
                    try Task.checkCancellation()
                    received += 1
                }
            } catch is CancellationError {
                // The expected stop: the consumer ends here instead of draining the buffer.
            }
            return received
        }
        // The producer finished while the consumer was still parked at the gate, so all four
        // batches (64+64+64+8) are sitting in the stream's buffer — the interleaving CI
        // caught (#213), where the old assertion raced the producer and lost. Waiting on the
        // walk's observable end (the summary) makes it the only possible interleaving, with
        // no sleep: a cancelled consumer must not admit any buffered batch.
        let summary = try await scan.summary()
        #expect(summary.logicalPhotoCount == 200)
        consumer.cancel()
        await gate.open()
        let received = try await consumer.value
        #expect(received == 0)
    }

    @Test func cancelledWalkStopsBeforeEmittingAnyBatch() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        for index in 0..<40 {
            try folder.file(String(format: "DCIM/100CAM/IMG_%04d.ARW", index))
        }
        let walk = PhotoFolderWalk(
            rootURL: folder.url, folderID: testFolderID, configuration: ScanConfiguration())
        let gate = TestGate()
        let task = Task { () throws -> ScanSummary in
            await gate.wait()
            return try walk.run { _ in }
        }
        task.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: - Partial scans

    @Test func unreadableSubfolderMakesTheScanPartialAndKeepsWhatItRead() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        let locked = try folder.directory("DCIM/101LOCKED")
        try folder.file("DCIM/101LOCKED/Inside.ARW")
        try folder.file("DCIM/100CAM/Read.ARW")
        try folder.file("DCIM/100CAM/Read.JPG")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: locked.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false))
        }

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        // A partial scan is never a complete scan with fewer photos (PRD scan scope).
        #expect(summary.status == .partial)
        #expect(!summary.isComplete)
        #expect(summary.logicalPhotoCount == 1)
        #expect(outcome.photos.first?.photoSet.id.stem == "read")
        let issue = try #require(summary.issues.first)
        #expect(issue.url.path.contains("DCIM/101LOCKED"))
        #expect(!issue.errorChain.isEmpty)
        #expect(!issue.message.isEmpty)
    }

    @Test func unreadableRootIsPartialRatherThanACompleteEmptyScan() async throws {
        let folder = try ScanTestFolder()
        defer { folder.remove() }
        try folder.file("Photo.ARW")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: folder.url.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: folder.url.path(percentEncoded: false))
        }

        let outcome = try await scanFolder(folder)
        let summary = try #require(outcome.summary)
        #expect(summary.logicalPhotoCount == 0)
        #expect(summary.status == .partial)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.url.path.hasSuffix(folder.url.lastPathComponent) == true)
    }
}
