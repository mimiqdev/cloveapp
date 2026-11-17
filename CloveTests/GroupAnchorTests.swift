import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct GroupAnchorTests {
    /// Issue #309: the split grid draws the same two levels as the Focus View filmstrip. In Group
    /// Focus it shows only the active group's visible members; choosing a member keeps the level,
    /// and folding returns to the folder on the group's stack, in place, without reloading.
    @Test func splitGridGroupFocusScopesToTheActiveGroupAndFoldsBackToItsStack() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let p2678 = try #require(model.photos.first { $0.id.stem == "mmq02678" }?.id)
        let p2695 = try #require(model.photos.first { $0.id.stem == "mmq02695" }?.id)
        let p2696 = try #require(model.photos.first { $0.id.stem == "mmq02696" }?.id)
        let p2698 = try #require(model.photos.first { $0.id.stem == "mmq02698" }?.id)
        let p2699 = try #require(model.photos.first { $0.id.stem == "mmq02699" }?.id)
        let burst2696 = GroupID(rawValue: "burst-2696")
        let burst2678 = GroupID(rawValue: "burst-2678")

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let state = GridAnchorHarnessState(
                model: model, expandedGroup: nil, currentPhoto: p2695)
            let host = UIHostingController(
                rootView: GridAnchorHarness(state: state, theme: theme))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 250, height: 700)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))

            let collectionView = try #require(
                findSubview(ofType: UICollectionView.self, in: window))
            // Timeline: the folder's own photos and its collapsed stacks. Scroll the group's
            // stack on screen the way a tap does before the person opens it.
            #expect(collectionView.numberOfSections == 1)
            let stackPathBefore = try #require(
                indexPath(for: .group(burst2696), in: collectionView, state: state))
            collectionView.scrollToItem(
                at: stackPathBefore, at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            #expect(indexPath(for: .photo(p2695), in: collectionView, state: state) != nil)
            #expect(indexPath(for: .group(burst2678), in: collectionView, state: state) != nil)
            let stackFrameBefore = try #require(
                itemScreenFrame(stackPathBefore, in: collectionView, window: window))
            let folderOffsetBefore = collectionView.contentOffset.y

            // Opening burst-2696 replaces the folder with only that group's visible members.
            state.currentPhoto = p2696
            state.expandedGroup = burst2696
            try await Task.sleep(for: .milliseconds(250))

            let memberCount = try #require(
                state.timeline.activeGroup(with: burst2696)?.visibleMembers.count)
            let viewport = viewportScreenBounds(in: collectionView, window: window)
            #expect(collectionView.numberOfSections == 1)
            #expect(collectionView.numberOfItems(inSection: 0) == memberCount)
            #expect(indexPath(for: .photo(p2696), in: collectionView, state: state) != nil)
            #expect(indexPath(for: .photo(p2698), in: collectionView, state: state) != nil)
            // Neither the folder's neighbouring photos nor the other group draw in Group Focus.
            #expect(indexPath(for: .photo(p2695), in: collectionView, state: state) == nil)
            #expect(indexPath(for: .photo(p2699), in: collectionView, state: state) == nil)
            #expect(indexPath(for: .group(burst2678), in: collectionView, state: state) == nil)
            let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
            #expect(headerFrame.minY >= viewport.top - 0.5)
            #expect(headerFrame.minY - viewport.top <= GridGroupRun.inset + 2)
            #expect(findFoldButton(in: collectionView) != nil)

            // Choosing another member changes the open photo and keeps Group Focus and its place.
            let offsetBeforeMemberChoice = collectionView.contentOffset.y
            state.currentPhoto = p2698
            try await Task.sleep(for: .milliseconds(200))
            #expect(abs(collectionView.contentOffset.y - offsetBeforeMemberChoice) <= 0.5)
            #expect(indexPath(for: .photo(p2695), in: collectionView, state: state) == nil)
            #expect(indexPath(for: .photo(p2698), in: collectionView, state: state) != nil)

            // Folding returns to the folder Timeline on the group's Representative Photo stack,
            // in place and without reloading the folder.
            state.currentPhoto = p2696
            state.expandedGroup = nil
            try await Task.sleep(for: .milliseconds(250))
            #expect(collectionView.numberOfSections == 1)
            #expect(indexPath(for: .photo(p2695), in: collectionView, state: state) != nil)
            #expect(indexPath(for: .group(burst2678), in: collectionView, state: state) != nil)
            let stackPathAfter = try #require(
                indexPath(for: .group(burst2696), in: collectionView, state: state))
            let stackFrameAfter = try #require(
                itemScreenFrame(stackPathAfter, in: collectionView, window: window))
            #expect(abs(collectionView.contentOffset.y - folderOffsetBefore) <= 0.5)
            #expect(abs(stackFrameAfter.minY - stackFrameBefore.minY) <= 0.5)

            // Opening the other group scopes the grid to that group instead.
            state.currentPhoto = p2678
            state.expandedGroup = burst2678
            try await Task.sleep(for: .milliseconds(250))
            #expect(collectionView.numberOfItems(inSection: 0) == 3)
            #expect(indexPath(for: .photo(p2678), in: collectionView, state: state) != nil)
            #expect(indexPath(for: .photo(p2696), in: collectionView, state: state) == nil)
            #expect(indexPath(for: .photo(p2695), in: collectionView, state: state) == nil)
        }
    }

    @Test func standardGridDoesNotFollowOffscreenCurrentPhoto() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let p2678 = try #require(model.photos.first { $0.id.stem == "mmq02678" }?.id)
        let p2713 = try #require(model.photos.first { $0.id.stem == "mmq02713" }?.id)

        let state = GridAnchorHarnessState(
            model: model, expandedGroup: nil, currentPhoto: p2678)
        let host = UIHostingController(
            rootView: GridAnchorHarness(
                state: state, theme: .light, columnCount: 3, followsCurrentPhoto: false))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let initialY = collectionView.contentOffset.y

        state.currentPhoto = p2713
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(collectionView.contentOffset.y - initialY) <= 0.5)
    }

    @Test func filmstripAnchorsGroupExpandFoldAndStillCentersOffscreenNavigation() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let p2695 = try #require(model.photos.first { $0.id.stem == "mmq02695" }?.id)
        let p2696 = try #require(model.photos.first { $0.id.stem == "mmq02696" }?.id)
        let p2697 = try #require(model.photos.first { $0.id.stem == "mmq02697" }?.id)
        let p2713 = try #require(model.photos.first { $0.id.stem == "mmq02713" }?.id)
        let burstID = GroupID(rawValue: "burst-2696")

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let state = FilmstripAnchorHarnessState(
                photos: model.photos, groups: model.groups, thumbnails: model.thumbnails,
                current: p2695, expandedGroup: nil)
            let host = UIHostingController(
                rootView: FilmstripAnchorHarness(state: state, theme: theme))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))

            let scrollView = try #require(findSubview(ofType: UIScrollView.self, in: window))
            let timelineContentWidth = scrollView.contentSize.width
            #expect(timelineContentWidth > 1200)
            let sxTimeline = scrollView.contentOffset.x

            // Selecting burst-2696 in Timeline while stack is already on screen: strip must not jump.
            state.current = p2696
            try await Task.sleep(for: .milliseconds(500))
            #expect(abs(scrollView.contentOffset.x - sxTimeline) <= 0.5)

            // Expanding burst-2696 enters Group Focus (only group members + fold control).
            state.expandedGroup = burstID
            try await Task.sleep(for: .milliseconds(450))
            let focusedWidth = scrollView.contentSize.width
            let focusedMemberCount = try #require(
                state.timeline.activeGroup(with: burstID)?.visibleMembers.count)
            #expect(focusedWidth > CGFloat(focusedMemberCount) * 54)
            #expect(focusedWidth < 300)
            let sxFocused = scrollView.contentOffset.x

            // Switching to the next visible member inside Group Focus does not jump.
            state.current = p2697
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(scrollView.contentOffset.x - sxFocused) <= 0.5)

            // Collapsing back to Timeline exits Group Focus cleanly.
            state.expandedGroup = nil
            state.current = p2696
            try await Task.sleep(for: .milliseconds(500))
            #expect(scrollView.contentSize.width > 1200)
            let sxAfterCollapse = scrollView.contentOffset.x

            // Leaving the collapsed stack back to visible p2695 does not jump.
            state.current = p2695
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(scrollView.contentOffset.x - sxAfterCollapse) <= 0.5)

            // Jumping to an off-screen photo (last photo) still scrolls it into view.
            state.current = p2713
            try await Task.sleep(for: .milliseconds(600))
            #expect(scrollView.contentOffset.x > sxAfterCollapse + 100)
        }
    }

    /// Entering Group Focus starts the run at its count header and fold control, and a group that
    /// fits is reviewable in the pane without scrolling. Folding restores the folder's viewport
    /// and its stack in place (#309).
    @Test func enteringGroupFocusShowsTheFocusedRunFromItsHeaderFor2_3_And10Members()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for memberCount in [2, 3, 10] {
            let (photos, groups, groupID, members) = makeSyntheticGrid(
                beforeCount: 24, groupMemberCount: memberCount, afterCount: 6)
            let beforePhoto = try #require(photos.first?.id)

            let state = GridAnchorHarnessState(
                photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
                expandedGroup: nil, currentPhoto: beforePhoto)
            let host = UIHostingController(
                rootView: GridAnchorHarness(state: state, theme: .light, columnCount: 2))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 250, height: 850)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))

            let collectionView = try #require(
                findSubview(ofType: UICollectionView.self, in: window))
            let stackPath = try #require(
                indexPath(for: .group(groupID), in: collectionView, state: state))
            let stackAttrs = try #require(collectionView.layoutAttributesForItem(at: stackPath))

            // Position the collapsed stack just above the bottom edge of the viewport, so the
            // focused run has to replace the folder's content there.
            let insets = collectionView.adjustedContentInset
            let desiredOffsetY = max(
                -insets.top,
                stackAttrs.frame.maxY + 8 - (collectionView.bounds.height - insets.bottom))
            collectionView.setContentOffset(CGPoint(x: 0, y: desiredOffsetY), animated: false)
            collectionView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))

            let viewport = viewportScreenBounds(in: collectionView, window: window)
            let yBefore = collectionView.contentOffset.y
            let stackFrameBefore = try #require(
                itemScreenFrame(stackPath, in: collectionView, window: window))
            #expect(stackFrameBefore.maxY <= viewport.bottom + 0.5)

            state.currentPhoto = members[0]
            state.expandedGroup = groupID
            try await Task.sleep(for: .milliseconds(250))

            #expect(collectionView.numberOfSections == 1)
            #expect(collectionView.numberOfItems(inSection: 0) == memberCount)
            let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
            let foldButton = try #require(findFoldButton(in: collectionView))
            let foldFrame = foldButton.convert(foldButton.bounds, to: window)
            #expect(headerFrame.minY >= viewport.top - 0.5)
            #expect(headerFrame.minY - viewport.top <= GridGroupRun.inset + 2)
            #expect(foldFrame.minY >= viewport.top - 0.5)
            let lastMemberFrame = try #require(
                itemScreenFrame(
                    IndexPath(item: memberCount - 1, section: 0), in: collectionView,
                    window: window))
            #expect(lastMemberFrame.maxY <= viewport.bottom + 0.5)

            // Folding without a scroll restores the folder's exact viewport and stack place.
            state.currentPhoto = members[0]
            state.expandedGroup = nil
            try await Task.sleep(for: .milliseconds(250))
            let stackPathAfter = try #require(
                indexPath(for: .group(groupID), in: collectionView, state: state))
            let stackFrameAfter = try #require(
                itemScreenFrame(stackPathAfter, in: collectionView, window: window))
            #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)
            #expect(abs(stackFrameAfter.minY - stackFrameBefore.minY) <= 0.5)
        }
    }

    /// A group taller than the pane opens on its first member; choosing a member far down brings
    /// it into view without leaving Group Focus, a mark keeps the pane still, and folding returns
    /// to the folder's stack (#309).
    @Test func overHeightGroupFocusKeepsTheChosenMemberInViewAndFoldsBackToTheStack()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 16, groupMemberCount: 14, afterCount: 6)
        let beforePhoto = try #require(photos.first?.id)

        let state = GridAnchorHarnessState(
            photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
            expandedGroup: nil, currentPhoto: beforePhoto)
        let host = UIHostingController(
            rootView: GridAnchorHarness(state: state, theme: .light, columnCount: 2))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 250, height: 480)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let stackPath = try #require(
            indexPath(for: .group(groupID), in: collectionView, state: state))
        let stackAttrs = try #require(collectionView.layoutAttributesForItem(at: stackPath))
        let insets = collectionView.adjustedContentInset
        let desiredOffsetY = max(
            -insets.top,
            stackAttrs.frame.maxY + 8 - (collectionView.bounds.height - insets.bottom))
        collectionView.setContentOffset(CGPoint(x: 0, y: desiredOffsetY), animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let viewport = viewportScreenBounds(in: collectionView, window: window)
        let yBefore = collectionView.contentOffset.y
        let stackFrameBefore = try #require(
            itemScreenFrame(stackPath, in: collectionView, window: window))

        state.currentPhoto = members[0]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))

        #expect(collectionView.numberOfItems(inSection: 0) == 14)
        let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
        let firstMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 0, section: 0), in: collectionView, window: window))
        #expect(headerFrame.minY >= viewport.top - 0.5)
        #expect(firstMemberFrame.minY >= viewport.top - 0.5)
        #expect(firstMemberFrame.maxY <= viewport.bottom + 0.5)

        // A member far down the run comes into view when it is chosen.
        state.currentPhoto = members[13]
        try await Task.sleep(for: .milliseconds(250))
        let deepMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 13, section: 0), in: collectionView, window: window))
        #expect(deepMemberFrame.minY >= viewport.top - 0.5)
        #expect(deepMemberFrame.maxY <= viewport.bottom + 0.5)
        let offsetAtMember = collectionView.contentOffset.y

        // Marking the open member updates its cell without moving the pane.
        var updatedPhotos = state.photos
        let memberIndex = try #require(updatedPhotos.firstIndex(where: { $0.id == members[13] }))
        updatedPhotos[memberIndex].marks.rating = try #require(Rating(rawValue: 4))
        state.photos = updatedPhotos
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(collectionView.contentOffset.y - offsetAtMember) <= 0.5)

        // Folding returns to the folder's own viewport with the group's stack where it was.
        state.currentPhoto = members[0]
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(250))
        let stackPathAfter = try #require(
            indexPath(for: .group(groupID), in: collectionView, state: state))
        let stackFrameAfter = try #require(
            itemScreenFrame(stackPathAfter, in: collectionView, window: window))
        #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)
        #expect(abs(stackFrameAfter.minY - stackFrameBefore.minY) <= 0.5)
    }

    /// Leaving Group Focus for the following Timeline photo, as auto-advance does, brings that
    /// photo into view instead of leaving it clipped behind the group's stack.
    @Test func leavingGroupFocusForTheFollowingPhotoShowsIt() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 20, groupMemberCount: 4, afterCount: 10)
        let beforePhoto = try #require(photos.first?.id)
        let afterPhoto = try #require(photos.dropFirst(24).first?.id)

        let state = GridAnchorHarnessState(
            photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
            expandedGroup: nil, currentPhoto: beforePhoto)
        let host = UIHostingController(
            rootView: GridAnchorHarness(state: state, theme: .light, columnCount: 2))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 250, height: 600)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let stackPath = try #require(
            indexPath(for: .group(groupID), in: collectionView, state: state))
        let stackAttrs = try #require(collectionView.layoutAttributesForItem(at: stackPath))
        let insets = collectionView.adjustedContentInset
        let desiredOffsetY = max(
            -insets.top,
            stackAttrs.frame.maxY + 8 - (collectionView.bounds.height - insets.bottom))
        collectionView.setContentOffset(CGPoint(x: 0, y: desiredOffsetY), animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        state.currentPhoto = members[0]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))

        state.currentPhoto = afterPhoto
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(250))

        let viewport = viewportScreenBounds(in: collectionView, window: window)
        let afterPath = try #require(
            indexPath(for: .photo(afterPhoto), in: collectionView, state: state))
        let afterFrame = try #require(
            itemScreenFrame(afterPath, in: collectionView, window: window))
        #expect(afterFrame.minY >= viewport.top - 0.5)
        #expect(afterFrame.maxY <= viewport.bottom + 0.5)
    }

    private func viewportScreenBounds(
        in collectionView: UICollectionView, window: UIWindow
    ) -> (top: CGFloat, bottom: CGFloat) {
        let insets = collectionView.adjustedContentInset
        let visibleRect = CGRect(
            x: 0,
            y: collectionView.contentOffset.y + insets.top,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height - insets.top - insets.bottom)
        let screenRect = collectionView.convert(visibleRect, to: window)
        return (screenRect.minY, screenRect.maxY)
    }

    private func makeSyntheticGrid(
        beforeCount: Int, groupMemberCount: Int, afterCount: Int
    ) -> (photos: [GridPhoto], groups: [BrowsingGroup], groupID: GroupID, members: [PhotoIdentity])
    {
        let folder = TestLibrary.sampleFolderKey
        let baseDate = Date(timeIntervalSince1970: 1_760_000_000)
        let total = beforeCount + groupMemberCount + afterCount
        var photos: [GridPhoto] = []
        photos.reserveCapacity(total)
        for index in 0..<total {
            let stem = String(format: "SYN%05d", index)
            let id = PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100SYN", stem: stem)
            photos.append(
                GridPhoto(
                    id: id,
                    fileName: "\(stem).ARW",
                    time: .known(
                        PhotoTime(
                            captureTime: baseDate.addingTimeInterval(Double(index) * 2),
                            hasUTCOffset: true)),
                    marks: PhotoMarks()))
        }
        let members = Array(photos[beforeCount..<(beforeCount + groupMemberCount)].map(\.id))
        let groupID = GroupID(rawValue: "syn-group")
        let groups = [BrowsingGroup(id: groupID, members: members)]
        return (photos, groups, groupID, members)
    }

    private func indexPath(
        for cellID: GridCellItem.ID, in collectionView: UICollectionView,
        state: GridAnchorHarnessState
    ) -> IndexPath? {
        for (sectionIndex, section) in state.display.sections.enumerated() {
            if let itemIndex = section.cells.firstIndex(where: { $0.id == cellID }) {
                return IndexPath(item: itemIndex, section: sectionIndex)
            }
        }
        return nil
    }

    private func findFoldButton(in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == "clove.grid.group.fold" { return root }
        for subview in root.subviews {
            if let found = findFoldButton(in: subview) { return found }
        }
        return nil
    }

    private func itemScreenFrame(
        _ indexPath: IndexPath, in collectionView: UICollectionView, window: UIWindow
    ) -> CGRect? {
        guard let attrs = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        return collectionView.convert(attrs.frame, to: window)
    }

    private func groupHeaderFrame(
        in collectionView: UICollectionView, window: UIWindow
    ) -> CGRect? {
        for view in collectionView.visibleSupplementaryViews(ofKind: GridGroupHeader.kind) {
            return view.convert(view.bounds, to: window)
        }
        return nil
    }

    private func findSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let found = findSubview(ofType: type, in: subview) { return found }
        }
        return nil
    }
}

@MainActor
@Observable
private final class GridAnchorHarnessState {
    var photos: [GridPhoto]
    let groups: [BrowsingGroup]
    let thumbnails: any GridThumbnailSource
    var expandedGroup: GroupID?
    var currentPhoto: PhotoIdentity?

    /// The two-level Detail model the split grid draws from.
    var timeline: DetailTimeline {
        DetailTimeline(photos: photos, groups: groups, groupsEnabled: true)
    }

    /// The grid's cells at the current level: the folder's run, or Group Focus's single run.
    var display: GridDisplay {
        if let focused = expandedGroup.flatMap({ timeline.activeGroup(with: $0) }) {
            return GridDisplay(focusing: focused)
        }
        return GridDisplay(photos: photos, groups: groups, groupsEnabled: true)
    }

    init(
        photos: [GridPhoto], groups: [BrowsingGroup], thumbnails: any GridThumbnailSource,
        expandedGroup: GroupID?, currentPhoto: PhotoIdentity?
    ) {
        self.photos = photos
        self.groups = groups
        self.thumbnails = thumbnails
        self.expandedGroup = expandedGroup
        self.currentPhoto = currentPhoto
    }

    convenience init(model: BrowsingModel, expandedGroup: GroupID?, currentPhoto: PhotoIdentity?) {
        self.init(
            photos: model.photos, groups: model.groups, thumbnails: model.thumbnails,
            expandedGroup: expandedGroup, currentPhoto: currentPhoto)
    }
}

private struct GridAnchorHarness: View {
    let state: GridAnchorHarnessState
    let theme: CloveTheme
    var columnCount: Int? = 2
    var followsCurrentPhoto = true

    var body: some View {
        let display = state.display
        GridCollectionView(
            sections: display.sections,
            currentPhoto: state.currentPhoto,
            groups: state.groups,
            shownPhotos: Set(state.photos.map(\.id)),
            selection: [],
            thumbnails: state.thumbnails,
            columnCount: columnCount,
            highlightsCurrentPhoto: followsCurrentPhoto,
            followsCurrentPhoto: followsCurrentPhoto,
            foldExpandedGroup: { _ in state.expandedGroup = nil },
            openPhoto: { state.currentPhoto = $0 },
            openGroup: { group in
                state.expandedGroup = group
            },
            beginSelection: { _ in },
            toggleSelection: { _ in }
        )
        .background(theme.tokens.canvas.color)
        .environment(\.cloveTheme, theme)
    }
}

@MainActor
@Observable
private final class FilmstripAnchorHarnessState {
    let photos: [GridPhoto]
    let groups: [BrowsingGroup]
    let thumbnails: any GridThumbnailSource
    var current: PhotoIdentity?
    var expandedGroup: GroupID?

    var timeline: DetailTimeline {
        DetailTimeline(photos: photos, groups: groups, groupsEnabled: true)
    }

    init(
        photos: [GridPhoto], groups: [BrowsingGroup], thumbnails: any GridThumbnailSource,
        current: PhotoIdentity?, expandedGroup: GroupID?
    ) {
        self.photos = photos
        self.groups = groups
        self.thumbnails = thumbnails
        self.current = current
        self.expandedGroup = expandedGroup
    }
}

private struct FilmstripAnchorHarness: View {
    let state: FilmstripAnchorHarnessState
    let theme: CloveTheme

    var body: some View {
        let timeline = state.timeline
        DetailFilmstrip(
            timeline: timeline,
            expandedGroup: state.expandedGroup.flatMap { timeline.activeGroup(with: $0) },
            current: state.current,
            thumbnails: state.thumbnails,
            openPhoto: {
                state.expandedGroup = nil
                state.current = $0
            },
            selectGroupPhoto: { state.current = $0 },
            expandGroup: { state.expandedGroup = $0 },
            collapseGroup: { state.expandedGroup = nil }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.tokens.stage.color)
        .environment(\.cloveTheme, theme)
    }
}
