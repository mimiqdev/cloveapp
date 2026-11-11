import Foundation
import Testing

@testable import CloveCore

@Suite struct FolderProgressTests {
    @Test func countsEachDecidedPhotoOnce() {
        let summary = FolderProgress(
            confirmedMarks: [
                PhotoMarks(), PhotoMarks(rating: Rating(rawValue: 4)!),
                PhotoMarks(label: ColourLabel(colour: .green)),
                PhotoMarks(rating: Rating(rawValue: 3)!, isRejected: true),
            ], isComplete: true)
        #expect(summary.total == 4)
        #expect(summary.marked == 2)
        #expect(summary.rejected == 1)
        #expect(summary.left == 1)
        #expect(!summary.finished)
    }

    @Test func doneRequiresCompleteNonemptyScan() {
        #expect(FolderProgress(marked: 2, rejected: 1, total: 3).finished)
        #expect(!FolderProgress(marked: 2, rejected: 1, total: 3, isComplete: false).finished)
        #expect(!FolderProgress(marked: 0, rejected: 0, total: 0).finished)
        let bounded = FolderProgress(marked: 20, rejected: 4, total: 3)
        #expect(bounded.left == 0)
        #expect(bounded.marked == 0)
        #expect(bounded.rejected == 3)
    }

    @Test func incompleteRescanKeepsTotalsAndAppliesConfirmedRejectClears() {
        let folder = FolderIdentity(rawValue: "progress-folder")
        let oldPhoto = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "IMG_001")
        let viewed = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "IMG_002")
        let previous = FolderProgress(
            marked: 90, rejected: 10, total: 100, lastViewedPhoto: oldPhoto,
            previewPhotos: [oldPhoto])
        let cleared = Dictionary(
            uniqueKeysWithValues: (0..<10).map { index in
                (
                    PhotoIdentity(
                        folderID: folder, relativeFolderPath: "", stem: "REJECT_\(index)"),
                    FolderProgress.ConfirmedChange(
                        before: PhotoMarks(isRejected: true), after: PhotoMarks())
                )
            })
        let partial = FolderProgress.snapshot(
            confirmedMarks: Array(repeating: PhotoMarks(), count: 20), scanIsComplete: false,
            previous: previous, lastViewedPhoto: viewed, previewPhotos: [viewed],
            confirmedChanges: cleared)
        #expect(partial.marked == 90)
        #expect(partial.rejected == 0)
        #expect(partial.total == 100)
        #expect(partial.left == 10)
        #expect(!partial.finished)
        #expect(partial.lastViewedPhoto == viewed)
        #expect(partial.previewPhotos == [oldPhoto])
    }

    @Test func partialScanPreservesDoneOnlyWhenNothingBecameUnmarked() throws {
        let folder = FolderIdentity(rawValue: "progress-folder")
        let photo = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "IMG_001")
        let previous = FolderProgress(marked: 0, rejected: 1, total: 1)
        let unchanged = FolderProgress.snapshot(
            confirmedMarks: [], scanIsComplete: false, previous: previous,
            lastViewedPhoto: photo, previewPhotos: [])
        #expect(unchanged.finished)
        let clear = FolderProgress.ConfirmedChange(
            before: PhotoMarks(isRejected: true), after: PhotoMarks())
        let restored = clear.updating(to: PhotoMarks(isRejected: true))
        let partial = FolderProgress.snapshot(
            confirmedMarks: [], scanIsComplete: false, previous: previous,
            lastViewedPhoto: photo, previewPhotos: [], confirmedChanges: [photo: restored])
        #expect(partial.total == 1)
        #expect(partial.rejected == 1)
        #expect(partial.left == 0)
        #expect(!partial.finished)
        let decoded = try JSONDecoder().decode(
            FolderProgress.self, from: JSONEncoder().encode(partial))
        #expect(!decoded.finished)
        let old = #"{"marked":1,"rejected":0,"total":1,"isComplete":true,"previewPhotos":[]}"#
        #expect(try JSONDecoder().decode(FolderProgress.self, from: Data(old.utf8)).finished)
    }

    @Test func partialChangesUseOneOriginalBaselineAcrossRepeatedFlushes() {
        let photo = PhotoIdentity(
            folderID: FolderIdentity(rawValue: "progress-folder"), relativeFolderPath: "",
            stem: "IMG_001")
        let baseline = FolderProgress(marked: 0, rejected: 1, total: 2)
        let change = FolderProgress.ConfirmedChange(
            before: PhotoMarks(isRejected: true), after: PhotoMarks()
        )
        .updating(to: PhotoMarks(rating: Rating(rawValue: 4)!))
        for _ in 0..<3 {
            let result = FolderProgress.snapshot(
                confirmedMarks: [], scanIsComplete: false, previous: baseline,
                lastViewedPhoto: photo, previewPhotos: [], confirmedChanges: [photo: change])
            #expect(result.marked == 1)
            #expect(result.rejected == 0)
            #expect(result.total == 2)
            #expect(result.left == 1)
        }
        let notDoneBefore = FolderProgress(marked: 0, rejected: 0, total: 1)
        let decided = FolderProgress.ConfirmedChange(
            before: PhotoMarks(), after: PhotoMarks(isRejected: true))
        let partial = FolderProgress.snapshot(
            confirmedMarks: [], scanIsComplete: false, previous: notDoneBefore,
            lastViewedPhoto: photo, previewPhotos: [], confirmedChanges: [photo: decided])
        #expect(partial.left == 0)
        #expect(!partial.finished)
    }

    @Test func unreadMarksNeverCreateLeftCountsBeforeFirstCompleteScan() {
        let unknown = FolderProgress.snapshot(
            confirmedMarks: Array(repeating: PhotoMarks(), count: 50), scanIsComplete: false,
            previous: nil, lastViewedPhoto: nil, previewPhotos: [])
        #expect(unknown.total == 0)
        #expect(unknown.left == 0)
        #expect(!unknown.finished)
        let complete = FolderProgress.snapshot(
            confirmedMarks: [PhotoMarks(), PhotoMarks(isRejected: true)], scanIsComplete: true,
            previous: unknown, lastViewedPhoto: nil, previewPhotos: [])
        #expect(complete.total == 2)
        #expect(complete.rejected == 1)
        #expect(complete.left == 1)
    }

    @Test func confirmedProgressSurvivesCloseAndReopen() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Shoots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))
        let access = FolderAccess(store: store)
        let opened = try #require(await access.pick(folder).openedFolder)
        let set = try makeScannedSet(folder: opened.recent.identity, root: folder, stem: "IMG_001")
        let queue = MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks"))
        let status = await queue.apply(.rating(Rating(rawValue: 4)!), to: set)
        #expect(status.state.isConfirmed)
        let photo = set.id
        let partial = FolderProgress(
            confirmedMarks: [PhotoMarks().including(status.requested)], isComplete: false,
            lastViewedPhoto: photo, previewPhotos: [photo])
        try await access.recordProgress(partial, for: opened.recent.identity)
        await queue.drain()
        await opened.session.end()
        let reopened = try #require(await access.reopen(opened.recent.id).openedFolder)
        #expect(reopened.recent.progress?.lastViewedPhoto == photo)
        #expect(reopened.recent.progress?.marked == 1)
        #expect(reopened.recent.progress?.finished == false)
        #expect(reopened.recent.lastOpened >= opened.recent.lastOpened)
        await reopened.session.end()
    }

    @Test func oldRecentJSONStillLoadsWithoutProgress() throws {
        let json =
            #"{"id":"10000000-0000-0000-0000-000000000001","bookmark":"","pathSummary":"/Shoots/2026","identityKeys":{},"mediaType":"unknown","photoCount":12,"scanStatus":"complete","lastOpened":0}"#
        let recent = try JSONDecoder().decode(RecentFolder.self, from: Data(json.utf8))
        #expect(recent.photoCount == 12)
        #expect(recent.progress == nil)
        #expect(recent.needsReconnect == nil)
        let photo = PhotoIdentity(
            folderID: recent.identity, relativeFolderPath: "Shoots", stem: "IMG_001")
        var updated = recent
        updated.progress = FolderProgress(marked: 5, rejected: 2, total: 12, lastViewedPhoto: photo)
        let restored = try JSONDecoder().decode(
            RecentFolder.self, from: JSONEncoder().encode(updated))
        #expect(restored.progress?.lastViewedPhoto == photo)
        #expect(restored.progress?.left == 5)
    }
}
