import Foundation
import Testing

import CloveCore

/// How a launch decides whether a saved scene still applies while its folder's scan runs
/// (PRD P0-02, P0-14).
@Suite("Pending browsing restore")
struct PendingBrowsingRestoreTests {
    /// The state the launch shows right after reopening the saved folder: its grid, nothing else.
    private var shown: BrowsingState {
        BrowsingState(folder: BrowsingFixtures.folder, route: .grid)
    }

    /// A pending restore of the fixture's fully populated saved state.
    private var pending: PendingBrowsingRestore {
        PendingBrowsingRestore(saved: BrowsingFixtures.saved, shown: shown)
    }

    @Test func waitsWhileANamedPhotoIsMissing() {
        // The saved state names beta (current and group), alpha and gamma (selection); delta is
        // the only photo the scan delivered so far.
        let partial = FolderContents(
            folder: BrowsingFixtures.folder, photos: [BrowsingFixtures.delta])
        #expect(pending.decision(current: shown, contents: partial) == .wait)
    }

    @Test func appliesOnceEveryNamedPhotoIsPresent() throws {
        let full = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [
                BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.gamma,
                BrowsingFixtures.delta,
            ],
            groups: BrowsingFixtures.groups)
        guard case .apply(let restored) = pending.decision(current: shown, contents: full) else {
            Issue.record("the pending restore did not apply")
            return
        }
        // PRD P0-14: the photo, filter, order, selection and group place all survive the launch.
        #expect(restored.state.currentPhoto == BrowsingFixtures.beta)
        #expect(restored.state.filter == .ratedAtLeast(BrowsingFixtures.threeStars))
        #expect(restored.state.order == .fileName)
        #expect(restored.state.selection == [BrowsingFixtures.alpha, BrowsingFixtures.gamma])
        #expect(restored.state.groupPosition?.photo == BrowsingFixtures.beta)
        #expect(restored.state.route == .group)
        #expect(restored.folderFailure == nil)
    }

    @Test func dropsAfterAnEarlyNavigation() {
        var navigated = shown
        navigated.currentPhoto = BrowsingFixtures.delta
        navigated.route = .detail
        let partial = FolderContents(folder: BrowsingFixtures.folder, photos: [])
        #expect(pending.decision(current: navigated, contents: partial) == .drop)
    }

    @Test func dropsWhenAnotherFolderAnswers() {
        let other = FolderContents(
            folder: FolderIdentity(rawValue: "another-folder"), photos: [BrowsingFixtures.beta])
        #expect(pending.decision(current: shown, contents: other) == .drop)
    }

    @Test func aSavedStateWithoutPhotosAppliesAtOnce() {
        let saved = BrowsingState(folder: BrowsingFixtures.folder, route: .grid)
        let restore = PendingBrowsingRestore(saved: saved, shown: shown)
        let empty = FolderContents(folder: BrowsingFixtures.folder, photos: [])
        guard case .apply(let restored) = restore.decision(current: shown, contents: empty) else {
            Issue.record("a saved grid with no photo did not apply")
            return
        }
        #expect(restored.state.route == .grid)
        #expect(restored.state.folder == BrowsingFixtures.folder)
    }
}
