import Foundation
import Testing

import CloveCore

@Test func captureTimeIsTheDefaultOrder() {
    let ordering = PhotoOrdering(photos: [
        photo("a", time: capture(seconds(20)), fileName: "IMG_0001.ARW"),
        photo("b", time: capture(seconds(10)), fileName: "IMG_0002.ARW"),
    ])
    #expect(ordering.photos().map(\.id.stem) == ["b", "a"])
    #expect(ordering.photos(order: .captureTime).map(\.id.stem) == ["b", "a"])
}

@Test func filenameOrderComparesNumbersLikeFinder() {
    let ordering = PhotoOrdering(photos: [
        photo("img_10", time: capture(seconds(1)), fileName: "IMG_10.ARW"),
        photo("img_9", time: capture(seconds(2)), fileName: "IMG_9.ARW"),
    ])
    // Capture time keeps its own order ...
    #expect(ordering.photos().map(\.id.stem) == ["img_10", "img_9"])
    // ... while the filename option puts IMG_9 before IMG_10, as Finder does.
    #expect(ordering.photos(order: .fileName).map(\.id.stem) == ["img_9", "img_10"])
}

@Test func filenameOrderReadsRelativeFoldersBeforeFiles() {
    let ordering = PhotoOrdering(photos: [
        photo("a", time: capture(seconds(1)), path: "DCIM/101CAM", fileName: "IMG_0001.ARW"),
        photo("b", time: capture(seconds(2)), path: "DCIM/100CAM", fileName: "IMG_9999.ARW"),
    ])
    #expect(
        ordering.photos(order: .fileName).map(\.id.relativeFolderPath)
            == ["DCIM/100CAM", "DCIM/101CAM"])
}

@Test func filenameOrderIgnoresTimeAndUntimedPlacement() {
    let ordering = PhotoOrdering(photos: [
        photo("zulu", time: capture(seconds(1)), fileName: "IMG_0002.ARW"),
        photo("alpha", time: capture(seconds(2)), fileName: "IMG_0001.ARW"),
        photo("untimed", time: .unavailable, fileName: "IMG_0000.ARW"),
    ])
    // The default order is time first, with untimed photos last.
    #expect(ordering.photos().map(\.id.stem) == ["zulu", "alpha", "untimed"])
    // The filename option reads only the path and the name.
    #expect(ordering.photos(order: .fileName).map(\.id.stem) == ["untimed", "alpha", "zulu"])
}

@Test func filenameOrderEndsAtIdentityForEqualPathsAndNames() {
    let zulu = photo("zulu", time: capture(seconds(1)), fileName: "SAME.ARW")
    let alpha = photo("alpha", time: capture(seconds(1)), fileName: "SAME.ARW")
    #expect(
        PhotoOrdering(photos: [zulu, alpha]).photos(order: .fileName).map(\.id.stem)
            == ["alpha", "zulu"])
}

@Test func aScannedSetSuppliesTheIdentityAndPrimaryFileName() throws {
    let directory = URL(fileURLWithPath: "/Photos/DCIM/100CAM")
    let set = try PhotoSet(
        folderID: orderingFolder, relativeFolderPath: "DCIM/100CAM",
        rawURL: directory.appendingPathComponent("MMQ05184.ARW"),
        jpegURL: directory.appendingPathComponent("MMQ05184.JPG"))
    let scanned = GridPhoto(set: set, time: .pending)
    #expect(scanned.id == set.id)
    #expect(scanned.fileName == "MMQ05184.ARW")
    #expect(scanned.time.isPending)
    #expect(scanned.marks == PhotoMarks())
}
