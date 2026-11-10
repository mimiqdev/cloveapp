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
        #expect(
            pending.decision(
                current: shown, contents: partial, scanFinished: false, groupsPublished: true)
                == .wait)
    }

    @Test func appliesOnceEveryNamedPhotoIsPresent() throws {
        let full = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [
                BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.gamma,
                BrowsingFixtures.delta,
            ],
            groups: BrowsingFixtures.groups)
        guard
            case .apply(let restored) = pending.decision(
                current: shown, contents: full, scanFinished: false, groupsPublished: true)
        else {
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

    @Test func appliesAtScanEndWhenTheSavedPhotoIsGone() throws {
        // beta, the saved current photo and group photo, was moved to the rejects folder before
        // this launch. The finished scan must still restore what survived instead of waiting.
        let remaining = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.delta])
        guard
            case .apply(let restored) = pending.decision(
                current: shown, contents: remaining, scanFinished: true, groupsPublished: true)
        else {
            Issue.record("the finished scan did not apply the saved state")
            return
        }
        // U1's fallback: the group and detail routes return to the grid, the missing photo and
        // group place drop, and the filter and order survive.
        #expect(restored.state.route == .grid)
        #expect(restored.state.currentPhoto == nil)
        #expect(restored.state.groupPosition == nil)
        #expect(restored.state.selection == [BrowsingFixtures.alpha])
        #expect(restored.state.filter == .ratedAtLeast(BrowsingFixtures.threeStars))
        #expect(restored.state.order == .fileName)
    }

    @Test func dropsAMissingSelectionItemAtScanEnd() throws {
        var saved = BrowsingFixtures.saved
        saved.route = .grid
        saved.groupPosition = nil
        let restore = PendingBrowsingRestore(saved: saved, shown: shown)
        // gamma, one of the two selected photos, is gone; alpha is still there.
        let partial = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.delta])
        guard
            case .apply(let restored) = restore.decision(
                current: shown, contents: partial, scanFinished: true, groupsPublished: true)
        else {
            Issue.record("the finished scan did not apply the saved state")
            return
        }
        #expect(restored.state.selection == [BrowsingFixtures.alpha])
        #expect(restored.state.currentPhoto == BrowsingFixtures.beta)
        #expect(restored.state.filter == .ratedAtLeast(BrowsingFixtures.threeStars))
        #expect(restored.state.order == .fileName)
    }

    @Test func dropsAfterAnEarlyNavigation() {
        var navigated = shown
        navigated.currentPhoto = BrowsingFixtures.delta
        navigated.route = .detail
        let partial = FolderContents(folder: BrowsingFixtures.folder, photos: [])
        #expect(
            pending.decision(
                current: navigated, contents: partial, scanFinished: false,
                groupsPublished: true) == .drop)
        #expect(
            pending.decision(
                current: navigated, contents: partial, scanFinished: true,
                groupsPublished: true) == .drop)
    }

    @Test func dropsWhenAnotherFolderAnswers() {
        let other = FolderContents(
            folder: FolderIdentity(rawValue: "another-folder"), photos: [BrowsingFixtures.beta])
        #expect(
            pending.decision(
                current: shown, contents: other, scanFinished: true, groupsPublished: true) == .drop
        )
    }

    @Test func aSavedStateWithoutPhotosAppliesAtOnce() {
        let saved = BrowsingState(folder: BrowsingFixtures.folder, route: .grid)
        let restore = PendingBrowsingRestore(saved: saved, shown: shown)
        let empty = FolderContents(folder: BrowsingFixtures.folder, photos: [])
        guard
            case .apply(let restored) = restore.decision(
                current: shown, contents: empty, scanFinished: false, groupsPublished: true)
        else {
            Issue.record("a saved grid with no photo did not apply")
            return
        }
        #expect(restored.state.route == .grid)
        #expect(restored.state.folder == BrowsingFixtures.folder)
    }

    @Test func waitsForGroupingBeforeDroppingASavedGroupView() {
        // The scan has finished and the folder holds the saved group photo, but grouping has not
        // published yet: the saved group key cannot be checked, so the place waits for the
        // folder's first groups instead of dropping on every launch (PRD P0-11, P0-14).
        var saved = BrowsingFixtures.saved
        saved.selection = []
        let restore = PendingBrowsingRestore(saved: saved, shown: shown)
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.gamma])
        #expect(
            restore.decision(
                current: shown, contents: contents, scanFinished: true, groupsPublished: false)
                == .wait)
    }

    @Test func keepsASavedGroupViewOnceGroupingPublishes() throws {
        // The same launch after grouping's time stage published: the saved group still holds the
        // saved photo, so the group route, its key and the photo apply (PRD P0-11, P0-14).
        var saved = BrowsingFixtures.saved
        saved.selection = []
        let restore = PendingBrowsingRestore(saved: saved, shown: shown)
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.gamma],
            groups: BrowsingFixtures.groups)
        guard
            case .apply(let restored) = restore.decision(
                current: shown, contents: contents, scanFinished: true, groupsPublished: true)
        else {
            Issue.record("the first published groups did not restore the saved group view")
            return
        }
        #expect(restored.state.route == .group)
        #expect(restored.state.groupPosition == saved.groupPosition)
        #expect(restored.state.currentPhoto == saved.currentPhoto)
    }

    @Test func dropsASavedGroupViewWhenGroupingPublishedNoGroup() throws {
        // Grouping published and the photo is no longer in a group, so U1's fallback applies:
        // the group route returns to the grid and the place drops (PRD P0-14).
        var saved = BrowsingFixtures.saved
        saved.selection = []
        let restore = PendingBrowsingRestore(saved: saved, shown: shown)
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.gamma])
        guard
            case .apply(let restored) = restore.decision(
                current: shown, contents: contents, scanFinished: true, groupsPublished: true)
        else {
            Issue.record("the finished grouping did not apply the saved state")
            return
        }
        #expect(restored.state.route == .grid)
        #expect(restored.state.groupPosition == nil)
        #expect(restored.state.currentPhoto == saved.currentPhoto)
    }
}
