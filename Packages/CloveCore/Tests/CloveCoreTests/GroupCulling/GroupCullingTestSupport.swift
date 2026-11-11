import Foundation
import Testing

@testable import CloveCore

/// The opened folder in-group culling tests use; identity only, never a path.
let groupCullingFolder = FolderIdentity(rawValue: "group-culling-folder")

/// A photo identity in the culling test folder, in one subfolder so members read apart.
func groupCullingPhoto(
    _ stem: String,
    folder: FolderIdentity = groupCullingFolder
) -> PhotoIdentity {
    PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: stem)
}

/// A refined group whose members keep the order given (PRD Similar groups step 1).
func groupCullingGroup(_ name: String, members: [PhotoIdentity]) -> SimilarGroup {
    SimilarGroup(
        id: GroupID(rawValue: "group-\(name)"),
        members: members,
        refinement: .refined,
        usedFallbackSimilarity: false)
}

/// A published grouping of the groups in grid order (PRD Similar groups rules).
func groupCullingGroups(_ groups: [SimilarGroup]) -> SimilarGroups {
    SimilarGroups(groups: groups, analysis: .analyzed)
}

/// A valid rating for tests; an out-of-range value records an issue instead of passing.
func groupCullingRating(_ value: Int) -> Rating {
    guard let rating = Rating(rawValue: value) else {
        Issue.record("\(value) is not a valid rating")
        return .unrated
    }
    return rating
}

/// An enabled-level set built from valid test values (PRD Enabled rating levels).
func groupCullingEnabledRatings(_ values: [Int]) -> EnabledRatings {
    EnabledRatings(values.map(groupCullingRating)) ?? .all
}

/// Two enabled levels, so Keep this has to use the lowest rather than the default 1.
let groupCullingTwoAndFour = groupCullingEnabledRatings([2, 4])

/// Marks a photo has when it has no rating, no label and no Reject (PRD P0-05).
let groupCullingUnmarked = PhotoMarks()

/// A dictionary of marks, built one photo at a time so tests read like the group view.
func groupCullingMarks(_ entries: [(PhotoIdentity, PhotoMarks)]) -> [PhotoIdentity: PhotoMarks] {
    var marks: [PhotoIdentity: PhotoMarks] = [:]
    for (photo, photoMarks) in entries { marks[photo] = photoMarks }
    return marks
}
