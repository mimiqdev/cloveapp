import Foundation
import Testing

@testable import CloveCore

private let admissionGreen = ColourLabel(colour: .green)
private let admissionOne = Rating(rawValue: 1) ?? .unrated
private let admissionThree = Rating(rawValue: 3) ?? .unrated
private let admissionFour = Rating(rawValue: 4) ?? .unrated

/// A queue whose Clove storage lives inside the test folder.
private func makeAdmissionQueue(
    _ folder: WriteTestFolder, _ double: WriteFileSystemDouble
) -> MarkWriteQueue {
    MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
}

/// Holds one sidecar replace until the test releases it, so more requests arrive while it runs.
private func holdReplace(
    _ double: WriteFileSystemDouble, at sidecar: URL, count: Int,
    reached: DispatchSemaphore, release: DispatchSemaphore
) {
    double.beforeOperation = { record in
        guard record.step == .replace, record.url == sidecar, record.count == count else { return }
        reached.signal()
        _ = release.wait(timeout: .now() + 10)
    }
}

/// What C4 says a change replaces, read atomically with its admission (PRD P0-05's Undo row).
///
/// These run against the real queue and a file seam that can hold or fail one write, so the
/// "before" marks are checked with several writers for one photo in flight at once.
@Suite struct MarkWriteQueueAdmissionTests {
    @Test func aRatingALabelAndAnotherRatingInFlightFoldInOrder() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let set = try makeScannedSet(
            folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
        let sidecar = folder.file("MMQ05184.xmp")
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        holdReplace(double, at: sidecar, count: 1, reached: reached, release: release)
        let queue = makeAdmissionQueue(folder, double)

        // ★3's write is held, so the label and ★4 are admitted while it runs.
        let first = await queue.admit(.rating(admissionThree), to: set, confirmed: PhotoMarks())
        #expect(waitForTestSignal(reached))
        let second = await queue.admit(.label(admissionGreen), to: set, confirmed: PhotoMarks())
        let third = await queue.admit(.rating(admissionFour), to: set, confirmed: PhotoMarks())

        #expect(first.marksBefore == PhotoMarks())
        #expect(second.marksBefore.rating == admissionThree)
        #expect(third.marksBefore.rating == admissionThree)
        #expect(third.marksBefore.label == admissionGreen)

        release.signal()
        _ = await queue.waitFor(third)
        #expect(
            try XMPCodec().read(try Data(contentsOf: sidecar))
                == XMPMarks(rating: .rated(admissionFour), label: admissionGreen))
    }

    @Test func aPlainApplyWriteIsFoldedWhileItRuns() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let set = try makeScannedSet(
            folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
        let sidecar = folder.file("MMQ05184.xmp")
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        holdReplace(double, at: sidecar, count: 1, reached: reached, release: release)
        let queue = makeAdmissionQueue(folder, double)

        // "Keep this" writes ★1 through the finishing executor's plain apply, which never asks
        // for the "before" marks itself.
        async let keep = queue.apply(.rating(admissionOne), to: set)
        #expect(waitForTestSignal(reached))
        let mark = await queue.admit(.rating(admissionFour), to: set, confirmed: PhotoMarks())

        // ★4 replaces ★1, not the unrated marks before the finishing action.
        #expect(mark.marksBefore.rating == admissionOne)

        release.signal()
        _ = await keep
        _ = await queue.waitFor(mark)
    }

    @Test func aRetryInFlightIsFoldedWhileItRuns() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let set = try makeScannedSet(
            folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
        let sidecar = folder.file("MMQ05184.xmp")
        double.fail(.replace, at: sidecar, with: CocoaError(.fileWriteUnknown))
        let queue = makeAdmissionQueue(folder, double)

        let failed = await queue.admit(.rating(admissionThree), to: set, confirmed: PhotoMarks())
        let failedStatus = await queue.waitFor(failed)
        #expect(failedStatus.state.failure != nil)

        // The retry re-admits the same change; hold its second replace, then mark ★4.
        double.stopFailing(.replace)
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        holdReplace(double, at: sidecar, count: 2, reached: reached, release: release)
        async let retried = queue.retry(failedStatus.id)
        #expect(waitForTestSignal(reached))
        let mark = await queue.admit(.rating(admissionFour), to: set, confirmed: PhotoMarks())

        #expect(mark.marksBefore.rating == admissionThree)

        release.signal()
        _ = await retried
        _ = await queue.waitFor(mark)
    }

    @Test func aConfirmedWriteIsKnownBeforeTheStreamDelivers() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let set = try makeScannedSet(
            folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
        let queue = makeAdmissionQueue(folder, double)

        let first = await queue.admit(.rating(admissionThree), to: set, confirmed: PhotoMarks())
        _ = await queue.waitFor(first)

        // The caller still holds the marks from before ★3, as it would before the update stream
        // delivers; the queue's own confirmed marks are what ★4 replaces.
        let second = await queue.admit(.rating(admissionFour), to: set, confirmed: PhotoMarks())
        #expect(second.marksBefore.rating == admissionThree)
    }

    @Test func aFailedChangeIsNotWhatUndoRestoresBefore() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let set = try makeScannedSet(
            folder: makeFolderIdentity(), root: folder.url, stem: "MMQ05184")
        let sidecar = folder.file("MMQ05184.xmp")
        double.fail(.replace, at: sidecar, with: CocoaError(.fileWriteUnknown))
        let queue = makeAdmissionQueue(folder, double)

        let failed = await queue.admit(.label(admissionGreen), to: set, confirmed: PhotoMarks())
        let failedStatus = await queue.waitFor(failed)
        #expect(failedStatus.state.failure != nil)
        double.stopFailing(.replace)

        // The failed label never reached the screen as a mark, so it is not part of the fold.
        let mark = await queue.admit(.rating(admissionFour), to: set, confirmed: PhotoMarks())
        #expect(mark.marksBefore == PhotoMarks())
    }

    @Test func aFailedBatchPhotoDoesNotCountItsValueWhileAnotherWrites() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let identity = makeFolderIdentity()
        let first = try makeScannedSet(folder: identity, root: folder.url, stem: "MMQ05184")
        let second = try makeScannedSet(folder: identity, root: folder.url, stem: "MMQ05185")
        let firstSidecar = folder.file("MMQ05184.xmp")
        let secondSidecar = folder.file("MMQ05185.xmp")
        double.fail(.replace, at: secondSidecar, with: CocoaError(.fileWriteUnknown))
        let queue = makeAdmissionQueue(folder, double)

        // A batch whose only photo fails: its value never lands, so it must not count.
        let failedBatch = await queue.admit(
            .rating(admissionThree), to: [second],
            confirmed: [second.id: PhotoMarks()])
        let failed = await queue.waitFor(failedBatch)
        #expect(failed.failedCount == 1)

        // Another batch's photo is still writing while a mark replaces its value.
        double.stopFailing(.replace)
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        holdReplace(double, at: firstSidecar, count: 1, reached: reached, release: release)
        let pending = await queue.admit(
            .rating(admissionThree), to: [first], confirmed: [first.id: PhotoMarks()])
        #expect(waitForTestSignal(reached))

        let onFirst = await queue.admit(
            .rating(admissionFour), to: first, confirmed: PhotoMarks())
        let onSecond = await queue.admit(
            .rating(admissionFour), to: second, confirmed: PhotoMarks())
        #expect(onFirst.marksBefore.rating == admissionThree)
        #expect(onSecond.marksBefore.rating == .unrated)

        release.signal()
        _ = await queue.waitFor(onFirst)
        _ = await queue.waitFor(pending)
    }
}
