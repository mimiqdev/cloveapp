import Foundation
import Testing

import CloveCore

/// The opened folder every grouping test uses; identity only, never a path.
let groupingFolder = FolderIdentity(rawValue: "opened-folder")

/// The base instant for grouping tests, so fractions and offsets stay readable.
let groupingBase = Date(timeIntervalSince1970: 1_700_000_000)

/// An instant `offset` seconds after the grouping base.
func groupingSeconds(_ offset: Double) -> Date {
    groupingBase.addingTimeInterval(offset)
}

/// A groupable capture time, with an explicit UTC offset by default.
func groupingCapture(_ offset: Double, offset hasUTCOffset: Bool = true) -> PhotoTimeState {
    .known(PhotoTime(captureTime: groupingSeconds(offset), hasUTCOffset: hasUTCOffset))
}

/// One input photo with a capture time by default (G1's Grouping row).
func groupingPhoto(
    _ stem: String,
    at offset: Double,
    model: String? = "ILCE-1M2",
    serial: String? = nil,
    fileName: String? = nil,
    path: String = "DCIM/100CAM",
    folder: FolderIdentity = groupingFolder,
    time: PhotoTimeState? = nil
) -> GroupingPhoto {
    GroupingPhoto(
        id: PhotoIdentity(folderID: folder, relativeFolderPath: path, stem: stem),
        fileName: fileName ?? "\(stem.uppercased()).ARW",
        time: time ?? groupingCapture(offset),
        cameraModel: model,
        cameraSerial: serial)
}

/// A stable key for one adjacent pair, as the fake provider records it.
func groupingPair(_ left: GroupingPhoto, _ right: GroupingPhoto) -> String {
    "\(left.id.stem)|\(right.id.stem)"
}

/// A fake feature source: each pair answers what the test scripted, and unscripted pairs are
/// still being computed. It records every pair it was asked about, so a test can prove that
/// grouping did no work (PRD Similar groups step 3).
actor ScriptedSimilarity: PhotoSimilarityProviding {
    private var answers: [String: PhotoSimilarity] = [:]
    private var asked: [String] = []

    /// Scripts one boundary's answer.
    func answer(_ similarity: PhotoSimilarity, for left: GroupingPhoto, _ right: GroupingPhoto) {
        answers[groupingPair(left, right)] = similarity
    }

    /// Scripts every boundary between `photos` in the order given.
    func answerAll(_ similarity: PhotoSimilarity, between photos: [GroupingPhoto]) {
        for index in photos.indices.dropFirst() {
            answer(similarity, for: photos[index - 1], photos[index])
        }
    }

    /// How many times the grouper asked for a distance.
    var askCount: Int { asked.count }

    func similarity(
        between left: GroupingPhoto,
        and right: GroupingPhoto
    ) async -> PhotoSimilarity {
        let key = groupingPair(left, right)
        asked.append(key)
        return answers[key] ?? .notReady
    }
}

/// An always-ready feature source for timing and round-trip tests (no work per pair).
struct InstantSimilarity: PhotoSimilarityProviding {
    /// The answer every boundary gets.
    let answer: PhotoSimilarity

    func similarity(
        between left: GroupingPhoto,
        and right: GroupingPhoto
    ) async -> PhotoSimilarity {
        answer
    }
}

/// The stems of one group's members, in the group's member order.
func groupingStems(_ group: SimilarGroup) -> [String] {
    group.members.map(\.stem)
}

/// Every group's member stems, in grid order.
func groupingStems(_ groups: SimilarGroups) -> [[String]] {
    groups.groups.map(groupingStems)
}

/// Runs a fresh grouper over `photos` and returns its published result.
func groupingRun(
    _ photos: [GroupingPhoto],
    using similarity: any PhotoSimilarityProviding,
    thresholds: GroupingThresholds = .standard,
    cache: SimilarGroupsCache? = nil,
    revision: GroupingInputRevision = GroupingInputRevision(rawValue: "revision-1"),
    similarGroupsEnabled: Bool = true,
    reuseCache: Bool = true,
    passes: Int = 1
) async -> SimilarGroups {
    let grouper = SimilarGrouping(
        similarity: similarity, thresholds: thresholds, cache: cache)
    await grouper.run(
        photos: photos,
        revision: revision,
        similarGroupsEnabled: similarGroupsEnabled,
        reuseCache: reuseCache)
    for _ in 0..<passes { await grouper.refine() }
    return await grouper.current
}

/// A throwaway directory for cache and folder tests; call ``remove()`` when the test ends.
struct GroupingTestFolder: Sendable {
    /// The directory, inside the system's temporary directory.
    let url: URL

    /// Creates an empty, uniquely named directory.
    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clove-grouping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The URL of `name` directly inside the directory, whether or not it exists.
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// The file names directly inside the directory, including hidden ones.
    func entries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    /// Deletes the whole tree.
    func remove() { try? FileManager.default.removeItem(at: url) }
}
