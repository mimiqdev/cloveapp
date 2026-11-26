import CloveCore

/// Coordinates dismissing the Grid Filter popover before presenting `MetadataFilterSheet`.
///
/// Presenting a sheet in the same transaction that dismisses a popover on the same presenting
/// view controller causes UIKit to drop the sheet while the popover dismissal transition is active.
/// Tracking the pending handoff lets `GridScreen` wait until the popover finishes disappearing
/// before presenting the sheet, and drop stale requests on folder change or scene deactivation.
struct GridFilterSheetHandoff: Equatable {
    private(set) var showsFilters = false
    private(set) var pendingMetadataFiltersAfterPopover = false
    private var pendingFolder: FolderIdentity?

    mutating func setFiltersPresented(_ presented: Bool) {
        showsFilters = presented
        if presented {
            cancelPendingMetadataFilters()
        }
    }

    mutating func toggleFilters() {
        setFiltersPresented(!showsFilters)
    }

    mutating func requestMetadataFiltersFromPopover(folder: FolderIdentity?) {
        showsFilters = false
        guard let folder else {
            cancelPendingMetadataFilters()
            return
        }
        pendingMetadataFiltersAfterPopover = true
        pendingFolder = folder
    }

    mutating func cancelPendingMetadataFilters() {
        pendingMetadataFiltersAfterPopover = false
        pendingFolder = nil
    }

    mutating func dismissFiltersAndCancelPending() {
        showsFilters = false
        cancelPendingMetadataFilters()
    }

    mutating func consumePendingMetadataFiltersOnPopoverDisappear(
        currentFolder: FolderIdentity?,
        isSceneActive: Bool,
        canPresent: Bool
    ) -> Bool {
        guard pendingMetadataFiltersAfterPopover else { return false }
        let expectedFolder = pendingFolder
        cancelPendingMetadataFilters()
        guard isSceneActive,
            canPresent,
            !showsFilters,
            let expectedFolder,
            currentFolder == expectedFolder
        else {
            return false
        }
        return true
    }
}
