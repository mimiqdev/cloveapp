import CloveCore
import SwiftUI

/// The 30% filtered folder grid shown beside the photo in Photo Preview on both iPad and expanded
/// Duo. Groups stay collapsed except the current photo's group, which expands inline without a
/// redundant folder header (#225, #256).
struct SplitFolderGridPane: View {
    let browsing: BrowsingModel
    let thumbnails: any GridThumbnailSource
    let similarGroupsEnabled: Bool
    @Binding var foldedGroup: GroupID?
    let openPhoto: (PhotoIdentity) -> Void

    @Environment(\.isDuoExpanded) private var isDuoExpanded

    private var gridDisplay: GridDisplay {
        let currentGroup = browsing.currentGroup
        return GridDisplay(
            photos: browsing.photos,
            groups: browsing.groups,
            groupsEnabled: similarGroupsEnabled && browsing.readingProgress == nil,
            display: .collapsed,
            expandedGroup: foldedGroup != currentGroup?.id ? currentGroup?.id : nil)
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
                    foldExpandedGroup: { foldedGroup = $0 },
                    openPhoto: openPhoto,
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

    private func openGroup(_ id: GroupID) {
        if browsing.currentGroup?.id == id {
            foldedGroup = nil
            return
        }
        guard let group = browsing.groups.first(where: { $0.id == id }) else { return }
        let visible = group.visible(in: Set(browsing.photos.map(\.id)))
        if let first = visible.members.first(where: { browsing.shownMarks(for: $0).isUnmarked })
            ?? visible.members.first
        {
            openPhoto(first)
        }
    }
}
