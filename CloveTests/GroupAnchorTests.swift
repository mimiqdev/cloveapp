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
    let model: BrowsingModel
    var expandedGroup: GroupID?
    var currentPhoto: PhotoIdentity?

    init(model: BrowsingModel, expandedGroup: GroupID?, currentPhoto: PhotoIdentity?) {
        self.model = model
        self.expandedGroup = expandedGroup
        self.currentPhoto = currentPhoto
    }
}

private struct GridAnchorHarness: View {
    let state: GridAnchorHarnessState
    let theme: CloveTheme
    var columnCount: Int? = 2
    var followsCurrentPhoto = true

    var body: some View {
        let display = GridDisplay(
            photos: state.model.photos, groups: state.model.groups, groupsEnabled: true,
            display: .collapsed, expandedGroup: state.expandedGroup)
        GridCollectionView(
            sections: display.sections,
            currentPhoto: state.currentPhoto,
            groups: state.model.groups,
            shownPhotos: Set(state.model.photos.map(\.id)),
            selection: [],
            thumbnails: state.model.thumbnails,
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
