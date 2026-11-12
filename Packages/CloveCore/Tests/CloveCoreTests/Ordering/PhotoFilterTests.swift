import Testing

import CloveCore

@Test func allIncludesRejectedPhotos() {
    #expect(PhotoFilter.all.matches(marks(), relativeFolderPath: ""))
    #expect(PhotoFilter.all.matches(marks(stars: 5, rejected: true), relativeFolderPath: ""))
    #expect(
        PhotoFilter.all.matches(marks(label: ColourLabel(colour: .red)), relativeFolderPath: ""))
}

@Test func unmarkedNeedsNoRatingNoLabelAndNoReject() {
    #expect(PhotoFilter.unmarked.matches(marks(), relativeFolderPath: ""))
    #expect(!PhotoFilter.unmarked.matches(marks(stars: 1), relativeFolderPath: ""))
    #expect(
        !PhotoFilter.unmarked.matches(
            marks(label: ColourLabel(colour: .red)), relativeFolderPath: ""))
    // Unknown external label text is still a label, so the photo counts as marked.
    #expect(
        !PhotoFilter.unmarked.matches(
            marks(label: ColourLabel(rawValue: "External workflow")), relativeFolderPath: ""))
    #expect(
        !PhotoFilter.unmarked.matches(
            marks(label: ColourLabel(rawValue: " ")), relativeFolderPath: ""))
    #expect(!PhotoFilter.unmarked.matches(marks(rejected: true), relativeFolderPath: ""))
}

@Test func rejectedShowsRejectedPhotosOnly() {
    #expect(
        PhotoFilter.rejected.matches(
            marks(stars: 5, label: ColourLabel(colour: .green), rejected: true),
            relativeFolderPath: ""))
    #expect(!PhotoFilter.rejected.matches(marks(stars: 5), relativeFolderPath: ""))
    #expect(!PhotoFilter.rejected.matches(marks(), relativeFolderPath: ""))
}

@Test(arguments: 1...5)
private func starsOrHigherKeepsThatRatingAndAbove(stars: Int) throws {
    let filter = PhotoFilter.ratedAtLeast(try #require(Rating(rawValue: stars)))
    for value in 0...5 {
        #expect(
            filter.matches(marks(stars: value), relativeFolderPath: "") == (value >= stars),
            "\(stars) stars or higher against a \(value)-star photo")
    }
}

@Test func starsOrHigherHidesRejectedPhotosByDefault() throws {
    // The policy lives in one constant so it is easy to flip (PRD P0-03).
    #expect(PhotoFilter.ratedAtLeastHidesRejected)
    let oneStar = try #require(Rating(rawValue: 1))
    #expect(
        !PhotoFilter.ratedAtLeast(oneStar).matches(
            marks(stars: 5, rejected: true), relativeFolderPath: ""))
    #expect(PhotoFilter.rejected.matches(marks(stars: 5, rejected: true), relativeFolderPath: ""))
}

@Test func filtersNeverChangeTheOrder() throws {
    let ordering = PhotoOrdering(photos: [
        photo("c", time: capture(seconds(3)), fileName: "IMG_0001.ARW", marks: marks(stars: 5)),
        photo("a", time: capture(seconds(1)), fileName: "IMG_0010.ARW", marks: marks(stars: 2)),
        photo("b", time: capture(seconds(2)), fileName: "IMG_0002.ARW"),
    ])
    #expect(ordering.photos(matching: .all).map(\.id.stem) == ["a", "b", "c"])
    #expect(ordering.photos(order: .fileName, matching: .all).map(\.id.stem) == ["c", "b", "a"])

    let twoStars = try #require(Rating(rawValue: 2))
    #expect(ordering.photos(matching: .ratedAtLeast(twoStars)).map(\.id.stem) == ["a", "c"])
    #expect(ordering.photos(matching: .unmarked).map(\.id.stem) == ["b"])
    #expect(
        ordering.photos(order: .fileName, matching: .ratedAtLeast(twoStars)).map(\.id.stem) == [
            "c", "a",
        ])
}
