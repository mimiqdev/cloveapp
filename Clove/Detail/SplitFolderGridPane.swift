import CloveCore
import SwiftUI

/// The 30% filtered folder grid shown beside the photo in Photo Preview on both iPad and expanded
/// Duo. Groups follow `browsing.expandedGroup`: collapsed stacks when nil (highlighting the stack
/// containing `currentPhoto`), or the expanded group inline when active (issue #304, decision 6).
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
        similarGroupsEnabled && browsing.readingProgress == nil
    }

    private var timeline: DetailTimeline {
        DetailTimeline(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: groupsEnabled)
    }

    private var activeExpandedGroup: ActiveBrowsingGroup? {
        guard let expanded = browsing.expandedGroup else { return nil }
        return timeline.activeGroup(with: expanded)
    }

    private var gridDisplay: GridDisplay {
        GridDisplay(
            photos: browsing.photos,
            groups: browsing.groups,
            groupsEnabled: groupsEnabled,
            expandedGroup: activeExpandedGroup?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let progress = browsing.readingProgress {
                ProgressLine(
                    progress: progress.total > 0
                        ? Double(progress.read) / Double(progress.total) : 0)
            } else if browsing.isFindingSimilarShots, similarGroupsEnabled {
                ProgressLine(progress: 1, tone: .grouping)
            }
            if !gridDisplay.cells.isEmpty || browsing.isFolderOpening {
                GridCollectionView(
                    sections: gridDisplay.sections,
                    currentPhoto: browsing.state.currentPhoto,
                    groups: browsing.groups,
                    shownPhotos: Set(browsing.photos.map(\.id)),
                    selection: [],
                    thumbnails: thumbnails,
                    isSelectingEmpty: false,
                    placeholderCount: browsing.readingProgress.map {
                        $0.total == 0 ? 9 : max($0.total - $0.read, 0)
                    } ?? 0,
                    columnCount: 2,
                    highlightsCurrentPhoto: true,
                    followsCurrentPhoto: true,
                    foldExpandedGroup: { _ in collapseGroup() },
                    openPhoto: { tapped in
                        if let activeExpandedGroup,
                            activeExpandedGroup.visibleMembers.contains(where: { $0.id == tapped })
                        {
                            selectGroupPhoto(tapped)
                        } else {
                            openPhoto(tapped)
                        }
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
