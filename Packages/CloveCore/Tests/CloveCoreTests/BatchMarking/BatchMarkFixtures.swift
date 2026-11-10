import Foundation

import CloveCore

/// Fixtures for the multi-select tests: one folder, four photos and one burst group.
///
/// Names stay inside this enum, so the tests share no free symbols with the rest of the target.
enum BatchMarkFixtures {
    /// The folder every fixture photo belongs to; identity only, never a path.
    static let folder = FolderIdentity(rawValue: "batch-folder")

    /// One photo of the fixture folder.
    static func photo(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: stem)
    }

    /// A rating for the fixtures, which only uses PRD P0-05's 0–5 range.
    static func stars(_ count: Int) -> Rating {
        guard let rating = Rating(rawValue: count) else {
            preconditionFailure("a fixture rating must be within 0–5")
        }
        return rating
    }

    /// One shown photo with the marks a batch reads; its time keeps it in the ordered list.
    static func gridPhoto(
        _ stem: String, stars count: Int = 0, label: ColourLabel = .clear,
        rejected: Bool = false
    ) -> GridPhoto {
        GridPhoto(
            id: photo(stem),
            fileName: "\(stem.uppercased()).ARW",
            time: .known(
                PhotoTime(
                    captureTime: Date(timeIntervalSince1970: 1_760_000_000),
                    hasUTCOffset: true)),
            marks: PhotoMarks(rating: stars(count), label: label, isRejected: rejected))
    }

    /// The group key the collapsed cover stands for.
    static let burst = GroupID(rawValue: "burst-one")

    /// One group of a, b and c, so a cover stands for more than its own photo.
    static var groups: [BrowsingGroup] {
        [BrowsingGroup(id: burst, members: [photo("a"), photo("b"), photo("c")])]
    }

    /// The enabled rating levels a test reads, never empty.
    static func enabled(_ levels: [Int]) -> EnabledRatings {
        guard let ratings = EnabledRatings(levels.map(stars)) else {
            preconditionFailure("a fixture rating set needs at least one enabled level")
        }
        return ratings
    }
}
