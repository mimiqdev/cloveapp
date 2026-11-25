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

    @Test func filmstripAnchorsGroupExpandFoldAndCentersAcrossSelection() async throws {
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

            let initialScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
            #expect(initialScrollViews.count == 1)
            let timelineScrollView = try #require(initialScrollViews.first)
            let timelineContentWidth = timelineScrollView.contentSize.width
            #expect(timelineContentWidth > 1200)
            let p2695Slot = try #require(state.timeline.slotIndex(containing: p2695))
            let sxP2695 = expectedFilmstripCenteredOffset(
                itemIndex: p2695Slot,
                itemCount: state.timeline.slots.count,
                scrollView: timelineScrollView,
                metrics: .standard,
                includesPadding: true)
            #expect(abs(timelineScrollView.contentOffset.x - sxP2695) <= 2.0)

            // Selecting burst-2696 in Timeline centers the collapsed stack even though it was visible.
            state.current = p2696
            try await Task.sleep(for: .milliseconds(500))
            let burstSlot = try #require(state.timeline.slotIndex(forGroup: burstID))
            let sxBurst = expectedFilmstripCenteredOffset(
                itemIndex: burstSlot,
                itemCount: state.timeline.slots.count,
                scrollView: timelineScrollView,
                metrics: .standard,
                includesPadding: true)
            #expect(abs(timelineScrollView.contentOffset.x - sxBurst) <= 2.0)
            #expect(timelineScrollView.contentOffset.x > sxP2695 + 40)

            // Expanding burst-2696 mounts Group Focus as a second track while keeping Timeline alive
            // and centered on the stack.
            state.expandedGroup = burstID
            try await Task.sleep(for: .milliseconds(450))
            let expandedScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
            #expect(expandedScrollViews.count == 2)
            #expect(expandedScrollViews.contains { $0 === timelineScrollView })
            #expect(timelineScrollView.contentSize.width > 1200)
            #expect(abs(timelineScrollView.contentOffset.x - sxBurst) <= 0.5)

            let groupScrollView = try #require(
                expandedScrollViews.first { $0 !== timelineScrollView })
            let focusedWidth = groupScrollView.contentSize.width
            let focusedMemberCount = try #require(
                state.timeline.activeGroup(with: burstID)?.visibleMembers.count)
            #expect(focusedWidth >= CGFloat(focusedMemberCount) * 54)
            #expect(focusedWidth < 300)
            let sxFocused = groupScrollView.contentOffset.x

            // Switching to the next visible member inside a short non-overflowing Group Focus
            // keeps the short group centered without scrolling.
            state.current = p2697
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(groupScrollView.contentOffset.x - sxFocused) <= 0.5)

            // Collapsing back to Timeline exits Group Focus cleanly without shifting Timeline's
            // already-centered offset.
            state.expandedGroup = nil
            state.current = p2696
            try await Task.sleep(for: .milliseconds(550))
            let collapsedScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
            #expect(collapsedScrollViews.count == 1)
            #expect(collapsedScrollViews.first === timelineScrollView)
            #expect(timelineScrollView.contentSize.width > 1200)
            let sxAfterCollapse = timelineScrollView.contentOffset.x
            #expect(abs(sxAfterCollapse - sxBurst) <= 0.5)

            // Leaving the collapsed stack back to p2695 re-centers p2695.
            state.current = p2695
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(timelineScrollView.contentOffset.x - sxP2695) <= 2.0)

            // Jumping to the last photo clamps cleanly to the trailing edge with no extra padding.
            state.current = p2713
            try await Task.sleep(for: .milliseconds(600))
            let maxOffset = max(
                0, timelineScrollView.contentSize.width - timelineScrollView.bounds.width)
            #expect(abs(timelineScrollView.contentOffset.x - maxOffset) <= 2.0)
        }
    }

    @Test func timelineFilmstripCentersMiddleClampsEdgesPreservesManualScrollAndRecentersOnResize()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let (photos, groups, _, _) = makeSyntheticGrid(
            beforeCount: 20, groupMemberCount: 0, afterCount: 0)
        let first = try #require(photos.first?.id)
        let midA = photos[8].id
        let midB = photos[10].id
        let midC = photos[12].id
        let last = try #require(photos.last?.id)

        let state = FilmstripAnchorHarnessState(
            photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
            current: first, expandedGroup: nil)
        let host = UIHostingController(
            rootView: FilmstripAnchorHarness(state: state, theme: .light))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))

        let scrollView = try #require(findSubviews(ofType: UIScrollView.self, in: window).first)
        let metrics = DetailFilmstrip.Metrics.standard
        let expectedContentWidth =
            2 * metrics.horizontalPadding
            + CGFloat(photos.count) * metrics.thumbnailWidth
            + CGFloat(photos.count - 1) * DetailFilmstrip.thumbnailSpacing
        #expect(abs(scrollView.contentSize.width - expectedContentWidth) <= 1.5)

        // Head photo clamps at leading edge (x = 0) with no empty half-viewport padding.
        #expect(scrollView.contentOffset.x <= 0.5)

        // Stepping to middle-range items centers each item in the viewport.
        for (index, target) in [(8, midA), (10, midB), (12, midC)] {
            state.current = target
            try await Task.sleep(for: .milliseconds(450))
            let expected = expectedFilmstripCenteredOffset(
                itemIndex: index,
                itemCount: photos.count,
                scrollView: scrollView,
                metrics: metrics,
                includesPadding: true)
            #expect(abs(scrollView.contentOffset.x - expected) <= 2.0)
        }

        // Non-navigation updates (e.g. changing marks on `current`) do not alter the offset.
        let centeredMidC = scrollView.contentOffset.x
        var markedPhotos = state.photos
        markedPhotos[12].marks.rating = try #require(Rating(rawValue: 4))
        state.photos = markedPhotos
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(scrollView.contentOffset.x - centeredMidC) <= 0.5)

        // Subsequent selection change re-centers the newly chosen item.
        state.current = midB
        try await Task.sleep(for: .milliseconds(450))
        let expectedMidB390 = expectedFilmstripCenteredOffset(
            itemIndex: 10,
            itemCount: photos.count,
            scrollView: scrollView,
            metrics: metrics,
            includesPadding: true)
        #expect(abs(scrollView.contentOffset.x - expectedMidB390) <= 2.0)

        // Width / rotation change recenters `current` without changing `current`.
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 110)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let expectedMidB640 = expectedFilmstripCenteredOffset(
            itemIndex: 10,
            itemCount: photos.count,
            scrollView: scrollView,
            metrics: metrics,
            includesPadding: true)
        #expect(abs(scrollView.contentOffset.x - expectedMidB640) <= 2.0)
        #expect(abs(expectedMidB640 - expectedMidB390) > 40)

        window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        #expect(abs(scrollView.contentOffset.x - expectedMidB390) <= 2.0)

        // Metrics change (.standard -> .compact) recenters `current` immediately.
        state.metrics = .compact
        try await Task.sleep(for: .milliseconds(350))
        let expectedCompactMidB = expectedFilmstripCenteredOffset(
            itemIndex: 10,
            itemCount: photos.count,
            scrollView: scrollView,
            metrics: .compact,
            includesPadding: true)
        #expect(abs(scrollView.contentOffset.x - expectedCompactMidB) <= 2.0)
        #expect(abs(expectedCompactMidB - expectedMidB390) > 20)

        state.metrics = .standard
        try await Task.sleep(for: .milliseconds(350))
        #expect(abs(scrollView.contentOffset.x - expectedMidB390) <= 2.0)

        // Tail photo clamps cleanly at the trailing edge.
        state.current = last
        try await Task.sleep(for: .milliseconds(450))
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        #expect(abs(scrollView.contentOffset.x - maxOffset) <= 2.0)
    }

    @Test func overflowingGroupFocusCentersMiddleMembersClampsEdgesAndPreservesTimelineOffset()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 8, groupMemberCount: 12, afterCount: 8)
        let metrics = DetailFilmstrip.Metrics.standard

        let state = FilmstripAnchorHarnessState(
            photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
            current: members[0], expandedGroup: nil)
        let host = UIHostingController(
            rootView: FilmstripAnchorHarness(state: state, theme: .light))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))

        let timelineScrollView = try #require(
            findSubviews(ofType: UIScrollView.self, in: window).first)
        let timelineGroupSlot = try #require(state.timeline.slotIndex(forGroup: groupID))
        let expectedTimelineOffset = expectedFilmstripCenteredOffset(
            itemIndex: timelineGroupSlot,
            itemCount: state.timeline.slots.count,
            scrollView: timelineScrollView,
            metrics: metrics,
            includesPadding: true)
        #expect(abs(timelineScrollView.contentOffset.x - expectedTimelineOffset) <= 2.0)

        // Enter overflowing Group Focus directly on a middle member (like a late Representative).
        state.current = members[6]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(550))

        let expandedScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
        #expect(expandedScrollViews.count == 2)
        #expect(expandedScrollViews.contains { $0 === timelineScrollView })
        #expect(abs(timelineScrollView.contentOffset.x - expectedTimelineOffset) <= 0.5)

        let groupScrollView = try #require(expandedScrollViews.first { $0 !== timelineScrollView })
        let expectedMid6 = expectedFilmstripCenteredOffset(
            itemIndex: 6,
            itemCount: members.count,
            scrollView: groupScrollView,
            metrics: metrics,
            includesPadding: false)
        #expect(abs(groupScrollView.contentOffset.x - expectedMid6) <= 2.0)

        // Stepping within overflowing Group Focus centers middle members and clamps head/tail.
        state.current = members[7]
        try await Task.sleep(for: .milliseconds(450))
        let expectedMid7 = expectedFilmstripCenteredOffset(
            itemIndex: 7,
            itemCount: members.count,
            scrollView: groupScrollView,
            metrics: metrics,
            includesPadding: false)
        #expect(abs(groupScrollView.contentOffset.x - expectedMid7) <= 2.0)

        state.current = members[6]
        try await Task.sleep(for: .milliseconds(450))
        #expect(abs(groupScrollView.contentOffset.x - expectedMid6) <= 2.0)

        // Resizing while in overflowing Group Focus recenters the active member cleanly.
        window.frame = CGRect(x: 0, y: 0, width: 520, height: 110)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let expectedMid6At520 = expectedFilmstripCenteredOffset(
            itemIndex: 6,
            itemCount: members.count,
            scrollView: groupScrollView,
            metrics: metrics,
            includesPadding: false)
        #expect(abs(groupScrollView.contentOffset.x - expectedMid6At520) <= 2.0)

        window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        #expect(abs(groupScrollView.contentOffset.x - expectedMid6) <= 2.0)

        state.current = members[0]
        try await Task.sleep(for: .milliseconds(450))
        #expect(groupScrollView.contentOffset.x <= 0.5)

        state.current = members[11]
        try await Task.sleep(for: .milliseconds(450))
        let groupMaxOffset = max(
            0, groupScrollView.contentSize.width - groupScrollView.bounds.width)
        #expect(abs(groupScrollView.contentOffset.x - groupMaxOffset) <= 2.0)

        // Collapsing back to Timeline keeps Timeline's ScrollView alive and centered on the stack.
        state.current = members[0]
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(500))
        let collapsedScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
        #expect(collapsedScrollViews.count == 1)
        #expect(collapsedScrollViews.first === timelineScrollView)
        #expect(abs(timelineScrollView.contentOffset.x - expectedTimelineOffset) <= 0.5)

        // Entering Group Focus directly on the tail member lands clamped at the trailing edge.
        state.current = members[11]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(550))
        let reenteredScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
        let reenteredGroupScroll = try #require(
            reenteredScrollViews.first { $0 !== timelineScrollView })
        let reenteredMaxOffset = max(
            0, reenteredGroupScroll.contentSize.width - reenteredGroupScroll.bounds.width)
        #expect(abs(reenteredGroupScroll.contentOffset.x - reenteredMaxOffset) <= 2.0)
    }

    private func expectedFilmstripCenteredOffset(
        itemIndex: Int,
        itemCount: Int,
        scrollView: UIScrollView,
        metrics: DetailFilmstrip.Metrics,
        includesPadding: Bool
    ) -> CGFloat {
        let leadingPadding = includesPadding ? metrics.horizontalPadding : 0
        let itemCenterX =
            leadingPadding
            + CGFloat(itemIndex) * (metrics.thumbnailWidth + DetailFilmstrip.thumbnailSpacing)
            + metrics.thumbnailWidth / 2
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        return min(maxOffset, max(0, itemCenterX - scrollView.bounds.width / 2))
    }

    @Test func filmstripGroupFocusPinsTrailingCollapseCapAndHugsShortGroup() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for memberCount in [2, 10] {
            let (photos, groups, groupID, members) = makeSyntheticGrid(
                beforeCount: 2, groupMemberCount: memberCount, afterCount: 2)
            let firstMember = try #require(members.first)
            let state = FilmstripAnchorHarnessState(
                photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
                current: firstMember, expandedGroup: groupID)
            let host = UIHostingController(
                rootView: FilmstripAnchorHarness(state: state, theme: .light))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))

            let scrollViews = findSubviews(ofType: UIScrollView.self, in: window)
            #expect(scrollViews.count == 2)
            let timelineScrollView = try #require(
                scrollViews.first { $0.contentSize.width < 400 && memberCount == 10 }
                    ?? scrollViews.first)
            let groupScrollView = try #require(
                scrollViews.first {
                    abs(
                        $0.contentSize.width
                            - (CGFloat(memberCount) * 54 + CGFloat(memberCount - 1) * 3))
                        < 12
                } ?? scrollViews.last { $0 !== timelineScrollView })
            let groupScrollFrameInWindow = groupScrollView.convert(
                groupScrollView.bounds, to: window)
            #expect(groupScrollView !== timelineScrollView)
            if memberCount == 2 {
                // Short groups hug their natural member width + trailing cap centered in the band.
                #expect(groupScrollFrameInWindow.width < 130)
                #expect(groupScrollFrameInWindow.minX > 100)
                #expect(groupScrollFrameInWindow.maxX < 390 - 100)
            } else {
                // Long groups scroll members on the left while leaving room for the trailing cap.
                #expect(groupScrollView.contentSize.width > groupScrollFrameInWindow.width + 100)
                #expect(groupScrollFrameInWindow.maxX <= 390 - 40)
            }
        }
    }

    @Test func filmstripScrollViewsSpanFullBandHeightAcrossMetrics() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 4, groupMemberCount: 8, afterCount: 4)
        let firstMember = try #require(members.first)

        for metrics in [DetailFilmstrip.Metrics.standard, .compact] {
            let state = FilmstripAnchorHarnessState(
                photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
                current: firstMember, expandedGroup: groupID, metrics: metrics)
            let host = UIHostingController(
                rootView: FilmstripAnchorHarness(state: state, theme: .light))
            host.safeAreaRegions = []
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))

            let scrollViews = findSubviews(ofType: UIScrollView.self, in: window)
            #expect(scrollViews.count == 2)
            for scrollView in scrollViews {
                #expect(abs(scrollView.bounds.height - metrics.bandHeight) <= 0.5)
            }
        }
    }

    @Test func filmstripVerticalPanGestureGatesAxisAndDirectionBeforeRecognizing() {
        var dragEvents: [Bool] = []
        var triggerCount = 0
        let downGesture = FilmstripVerticalPanGesture(
            direction: .down,
            isEnabled: true,
            onDragChanged: { dragEvents.append($0) },
            onTrigger: { triggerCount += 1 })
        let downCoordinator = FilmstripVerticalPanGesture.Coordinator(downGesture)
        let pan = FilmstripTestPan()
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 76))
        hostView.addGestureRecognizer(pan)

        // Horizontal and slightly diagonal horizontal drags fail before recognition begins.
        pan.travel = CGPoint(x: -36, y: 4)
        #expect(!downCoordinator.gestureRecognizerShouldBegin(pan))
        pan.travel = CGPoint(x: 20, y: 12)
        #expect(!downCoordinator.gestureRecognizerShouldBegin(pan))

        // Opposite vertical direction (upward) fails on downward recognizer.
        pan.travel = CGPoint(x: 0, y: -32)
        #expect(!downCoordinator.gestureRecognizerShouldBegin(pan))

        // Zero translation falls back to velocity for axis & direction check.
        pan.travel = .zero
        pan.velocityPoint = CGPoint(x: 180, y: 20)
        #expect(!downCoordinator.gestureRecognizerShouldBegin(pan))
        pan.velocityPoint = CGPoint(x: 0, y: 220)
        #expect(downCoordinator.gestureRecognizerShouldBegin(pan))

        // Disabled state rejects both touch reception and recognition.
        downCoordinator.parent = FilmstripVerticalPanGesture(
            direction: .down,
            isEnabled: false,
            onDragChanged: { dragEvents.append($0) },
            onTrigger: { triggerCount += 1 })
        pan.travel = CGPoint(x: 0, y: 36)
        #expect(
            !downCoordinator.gestureRecognizer(pan, shouldReceive: FilmstripTestTouch(hostView)))
        #expect(!downCoordinator.gestureRecognizerShouldBegin(pan))

        // Re-enable and verify downward vertical drag >= 24 pt tracks and triggers once.
        downCoordinator.parent = downGesture
        #expect(downCoordinator.gestureRecognizerShouldBegin(pan))
        pan.sampleState = .began
        downCoordinator.handle(pan)
        pan.travel = CGPoint(x: 4, y: 28)
        pan.sampleState = .ended
        downCoordinator.handle(pan)
        #expect(dragEvents == [true, false])
        #expect(triggerCount == 1)

        // Sub-threshold downward drag (< 24 pt) clears tracking without firing trigger.
        pan.travel = CGPoint(x: 0, y: 16)
        pan.sampleState = .began
        downCoordinator.handle(pan)
        pan.sampleState = .ended
        downCoordinator.handle(pan)
        #expect(dragEvents == [true, false, true, false])
        #expect(triggerCount == 1)

        // Upward recognizer accepts upward drags, rejects horizontal/downward drags.
        var upTriggers = 0
        let upGesture = FilmstripVerticalPanGesture(
            direction: .up,
            isEnabled: true,
            onDragChanged: { _ in },
            onTrigger: { upTriggers += 1 })
        let upCoordinator = FilmstripVerticalPanGesture.Coordinator(upGesture)
        pan.sampleState = .possible
        pan.travel = CGPoint(x: -40, y: -6)
        #expect(!upCoordinator.gestureRecognizerShouldBegin(pan))
        pan.travel = CGPoint(x: 0, y: 36)
        #expect(!upCoordinator.gestureRecognizerShouldBegin(pan))
        pan.travel = .zero
        pan.velocityPoint = CGPoint(x: 0, y: -200)
        #expect(upCoordinator.gestureRecognizerShouldBegin(pan))
        pan.travel = CGPoint(x: -4, y: -30)
        #expect(upCoordinator.gestureRecognizerShouldBegin(pan))
        pan.sampleState = .began
        upCoordinator.handle(pan)
        pan.sampleState = .ended
        upCoordinator.handle(pan)
        #expect(upTriggers == 1)
    }

    @Test func filmstripScrollPhaseProtectsManualDragAgainstBackgroundSlotCountUpdates()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let (photos, _, _, _) = makeSyntheticGrid(
            beforeCount: 24, groupMemberCount: 0, afterCount: 0)
        let currentPhoto = photos[20].id
        let state = FilmstripAnchorHarnessState(
            photos: photos, groups: [], thumbnails: TestLibrary.sampleThumbnails,
            current: currentPhoto, expandedGroup: nil)
        let host = UIHostingController(
            rootView: FilmstripAnchorHarness(state: state, theme: .light))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 110)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(450))

        let timelineScrollView = try #require(
            findSubviews(ofType: UIScrollView.self, in: window).first)
        let centeredOffset = timelineScrollView.contentOffset.x
        #expect(centeredOffset > 300)

        // Simulate active user drag to the leading edge and notify scroll phase (.interacting).
        timelineScrollView.delegate?.scrollViewWillBeginDragging?(timelineScrollView)
        timelineScrollView.setContentOffset(.zero, animated: false)
        timelineScrollView.delegate?.scrollViewDidScroll?(timelineScrollView)
        try await Task.sleep(for: .milliseconds(50))

        // Background grouping update changes slotCount and currentSlotIndex while `current` is
        // unchanged; the active drag must not be yanked back toward `current`.
        state.groups = [
            BrowsingGroup(
                id: GroupID(rawValue: "bg-group-1"),
                members: Array(photos[0..<4].map(\.id))),
            BrowsingGroup(
                id: GroupID(rawValue: "bg-group-2"),
                members: Array(photos[4..<8].map(\.id))),
        ]
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(timelineScrollView.contentOffset.x - 0) <= 1.0)

        // End dragging -> decelerating still protects against background slotCount updates.
        timelineScrollView.delegate?.scrollViewDidEndDragging?(
            timelineScrollView, willDecelerate: true)
        state.groups.append(
            BrowsingGroup(
                id: GroupID(rawValue: "bg-group-3"),
                members: Array(photos[8..<12].map(\.id))))
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(timelineScrollView.contentOffset.x - 0) <= 1.0)

        // Explicit `current` change still centers the new selection once scrolling ends.
        timelineScrollView.delegate?.scrollViewDidEndDecelerating?(timelineScrollView)
        state.current = photos[19].id
        try await Task.sleep(for: .milliseconds(400))
        #expect(timelineScrollView.contentOffset.x > 200)

        // Group Focus also protects active drags against background memberCount updates.
        let groupID = GroupID(rawValue: "bg-group-overflow")
        var members = Array(photos[12..<23].map(\.id))
        state.groups = [BrowsingGroup(id: groupID, members: members)]
        state.current = members[9]
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(500))

        let expandedScrollViews = findSubviews(ofType: UIScrollView.self, in: window)
        let groupScrollView = try #require(
            expandedScrollViews.first { $0 !== timelineScrollView })
        #expect(groupScrollView.contentOffset.x > 120)

        groupScrollView.delegate?.scrollViewWillBeginDragging?(groupScrollView)
        groupScrollView.setContentOffset(.zero, animated: false)
        groupScrollView.delegate?.scrollViewDidScroll?(groupScrollView)
        try await Task.sleep(for: .milliseconds(50))

        members.append(photos[23].id)
        state.groups = [BrowsingGroup(id: groupID, members: members)]
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(groupScrollView.contentOffset.x - 0) <= 1.0)

        groupScrollView.delegate?.scrollViewDidEndDragging?(groupScrollView, willDecelerate: false)
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

    /// #290, #309: direct entry uses the group's Representative Photo, which can be its last
    /// member. Entering then keeps the run's count header and fold control on screen instead of
    /// centering that member away from them, and later navigation still follows the chosen member.
    @Test func timelineEntryOnALateRepresentativeKeepsTheHeaderAndFoldOnScreen() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 16, groupMemberCount: 14, afterCount: 6)

        // The Representative Photo rule picks the highest-rated member, so a late member can be
        // the photo Detail opens on through BrowsingModel.openGroup.
        var ratedPhotos = photos
        let lateIndex = try #require(ratedPhotos.firstIndex(where: { $0.id == members[13] }))
        ratedPhotos[lateIndex].marks.rating = try #require(Rating(rawValue: 5))
        let representative = try #require(
            BrowsingGroup.representative(
                of: ratedPhotos.filter { members.contains($0.id) }))
        #expect(representative.id == members[13])

        let state = GridAnchorHarnessState(
            photos: ratedPhotos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
            expandedGroup: nil, currentPhoto: representative.id)
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

        // The tap that opens the group, at the late Representative Photo.
        state.expandedGroup = groupID
        try await Task.sleep(for: .milliseconds(250))

        let viewport = viewportScreenBounds(in: collectionView, window: window)
        let currentInsets = collectionView.adjustedContentInset
        let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
        let foldButton = try #require(findFoldButton(in: collectionView))
        let foldFrame = foldButton.convert(foldButton.bounds, to: window)
        let firstMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 0, section: 0), in: collectionView, window: window))
        let lateMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 13, section: 0), in: collectionView, window: window))

        #expect(collectionView.numberOfItems(inSection: 0) == 14)
        // Entry keeps the run's own top as the viewport, not the late member centered.
        #expect(abs(collectionView.contentOffset.y + currentInsets.top) <= 0.5)
        #expect(headerFrame.minY >= viewport.top - 0.5)
        #expect(headerFrame.minY - viewport.top <= GridGroupRun.inset + 2)
        #expect(foldFrame.minY >= viewport.top - 0.5)
        #expect(firstMemberFrame.minY >= viewport.top - 0.5)
        #expect(firstMemberFrame.maxY <= viewport.bottom + 0.5)
        #expect(lateMemberFrame.minY > viewport.bottom - 0.5)

        // Later navigation still follows the chosen member into view.
        state.currentPhoto = members[12]
        try await Task.sleep(for: .milliseconds(250))
        let chosenFrame = try #require(
            itemScreenFrame(IndexPath(item: 12, section: 0), in: collectionView, window: window))
        #expect(chosenFrame.minY >= viewport.top - 0.5)
        #expect(chosenFrame.maxY <= viewport.bottom + 0.5)
    }

    /// #309: the pane can open already in Group Focus, as a stack tapped in Grid does. It still
    /// starts on the run's header and fold control, and folding hands the folder back with the
    /// group's stack on screen instead of leaving it out of view.
    @Test func groupFocusOpenedDirectlyOnALateRepresentativeFoldsBackToTheStack() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 16, groupMemberCount: 14, afterCount: 6)

        let state = GridAnchorHarnessState(
            photos: photos, groups: groups, thumbnails: TestLibrary.sampleThumbnails,
            expandedGroup: groupID, currentPhoto: members[13])
        let host = UIHostingController(
            rootView: GridAnchorHarness(state: state, theme: .light, columnCount: 2))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 250, height: 480)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let viewport = viewportScreenBounds(in: collectionView, window: window)
        let insets = collectionView.adjustedContentInset
        let headerFrame = try #require(groupHeaderFrame(in: collectionView, window: window))
        let foldButton = try #require(findFoldButton(in: collectionView))
        let foldFrame = foldButton.convert(foldButton.bounds, to: window)
        let lateMemberFrame = try #require(
            itemScreenFrame(IndexPath(item: 13, section: 0), in: collectionView, window: window))
        #expect(collectionView.numberOfItems(inSection: 0) == 14)
        #expect(abs(collectionView.contentOffset.y + insets.top) <= 0.5)
        #expect(headerFrame.minY >= viewport.top - 0.5)
        #expect(headerFrame.minY - viewport.top <= GridGroupRun.inset + 2)
        #expect(foldFrame.minY >= viewport.top - 0.5)
        #expect(lateMemberFrame.minY > viewport.bottom - 0.5)

        // Folding hands the folder back with the group's stack brought on screen.
        state.expandedGroup = nil
        try await Task.sleep(for: .milliseconds(250))
        let stackPath = try #require(
            indexPath(for: .group(groupID), in: collectionView, state: state))
        let stackFrame = try #require(
            itemScreenFrame(stackPath, in: collectionView, window: window))
        #expect(collectionView.numberOfSections == 1)
        #expect(collectionView.numberOfItems(inSection: 0) == 23)
        #expect(stackFrame.minY >= viewport.top - 0.5)
        #expect(stackFrame.maxY <= viewport.bottom + 0.5)
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

    private func findSubviews<T: UIView>(ofType type: T.Type, in root: UIView) -> [T] {
        var matches: [T] = []
        if let match = root as? T { matches.append(match) }
        for subview in root.subviews {
            matches.append(contentsOf: findSubviews(ofType: type, in: subview))
        }
        return matches
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
    var photos: [GridPhoto]
    var groups: [BrowsingGroup]
    let thumbnails: any GridThumbnailSource
    var current: PhotoIdentity?
    var expandedGroup: GroupID?
    var metrics: DetailFilmstrip.Metrics

    var timeline: DetailTimeline {
        DetailTimeline(photos: photos, groups: groups, groupsEnabled: true)
    }

    init(
        photos: [GridPhoto], groups: [BrowsingGroup], thumbnails: any GridThumbnailSource,
        current: PhotoIdentity?, expandedGroup: GroupID?,
        metrics: DetailFilmstrip.Metrics = .standard
    ) {
        self.photos = photos
        self.groups = groups
        self.thumbnails = thumbnails
        self.current = current
        self.expandedGroup = expandedGroup
        self.metrics = metrics
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
            metrics: state.metrics,
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

@MainActor
private final class FilmstripTestPan: UIPanGestureRecognizer {
    var travel: CGPoint = .zero
    var velocityPoint: CGPoint = .zero
    var sampleState: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { travel }
    override func velocity(in view: UIView?) -> CGPoint { velocityPoint }
}

@MainActor
private final class FilmstripTestTouch: UITouch {
    private let target: UIView

    init(_ target: UIView) {
        self.target = target
        super.init()
    }

    override var view: UIView? { target }

    override func location(in view: UIView?) -> CGPoint {
        target.convert(CGPoint(x: 20, y: 20), to: view)
    }
}
