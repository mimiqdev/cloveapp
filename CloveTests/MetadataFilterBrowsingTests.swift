import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Testing

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
