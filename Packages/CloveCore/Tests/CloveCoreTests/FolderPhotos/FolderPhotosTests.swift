import Foundation
import Testing

@testable import CloveCore

/// The photos one open folder holds, as the scan, metadata reads and writes update them
/// (PRD P0-01, P0-03, P0-05, P0-08).
@Suite("Folder photos")
struct FolderPhotosTests {
    /// The opened folder every test photo belongs to.
    private let folder = FolderIdentity(rawValue: "folder-photos-tests")

    /// One scan item for a RAW set, with no sidecar unless the test names one.
    private func rawItem(
        _ stem: String,
        path: String = "DCIM/100CAM",
        sidecar: SidecarState = .absent
    ) throws -> ScanItem {
        let rawURL = URL(fileURLWithPath: "/photos/\(path)/\(stem).ARW")
        let set = try PhotoSet(
            folderID: folder, relativeFolderPath: path, rawURL: rawURL,
            sidecarURL: sidecar.resolvedURL)
        let file = try #require(PhotoFile(url: rawURL))
        return .photo(
            ScannedPhotoSet(
                photoSet: set, sidecar: sidecar,
                imageFiles: [
                    ScannedImageFile(file: file, size: 32, modificationDate: nil)
                ]))
    }

    /// One scan item for a standalone JPEG, which keeps its marks in Clove (G1 decision 6).
    private func jpegItem(_ stem: String) throws -> ScanItem {
        let url = URL(fileURLWithPath: "/photos/DCIM/100CAM/\(stem).JPG")
        let set = try PhotoSet(
            folderID: folder, relativeFolderPath: "DCIM/100CAM", jpegURL: url)
        let file = try #require(PhotoFile(url: url))
        return .photo(
            ScannedPhotoSet(
                photoSet: set, sidecar: .absent,
                imageFiles: [ScannedImageFile(file: file, size: 8, modificationDate: nil)]))
    }

    /// The stem's identity, built the way the scan builds it.
    private func identity(_ stem: String, path: String = "DCIM/100CAM") -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: path, stem: stem)
    }

    @Test func scannedPhotosEnterPendingWithStoredMarks() throws {
        var photos = FolderPhotos()
        let added = photos.insert(
            [try rawItem("MMQ05184"), try jpegItem("IMG_0001")],
            storedMarks: [identity("IMG_0001"): CloveStoredMarks(rating: .rejected)])

        #expect(added.map(\.id) == [identity("MMQ05184"), identity("IMG_0001")])
        #expect(photos.count == 2)
        #expect(photos.photos.allSatisfy { $0.time.isPending })
        #expect(photos.photo(for: identity("MMQ05184"))?.marks == PhotoMarks())
        // G1 decision 5: Reject arrives from Clove's storage, not from the scan.
        #expect(photos.photo(for: identity("IMG_0001"))?.marks.isRejected == true)
        #expect(photos.photo(for: identity("IMG_0001"))?.fileName == "IMG_0001.JPG")
    }

    @Test func ambiguousStemsEnterNoPhoto() throws {
        var photos = FolderPhotos()
        let ambiguous = ScanItem.ambiguousStem(
            AmbiguousStem(
                relativeFolderPath: "DCIM/100CAM", stem: "MMQ05185",
                imageFiles: [], sidecar: .absent))
        #expect(photos.insert([ambiguous]).isEmpty)
        #expect(photos.isEmpty)
    }

    @Test func aReadTimePlacesAPhotoWithoutMovingTheOthers() throws {
        var photos = FolderPhotos()
        photos.insert([try rawItem("MMQ05184"), try rawItem("MMQ05185")])
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        photos.setTime(
            .known(PhotoTime(captureTime: instant, hasUTCOffset: true)), for: identity("MMQ05185"))

        #expect(photos.photo(for: identity("MMQ05184"))?.time.isPending == true)
        #expect(photos.photo(for: identity("MMQ05185"))?.time.time?.instant == instant)
        // Insertion order is kept: C8 decides the grid order, not this value.
        #expect(photos.photos.map(\.id) == [identity("MMQ05184"), identity("MMQ05185")])
    }

    @Test func aRepeatedIdentityKeepsItsTimeAndMarks() throws {
        var photos = FolderPhotos()
        photos.insert([try rawItem("MMQ05184")])
        photos.setTime(.unavailable, for: identity("MMQ05184"))
        photos.setMarks(
            PhotoMarks(rating: Rating(rawValue: 4) ?? .unrated), for: identity("MMQ05184"))

        #expect(photos.insert([try rawItem("MMQ05184")]).isEmpty)
        #expect(photos.count == 1)
        #expect(photos.photo(for: identity("MMQ05184"))?.time == .unavailable)
        #expect(photos.photo(for: identity("MMQ05184"))?.marks.rating.rawValue == 4)
    }

    @Test func aConfirmedChangeReplacesOnlyTheNamedFields() throws {
        var photos = FolderPhotos()
        photos.insert([try rawItem("MMQ05184")])
        let id = identity("MMQ05184")
        photos.setMarks(
            PhotoMarks(rating: Rating(rawValue: 2) ?? .unrated, label: ColourLabel(colour: .green)),
            for: id)

        // Reject replaces the rating and keeps the label (PRD P0-05).
        photos.apply(MarkChange(rating: .rejected), to: id)
        #expect(photos.photo(for: id)?.marks.rating == .rejected)
        #expect(photos.photo(for: id)?.marks.label.colour == .green)
        #expect(photos.photo(for: id)?.marks.isRejected == true)

        photos.apply(MarkChange.rating(Rating(rawValue: 5) ?? .unrated), to: id)
        #expect(photos.photo(for: id)?.marks.rating.rawValue == 5)
        #expect(photos.photo(for: id)?.marks.isRejected == false)

        photos.apply(MarkChange.label(.clear), to: id)
        #expect(photos.photo(for: id)?.marks.label.isClear == true)
        #expect(photos.photo(for: id)?.marks.rating.rawValue == 5)
    }

    @Test func theScannedSetLookupAnswersWritesAndThumbnails() throws {
        var photos = FolderPhotos()
        photos.insert([try rawItem("MMQ05184"), try jpegItem("IMG_0001")])

        let set = try #require(photos.scannedSet(for: identity("IMG_0001")))
        #expect(set.photoSet.primary.url.lastPathComponent == "IMG_0001.JPG")
        #expect(photos.scannedSet(for: identity("missing")) == nil)
    }

    @Test func removingPhotosDropsTheirSets() throws {
        var photos = FolderPhotos()
        photos.insert([try rawItem("MMQ05184"), try rawItem("MMQ05185")])

        photos.remove([identity("MMQ05184")])
        #expect(photos.photos.map(\.id) == [identity("MMQ05185")])
        #expect(photos.scannedSet(for: identity("MMQ05184")) == nil)

        photos.remove([identity("MMQ05185")])
        #expect(photos.isEmpty)
    }
}
