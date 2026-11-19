import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct GroupSelectUnfoldTests {
    @Test func twoBeatUnfoldRevealsGroupedMembersAndRefoldsOnExit() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let store = SettingsStore.sample

        let collapsedCount = GridDisplay(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: true
        ).cells.count
        let unfoldedCount = browsing.photos.count
        #expect(collapsedCount < unfoldedCount)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
            }
            .environment(store)
            .environment(\.scenePhase, .active))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        #expect(collectionView.numberOfItems(inSection: 0) == collapsedCount)

        // Beat 1: entering select mode keeps collapsed stacks briefly before unfolding.
        let p2680 = try #require(browsing.photos.first { $0.id.stem == "mmq02680" }?.id)
        browsing.toggleSelection(p2680)
        try await Task.sleep(for: .milliseconds(30))
        #expect(collectionView.numberOfItems(inSection: 0) == collapsedCount)

        // Beat 2 (~120 ms + spring): active groups unfold inline with connected tray positions.
        try await waitUntil(timeout: .seconds(2)) {
            collectionView.numberOfItems(inSection: 0) == unfoldedCount
        }
        try await Task.sleep(for: .milliseconds(350))

        let p2678 = try #require(browsing.photos.first { $0.id.stem == "mmq02678" }?.id)
        let p2678Index = try #require(browsing.photos.firstIndex { $0.id == p2678 })
        let memberCell = try #require(
            collectionView.cellForItem(at: IndexPath(item: p2678Index, section: 0))
                as? GridPhotoCell)
        #expect(memberCell.trayPosition != nil)
        #expect(memberCell.contentView.clipsToBounds == false)

        // Exiting select mode refolds active groups back into collapsed stacks.
        browsing.clearSelection()
        try await waitUntil(timeout: .seconds(2)) {
            collectionView.numberOfItems(inSection: 0) == collapsedCount
        }
        try await Task.sleep(for: .milliseconds(350))
        let visibleCells = collectionView.visibleCells.compactMap { $0 as? GridPhotoCell }
        #expect(!visibleCells.isEmpty)
        #expect(visibleCells.allSatisfy { $0.trayPosition == nil && $0.contentView.clipsToBounds })
    }

    @Test func mountedInSelectModeUnfoldsGroupsImmediately() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let first = try #require(browsing.photos.first)
        browsing.toggleSelection(first.id)
        let store = SettingsStore.sample

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
            }
            .environment(store)
            .environment(\.scenePhase, .active))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(60))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        #expect(collectionView.numberOfItems(inSection: 0) == browsing.photos.count)
    }

    @Test func earlyTapDuringPreUnfoldBeatCompletesUnfoldImmediately() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let store = SettingsStore.sample

        let collapsedCount = GridDisplay(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: true
        ).cells.count
        let unfoldedCount = browsing.photos.count

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
            }
            .environment(store)
            .environment(\.scenePhase, .active))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let coordinator = try #require(collectionView.delegate as? GridCollectionView.Coordinator)

        let first = try #require(browsing.photos.first)
        browsing.toggleSelection(first.id)
        try await Task.sleep(for: .milliseconds(15))
        #expect(collectionView.numberOfItems(inSection: 0) == collapsedCount)

        // Tapping a cell right away finishes the unfold before the 120 ms timer elapses.
        coordinator.collectionView(collectionView, didSelectItemAt: IndexPath(item: 1, section: 0))
        try await waitUntil(timeout: .milliseconds(250)) {
            collectionView.numberOfItems(inSection: 0) == unfoldedCount
        }
    }

    @Test func foldAndUnfoldAnchorTopVisibleOrLongPressedCellEvenWithOffscreenCurrentPhoto()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let (photos, groups, groupID, members) = makeSyntheticGrid(
            beforeCount: 18, groupMemberCount: 4, afterCount: 12)
        // Current photo sits far off-screen at index 0, mimicking returning from Detail and scrolling down.
        let offscreenCurrent = try #require(photos.first?.id)
        let state = SelectUnfoldHarnessState(
            photos: photos, groups: groups, currentPhoto: offscreenCurrent)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        let host = UIHostingController(rootView: SelectUnfoldHarness(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let groupIndex = try #require(
            state.display.cells.firstIndex { $0.id == .group(groupID) })
        let groupPath = IndexPath(item: groupIndex, section: 0)
        collectionView.scrollToItem(at: groupPath, at: .top, animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let topPathBefore = try #require(collectionView.indexPathsForVisibleItems.min())
        let topItemBefore = try #require(state.display.cells[safe: topPathBefore.item])
        let topFrameBefore =
            try #require(
                collectionView.layoutAttributesForItem(at: topPathBefore)?.frame.minY)
            - collectionView.contentOffset.y

        // Simulate "…" ▶ Select unfolding inline.
        state.isSelectingEmpty = true
        state.areGroupsUnfolded = true
        try await Task.sleep(for: .milliseconds(420))

        // The top visible anchor keeps its viewport position instead of jumping to offscreen index 0.
        let unfoldedAnchorID: GridCellItem.ID =
            if case .group(let anchoredGroup) = topItemBefore.id,
                let firstMember = state.display.cells.first(where: { $0.group?.id == anchoredGroup }
                )
            {
                firstMember.id
            } else {
                topItemBefore.id
            }
        let anchorIndexUnfolded = try #require(
            state.display.cells.firstIndex { $0.id == unfoldedAnchorID })
        let anchorTopUnfolded =
            try #require(
                collectionView.layoutAttributesForItem(
                    at: IndexPath(item: anchorIndexUnfolded, section: 0))?.frame.minY)
            - collectionView.contentOffset.y
        #expect(abs(anchorTopUnfolded - topFrameBefore) <= 1.0)
        #expect(collectionView.contentOffset.y > 200)

        // Simulate Done refolding inline: returns cleanly to the matching stack/tile offset.
        state.isSelectingEmpty = false
        state.areGroupsUnfolded = false
        try await Task.sleep(for: .milliseconds(420))

        let refoldedIndex = try #require(
            state.display.cells.firstIndex { $0.id == topItemBefore.id })
        let refoldedTop =
            try #require(
                collectionView.layoutAttributesForItem(
                    at: IndexPath(item: refoldedIndex, section: 0))?
                    .frame.minY) - collectionView.contentOffset.y
        #expect(abs(refoldedTop - topFrameBefore) <= 1.0)

        // Long-pressing a collapsed group cover selects only the cover photo and holds it in place.
        let coordinator = try #require(collectionView.delegate as? GridCollectionView.Coordinator)
        let collapsedGroupIndex = try #require(
            state.display.cells.firstIndex { $0.id == .group(groupID) })
        let collapsedCoverCell = try #require(state.display.cells[safe: collapsedGroupIndex])
        let coverTopBefore =
            try #require(
                collectionView.layoutAttributesForItem(
                    at: IndexPath(item: collapsedGroupIndex, section: 0))?.frame.minY)
            - collectionView.contentOffset.y

        let coverPhoto = collapsedCoverCell.photo.id
        #expect(coverPhoto == members[0])
        // Simulate long-press beginning selection on the collapsed stack cover.
        state.selection = BatchSelection(groups: groups, selection: []).selecting(
            collapsedCoverCell)
        #expect(state.selection == [coverPhoto])
        state.areGroupsUnfolded = true
        try await Task.sleep(for: .milliseconds(420))

        let unfoldedCoverIndex = try #require(
            state.display.cells.firstIndex { $0.id == .photo(coverPhoto) })
        let unfoldedCoverTop =
            try #require(
                collectionView.layoutAttributesForItem(
                    at: IndexPath(item: unfoldedCoverIndex, section: 0))?.frame.minY)
            - collectionView.contentOffset.y
        #expect(abs(unfoldedCoverTop - coverTopBefore) <= 1.0)
        _ = coordinator
    }

    @Test func inlineTrayConnectionsBreakAtRowBoundariesAndAdaptOnWidthChange() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        // 1 standalone photo, then a 3-member group at indices [1, 2, 3], then 1 trailing photo.
        // At 3 columns (width 390): index 1 = col 1, index 2 = col 2 (row end), index 3 = col 0 (row 2).
        // At 5 columns (width 700): indices 1, 2, 3 are all on row 0!
        let (photos, groups, _, members) = makeSyntheticGrid(
            beforeCount: 1, groupMemberCount: 3, afterCount: 1)
        let state = SelectUnfoldHarnessState(photos: photos, groups: groups, currentPhoto: nil)
        state.isSelectingEmpty = true
        state.areGroupsUnfolded = true

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        let host = UIHostingController(rootView: SelectUnfoldHarness(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let c0 = try #require(
            collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? GridPhotoCell)
        let m0 = try #require(
            collectionView.cellForItem(at: IndexPath(item: 1, section: 0)) as? GridPhotoCell)
        let m1 = try #require(
            collectionView.cellForItem(at: IndexPath(item: 2, section: 0)) as? GridPhotoCell)
        let m2 = try #require(
            collectionView.cellForItem(at: IndexPath(item: 3, section: 0)) as? GridPhotoCell)
        let cLast = try #require(
            collectionView.cellForItem(at: IndexPath(item: 4, section: 0)) as? GridPhotoCell)

        #expect(c0.trayPosition == nil)
        #expect(c0.contentView.clipsToBounds == true)
        #expect(
            m0.trayPosition
                == GridGroupTrayPosition(
                    memberIndex: 0, memberCount: 3, connectsLeading: false, connectsTrailing: true))
        #expect(
            m1.trayPosition
                == GridGroupTrayPosition(
                    memberIndex: 1, memberCount: 3, connectsLeading: true, connectsTrailing: false)
        )
        #expect(
            m2.trayPosition
                == GridGroupTrayPosition(
                    memberIndex: 2, memberCount: 3, connectsLeading: false, connectsTrailing: false
                ))
        #expect(m0.contentView.clipsToBounds == false)
        #expect(m1.contentView.clipsToBounds == false)
        #expect(m2.contentView.clipsToBounds == false)
        #expect(cLast.trayPosition == nil)
        _ = members

        // Resize to 720 pt wide (5 columns): indices 1, 2, 3 sit continuously on row 0.
        window.frame = CGRect(x: 0, y: 0, width: 720, height: 600)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let m0Wide = try #require(
            collectionView.cellForItem(at: IndexPath(item: 1, section: 0)) as? GridPhotoCell)
        let m1Wide = try #require(
            collectionView.cellForItem(at: IndexPath(item: 2, section: 0)) as? GridPhotoCell)
        let m2Wide = try #require(
            collectionView.cellForItem(at: IndexPath(item: 3, section: 0)) as? GridPhotoCell)
        #expect(
            m0Wide.trayPosition
                == GridGroupTrayPosition(
                    memberIndex: 0, memberCount: 3, connectsLeading: false, connectsTrailing: true))
        #expect(
            m1Wide.trayPosition
                == GridGroupTrayPosition(
                    memberIndex: 1, memberCount: 3, connectsLeading: true, connectsTrailing: true))
        #expect(
            m2Wide.trayPosition
                == GridGroupTrayPosition(
                    memberIndex: 2, memberCount: 3, connectsLeading: true, connectsTrailing: false
                ))
    }

    @Test func filteredGroupNarrowedToOneMemberRendersStandaloneWithoutTray() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        // Reject two members of burst-2696 (2696, 2697, 2698) and filter to Unmarked.
        let p2696 = try #require(browsing.photos.first { $0.id.stem == "mmq02696" }?.id)
        let p2697 = try #require(browsing.photos.first { $0.id.stem == "mmq02697" }?.id)
        let p2698 = try #require(browsing.photos.first { $0.id.stem == "mmq02698" }?.id)
        browsing.apply(.rating(.rejected), to: p2696)
        browsing.apply(.rating(.rejected), to: p2697)
        browsing.setFilter(.unmarked)

        let firstVisible = try #require(browsing.photos.first)
        browsing.toggleSelection(firstVisible.id)

        let store = SettingsStore.sample
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
            }
            .environment(store)
            .environment(\.scenePhase, .active))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let collectionView = try #require(findSubview(ofType: UICollectionView.self, in: window))
        let item2698Index = try #require(browsing.photos.firstIndex { $0.id == p2698 })
        let path = IndexPath(item: item2698Index, section: 0)
        collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))

        let cell2698 = try #require(collectionView.cellForItem(at: path) as? GridPhotoCell)
        #expect(cell2698.trayPosition == nil)
        #expect(cell2698.contentView.clipsToBounds == true)

        // Select all selects only visible unmarked photos, never pulling in rejected/hidden members.
        browsing.selectAllVisible()
        #expect(browsing.batchTargets.count == browsing.photos.count)
        #expect(!browsing.state.selection.contains(p2696))
        #expect(!browsing.state.selection.contains(p2697))
        #expect(browsing.showsAllVisibleSelected)
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
            let stem = String(format: "SEL%05d", index)
            let id = PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100SEL", stem: stem)
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
        let groupID = GroupID(rawValue: "sel-group")
        let groups = [BrowsingGroup(id: groupID, members: members)]
        return (photos, groups, groupID, members)
    }

    private func findSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let found = findSubview(ofType: type, in: subview) { return found }
        }
        return nil
    }

    private func waitUntil(
        timeout: Duration = .seconds(2), condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                Issue.record("timed out waiting for select unfold condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
@Observable
private final class SelectUnfoldHarnessState {
    var photos: [GridPhoto]
    let groups: [BrowsingGroup]
    var currentPhoto: PhotoIdentity?
    var selection: Set<PhotoIdentity> = []
    var isSelectingEmpty = false
    var areGroupsUnfolded = false

    var display: GridDisplay {
        GridDisplay(
            photos: photos,
            groups: groups,
            groupsEnabled: true,
            expandGroupsInline: areGroupsUnfolded)
    }

    init(photos: [GridPhoto], groups: [BrowsingGroup], currentPhoto: PhotoIdentity?) {
        self.photos = photos
        self.groups = groups
        self.currentPhoto = currentPhoto
    }
}

private struct SelectUnfoldHarness: View {
    let state: SelectUnfoldHarnessState

    var body: some View {
        let display = state.display
        GridCollectionView(
            sections: display.sections,
            currentPhoto: state.currentPhoto,
            groups: state.groups,
            shownPhotos: Set(state.photos.map(\.id)),
            selection: state.selection,
            thumbnails: TestLibrary.sampleThumbnails,
            isSelectingEmpty: state.isSelectingEmpty,
            openPhoto: { _ in },
            openGroup: { _ in },
            beginSelection: { item in
                state.selection = BatchSelection(groups: state.groups, selection: state.selection)
                    .selecting(item)
            },
            toggleSelection: { item in
                state.selection = BatchSelection(groups: state.groups, selection: state.selection)
                    .toggling(item)
            },
            setSelection: { state.selection = $0 },
            keepSelectingWhenEmpty: { state.isSelectingEmpty = true },
            areGroupsUnfolded: state.areGroupsUnfolded,
            completeGroupUnfold: { state.areGroupsUnfolded = true }
        )
        .environment(\.cloveTheme, .light)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
