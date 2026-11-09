import Foundation

import CloveCore

/// Fixtures for the browsing-state tests: one folder, four photos and one burst group.
///
/// Names stay inside this enum, so the tests share no free symbols with the rest of the target.
enum BrowsingFixtures {
    /// The folder every fixture photo belongs to; identity only, never a path.
    static let folder = FolderIdentity(rawValue: "browsing-folder")

    static func photo(_ stem: String, path: String = "DCIM/100CAM") -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: path, stem: stem)
    }

    static let alpha = photo("alpha")
    static let beta = photo("beta")
    static let gamma = photo("gamma")
    static let delta = photo("delta")

    /// The group the saved state names while grouping still publishes it.
    static let burst = GroupID(rawValue: "burst")

    /// A group key the folder no longer publishes.
    static let vanishedBurst = GroupID(rawValue: "vanished-burst")

    /// The group key a refinement split the burst into.
    static let splitBurst = GroupID(rawValue: "split-burst")

    /// One group of alpha, beta and gamma; delta stays ungrouped.
    static var groups: [BrowsingGroup] {
        [BrowsingGroup(id: burst, members: [alpha, beta, gamma])]
    }

    /// Every fixture photo and the group above, in one folder.
    static var contents: FolderContents {
        FolderContents(folder: folder, photos: [alpha, beta, gamma, delta], groups: groups)
    }

    /// The rating the fixture filter asks for.
    static var threeStars: Rating {
        guard let rating = Rating(rawValue: 3) else {
            preconditionFailure("three stars is a valid rating")
        }
        return rating
    }

    /// A state that names every part PRD P0-14 preserves.
    static var saved: BrowsingState {
        BrowsingState(
            folder: folder,
            currentPhoto: beta,
            filter: .ratedAtLeast(threeStars),
            order: .fileName,
            selection: [alpha, gamma],
            groupPosition: BrowsingGroupPosition(group: burst, photo: beta),
            route: .group)
    }

    /// A permission failure, as C11 reports one (PRD P0-02).
    static var permissionDenied: FolderAccessFailure {
        .permissionDenied(FolderErrorChain(NSError(domain: NSPOSIXErrorDomain, code: 13)))
    }
}
