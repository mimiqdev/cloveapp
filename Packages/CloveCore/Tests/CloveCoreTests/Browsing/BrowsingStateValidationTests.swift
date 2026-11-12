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
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.beta])
        let restored = saved.restored(from: .available(contents))
        #expect(restored.state.route == .grid)
        #expect(restored.state.currentPhoto == nil)
    }

    @Test func presentPhotoKeepsTheDetailRoute() {
        var saved = BrowsingFixtures.saved
        saved.route = .detail
        let restored = saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state.route == .detail)
        #expect(restored.state.currentPhoto == BrowsingFixtures.beta)
    }

    @Test func selectionDropsMissingPhotos() {
        var saved = BrowsingFixtures.saved
        saved.route = .grid
        saved.selection = [BrowsingFixtures.alpha, BrowsingFixtures.gamma, BrowsingFixtures.delta]
        let contents = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [BrowsingFixtures.alpha, BrowsingFixtures.delta])
        let restored = saved.restored(from: .available(contents))
        #expect(restored.state.selection == [BrowsingFixtures.alpha, BrowsingFixtures.delta])
    }

    @Test func settingsWithoutAFolderAreRestored() {
        var saved = BrowsingState.entry
        saved.route = .settings
        let restored = saved.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state.route == .settings)
        #expect(restored.state.folder == nil)
    }

    @Test func settingsRestoredOverAnotherFolderDropThatFolder() {
        var saved = BrowsingFixtures.saved
        saved.route = .settings
        let other = FolderContents(
            folder: FolderIdentity(rawValue: "another-folder"), photos: [], groups: [])
        let restored = saved.restored(from: .available(other))
        #expect(restored.state.route == .settings)
        #expect(restored.state.folder == nil)
    }

    @Test func entryStaysAtEntry() {
        let restored = BrowsingState.entry.restored(from: .available(BrowsingFixtures.contents))
        #expect(restored.state == .entry)
    }
}
