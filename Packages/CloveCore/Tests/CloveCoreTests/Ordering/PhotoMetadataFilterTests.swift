import Foundation
import Testing

import CloveCore

@Suite("Photo metadata and keyword filters")
struct PhotoMetadataFilterTests {
    @Test(arguments: [
        (0.1, FocalLengthBucket.ultraWide),
        (14.0, .ultraWide),
        (23.0, .ultraWide),
        (23.9, .ultraWide),
        (24.0, .wide),
        (28.0, .wide),
        (35.0, .wide),
        (35.5, .wide),
        (36.0, .standard),
        (50.0, .standard),
        (70.0, .standard),
        (70.5, .standard),
        (71.0, .shortTelephoto),
        (85.0, .shortTelephoto),
        (135.0, .shortTelephoto),
        (135.1, .telephoto),
        (136.0, .telephoto),
        (400.0, .telephoto),
    ])
    func focalLengthBucketBoundaries(millimetres: Double, expected: FocalLengthBucket) {
        #expect(FocalLengthBucket(millimetres: millimetres) == expected)
    }

    @Test(arguments: [-50.0, 0.0, Double.nan, Double.infinity, -Double.infinity])
    func nonPositiveOrNonFiniteFocalLengthHasNoBucket(millimetres: Double) {
        #expect(FocalLengthBucket(millimetres: millimetres) == nil)
        #expect(PhotoFilterMetadata(focalLengthMillimetres: millimetres).focalLengthBucket == nil)
    }

    @Test func filterMetadataNormalizesWhitespaceAndInvalidNumbers() {
        let metadata = PhotoFilterMetadata(
            camera: "  ILCE-1M2 \n", lens: "   ", focalLengthMillimetres: 0)
        #expect(metadata.camera == "ILCE-1M2")
        #expect(metadata.lens == nil)
        #expect(metadata.focalLengthMillimetres == nil)
        #expect(metadata.focalLengthBucket == nil)
    }

    @Test func secondaryFilterCombinesDimensionsWithAndSemantics() {
        let portrait = makePhoto(
            "a", seconds: 1,
            marks: PhotoMarks(rating: stars(4), keywords: ["portrait", "outdoor"]),
            metadata: PhotoFilterMetadata(
                camera: "ILCE-1M2", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85))
        let wide = makePhoto(
            "b", seconds: 2,
            marks: PhotoMarks(rating: stars(4), keywords: ["outdoor"]),
            metadata: PhotoFilterMetadata(
                camera: "ILCE-1M2", lens: "FE 24mm F1.4 GM", focalLengthMillimetres: 24))
        let missingFocal = makePhoto(
            "c", seconds: 3,
            marks: PhotoMarks(keywords: ["portrait"]),
            metadata: PhotoFilterMetadata(
                camera: "ILCE-1M2", lens: nil, focalLengthMillimetres: nil)
        )

        #expect(PhotoMetadataFilter.none.isEmpty)
        #expect(PhotoMetadataFilter.none.activeCount == 0)
        #expect(PhotoMetadataFilter.none.matches(missingFocal))

        let combined = PhotoMetadataFilter(
            camera: "ILCE-1M2", lens: "FE 85mm F1.4 GM", focalLength: .shortTelephoto,
            keyword: "portrait")
        #expect(!combined.isEmpty)
        #expect(combined.activeCount == 4)
        #expect(combined.matches(portrait))
        #expect(!combined.matches(wide))
        #expect(!combined.matches(missingFocal))

        // Photos lacking focal-length metadata never match a specific focal-length bucket.
        let bucketOnly = PhotoMetadataFilter(focalLength: .shortTelephoto)
        #expect(bucketOnly.matches(portrait))
        #expect(!bucketOnly.matches(missingFocal))
    }

    @Test func orderingCombinesPrimaryAndMetadataFiltersWithoutChangingOrder() {
        let photos = [
            makePhoto(
                "p3", seconds: 3, fileName: "IMG_0001.ARW",
                marks: PhotoMarks(rating: stars(5), keywords: ["street"]),
                metadata: PhotoFilterMetadata(
                    camera: "Body A", lens: "Lens 35", focalLengthMillimetres: 35)),
            makePhoto(
                "p1", seconds: 1, fileName: "IMG_0003.ARW",
                marks: PhotoMarks(rating: stars(4), keywords: ["street"]),
                metadata: PhotoFilterMetadata(
                    camera: "Body A", lens: "Lens 35", focalLengthMillimetres: 35)),
            makePhoto(
                "p2", seconds: 2, fileName: "IMG_0002.ARW",
                marks: PhotoMarks(rating: .rejected, keywords: ["street"]),
                metadata: PhotoFilterMetadata(
                    camera: "Body A", lens: "Lens 35", focalLengthMillimetres: 35)),
            makePhoto(
                "p4", seconds: 4, fileName: "IMG_0004.ARW",
                marks: PhotoMarks(rating: stars(5), keywords: ["studio"]),
                metadata: PhotoFilterMetadata(
                    camera: "Body B", lens: "Lens 85", focalLengthMillimetres: 85)),
        ]
        let ordering = PhotoOrdering(photos: photos)
        let streetWide = PhotoMetadataFilter(
            camera: "Body A", focalLength: .wide, keyword: "street")

        // Primary rating filter + metadata filter AND together, preserving capture-time order.
        #expect(
            ordering.photos(
                order: .captureTime, matching: .ratedAtLeast(stars(4)), metadataFilter: streetWide
            ).map(\.id.stem) == ["p1", "p3"])

        // Filename order also preserved under the same filter combination.
        #expect(
            ordering.photos(
                order: .fileName, matching: .ratedAtLeast(stars(4)), metadataFilter: streetWide
            ).map(\.id.stem) == ["p3", "p1"])

        // Rejected primary filter + metadata filter selects only the rejected match.
        #expect(
            ordering.photos(matching: .rejected, metadataFilter: streetWide).map(\.id.stem)
                == ["p2"])

        // Disjoint criteria return an empty result cleanly.
        let impossible = PhotoMetadataFilter(camera: "Body B", keyword: "street")
        #expect(ordering.photos(matching: .all, metadataFilter: impossible).isEmpty)
    }

    @Test func optionsAutoHideDimensionsWithFewerThanTwoDistinctValues() {
        // Single-body, single-prime shoot where every photo shares one keyword: all 4 dimensions auto-hide.
        let homogeneous = [
            makePhoto(
                "a", seconds: 1,
                marks: PhotoMarks(keywords: ["wedding"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
            makePhoto(
                "b", seconds: 2,
                marks: PhotoMarks(keywords: ["wedding"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
            makePhoto("c", seconds: 3, marks: PhotoMarks(keywords: ["wedding"])),
        ]
        let hidden = PhotoMetadataFilterOptions(photos: homogeneous)
        #expect(hidden.cameras.isEmpty)
        #expect(hidden.lenses.isEmpty)
        #expect(hidden.focalLengths.isEmpty)
        #expect(hidden.keywords.isEmpty)
        #expect(!hidden.hasAnyDimension)

        // Single-body, single-prime shoot with zero keywords also hides all 4 dimensions.
        let untagged = [
            makePhoto(
                "a", seconds: 1,
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
            makePhoto("b", seconds: 2),
        ]
        let hiddenUntagged = PhotoMetadataFilterOptions(photos: untagged)
        #expect(!hiddenUntagged.hasAnyDimension)
        #expect(hiddenUntagged.keywords.isEmpty)

        // A single keyword on a strict subset of photos narrows the folder and stays visible,
        // while single-value EXIF dimensions stay hidden.
        let singleKeywordSubset = [
            makePhoto(
                "a", seconds: 1,
                marks: PhotoMarks(keywords: ["Client"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
            makePhoto(
                "b", seconds: 2,
                marks: PhotoMarks(keywords: ["Client"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
            makePhoto(
                "c", seconds: 3,
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
        ]
        let subsetOptions = PhotoMetadataFilterOptions(photos: singleKeywordSubset)
        #expect(subsetOptions.cameras.isEmpty)
        #expect(subsetOptions.lenses.isEmpty)
        #expect(subsetOptions.focalLengths.isEmpty)
        #expect(subsetOptions.keywords == [PhotoFilterOption(value: "Client", count: 2)])
        #expect(subsetOptions.hasAnyDimension)

        // Two distinct values reveal only those dimensions, with exact counts and deterministic order.
        let mixed = [
            makePhoto(
                "a", seconds: 1,
                marks: PhotoMarks(keywords: ["candid", "bride"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-7M4", lens: "FE 85mm F1.4 GM", focalLengthMillimetres: 85)),
            makePhoto(
                "b", seconds: 2,
                marks: PhotoMarks(keywords: ["candid"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 24-70mm F2.8 GM II", focalLengthMillimetres: 24)),
            makePhoto(
                "c", seconds: 3,
                marks: PhotoMarks(keywords: ["candid", "ceremony"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 24-70mm F2.8 GM II", focalLengthMillimetres: 200)
            ),
        ]
        let visible = PhotoMetadataFilterOptions(photos: mixed)
        #expect(visible.hasAnyDimension)
        #expect(
            visible.cameras == [
                PhotoFilterOption(value: "ILCE-1M2", count: 2),
                PhotoFilterOption(value: "ILCE-7M4", count: 1),
            ])
        #expect(
            visible.lenses == [
                PhotoFilterOption(value: "FE 24-70mm F2.8 GM II", count: 2),
                PhotoFilterOption(value: "FE 85mm F1.4 GM", count: 1),
            ])
        // Focal-length buckets stay in widest-to-longest photographer order.
        #expect(
            visible.focalLengths == [
                PhotoFilterOption(value: .wide, count: 1),
                PhotoFilterOption(value: .shortTelephoto, count: 1),
                PhotoFilterOption(value: .telephoto, count: 1),
            ])
        // Keywords sort by frequency descending, then localized alphabetical order.
        #expect(
            visible.keywords == [
                PhotoFilterOption(value: "candid", count: 3),
                PhotoFilterOption(value: "bride", count: 1),
                PhotoFilterOption(value: "ceremony", count: 1),
            ])
    }

    @Test func optionsDeduplicateMultiAndSingleKeywordPhotosEqually() {
        var manualDuplicate = makePhoto("a", seconds: 1)
        manualDuplicate.marks.keywords = ["solo", "solo", ""]
        var singleEmpty = makePhoto("b", seconds: 2)
        singleEmpty.marks.keywords = [""]
        let singleValid = makePhoto("c", seconds: 3, marks: PhotoMarks(keywords: ["dawn"]))
        let multiValid = makePhoto("d", seconds: 4, marks: PhotoMarks(keywords: ["dawn", "coast"]))

        let options = PhotoMetadataFilterOptions(photos: [
            manualDuplicate, singleEmpty, singleValid, multiValid,
        ])
        #expect(
            options.keywords == [
                PhotoFilterOption(value: "dawn", count: 2),
                PhotoFilterOption(value: "coast", count: 1),
                PhotoFilterOption(value: "solo", count: 1),
            ])
    }

    private func makePhoto(
        _ stem: String,
        seconds: TimeInterval,
        fileName: String? = nil,
        marks: PhotoMarks = PhotoMarks(),
        metadata: PhotoFilterMetadata = .empty
    ) -> GridPhoto {
        let id = PhotoIdentity(
            folderID: FolderIdentity(rawValue: "metadata-filter-tests"),
            relativeFolderPath: "",
            stem: stem)
        return GridPhoto(
            id: id,
            fileName: fileName ?? "\(stem).ARW",
            time: .known(
                PhotoTime(
                    captureTime: Date(timeIntervalSince1970: 1_760_000_000 + seconds),
                    hasUTCOffset: true)),
            marks: marks,
            metadata: metadata)
    }

    private func stars(_ count: Int) -> Rating {
        Rating(rawValue: count) ?? .unrated
    }
}
