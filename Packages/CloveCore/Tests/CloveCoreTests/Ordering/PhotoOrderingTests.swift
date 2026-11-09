import Foundation
import Testing

import CloveCore

@Test func subsecondCaptureTimesOrderAscending() {
    let ordering = PhotoOrdering(photos: [
        photo("c", time: capture(seconds(0.500_000))),
        photo("a", time: capture(seconds(0.250_000))),
        photo("b", time: capture(seconds(0.250_001))),
    ])
    // One microsecond at a 2023 instant still separates the frames; nothing is rounded.
    #expect(ordering.photos().map(\.id.stem) == ["a", "b", "c"])
}

@Test func oneTimelineInterleavesCaptureAndFallbackTimes() {
    let ordering = PhotoOrdering(photos: [
        photo("d", time: capture(seconds(4), offset: false)),
        photo("a", time: capture(seconds(1))),
        photo("c", time: fileCreation(seconds(3))),
        photo("b", time: capture(seconds(2), offset: false)),
        photo("e", time: fileModification(seconds(5))),
    ])
    // Capture times with and without an offset and both file times share one timeline.
    #expect(ordering.photos().map(\.id.stem) == ["a", "b", "c", "d", "e"])
    #expect(
        ordering.photos().map(\.time.time?.source) == [
            .captureMetadata, .captureMetadata, .fileCreation, .captureMetadata, .fileModification,
        ])
}

@Test func equalInstantsBreakOnRelativeFolderPath() {
    let instant = seconds(7)
    let later = photo("same", time: capture(instant), path: "DCIM/101CAM")
    let earlier = photo("same", time: capture(instant), path: "DCIM/100CAM")
    let ordering = PhotoOrdering(photos: [later, earlier])
    #expect(ordering.photos().map(\.id.relativeFolderPath) == ["DCIM/100CAM", "DCIM/101CAM"])
}

@Test func equalInstantsBreakOnFileNameBeforeIdentity() {
    let instant = seconds(7)
    // Identity would order `alpha` first; the file name has to decide instead.
    let alpha = photo("alpha", time: capture(instant), fileName: "IMG_0010.ARW")
    let zulu = photo("zulu", time: capture(instant), fileName: "IMG_0009.ARW")
    let ordering = PhotoOrdering(photos: [alpha, zulu])
    #expect(ordering.photos().map(\.id.stem) == ["zulu", "alpha"])
}

@Test func equalInstantsAndNamesBreakOnIdentityLast() {
    let instant = seconds(7)
    let zulu = photo("zulu", time: capture(instant), fileName: "SAME.ARW")
    let alpha = photo("alpha", time: capture(instant), fileName: "SAME.ARW")
    #expect(PhotoOrdering(photos: [zulu, alpha]).photos().map(\.id.stem) == ["alpha", "zulu"])

    let secondCard = photo(
        "alpha", time: capture(instant), folder: FolderIdentity(rawValue: "card-b"))
    let firstCard = photo(
        "alpha", time: capture(instant), folder: FolderIdentity(rawValue: "card-a"))
    #expect(
        PhotoOrdering(photos: [secondCard, firstCard]).photos().map(\.id.folderID.rawValue)
            == ["card-a", "card-b"])
}

@Test func pendingPhotosAreWithheldUntilTheirTimeArrives() {
    let pendingPhoto = photo("b", time: .pending)
    var ordering = PhotoOrdering(photos: [
        photo("a", time: capture(seconds(1))),
        photo("c", time: capture(seconds(3))),
        pendingPhoto,
    ])
    #expect(ordering.pendingCount == 1)
    // No temporary filename order appears: `b` is absent even though it sorts between a and c.
    #expect(ordering.photos().map(\.id.stem) == ["a", "c"])

    let placedBefore = ordering.photos().map(\.id)
    ordering.setTime(capture(seconds(2)), for: pendingPhoto.id)
    #expect(ordering.pendingCount == 0)
    #expect(ordering.photos().map(\.id.stem) == ["a", "b", "c"])
    #expect(ordering.photos().map(\.id).filter { $0 != pendingPhoto.id } == placedBefore)
}

@Test func insertingPhotosOnlyInsertsThem() {
    var ordering = PhotoOrdering(photos: [
        photo("a", time: capture(seconds(1))),
        photo("c", time: capture(seconds(3))),
        photo("e", time: capture(seconds(5))),
    ])
    let placedBefore = ordering.photos().map(\.id)

    let first = photo("0", time: capture(seconds(0)))
    let middle = photo("b", time: capture(seconds(2)))
    let last = photo("f", time: capture(seconds(6)))
    ordering.insert([last, middle, first])

    let after = ordering.photos()
    let newcomers = Set([first.id, middle.id, last.id])
    #expect(after.map(\.id.stem) == ["0", "a", "b", "c", "e", "f"])
    #expect(after.map(\.id).filter { !newcomers.contains($0) } == placedBefore)
}

@Test func unavailablePhotosFollowEveryTimedPhoto() {
    let ordering = PhotoOrdering(photos: [
        photo("z", time: .unavailable),
        photo("y", time: .unavailable, path: "DCIM/101CAM"),
        photo("x", time: .unavailable),
        photo("w", time: capture(seconds(9_000))),
        photo("v", time: fileModification(seconds(0.5))),
    ])
    // Timed photos first, then untimed ones by relative folder path and file name.
    #expect(ordering.photos().map(\.id.stem) == ["v", "w", "x", "z", "y"])
}

@Test func onlyCaptureTimesAreGroupable() {
    let ordering = PhotoOrdering(photos: [
        photo("capture", time: capture(seconds(1))),
        photo("wall-clock", time: capture(seconds(2), offset: false)),
        photo("created", time: fileCreation(seconds(3))),
        photo("modified", time: fileModification(seconds(4))),
        photo("untimed", time: .unavailable),
    ])
    #expect(
        ordering.photos().filter(\.time.isGroupable).map(\.id.stem) == [
            "capture", "wall-clock",
        ])
}

@Test func reinsertingAPhotoReplacesItWithoutDuplicating() {
    var ordering = PhotoOrdering(photos: [photo("a", time: capture(seconds(1)))])
    ordering.insert([photo("a", time: capture(seconds(5)))])
    #expect(ordering.photos().map(\.id.stem) == ["a"])
    #expect(ordering.photos().first?.time.time?.instant == seconds(5))
}

@Test func unknownIdentitiesAreIgnored() {
    var ordering = PhotoOrdering(photos: [photo("a", time: capture(seconds(1)))])
    let stranger = photo("stranger", time: capture(seconds(2)))
    ordering.setTime(capture(seconds(0)), for: stranger.id)
    ordering.setMarks(marks(stars: 5), for: stranger.id)
    ordering.remove([stranger.id])
    #expect(ordering.photos().map(\.id.stem) == ["a"])
    #expect(ordering.pendingCount == 0)
}

@Test func marksUpdatesKeepThePlaceAndFeedFilters() throws {
    let target = photo("b", time: capture(seconds(2)))
    var ordering = PhotoOrdering(photos: [
        photo("a", time: capture(seconds(1))),
        target,
        photo("c", time: capture(seconds(3))),
    ])
    ordering.setMarks(marks(stars: 4), for: target.id)
    #expect(ordering.photos().map(\.id.stem) == ["a", "b", "c"])
    let fourStars = try #require(Rating(rawValue: 4))
    #expect(ordering.photos(matching: .ratedAtLeast(fourStars)).map(\.id.stem) == ["b"])
    #expect(ordering.photos(matching: .unmarked).map(\.id.stem) == ["a", "c"])

    ordering.setMarks(marks(stars: 4, rejected: true), for: target.id)
    #expect(ordering.photos(matching: .rejected).map(\.id.stem) == ["b"])
    #expect(ordering.photos(order: .fileName, matching: .unmarked).map(\.id.stem) == ["a", "c"])
}

@Test func removingPhotosDropsThemFromBothSets() {
    let placed = photo("a", time: capture(seconds(1)))
    let pendingPhoto = photo("b", time: .pending)
    let untimed = photo("c", time: .unavailable)
    var ordering = PhotoOrdering(photos: [placed, pendingPhoto, untimed])

    // A move to the rejects folder removes the whole set from the grid.
    ordering.remove([placed.id, pendingPhoto.id])
    #expect(ordering.pendingCount == 0)
    #expect(ordering.photos().map(\.id.stem) == ["c"])

    ordering.remove([untimed.id])
    ordering.remove([untimed.id])
    #expect(ordering.photos().isEmpty)
}

/// Mixed sources, ties, subseconds and untimed photos, written unordered on purpose.
private let permutedPhotos: [GridPhoto] = [
    photo("frame_01", time: capture(seconds(0.125))),
    photo("frame_02", time: capture(seconds(0.5), offset: false)),
    photo("frame_03", time: capture(seconds(0.5))),
    photo("frame_04", time: fileCreation(seconds(0.25))),
    photo("frame_05", time: fileModification(seconds(0.25))),
    photo("frame_06", time: capture(seconds(2.000_001))),
    photo("frame_07", time: capture(seconds(2.000_002))),
    photo("frame_08", time: .unavailable),
    photo("frame_09", time: .unavailable),
    photo("frame_10", time: capture(seconds(1)), path: "DCIM/101CAM"),
    photo("frame_11", time: capture(seconds(3))),
    photo("frame_12", time: capture(seconds(0.125)), path: "DCIM/099CAM"),
]

@Test(arguments: 0..<24)
private func orderIsDeterministicForAnyInputOrderAndBatchSize(seed: Int) {
    let expected = PhotoOrdering(photos: permutedPhotos).photos().map(\.id)
    let expectedByName = PhotoOrdering(photos: permutedPhotos).photos(order: .fileName).map(\.id)
    var generator = SeededGenerator(seed: UInt64(seed))

    for _ in 0..<25 {
        let input = permutedPhotos.shuffled(using: &generator)
        var ordering = PhotoOrdering()
        var index = 0
        while index < input.count {
            let size = Int.random(in: 1...5, using: &generator)
            let end = min(index + size, input.count)
            ordering.insert(Array(input[index..<end]))
            index = end
        }
        #expect(ordering.photos().map(\.id) == expected, "seed \(seed)")
        #expect(ordering.photos(order: .fileName).map(\.id) == expectedByName, "seed \(seed)")
    }
}

@Test func aPendingPhotoWithNoUsableTimeJoinsTheEndOfTheOrder() {
    let pendingPhoto = photo("b", time: .pending)
    var ordering = PhotoOrdering(photos: [photo("a", time: capture(seconds(1))), pendingPhoto])
    ordering.setTime(.unavailable, for: pendingPhoto.id)
    #expect(ordering.pendingCount == 0)
    #expect(ordering.photos().map(\.id.stem) == ["a", "b"])
    #expect(!ordering.photos()[1].time.isGroupable)
}

@Test func orderingValuesAreSendableAndHashable() {
    func requireValue<T: Sendable & Hashable>(_: T.Type) {}
    requireValue(PhotoTimeSource.self)
    requireValue(PhotoTime.self)
    requireValue(PhotoTimeState.self)
    requireValue(GridPhoto.self)
    requireValue(PhotoOrder.self)
    requireValue(PhotoFilter.self)

    func requireSendable<T: Sendable>(_: T.Type) {}
    requireSendable(PhotoOrdering.self)
}
