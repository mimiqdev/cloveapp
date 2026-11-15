import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct GroupAnchorTests {
    @Test func duoGridAnchorsGroupExpandFoldAndStillCentersOffscreenNavigation() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let p2678 = try #require(model.photos.first { $0.id.stem == "mmq02678" }?.id)
        let p2695 = try #require(model.photos.first { $0.id.stem == "mmq02695" }?.id)
        let p2696 = try #require(model.photos.first { $0.id.stem == "mmq02696" }?.id)
        let p2698 = try #require(model.photos.first { $0.id.stem == "mmq02698" }?.id)
        let p2699 = try #require(model.photos.first { $0.id.stem == "mmq02699" }?.id)
        let p2713 = try #require(model.photos.first { $0.id.stem == "mmq02713" }?.id)

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
            collectionView.scrollToItem(
                at: IndexPath(item: 16, section: 0), at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))

            let yBefore = collectionView.contentOffset.y
            let f2695Before = try #require(
                itemScreenFrame(IndexPath(item: 15, section: 0), in: collectionView, window: window)
            )
            let coverBefore = try #require(
                itemScreenFrame(IndexPath(item: 16, section: 0), in: collectionView, window: window)
            )

            // Expand burst-2696 in place: preceding cell stays put and header aligns with old cover.
            state.currentPhoto = p2696
            state.expandedGroup = GroupID(rawValue: "burst-2696")
            try await Task.sleep(for: .milliseconds(250))

            let yExpanded = collectionView.contentOffset.y
            let f2695Expanded = try #require(
                itemScreenFrame(IndexPath(item: 15, section: 0), in: collectionView, window: window)
            )
            let headerExpanded = try #require(groupHeaderFrame(in: collectionView, window: window))

            #expect(abs(yExpanded - yBefore) <= 0.5)
            #expect(abs(f2695Expanded.minY - f2695Before.minY) <= 0.5)
            #expect(abs(headerExpanded.minY - coverBefore.minY) <= 0.5)

            // Move to 3rd member (still on screen) and fold back: stack replaces header with 0 jump.
            state.currentPhoto = p2698
            try await Task.sleep(for: .milliseconds(200))
            let yAt2698 = collectionView.contentOffset.y
            #expect(abs(yAt2698 - yBefore) <= 0.5)

            state.expandedGroup = nil
            try await Task.sleep(for: .milliseconds(250))

            let yFolded = collectionView.contentOffset.y
            let f2695Folded = try #require(
                itemScreenFrame(IndexPath(item: 15, section: 0), in: collectionView, window: window)
            )
            let coverFolded = try #require(
                itemScreenFrame(IndexPath(item: 16, section: 0), in: collectionView, window: window)
            )

            #expect(abs(yFolded - yBefore) <= 0.5)
            #expect(abs(f2695Folded.minY - f2695Before.minY) <= 0.5)
            #expect(abs(coverFolded.minY - headerExpanded.minY) <= 0.5)

            // Leaving the group for a visible neighbor photo keeps the viewport anchored.
            state.currentPhoto = p2696
            state.expandedGroup = GroupID(rawValue: "burst-2696")
            try await Task.sleep(for: .milliseconds(250))
            let yBeforeLeave = collectionView.contentOffset.y
            state.currentPhoto = p2699
            state.expandedGroup = nil
            try await Task.sleep(for: .milliseconds(250))
            #expect(abs(collectionView.contentOffset.y - yBeforeLeave) <= 0.5)

            // Jumping to an off-screen photo still brings it into view.
            state.currentPhoto = p2713
            try await Task.sleep(for: .milliseconds(250))
            let p2713Path = IndexPath(item: 31, section: 0)
            #expect(collectionView.indexPathsForVisibleItems.contains(p2713Path))

            // Expanding burst-2678 at the very top of the folder keeps its header on screen.
            collectionView.setContentOffset(
                CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
            collectionView.layoutIfNeeded()
            state.currentPhoto = p2678
            state.expandedGroup = GroupID(rawValue: "burst-2678")
            try await Task.sleep(for: .milliseconds(250))
            let topHeader = try #require(groupHeaderFrame(in: collectionView, window: window))
            #expect(topHeader.minY >= 0)
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

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let state = FilmstripAnchorHarnessState(
                photos: model.photos, groups: model.groups, thumbnails: model.thumbnails,
                current: p2695, isFolded: false)
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
            let sxCollapsed = scrollView.contentOffset.x

            // Enter burst-2696 while stack is already on screen: strip must not jump.
            state.current = p2696
            try await Task.sleep(for: .milliseconds(500))
            let sxExpanded = scrollView.contentOffset.x
            #expect(abs(sxExpanded - sxCollapsed) <= 0.5)

            // Switching to the next visible member inside the expanded group does not jump.
            state.current = p2697
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(scrollView.contentOffset.x - sxCollapsed) <= 0.5)

            // Folding while the group is on screen keeps the offset steady.
            state.isFolded = true
            try await Task.sleep(for: .milliseconds(450))
            let sxFolded = scrollView.contentOffset.x
            #expect(abs(sxFolded - sxCollapsed) <= 0.5)

            // Unfolding while the stack is on screen keeps the offset steady.
            state.isFolded = false
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(scrollView.contentOffset.x - sxCollapsed) <= 0.5)

            // Leaving the group back to visible p2695 does not jump.
            state.current = p2695
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(scrollView.contentOffset.x - sxCollapsed) <= 0.5)

            // Jumping to an off-screen photo (last photo) still scrolls it into view.
            state.current = p2713
            try await Task.sleep(for: .milliseconds(600))
            #expect(scrollView.contentOffset.x > sxCollapsed + 100)
        }
    }

    @Test func expandingGroupNearBottomRevealsRunWithMinimumScrollFor2_3_And10PlusMembers()
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

            // Position the collapsed stack just above the bottom edge of the viewport so expanding
            // pushes its members below the visible bounds.
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

            // Expand the group at its first member.
            state.currentPhoto = members[0]
            state.expandedGroup = groupID
            try await Task.sleep(for: .milliseconds(250))

            let yExpanded = collectionView.contentOffset.y
            let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
            let foldButton = try #require(findFoldButton(in: collectionView))
            let foldFrame = foldButton.convert(foldButton.bounds, to: window)
            let firstMemberFrame = try #require(
                itemScreenFrame(IndexPath(item: 0, section: 1), in: collectionView, window: window))
            let lastMemberFrame = try #require(
                itemScreenFrame(
                    IndexPath(item: memberCount - 1, section: 1),
                    in: collectionView, window: window))

            // Minimum upward scroll (contentOffset.y increased), header/fold and first row visible.
            #expect(yExpanded > yBefore)
            #expect(headerFrame.minY >= viewport.top - 0.5)
            #expect(foldFrame.minY >= viewport.top - 0.5)
            #expect(firstMemberFrame.minY >= viewport.top - 0.5)
            #expect(firstMemberFrame.maxY <= viewport.bottom + 0.5)

            // All 2, 3, and 10-member runs fit in the 850pt window's 2-column viewport, so the
            // whole run (including bottom inset) is bottom-aligned without blind centering.
            #expect(lastMemberFrame.maxY <= viewport.bottom + 0.5)
            let expectedBottomEdge = viewport.bottom - GridGroupRun.inset
            #expect(abs(lastMemberFrame.maxY - expectedBottomEdge) <= 2.0)

            // Fold without user scroll restores the exact pre-expansion viewport.
            state.expandedGroup = nil
            try await Task.sleep(for: .milliseconds(250))
            #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)
        }
    }

    @Test func expandingAlreadyVisibleGroupIn2_3_And10MemberRunsHasZeroDeltaOnExpandAndFold()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for memberCount in [2, 3, 10] {
            let (photos, groups, groupID, members) = makeSyntheticGrid(
                beforeCount: 2, groupMemberCount: memberCount, afterCount: 20)
            let beforePhoto = try #require(photos.first?.id)

            let state = GridAnchorHarnessState(
                photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
                expandedGroup: nil, currentPhoto: beforePhoto)
            let host = UIHostingController(
                rootView: GridAnchorHarness(state: state, theme: .light, columnCount: 2))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 250, height: 950)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))

            let collectionView = try #require(
                findSubview(ofType: UICollectionView.self, in: window))
            let yBefore = collectionView.contentOffset.y

            state.currentPhoto = members[0]
            state.expandedGroup = groupID
            try await Task.sleep(for: .milliseconds(250))
            #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)

            state.expandedGroup = nil
            try await Task.sleep(for: .milliseconds(250))
            #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)
        }
    }

    @Test func overHeightGroupRevealsCurrentMemberAndKeepsHeaderDiscoverableWithoutCentering()
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

        // Expand near bottom at first member: over-height (14 members > viewport) reveals first
        // member at bottom edge and keeps header/fold visible, rather than centering.
        state.currentPhoto = members[0]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))

        let yExpanded = collectionView.contentOffset.y
        let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
        let firstMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 0, section: 1), in: collectionView, window: window))

        #expect(yExpanded > yBefore)
        #expect(headerFrame.minY >= viewport.top - 0.5)
        #expect(firstMemberFrame.minY >= viewport.top - 0.5)
        #expect(firstMemberFrame.maxY <= viewport.bottom + 0.5)
        // Minimum upward scroll bottom-aligns the first member rather than centering it.
        #expect(abs(firstMemberFrame.maxY - viewport.bottom) <= 2.0)

        // Member tap inside visible row does not jump.
        state.currentPhoto = members[1]
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(collectionView.contentOffset.y - yExpanded) <= 0.5)

        // Navigating to an off-screen member inside the expanded group centers it into view.
        state.currentPhoto = members[13]
        try await Task.sleep(for: .milliseconds(250))
        let offscreenMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 13, section: 1), in: collectionView, window: window))
        #expect(offscreenMemberFrame.minY >= viewport.top - 0.5)
        #expect(offscreenMemberFrame.maxY <= viewport.bottom + 0.5)

        // Fold after resetting from top, without user scroll, restores pre-expansion viewport.
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)

        // Expand while current photo is deep inside the over-height group (last member): reveals
        // that member at the bottom edge without blind centering.
        state.currentPhoto = members[13]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))

        let deepMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 13, section: 1), in: collectionView, window: window))
        #expect(deepMemberFrame.minY >= viewport.top - 0.5)
        #expect(deepMemberFrame.maxY <= viewport.bottom + 0.5)
        #expect(abs(deepMemberFrame.maxY - viewport.bottom) <= 2.0)

        // When no photo is current (currentPhoto == nil) on an over-height expansion near the
        // bottom, the first member is revealed while keeping header/fold discoverable.
        state.expandedGroup = nil
        state.currentPhoto = nil
        try await Task.sleep(for: .milliseconds(250))
        collectionView.setContentOffset(CGPoint(x: 0, y: desiredOffsetY), animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))
        let nilCurrentHeader = try #require(groupHeaderFrame(in: collectionView, window: window))
        let nilCurrentFirst = try #require(
            itemScreenFrame(IndexPath(item: 0, section: 1), in: collectionView, window: window))
        #expect(nilCurrentHeader.minY >= viewport.top - 0.5)
        #expect(nilCurrentFirst.minY >= viewport.top - 0.5)
        #expect(nilCurrentFirst.maxY <= viewport.bottom + 0.5)
    }

    @Test func foldAfterManualUserScrollDoesNotYankViewportBack() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 20, groupMemberCount: 6, afterCount: 10)
        let beforePhoto = try #require(photos.first?.id)

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

        let yBefore = collectionView.contentOffset.y

        // Expand near bottom.
        state.currentPhoto = members[0]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))
        let yExpanded = collectionView.contentOffset.y
        #expect(yExpanded > yBefore)

        // Simulate user manually scrolling to inspect the run.
        let userScrolledY = yExpanded + 80
        collectionView.delegate?.scrollViewWillBeginDragging?(collectionView)
        collectionView.setContentOffset(CGPoint(x: 0, y: userScrolledY), animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        // Folding after a manual scroll must NOT yank back to yBefore.
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(250))
        let yAfterFold = collectionView.contentOffset.y
        #expect(abs(yAfterFold - yBefore) > 30)
        #expect(abs(yAfterFold - userScrolledY) <= 1.0)
    }

    @Test func expandingGroupClippedAtTopRevealsHeaderAndMembersWithMinimumScroll() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 16, groupMemberCount: 3, afterCount: 20)
        let beforePhoto = try #require(photos.first?.id)

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

        // Scroll so the collapsed stack is clipped by 40pt at the top edge of the viewport.
        let insets = collectionView.adjustedContentInset
        let clippedTopY = stackAttrs.frame.minY - insets.top + 40
        collectionView.setContentOffset(CGPoint(x: 0, y: clippedTopY), animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let viewport = viewportScreenBounds(in: collectionView, window: window)

        state.currentPhoto = members[0]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))

        let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
        let firstMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 0, section: 1), in: collectionView, window: window))
        #expect(headerFrame.minY >= viewport.top - 0.5)
        #expect(abs(headerFrame.minY - viewport.top) <= 2.0)
        #expect(firstMemberFrame.minY >= viewport.top - 0.5)
    }

    @Test func markingInsideExpandedGroupStillRestoresPreExpansionViewportOnFold() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 20, groupMemberCount: 4, afterCount: 10)
        let beforePhoto = try #require(photos.first?.id)

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

        let yBefore = collectionView.contentOffset.y

        state.currentPhoto = members[0]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))
        let yExpanded = collectionView.contentOffset.y
        #expect(yExpanded > yBefore)

        // Marking a member while expanded updates section items without changing structure.
        var updatedPhotos = state.photos
        let memberIndex = try #require(updatedPhotos.firstIndex(where: { $0.id == members[0] }))
        updatedPhotos[memberIndex].marks.rating = try #require(Rating(rawValue: 4))
        state.photos = updatedPhotos
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(collectionView.contentOffset.y - yExpanded) <= 0.5)

        // Folding still restores the pre-expansion viewport offset.
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(collectionView.contentOffset.y - yBefore) <= 0.5)
    }

    @Test func leavingNearBottomExpandedGroupRevealsFollowingPhotoWithoutYankingBack() async throws
    {
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

        // Advancing out of the group to the following photo folds the group and keeps the new
        // current photo fully visible instead of restoring pre-expansion offset with it clipped.
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
        let display = GridDisplay(
            photos: state.photos, groups: state.groups, groupsEnabled: true,
            display: .collapsed, expandedGroup: state.expandedGroup)
        for (sectionIndex, section) in display.sections.enumerated() {
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
        let display = GridDisplay(
            photos: state.photos, groups: state.groups, groupsEnabled: true,
            display: .collapsed, expandedGroup: state.expandedGroup)
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
    var isFolded: Bool

    init(
        photos: [GridPhoto], groups: [BrowsingGroup], thumbnails: any GridThumbnailSource,
        current: PhotoIdentity?, isFolded: Bool
    ) {
        self.photos = photos
        self.groups = groups
        self.thumbnails = thumbnails
        self.current = current
        self.isFolded = isFolded
    }
}

private struct FilmstripAnchorHarness: View {
    let state: FilmstripAnchorHarnessState
    let theme: CloveTheme

    var body: some View {
        DetailFilmstrip(
            photos: state.photos,
            current: state.current,
            thumbnails: state.thumbnails,
            open: { state.current = $0 },
            groups: state.groups,
            groupFold: FilmstripGroupFold(
                isFolded: state.isFolded,
                fold: { state.isFolded = true },
                unfold: { state.isFolded = false })
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.tokens.stage.color)
        .environment(\.cloveTheme, theme)
    }
}
