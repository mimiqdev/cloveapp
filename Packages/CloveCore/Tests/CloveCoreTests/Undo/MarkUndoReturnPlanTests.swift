import Testing

import CloveCore

/// Where each screen returns after an undo (PRD P0-05's Undo row; PRD P0-09, P0-12).
///
/// The names stay inside this suite, so the tests share no free symbols with the rest of the
/// target.
@Suite struct MarkUndoReturnPlanTests {
    /// The folder every fixture photo belongs to; identity only, never a path.
    static let folder = FolderIdentity(rawValue: "undo-return-folder")

    /// One photo of the fixture folder.
    static func photo(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: stem)
    }

    /// The photo the undo returns to.
    static let marked = photo("marked")

    /// A photo that is not in the group.
    static let ungrouped = photo("ungrouped")

    /// The group holding the marked photo.
    static let burst = GroupID(rawValue: "burst")

    /// A folder that holds both photos and one group around the marked photo.
    static var contents: FolderContents {
        FolderContents(
            folder: folder, photos: [marked, ungrouped],
            groups: [BrowsingGroup(id: burst, members: [marked])])
    }

    @Test func detailReturnsToThePhoto() {
        let place = MarkUndoReturnPlan.place(
            from: .detail, photo: Self.marked, in: Self.contents)
        #expect(place == .detail(photo: Self.marked))
    }

    @Test func detailDoesNotTakeAGroupedPhotoIntoItsGroup() {
        // Detail has no group view, so the photo comes back on the screen that asked even when
        // grouping also holds it (PRD P0-05, PRD P0-11).
        let place = MarkUndoReturnPlan.place(
            from: .detail, photo: Self.marked, in: Self.contents)
        #expect(place == .detail(photo: Self.marked))
    }

    @Test func groupViewReturnsToThePhotoInItsGroup() {
        let place = MarkUndoReturnPlan.place(
            from: .group, photo: Self.marked, in: Self.contents)
        #expect(place == .group(group: Self.burst, photo: Self.marked))
    }

    @Test func groupViewFallsBackToTheGridForAnUngroupedPhoto() {
        let place = MarkUndoReturnPlan.place(
            from: .group, photo: Self.ungrouped, in: Self.contents)
        #expect(place == .grid(photo: Self.ungrouped))
    }

    @Test func gridBringsThePhotoIntoView() {
        let place = MarkUndoReturnPlan.place(
            from: .grid, photo: Self.ungrouped, in: Self.contents)
        #expect(place == .grid(photo: Self.ungrouped))
    }

    @Test func entryAndSettingsStayWhereTheyAre() {
        let place = MarkUndoReturnPlan.place(
            from: .elsewhere, photo: Self.marked, in: Self.contents)
        #expect(place == .stay)
    }

    @Test func missingPhotoStaysWhereTheViewIs() {
        // A rescan or a move can drop the photo the step wanted to return to (PRD P0-01,
        // PRD Move rejects); there is no photo to show and no cell to scroll to.
        let emptied = FolderContents(folder: Self.folder, photos: [], groups: [])
        for screen in [
            MarkUndoReturnScreen.detail, .group, .grid, .elsewhere,
        ] {
            #expect(
                MarkUndoReturnPlan.place(
                    from: screen, photo: Self.marked, in: emptied) == .stay)
        }
    }
}
