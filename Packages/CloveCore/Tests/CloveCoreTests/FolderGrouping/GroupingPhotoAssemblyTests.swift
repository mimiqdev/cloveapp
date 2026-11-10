import Foundation
import Testing

import CloveCore

/// How a folder's scan and I4's values reach grouping (PRD P0-11, G1's Grouping row).
@Suite("Grouping photo assembly")
struct GroupingPhotoAssemblyTests {
    @Test func carriesIdentityFileNameTimeAndCameraBody() throws {
        var photos = FolderPhotos()
        photos.insert([try folderGroupingItem("MMQ05184")])
        let id = folderGroupingID("MMQ05184")
        photos.setTime(groupingCapture(0), for: id)
        photos.setCameraBody(CameraBody(model: "ILCE-1M2"), for: id)

        let photo = try #require(photos.groupingPhotos.first)
        #expect(photo.id == id)
        #expect(photo.fileName == "MMQ05184.ARW")
        #expect(photo.time == groupingCapture(0))
        // CameraBody folds the model's case, so the key ignores the file's spelling (G1).
        #expect(photo.body?.model == "ilce-1m2")
        #expect(photo.body?.serial == nil)
        #expect(photo.isEligibleForGrouping)
    }

    @Test func keepsABodySerialWhenTheFileCarriesOne() throws {
        var photos = FolderPhotos()
        photos.insert([try folderGroupingItem("MMQ05185")])
        let id = folderGroupingID("MMQ05185")
        photos.setTime(groupingCapture(0.4), for: id)
        photos.setCameraBody(
            CameraBody(model: "ILCE-1M2", serial: " 0123456 "), for: id)

        let photo = try #require(photos.groupingPhotos.first)
        // A serial separates two bodies of the same model, trimmed as G1 reads it.
        #expect(photo.body?.serial == "0123456")
        #expect(photo.isEligibleForGrouping)
    }

    @Test func aFallbackTimeIsNeverGrouped() throws {
        var photos = FolderPhotos()
        photos.insert([try folderGroupingItem("MMQ05186")])
        let id = folderGroupingID("MMQ05186")
        let fallback = PhotoTimeState.known(PhotoTime(fileCreation: groupingSeconds(0)))
        photos.setTime(fallback, for: id)
        photos.setCameraBody(CameraBody(model: "ILCE-1M2"), for: id)

        let photo = try #require(photos.groupingPhotos.first)
        // G1 decision 3: a file time can drift from the real shot time, so it only sorts.
        #expect(photo.time == fallback)
        #expect(!photo.isEligibleForGrouping)
    }

    @Test func aPhotoWithoutAModelIsNeverGrouped() throws {
        var photos = FolderPhotos()
        photos.insert([try folderGroupingItem("MMQ05187")])
        let id = folderGroupingID("MMQ05187")
        photos.setTime(groupingCapture(0.8), for: id)

        let photo = try #require(photos.groupingPhotos.first)
        // G1's Grouping row: grouping never guesses a body, so a model-less photo stays out.
        #expect(photo.body == nil)
        #expect(!photo.isEligibleForGrouping)
    }

    @Test func dropsTheBodyOfAPhotoThatLeftTheFolder() throws {
        var photos = FolderPhotos()
        photos.insert([try folderGroupingItem("MMQ05188")])
        let id = folderGroupingID("MMQ05188")
        photos.setTime(groupingCapture(0), for: id)
        photos.setCameraBody(CameraBody(model: "ILCE-1M2"), for: id)

        photos.remove([id])

        #expect(photos.groupingPhotos.isEmpty)
    }
}
