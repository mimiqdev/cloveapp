import Testing

import CloveCore

/// Restore validation: a saved state survives only where the folder still holds it, and an
/// unavailable folder starts entry with its reason (PRD P0-02, P0-13, P0-14).
@Suite struct BrowsingStateValidationTests {
    @Test func availableFolderKeepsTheWholeState() {
        let restored = BrowsingFixtures.saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state == BrowsingFixtures.saved)
        #expect(restored.folderFailure == nil)
    }

    @Test func unavailableFolderStartsAtEntryAndKeepsTheReason() {
        let failure = BrowsingFixtures.permissionDenied
        let restored = BrowsingFixtures.saved.restored(from: .unavailable(failure))
        #expect(restored.state == .entry)
        // PRD P0-02 asks for an explicit message instead of a silent failure; entry shows this.
        #expect(restored.folderFailure == failure)
    }

    @Test func stateSavedForAnotherFolderStartsAtEntry() {
        let other = FolderContents(
            folder: FolderIdentity(rawValue: "another-folder"),
            photos: [BrowsingFixtures.alpha],
            groups: [])
        let restored = BrowsingFixtures.saved.restored(from: .available(other))
        #expect(restored.state == .entry)
        #expect(restored.folderFailure == nil)
    }

    @Test func missingPhotoFallsBackToTheGrid() {
        var saved = BrowsingFixtures.saved
        saved.route = .detail
        saved.currentPhoto = BrowsingFixtures.gamma
        saved.groupPosition = nil
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta])
        let restored = saved.restored(from: .available(contents))
        #expect(restored.state.route == .grid)
        #expect(restored.state.currentPhoto == nil)
    }

    @Test func presentPhotoKeepsTheDetailRoute() {
        let restored = BrowsingFixtures.saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state.route == .group)
        #expect(restored.state.currentPhoto == BrowsingFixtures.beta)
    }

    @Test func selectionDropsMissingPhotos() {
        var saved = BrowsingFixtures.saved
        saved.route = .grid
        saved.groupPosition = nil
        saved.selection = [BrowsingFixtures.alpha, BrowsingFixtures.gamma, BrowsingFixtures.delta]
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.delta])
        let restored = saved.restored(from: .available(contents))
        #expect(restored.state.selection == [BrowsingFixtures.alpha, BrowsingFixtures.delta])
    }

    @Test func vanishedGroupFallsBackToTheGroupHoldingTheSavedPhoto() {
        var saved = BrowsingFixtures.saved
        saved.groupPosition = BrowsingGroupPosition(
            group: BrowsingFixtures.vanishedBurst, photo: BrowsingFixtures.beta)
        let restored = saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(
            restored.state.groupPosition
                == BrowsingGroupPosition(
                    group: BrowsingFixtures.burst, photo: BrowsingFixtures.beta))
        // The same photo stays on screen, in the group that now holds it.
        #expect(restored.state.route == .group)
    }

    @Test func vanishedGroupWithoutItsPhotoFallsBackToTheGrid() {
        var saved = BrowsingFixtures.saved
        saved.groupPosition = BrowsingGroupPosition(
            group: BrowsingFixtures.vanishedBurst, photo: BrowsingFixtures.delta)
        let restored = saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state.groupPosition == nil)
        #expect(restored.state.route == .grid)
    }

    @Test func groupThatSplitAwayTheSavedPhotoFallsBackToItsNewGroup() {
        var saved = BrowsingFixtures.saved
        saved.groupPosition = BrowsingGroupPosition(
            group: BrowsingFixtures.burst, photo: BrowsingFixtures.delta)
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta, BrowsingFixtures.delta],
            groups: [
                BrowsingGroup(id: BrowsingFixtures.burst, members: [BrowsingFixtures.alpha]),
                BrowsingGroup(
                    id: BrowsingFixtures.vanishedBurst, members: [BrowsingFixtures.delta]),
            ])
        let restored = saved.restored(from: .available(contents))
        #expect(
            restored.state.groupPosition
                == BrowsingGroupPosition(
                    group: BrowsingFixtures.vanishedBurst, photo: BrowsingFixtures.delta))
        #expect(restored.state.route == .group)
    }

    @Test func groupRouteWithoutASavedPositionFallsBackToTheGrid() {
        var saved = BrowsingFixtures.saved
        saved.groupPosition = nil
        let restored = saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state.route == .grid)
    }

    @Test func entryStaysAtEntry() {
        let restored = BrowsingState.entry.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state == .entry)
    }
}
