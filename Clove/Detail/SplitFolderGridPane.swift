import CloveCore
import SwiftUI

/// The 30% filtered folder grid shown beside the photo in Photo Preview on both iPad and expanded
/// Duo. It draws the same two levels as Focus View's filmstrip (issue #304, #309): the full folder
/// with collapsed group stacks when `browsing.expandedGroup` is nil, or only the focused group's
/// visible members when it is set. A member tap keeps Group Focus; the header's fold control
/// returns to Timeline on the group's Representative Photo.
struct SplitFolderGridPane: View {
    let browsing: BrowsingModel
    let thumbnails: any GridThumbnailSource
    let similarGroupsEnabled: Bool
    let openPhoto: (PhotoIdentity) -> Void
    let selectGroupPhoto: (PhotoIdentity) -> Void
    let openGroup: (GroupID) -> Void
    let collapseGroup: () -> Void

    @Environment(\.isDuoExpanded) private var isDuoExpanded

    private var groupsEnabled: Bool {
        similarGroupsEnabled && !browsing.isScanning
    }

    private var timeline: DetailTimeline {
        DetailTimeline(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: groupsEnabled)
    }

    private var activeExpandedGroup: ActiveBrowsingGroup? {
        guard let expanded = browsing.expandedGroup else { return nil }
        return timeline.activeGroup(with: expanded)
    }

    private func gridDisplay(focused: ActiveBrowsingGroup?) -> GridDisplay {
        if let focused { return GridDisplay(focusing: focused) }
        return GridDisplay(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: groupsEnabled)
    }

    var body: some View {
        let focused = activeExpandedGroup
        let display = gridDisplay(focused: focused)
        VStack(spacing: 0) {
            if let progress = browsing.visibleReadingProgress {
                ProgressLine(
                    progress: progress.total > 0
                        ? Double(progress.read) / Double(progress.total) : 0)
            }
            if !display.cells.isEmpty || browsing.isFolderOpening {
                GridCollectionView(
                    sections: display.sections,
                    currentPhoto: browsing.state.currentPhoto,
                    groups: browsing.groups,
                    shownPhotos: Set(browsing.photos.map(\.id)),
                    selection: [],
                    thumbnails: thumbnails,
                    isSelectingEmpty: false,
                    placeholderCount: browsing.visibleReadingProgress.map {
                        $0.total == 0 ? 9 : max($0.total - $0.read, 0)
                    } ?? 0,
                    columnCount: 2,
                    highlightsCurrentPhoto: true,
                    followsCurrentPhoto: true,
                    foldExpandedGroup: { _ in collapseGroup() },
                    openPhoto: { tapped in
                        // Group Focus draws only the active group's members, so a tile there is
                        // always another member; Timeline tiles open their photo.
                        if focused == nil { openPhoto(tapped) } else { selectGroupPhoto(tapped) }
                    },
                    openGroup: openGroup,
                    beginSelection: { _ in },
                    toggleSelection: { _ in }
                )
                .opacity(browsing.folderLocationLoss == nil ? 1 : 0.35)
            }
        }
        .background(Color.clove.bg.canvas)
        .ignoresSafeArea(.container, edges: isDuoExpanded ? .bottom : [])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.photoGrid")
    }
}
