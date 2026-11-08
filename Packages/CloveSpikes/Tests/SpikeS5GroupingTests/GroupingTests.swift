import Foundation
import SpikeSupport
import Testing

@testable import SpikeS5Grouping

private func photo(_ id: String, _ time: Double?, model: String? = "Camera", serial: String? = "A")
    -> GroupingPhoto
{
    .init(
        id: id, model: model, serial: serial,
        captureTime: time.map { Date(timeIntervalSince1970: $0) })
}

@Test func bodySeparationAndSorting() {
    let photos = [
        photo("a2", 0.2), photo("b1", 0, serial: "B"), photo("a1", 0),
        photo("b2", 0.2, serial: "B"),
    ]
    #expect(Grouping.groups(photos, distance: { _, _ in 0 }) == [["a1", "a2"], ["b1", "b2"]])
    #expect(
        Grouping.groups([photo("a", 0), photo("b", 0.1, model: "Other")], distance: { _, _ in 0 })
            .isEmpty)
}

@Test func gapsSimilarityAndMinimumSize() {
    let photos = [
        photo("1", 0), photo("2", 0.1), photo("3", 2.1), photo("4", 2.2), photo("5", 2.3),
    ]
    #expect(
        Grouping.groups(photos, distance: { a, b in a == "4" && b == "5" ? 1 : 0 }) == [
            ["1", "2"], ["3", "4"],
        ])
    #expect(Grouping.groups([photo("alone", 0)], distance: { _, _ in 0 }).isEmpty)
    #expect(Grouping.groups([], distance: { _, _ in 0 }).isEmpty)
}

@Test func missingTimesExcludedAndMissingFeaturesSplit() {
    let photos = [photo("1", 0), photo("missing", nil), photo("2", 0.1), photo("3", 0.2)]
    #expect(Grouping.groups(photos, distance: { a, _ in a == "1" ? nil : 0 }) == [["2", "3"]])
    #expect(Grouping.groups([photo("missing", nil)], distance: { _, _ in 0 }).isEmpty)
}

@Test func coarseTimeUsesNumericFilenameAndModelFallback() {
    let photos = [photo("IMG_10", 0, serial: nil), photo("IMG_2", 0, serial: nil)]
    #expect(Grouping.groups(photos, distance: { _, _ in 0 }) == [["IMG_2", "IMG_10"]])
    let known = photo("known", 0.1)
    #expect(Grouping.groups(photos + [known], distance: { _, _ in 0 }) == [["IMG_2", "IMG_10"]])
}

@Test func strictGapAndInclusiveDistance() {
    #expect(Grouping.shouldSplit(gap: 2, distance: 0, parameters: .init()))
    #expect(!Grouping.shouldSplit(gap: 1.999, distance: 0.5, parameters: .init()))
    #expect(Grouping.shouldSplit(gap: 0, distance: .nan, parameters: .init()))
}

@Test func metadataPathsFractionsAndOffset() throws {
    let metadata = GroupingMetadataReader.parse(
        flat: [
            "{TIFF}.Model": "Camera", "{Exif}.BodySerialNumber": "body",
            "{Exif}.LensSerialNumber": "lens", "{MakerCanon}.SerialNumber": "maker",
            "{Exif}.DateTimeOriginal": "2026:11:13 12:00:00",
            "{Exif}.SubsecTimeOriginal": "0123", "{Exif}.OffsetTimeOriginal": "+02:30",
        ], id: "test")
    #expect(metadata.photo.serial == "body")
    #expect(metadata.selectedPaths["serial"] == "{Exif}.BodySerialNumber")
    let reference = try #require(
        GroupingMetadataReader.captureTime("2026-11-13T09:30:00.0123Z", subsecond: nil, offset: nil)
    )
    #expect(abs(try #require(metadata.photo.captureTime).timeIntervalSince(reference)) < 0.00001)
    #expect(
        GroupingMetadataReader.parse(flat: ["{Exif}.LensSerialNumber": "lens"], id: "x").photo
            .serial == nil)
    #expect(
        GroupingMetadataReader.parse(flat: ["{MakerNikon}.SerialNumber": "123"], id: "x").photo
            .serial == "123")
}

@Test func invalidDatesAndAbsentMetadata() {
    for (time, fraction, offset) in [
        ("bad", "1", "+00:00"), ("2026:02:30 00:00:00", "1", "+00:00"),
        ("2026:11:13 00:00:00", "abc", "+00:00"), ("2026:11:13 00:00:00", "1", "+99:99"),
        ("2026:11:13 00:00:00", "1", "+-1:00"), ("2026:11:13 00:00:00", "1", "+01:-1"),
    ] {
        #expect(
            GroupingMetadataReader.captureTime(time, subsecond: fraction, offset: offset) == nil)
    }
    #expect(GroupingMetadataReader.parse(flat: [:], id: "empty").photo.captureTime == nil)
}

@Test func labelsAreExplicitAndSweepHasBothErrorKinds() {
    let boundaries: [GroupingBoundary] = [
        .init(
            left: "a", right: "b", gap: 0.2, distance: 0.6, proposedSplit: true,
            expectedSplit: false),
        .init(
            left: "b", right: "c", gap: 0.8, distance: 0.2, proposedSplit: false,
            expectedSplit: true),
        .init(left: "c", right: "d", gap: 1, distance: 0, proposedSplit: false),
    ]
    let sweep = Grouping.sweep(boundaries)
    #expect(sweep.count == 30)
    #expect(sweep.allSatisfy { $0.reviewed == 2 })
    #expect(
        sweep.contains {
            $0.timeGap == 2 && $0.distance == 0.5 && $0.wrongSplits == 1 && $0.wrongMerges == 1
        })
    let run = GroupingRun(
        report: .init(spike: "S5"), photos: [], thumbnails: [:], boundaries: boundaries, groups: [])
    let report = run.labeledReport()
    #expect(report.measurements.filter { $0.name == "boundary" }.count == 3)
    #expect(report.context["reviewedBoundaries"] == "2")
    #expect(report.measurements.contains { $0.tags["expectedSplit"] == "unreviewed" })
}

@Test func fixtureMeasurementWhenRequested() async throws {
    guard let path = ProcessInfo.processInfo.environment["CLOVE_S5_REPORT"] else { return }
    let folder = try #require(Fixtures.set("formats"))
    let run = try await GroupingSuite.run(folder: folder, includeSyntheticFixtures: true)
    #expect(run.photos.count == 10)
    #expect(run.report.measurements.contains { $0.name == "vision-feature" })
    #expect(run.report.measurements.filter { $0.name == "metadata-read" }.count == 10)
    try run.labeledReport().write(to: URL(fileURLWithPath: path))
}
