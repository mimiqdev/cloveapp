/// The screen an undo was asked from, which decides where the view goes back to (PRD P0-05).
///
/// PRD P0-05's Undo row reads "Undoing after auto-advance returns to the photo whose mark was
/// undone", and the toolbar Undo belongs to detail, the group view and the grid (PRD Detail and
/// marking; PRD P0-12). Which screen returns where therefore depends on the screen that took the
/// request, not on the photo alone.
public enum MarkUndoReturnScreen: Hashable, Sendable {
    /// The single-photo detail screen (PRD P0-04).
    case detail
    /// A similar group's view (PRD P0-12).
    case group
    /// The grid (PRD Grid).
    case grid
    /// A screen that shows no photo: entry or settings (PRD P0-13).
    case elsewhere
}

/// What the browsing view shows after an undo or redo (PRD P0-05's Undo row; PRD P0-12).
public enum MarkUndoReturnPlace: Hashable, Sendable {
    /// Show the photo in detail, even when the current filter hides it (PRD P0-05).
    case detail(photo: PhotoIdentity)
    /// Show the photo in the group that holds it (PRD P0-12: a finishing action is undone in its
    /// group, and a group that completed can come back).
    case group(group: GroupID, photo: PhotoIdentity)
    /// Bring the photo into view in the grid, which is where a batch is undone (PRD P0-09).
    case grid(photo: PhotoIdentity)
    /// Leave the screen where it is: an entry or settings screen shows no photo to return to.
    case stay
}

/// Decides where a step returns the view after an undo or redo (PRD P0-05's Undo row).
///
/// The rule reads only the screen that asked and what the open folder holds now, so it is pure
/// and testable, and the browsing model applies the answer to its own state:
///
/// - **Detail** returns to the photo, whether or not the current filter still shows it. PRD
///   Auto-advance moves the view on after a mark, and the PRD requires undo to come back to the
///   photo whose mark it restored.
/// - **The group view** returns to the photo in its group, so undoing a finishing action reopens
///   the group that completed and moved the view on (PRD P0-12). A photo grouping no longer puts
///   in a group falls back to the grid.
/// - **The grid** brings the photo into view; a batch is one undo step from the grid
///   (PRD P0-09).
/// - **Entry and settings** stay where they are, because neither shows a photo.
///
/// A photo the folder no longer holds, as after a rescan or a move, leaves the view where it is:
/// there is no photo to show and no place to scroll to (PRD P0-01, PRD Move rejects).
public enum MarkUndoReturnPlan {
    /// The place the supplied screen returns to for one step (PRD P0-05).
    ///
    /// - Parameters:
    ///   - screen: The screen the undo was asked from.
    ///   - photo: The photo the step returned to, C5's `photoToReturnTo` (PRD P0-05).
    ///   - contents: What the open folder holds now, for the photo's group and availability
    ///     (PRD P0-11, P0-14).
    public static func place(
        from screen: MarkUndoReturnScreen,
        photo: PhotoIdentity,
        in contents: FolderContents
    ) -> MarkUndoReturnPlace {
        guard contents.photos.contains(photo) else { return .stay }
        switch screen {
        case .detail:
            return .detail(photo: photo)
        case .group:
            guard let group = contents.group(containing: photo) else {
                return .grid(photo: photo)
            }
            return .group(group: group.id, photo: photo)
        case .grid:
            return .grid(photo: photo)
        case .elsewhere:
            return .stay
        }
    }
}
