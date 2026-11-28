import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI
import Testing
import UIKit

@testable import Clove
@testable import CloveImaging

@MainActor
@Suite("Metadata and keyword browsing filters")
struct MetadataFilterBrowsingTests {
    @Test func browsingModelCombinesPrimaryLabelAndMetadataFilters() throws {
        let folder = TestLibrary.sampleFolderKey
        let fourStars = try #require(Rating(rawValue: 4))
        let photos = [
            makePhoto(
                folder: folder, stem: "p1", seconds: 1,
                marks: PhotoMarks(
                    rating: fourStars, label: ColourLabel(colour: .green),
                    keywords: ["portrait", "outdoor"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85)),
            makePhoto(
                folder: folder, stem: "p2", seconds: 2,
                marks: PhotoMarks(rating: fourStars, keywords: ["outdoor"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 24mm F1.4 GM", focalLengthMillimetres: 24)),
            makePhoto(
                folder: folder, stem: "p3", seconds: 3,
                marks: PhotoMarks(rating: .rejected, keywords: ["portrait"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-7M4", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85)),
            makePhoto(
                folder: folder, stem: "p4", seconds: 4,
                marks: PhotoMarks(),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-7M4", lens: "FE 200-600mm", focalLengthMillimetres: 400)),
        ]
        let library = TestLibrary(photos: photos, groups: [])
        let model = BrowsingModel(library: library)
        model.openFolder()

        #expect(model.photos.map(\.id.stem) == ["p1", "p2", "p3", "p4"])
        #expect(model.metadataFilterOptions.hasAnyDimension)
        #expect(model.metadataFilterOptions.cameras.map(\.value) == ["ILCE-1M2", "ILCE-7M4"])
        #expect(
            model.metadataFilterOptions.focalLengths.map(\.value)
                == [.wide, .shortTelephoto, .telephoto])

        // Filter by camera AND focal length.
        model.toggleCameraFilter("ILCE-1M2")
        #expect(model.photos.map(\.id.stem) == ["p1", "p2"])
        #expect(model.hasActiveFilter)

        model.toggleFocalLengthFilter(.shortTelephoto)
        #expect(model.photos.map(\.id.stem) == ["p1"])

        // Primary rating filter combines with AND and keeps metadataFilter active.
        model.setFilter(.ratedAtLeast(fourStars))
        #expect(model.photos.map(\.id.stem) == ["p1"])
        #expect(!model.metadataFilter.isEmpty)

        // Switching primary filter to rejected yields empty set while both filters remain active.
        model.setFilter(.rejected)
        #expect(model.photos.isEmpty)

        // Clearing metadata filters leaves primary filter (.rejected) intact.
        model.clearMetadataFilter()
        #expect(model.metadataFilter.isEmpty)
        #expect(model.photos.map(\.id.stem) == ["p3"])

        // Label filter combines with metadata filter via AND.
        model.setLabelFilter(.green)
        model.toggleKeywordFilter("portrait")
        #expect(model.photos.map(\.id.stem) == ["p1"])

        // Toggling the active keyword off clears just that dimension.
        model.toggleKeywordFilter("portrait")
        #expect(model.metadataFilter.keyword == nil)
        #expect(model.photos.map(\.id.stem) == ["p1"])

        // One-tap clearAllFilters clears primary, label, and metadata filters together.
        model.toggleCameraFilter("ILCE-7M4")
        #expect(model.photos.isEmpty)
        model.clearAllFilters()
        #expect(!model.hasActiveFilter)
        #expect(model.state.filter == .all)
        #expect(model.labelFilter == nil)
        #expect(model.metadataFilter.isEmpty)
        #expect(model.photos.map(\.id.stem) == ["p1", "p2", "p3", "p4"])
    }

    @Test func removingLastMatchingKeywordKeepsClearAccessible() async throws {
        let folder = TestLibrary.sampleFolderKey
        let p1 = makePhoto(
            folder: folder, stem: "p1", seconds: 1,
            marks: PhotoMarks(keywords: ["sunset", "beach"]))
        let p2 = makePhoto(
            folder: folder, stem: "p2", seconds: 2,
            marks: PhotoMarks(keywords: ["beach"]))
        let library = TestLibrary(photos: [p1, p2], groups: [])
        let model = BrowsingModel(library: library)
        model.openFolder()

        #expect(model.metadataFilterOptions.keywords.map(\.value) == ["beach", "sunset"])
        model.toggleKeywordFilter("sunset")
        #expect(model.photos.map(\.id.stem) == ["p1"])

        // Editing keywords removes "sunset" from the folder, dropping distinct keywords below 2.
        model.apply(MarkChange(keywords: ["beach"]), to: p1.id)
        await model.drainActions()

        #expect(model.metadataFilterOptions.keywords.isEmpty)
        #expect(model.metadataFilter.keyword == "sunset")
        #expect(model.photos.isEmpty)
        #expect(model.hasActiveFilter)

        model.clearMetadataFilter()
        #expect(model.photos.map(\.id.stem) == ["p1", "p2"])
    }

    @Test func scanExtractsCameraLensAndFocalLengthInSinglePass() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-filter-scan-\(UUID().uuidString)")
        let photosDir = root.appendingPathComponent("Shoot", isDirectory: true)
        let storeDir = root.appendingPathComponent("Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJPEG(
            to: photosDir.appendingPathComponent("IMG_0001.JPG"),
            tiff: ["Model": "ILCE-1M2"],
            exif: [
                "DateTimeOriginal": "2026:11:10 10:00:01",
                "LensModel": "FE 24-70mm F2.8 GM II",
                "FocalLength": 23.0,
                "FocalLenIn35mmFilm": 35,
            ])
        try writeJPEG(
            to: photosDir.appendingPathComponent("IMG_0002.JPG"),
            tiff: ["Model": "ILCE-7M4"],
            exif: [
                "DateTimeOriginal": "2026:11:10 10:00:02",
                "LensModel": "FE 70-200mm F2.8 GM OSS II",
                "FocalLength": 180.0,
            ])

        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(
                    fileURL: storeDir.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(
                store: CloveMarkStore(
                    directory: storeDir.appendingPathComponent("marks", isDirectory: true))),
            groups: SimilarGroupsCache(
                directory: storeDir.appendingPathComponent("groups", isDirectory: true)))
        let session = FolderLibrarySession(
            stores: Task { stores },
            caches: Task { nil })
        let model = BrowsingModel(library: session, similarGroupsEnabled: false)

        await model.openPickedFolder(photosDir)
        let deadline = ContinuousClock.now + .seconds(10)
        while model.isFolderOpening || model.allPlacedPhotos.count < 2 {
            if ContinuousClock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(model.allPlacedPhotos.count == 2)
        let first = try #require(model.allPlacedPhotos.first { $0.fileName == "IMG_0001.JPG" })
        let second = try #require(model.allPlacedPhotos.first { $0.fileName == "IMG_0002.JPG" })

        #expect(first.metadata.camera == "ILCE-1M2")
        #expect(first.metadata.lens == "FE 24-70mm F2.8 GM II")
        #expect(first.metadata.focalLengthMillimetres == 35.0)
        #expect(first.metadata.focalLengthBucket == .wide)

        #expect(second.metadata.camera == "ILCE-7M4")
        #expect(second.metadata.lens == "FE 70-200mm F2.8 GM OSS II")
        #expect(second.metadata.focalLengthMillimetres == 180.0)
        #expect(second.metadata.focalLengthBucket == .telephoto)

        #expect(model.metadataFilterOptions.cameras.map(\.value) == ["ILCE-1M2", "ILCE-7M4"])
        #expect(model.metadataFilterOptions.focalLengths.map(\.value) == [.wide, .telephoto])

        model.toggleFocalLengthFilter(.telephoto)
        #expect(model.photos.map(\.fileName) == ["IMG_0002.JPG"])

        // Leaving the folder clears secondary filters cleanly.
        model.back()
        await session.closeFolder()
        #expect(model.metadataFilter.isEmpty)
        #expect(model.metadataFilterOptions == .empty)
        #expect(model.sidebarCounts == .empty)
    }

    @Test func cachedOptionsAndCountsStayAccurateAcrossScanBatchesMetadataAndSortOrder()
        async throws
    {
        let library = StreamingMetadataFilterLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()

        #expect(model.metadataFilterOptions == .empty)
        #expect(model.sidebarCounts == .empty)

        // Pending-only batch keeps allPlacedPhotos, metadataFilterOptions, and sidebarCounts empty.
        let p1 = library.identity("p1", folderPath: "DCIM/100CAM")
        let p2 = library.identity("p2", folderPath: "DCIM/101CAM")
        let p3 = library.identity("p3", folderPath: "DCIM/101CAM")
        let pendingBatch = [
            GridPhoto(
                id: p1, fileName: "IMG_0001.ARW", time: .pending,
                marks: PhotoMarks(keywords: ["dawn"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 35mm F1.4 GM", focalLengthMillimetres: 35)),
            GridPhoto(id: p2, fileName: "IMG_0002.ARW", time: .pending),
        ]
        library.replacePhotos(pendingBatch, emit: .photos(pendingBatch))
        try await waitUntil { model.hasFolderContents }
        #expect(model.allPlacedPhotos.isEmpty)
        #expect(model.metadataFilterOptions == .empty)
        #expect(model.sidebarCounts == .empty)

        // Pending -> placed transition plus a new placed photo updates both caches accurately.
        let five = try #require(Rating(rawValue: 5))
        let placedBatch = [
            GridPhoto(
                id: p1, fileName: "IMG_0001.ARW",
                time: .known(
                    PhotoTime(captureTime: Date(timeIntervalSince1970: 10), hasUTCOffset: true)),
                marks: PhotoMarks(rating: five, keywords: ["dawn"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 35mm F1.4 GM", focalLengthMillimetres: 35)),
            GridPhoto(
                id: p2, fileName: "IMG_0002.ARW",
                time: .known(
                    PhotoTime(captureTime: Date(timeIntervalSince1970: 20), hasUTCOffset: true)),
                marks: PhotoMarks(),
                metadata: .empty),
            GridPhoto(
                id: p3, fileName: "IMG_0003.ARW",
                time: .known(
                    PhotoTime(captureTime: Date(timeIntervalSince1970: 30), hasUTCOffset: true)),
                marks: PhotoMarks(rating: .rejected, label: ColourLabel(colour: .red)),
                metadata: .empty),
        ]
        library.replacePhotos(placedBatch, emit: .photos(placedBatch))
        try await waitUntil { model.allPlacedPhotos.count == 3 }
        assertCachedStateMatchesPlacedPhotos(model)
        #expect(model.sidebarCounts.all == 3)
        #expect(model.sidebarCounts.unmarked == 1)
        #expect(model.sidebarCounts.rejected == 1)
        #expect(model.sidebarCounts.subfolders == ["DCIM/100CAM", "DCIM/101CAM"])
        #expect(
            model.metadataFilterOptions.keywords == [PhotoFilterOption(value: "dawn", count: 1)])
        #expect(model.metadataFilterOptions.cameras.isEmpty)

        // Metadata arriving on already-placed photos updates metadataFilterOptions without mutating sidebarCounts.
        let countsTracker = ObservationChangeFlag()
        withObservationTracking {
            _ = model.sidebarCounts
        } onChange: {
            countsTracker.markChanged()
        }
        var withMetadata = placedBatch
        withMetadata[1].metadata = PhotoFilterMetadata(
            camera: "ILCE-7M4", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85)
        withMetadata[2].metadata = PhotoFilterMetadata(
            camera: "ILCE-7M4", lens: "FE 200-600mm", focalLengthMillimetres: 400)
        library.replacePhotos(withMetadata, emit: .photos([]))
        library.emitScanFinished(total: 3)
        try await waitUntil {
            !model.isFolderOpening && model.metadataFilterOptions.cameras.count == 2
        }
        assertCachedStateMatchesPlacedPhotos(model)
        #expect(countsTracker.changeCount == 0)
        #expect(
            model.metadataFilterOptions.cameras == [
                PhotoFilterOption(value: "ILCE-1M2", count: 1),
                PhotoFilterOption(value: "ILCE-7M4", count: 2),
            ])
        #expect(
            model.metadataFilterOptions.lenses == [
                PhotoFilterOption(value: "FE 35mm F1.4 GM", count: 1),
                PhotoFilterOption(value: "FE 85mm F1.4 GM", count: 1),
                PhotoFilterOption(value: "FE 200-600mm", count: 1),
            ])
        #expect(
            model.metadataFilterOptions.focalLengths == [
                PhotoFilterOption(value: .wide, count: 1),
                PhotoFilterOption(value: .shortTelephoto, count: 1),
                PhotoFilterOption(value: .telephoto, count: 1),
            ])

        // Sort-order, filter, and navigation changes never mutate either cached property.
        let optionsTracker = ObservationChangeFlag()
        let orderCountsTracker = ObservationChangeFlag()
        withObservationTracking {
            _ = model.metadataFilterOptions
        } onChange: {
            optionsTracker.markChanged()
        }
        withObservationTracking {
            _ = model.sidebarCounts
        } onChange: {
            orderCountsTracker.markChanged()
        }
        model.setOrder(.fileName)
        model.setOrder(.captureTime)
        model.setFilter(.unmarked)
        model.setLabelFilter(.red)
        model.toggleCameraFilter("ILCE-7M4")
        model.clearAllFilters()
        model.openPhoto(p1)
        model.back()
        #expect(optionsTracker.changeCount == 0)
        #expect(orderCountsTracker.changeCount == 0)
        assertCachedStateMatchesPlacedPhotos(model)
    }

    @Test func nonKeywordMarksAndOrderNeverMutateMetadataOptionsWhileBatchKeywordsAndUndoDo()
        async throws
    {
        let folder = FolderIdentity(rawValue: "cached-marks-test")
        let three = try #require(Rating(rawValue: 3))
        let four = try #require(Rating(rawValue: 4))
        let p1 = makePhoto(
            folder: folder, stem: "p1", seconds: 1,
            marks: PhotoMarks(keywords: ["coast"]),
            metadata: PhotoFilterMetadata(
                camera: "ILCE-1M2", lens: "FE 35mm F1.4 GM", focalLengthMillimetres: 35))
        let p2 = makePhoto(
            folder: folder, stem: "p2", seconds: 2,
            metadata: PhotoFilterMetadata(
                camera: "ILCE-7M4", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85))
        let p3 = makePhoto(
            folder: folder, stem: "p3", seconds: 3,
            metadata: PhotoFilterMetadata(
                camera: "ILCE-7M4", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85))
        let group = BrowsingGroup(id: GroupID(rawValue: "burst"), members: [p1.id, p2.id, p3.id])
        let library = StreamingMetadataFilterLibrary(
            folder: folder, photos: [p1, p2, p3], groups: [group])
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.emitScanFinished(total: 3)
        try await waitUntil { !model.isFolderOpening }
        assertCachedStateMatchesPlacedPhotos(model)

        // Observe metadataFilterOptions across single mark edits, batch marks, group finishing,
        // rating undo, and sort-order changes. None of these may mutate metadataFilterOptions.
        let optionsTracker = ObservationChangeFlag()
        withObservationTracking {
            _ = model.metadataFilterOptions
        } onChange: {
            optionsTracker.markChanged()
        }

        model.apply(.rating(four), to: p1.id)
        #expect(model.sidebarCounts.ratings[four] == 1)
        #expect(model.sidebarCounts.unmarked == 2)

        model.apply(.label(ColourLabel(colour: .green)), to: p2.id)
        #expect(model.sidebarCounts.labels[.green] == 1)
        #expect(model.sidebarCounts.unmarked == 1)

        model.apply(.rating(.rejected), to: p3.id)
        #expect(model.sidebarCounts.rejected == 1)
        #expect(model.sidebarCounts.unmarked == 0)

        model.toggleSelection(p1.id)
        model.toggleSelection(p2.id)
        model.applyBatch(.rating(three), settings: AppSettings())
        #expect(model.sidebarCounts.ratings[three] == 2)
        model.clearSelection()

        // Group finishing rejects remaining unmarked photos without touching keywords.
        model.apply(.rating(.unrated), to: p3.id)
        model.openGroup(group.id, on: p1.id)
        let plan = GroupFinishingPlan(
            groupID: group.id, members: group.members, action: .rejectUnmarked,
            currentPhoto: p1.id,
            marks: Dictionary(uniqueKeysWithValues: model.groupPhotos.map { ($0.id, $0.marks) }))
        #expect(model.runGroupFinishing(plan) == 1)
        #expect(model.sidebarCounts.rejected == 1)
        model.undoLastMark()
        #expect(model.sidebarCounts.rejected == 0)
        model.back()

        model.setOrder(.fileName)
        model.setOrder(.captureTime)
        await model.drainActions()
        try await Task.sleep(for: .milliseconds(30))

        #expect(optionsTracker.changeCount == 0)
        assertCachedStateMatchesPlacedPhotos(model)

        // A batch keyword edit MUST mutate metadataFilterOptions and must NOT invalidate sidebarCounts.
        let countsTracker = ObservationChangeFlag()
        withObservationTracking {
            _ = model.sidebarCounts
        } onChange: {
            countsTracker.markChanged()
        }

        model.toggleSelection(p2.id)
        model.toggleSelection(p3.id)
        model.applyBatch(.addKeywords(["studio"]), settings: AppSettings())
        #expect(optionsTracker.changeCount == 1)
        #expect(
            model.metadataFilterOptions.keywords == [
                PhotoFilterOption(value: "studio", count: 2),
                PhotoFilterOption(value: "coast", count: 1),
            ])
        #expect(countsTracker.changeCount == 0)

        // Removing and undoing keywords updates metadataFilterOptions accurately.
        model.applyBatch(.removeKeywords(["studio"]), settings: AppSettings())
        #expect(
            model.metadataFilterOptions.keywords == [PhotoFilterOption(value: "coast", count: 1)])
        model.undoLastMark()
        await model.drainActions()
        #expect(
            model.metadataFilterOptions.keywords == [
                PhotoFilterOption(value: "studio", count: 2),
                PhotoFilterOption(value: "coast", count: 1),
            ])
        #expect(countsTracker.changeCount == 0)
        assertCachedStateMatchesPlacedPhotos(model)
    }

    @Test func locationLossMoveRejectsUndoAndCloseReopenKeepCachedOptionsAndCountsAccurate()
        async throws
    {
        // 1. Location-loss rollback drops optimistic rating and keyword edits cleanly.
        do {
            let folder = FolderIdentity(rawValue: "disconnect-cache-rollback")
            let initialPhotos = [
                makePhoto(
                    folder: folder, stem: "a", seconds: 1,
                    marks: PhotoMarks(keywords: ["coast"]),
                    metadata: PhotoFilterMetadata(camera: "CamA", lens: "LensA")),
                makePhoto(
                    folder: folder, stem: "b", seconds: 2,
                    metadata: PhotoFilterMetadata(camera: "CamB", lens: "LensB")),
            ]
            let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b"])
            library.photos = initialPhotos.map {
                GridPhoto(
                    id: library.identity($0.id.stem), fileName: $0.fileName, time: $0.time,
                    marks: $0.marks, metadata: $0.metadata)
            }
            let a = library.identity("a")
            let b = library.identity("b")
            let model = BrowsingModel(library: library)
            model.openFolder()
            assertCachedStateMatchesPlacedPhotos(model)

            // Held rating edit updates sidebarCounts without mutating metadataFilterOptions, then
            // disconnect rolls sidebarCounts back while still not mutating metadataFilterOptions.
            let optionsTracker = ObservationChangeFlag()
            withObservationTracking {
                _ = model.metadataFilterOptions
            } onChange: {
                optionsTracker.markChanged()
            }
            library.heldPhoto = a
            model.apply(.rating(.rejected), to: a)
            #expect(model.sidebarCounts.rejected == 1)
            #expect(model.sidebarCounts.unmarked == 1)
            #expect(optionsTracker.changeCount == 0)
            try await waitUntil { library.writing == a }
            library.reportDriveLoss()
            try await waitUntil { model.folderLocationLoss != nil }
            #expect(model.sidebarCounts.rejected == 0)
            #expect(model.sidebarCounts.unmarked == 2)
            #expect(optionsTracker.changeCount == 0)
            library.heldPhoto = nil
            await model.drainActions()

            // Reopen restores marking; test pending keyword rollback on disconnect.
            await model.reopenOpenFolder()
            #expect(model.canMark)
            library.heldPhoto = b
            model.apply(MarkChange(keywords: ["temporary"]), to: b)
            #expect(
                model.metadataFilterOptions.keywords == [
                    PhotoFilterOption(value: "coast", count: 1),
                    PhotoFilterOption(value: "temporary", count: 1),
                ])
            try await waitUntil { library.writing == b }
            library.reportDriveLoss()
            try await waitUntil { model.folderLocationLoss != nil }
            #expect(
                model.metadataFilterOptions.keywords == [
                    PhotoFilterOption(value: "coast", count: 1)
                ])
            assertCachedStateMatchesPlacedPhotos(model)
            library.heldPhoto = nil
            await model.drainActions()
        }

        // 2. Pre-populated init, Move Rejects + Undo Move Rejects, and folder close/reopen.
        let library = TestLibrary.sample(includeMetadataSamples: true)
        let model = BrowsingModel(library: library)
        assertCachedStateMatchesPlacedPhotos(model)
        model.openFolder()
        try await waitUntil { !model.isFolderOpening }
        assertCachedStateMatchesPlacedPhotos(model)

        let rejectedIDs = model.allPlacedPhotos.filter(\.marks.isRejected).map(\.id)
        let moved = try #require(rejectedIDs.last)
        let initialAllCount = model.sidebarCounts.all
        let initialRejectedCount = model.sidebarCounts.rejected
        #expect(initialRejectedCount == 2)

        // Add a unique keyword to the moved photo so Move Rejects and Undo Move Rejects visibly
        // alter both sidebarCounts and metadataFilterOptions.
        model.apply(MarkChange(keywords: ["DiscardTag"]), to: moved)
        await model.drainActions()
        #expect(model.metadataFilterOptions.keywords.contains { $0.value == "DiscardTag" })

        let plan = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(plan) { _ in }
        await model.drainActions()
        #expect(model.sidebarCounts.all == initialAllCount - initialRejectedCount)
        #expect(model.sidebarCounts.rejected == 0)
        #expect(!model.metadataFilterOptions.keywords.contains { $0.value == "DiscardTag" })
        assertCachedStateMatchesPlacedPhotos(model)

        let completed = try #require(model.lastRejectMove)
        model.undoRejectMove(completed)
        await model.drainActions()
        #expect(model.sidebarCounts.all == initialAllCount)
        #expect(model.sidebarCounts.rejected == initialRejectedCount)
        #expect(model.metadataFilterOptions.keywords.contains { $0.value == "DiscardTag" })
        assertCachedStateMatchesPlacedPhotos(model)

        // Leaving folder resets both caches to .empty; reopening restores them accurately.
        let recent = try #require(library.recents.first)
        model.back()
        try await waitUntil { !model.hasFolderContents }
        #expect(model.metadataFilterOptions == .empty)
        #expect(model.sidebarCounts == .empty)

        await model.reopen(recent)
        #expect(model.hasFolderContents)
        assertCachedStateMatchesPlacedPhotos(model)
    }

    @Test func closingAndReopeningUpdatedFolderRecomputesCachedOptionsAndCounts() async throws {
        let folder = FolderIdentity(rawValue: "reopen-updated-folder")
        let p1 = makePhoto(
            folder: folder, stem: "p1", seconds: 1,
            marks: PhotoMarks(keywords: ["dawn"]),
            metadata: PhotoFilterMetadata(camera: "CamA", lens: "LensA"))
        let p2 = makePhoto(
            folder: folder, stem: "p2", seconds: 2,
            marks: PhotoMarks(rating: .rejected),
            metadata: PhotoFilterMetadata(camera: "CamB", lens: "LensB"))
        let library = StreamingMetadataFilterLibrary(folder: folder, photos: [p1, p2])
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.emitScanFinished(total: 2)
        try await waitUntil { !model.isFolderOpening }
        assertCachedStateMatchesPlacedPhotos(model)
        #expect(model.sidebarCounts.rejected == 1)
        #expect(model.metadataFilterOptions.cameras.map(\.value) == ["CamA", "CamB"])

        // Leave folder: cached properties reset to empty once close completes.
        let recent = RecentFolder(
            id: UUID(), bookmark: Data(), pathSummary: "/Shoots/Test", lastOpened: Date())
        model.back()
        try await waitUntil { !model.hasFolderContents }
        #expect(model.metadataFilterOptions == .empty)
        #expect(model.sidebarCounts == .empty)

        // Reopen with updated disk marks and photos: caches reflect the reopened folder.
        let p3 = makePhoto(
            folder: folder, stem: "p3", seconds: 3,
            marks: PhotoMarks(label: ColourLabel(colour: .blue), keywords: ["harbour"]),
            metadata: PhotoFilterMetadata(camera: "CamC", lens: "LensC"))
        var updatedP1 = p1
        updatedP1.marks = PhotoMarks(
            rating: try #require(Rating(rawValue: 4)), keywords: ["harbour"])
        library.prepareForReopen(photos: [updatedP1, p3])
        await model.reopen(recent)
        library.emitScanFinished(total: 2)
        try await waitUntil { !model.isFolderOpening && model.allPlacedPhotos.count == 2 }
        assertCachedStateMatchesPlacedPhotos(model)
        #expect(model.sidebarCounts.rejected == 0)
        #expect(model.sidebarCounts.labels[.blue] == 1)
        #expect(model.metadataFilterOptions.cameras.map(\.value) == ["CamA", "CamC"])
        #expect(model.metadataFilterOptions.keywords.isEmpty)
    }

    @Test func filterMenuAndMetadataSheetRenderFromCachedCountsAndOptions() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.metadataSamplesVariable: "1",
        ])
        let model = BrowsingModel(library: library)
        model.openFolder()
        try await waitUntil { !model.isFolderOpening }

        struct HostView: View {
            let browsing: BrowsingModel
            var body: some View {
                VStack {
                    PhotoFilterButton(
                        browsing: browsing,
                        onMoreFilters: {})
                    MetadataFilterSheet(browsing: browsing)
                }
                .environment(\.cloveTheme, .light)
                .environment(\.appLanguage, .english)
            }
        }

        let host = UIHostingController(rootView: HostView(browsing: model))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 780)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        #expect(rendered.size.width > 0 && rendered.size.height > 0)
        assertCachedStateMatchesPlacedPhotos(model)
    }

    @MainActor
    @Test func testLibraryMetadataSamplesExposeAllFilterDimensions() {
        let library = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.metadataSamplesVariable: "1",
        ])
        let model = BrowsingModel(library: library)
        model.openFolder()

        let options = model.metadataFilterOptions
        #expect(options.hasAnyDimension)
        #expect(options.cameras.map(\.value) == ["ILCE-1M2", "ILCE-7M4"])
        #expect(
            options.lenses.map(\.value) == [
                "FE 24-70mm F2.8 GM II", "FE 35mm F1.4 GM", "FE 85mm F1.4 GM",
            ])
        #expect(options.focalLengths.map(\.value) == [.wide, .standard, .shortTelephoto])
        #expect(options.keywords.map(\.value) == ["Coast", "Portrait"])
    }

    @MainActor
    @Test func gridScreenAndDetailMarkingAllowMetadataFiltersInDuoExpandedCoverAndPadDetail() {
        // Ordinary phone Grid and Compact iPad Grid allow "More filters"; Regular iPad Grid uses sidebar.
        #expect(
            GridScreen.allowsMetadataFilters(
                isRegular: false, usesDock: false, route: .grid))
        #expect(
            !GridScreen.allowsMetadataFilters(
                isRegular: true, usesDock: false, route: .grid))
        // Expanded Duo Grid & Duo Cover Grid always allow "More filters" even when Expanded Duo is .regular.
        #expect(
            GridScreen.allowsMetadataFilters(
                isRegular: true, usesDock: true, route: .grid))
        #expect(
            GridScreen.allowsMetadataFilters(
                isRegular: false, usesDock: true, route: .grid))
        // GridScreen's own filterButton does not present when route is .detail (Detail owns its sheet).
        #expect(
            !GridScreen.allowsMetadataFilters(
                isRegular: false, usesDock: true, route: .detail))

        // DetailMarkingView allows "More filters" across Phone, iPad, Duo Cover, and Expanded Duo unless comparing.
        #expect(DetailMarkingView.allowsMetadataFilters(isComparing: false))
        #expect(!DetailMarkingView.allowsMetadataFilters(isComparing: true))
    }

    private func assertCachedStateMatchesPlacedPhotos(_ model: BrowsingModel) {
        #expect(
            model.metadataFilterOptions == PhotoMetadataFilterOptions(photos: model.allPlacedPhotos)
        )
        #expect(model.sidebarCounts == SidebarCounts(photos: model.allPlacedPhotos))
    }

    private func waitUntil(
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for condition", sourceLocation: sourceLocation)
        throw MetadataFilterTestTimeout()
    }

    private func makePhoto(
        folder: FolderIdentity,
        stem: String,
        seconds: TimeInterval,
        marks: PhotoMarks = PhotoMarks(),
        metadata: PhotoFilterMetadata = .empty
    ) -> GridPhoto {
        GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem),
            fileName: "\(stem).ARW",
            time: .known(
                PhotoTime(
                    captureTime: Date(timeIntervalSince1970: 1_760_000_000 + seconds),
                    hasUTCOffset: true)),
            marks: marks,
            metadata: metadata)
    }

    private func writeJPEG(
        to url: URL,
        tiff: [String: Any],
        exif: [String: Any]
    ) throws {
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImagePropertyExifDictionary: exif,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }
}

private struct MetadataFilterTestTimeout: Error {}

private final class ObservationChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func markChanged() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

@MainActor
private final class StreamingMetadataFilterLibrary: FolderLibrary {
    let folder: FolderIdentity
    var photos: [GridPhoto]
    var groups: [BrowsingGroup]
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation
    var openGeneration = 1

    init(
        folder: FolderIdentity = FolderIdentity(rawValue: "streaming-metadata-filter-test"),
        photos: [GridPhoto] = [],
        groups: [BrowsingGroup] = []
    ) {
        self.folder = folder
        self.photos = photos
        self.groups = groups
        (updates, continuation) = AsyncStream.makeStream()
    }

    func identity(_ stem: String, folderPath: String = "") -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: folderPath, stem: stem)
    }

    func replacePhotos(_ updated: [GridPhoto], emit update: FolderLibraryUpdate) {
        photos = updated
        continuation.yield(update)
    }

    func prepareForReopen(photos updated: [GridPhoto]) {
        photos = updated
    }

    func closeFolder() async {
        openGeneration += 1
    }

    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? {
        openGeneration += 1
        continuation.yield(.scanStarted)
        continuation.yield(.photos(photos))
        return nil
    }

    func emitScanFinished(total: Int) {
        continuation.yield(.scanFinished(FolderScanSummary(photoCount: total, status: .complete)))
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
