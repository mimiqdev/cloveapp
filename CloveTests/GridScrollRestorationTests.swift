import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct GridScrollRestorationTests {
    @Test func phoneBrowseShellPreservesGridCollectionViewAndScrollOffsetOnBack() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let photos = makeSyntheticPhotos(count: 120)
        let model = BrowsingModel(
            library: TestLibrary(photos: photos, groups: []),
            similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(
            rootView: BrowseShell(browsing: model)
                .environment(SettingsStore.sample)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, false)
                .environment(\.isDuoExpanded, false)
                .environment(\.isDuoCover, false))
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        var initialCollection: UICollectionView?
        try await waitFor("iPhone Grid collection did not lay out") {
            initialCollection = self.findGridCollectionView(in: window)
            guard let grid = initialCollection else { return false }
            return grid.window != nil
                && grid.bounds.height > 0
                && grid.contentSize.height > 1500
                && !grid.visibleCells.isEmpty
        }
        let grid = try #require(initialCollection)

        // Scroll far down into the folder so y = 0 is off-screen, with photo #36 visible.
        let targetIndex = 36
        let targetPath = IndexPath(item: targetIndex, section: 0)
        grid.scrollToItem(at: targetPath, at: .centeredVertically, animated: false)
        grid.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let savedOffsetY = grid.contentOffset.y
        #expect(savedOffsetY > 400)
        #expect(isItemVisible(at: targetPath, in: grid))

        // Enter Detail on photo #36 and wait for DetailScreen to push.
        model.openPhoto(photos[targetIndex].id)
        try await waitFor("DetailScreen did not mount on iPhone") {
            model.state.route == .detail
                && self.findDetailZoomViews(in: window).count == 1
        }
        try await Task.sleep(for: .milliseconds(150))

        // Return to Grid via Back without changing photo: same UICollectionView and exact offset.
        model.back()
        try await waitFor("Back did not return to Grid on iPhone") {
            model.state.route == .grid
                && self.findGridCollectionView(in: window)?.window != nil
                && self.findDetailZoomViews(in: window).isEmpty
        }
        try await Task.sleep(for: .milliseconds(150))

        let restoredGrid = try #require(findGridCollectionView(in: window))
        #expect(restoredGrid === grid)
        #expect(abs(restoredGrid.contentOffset.y - savedOffsetY) <= 1.0)
        #expect(isItemVisible(at: targetPath, in: restoredGrid))
    }

    @Test func returningFromDetailScrollsOffscreenCurrentPhotoIntoViewOnPhoneAndIPad() async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        struct LayoutCase {
            let name: String
            let idiom: UIUserInterfaceIdiom
            let sizeClass: UIUserInterfaceSizeClass
            let frame: CGRect
        }

        let cases = [
            LayoutCase(
                name: "iPhone",
                idiom: .phone,
                sizeClass: .compact,
                frame: CGRect(x: 0, y: 0, width: 393, height: 852)),
            LayoutCase(
                name: "iPad",
                idiom: .pad,
                sizeClass: .regular,
                frame: CGRect(x: 0, y: 0, width: 1024, height: 768)),
        ]

        for layout in cases {
            let photos = makeSyntheticPhotos(count: 150)
            let model = BrowsingModel(
                library: TestLibrary(photos: photos, groups: []),
                similarGroupsEnabled: false)
            model.openFolder()
            try await waitFor("folder did not open for \(layout.name)") { !model.isFolderOpening }

            let window = UIWindow(windowScene: scene)
            window.frame = layout.frame
            let host = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveUserInterfaceIdiom, layout.idiom)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, false)
                    .environment(\.isDuoExpanded, false)
                    .environment(\.isDuoCover, false))
            host.traitOverrides.horizontalSizeClass = layout.sizeClass
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            var initialCollection: UICollectionView?
            try await waitFor("\(layout.name) Grid collection did not lay out") {
                initialCollection = self.findGridCollectionView(in: window)
                guard let grid = initialCollection else { return false }
                return grid.window != nil
                    && grid.bounds.height > 0
                    && grid.contentSize.height > 1500
                    && !grid.visibleCells.isEmpty
            }
            let grid = try #require(initialCollection)

            // Open an early visible photo (#4), then navigate in Detail to an off-screen photo (#120).
            let offscreenIndex = 120
            let offscreenPath = IndexPath(item: offscreenIndex, section: 0)
            #expect(!isItemVisible(at: offscreenPath, in: grid))

            model.openPhoto(photos[4].id)
            try await waitFor("\(layout.name) Detail did not mount") {
                model.state.route == .detail
                    && self.findDetailZoomViews(in: window).count == 1
            }
            try await Task.sleep(for: .milliseconds(100))

            model.openPhoto(photos[offscreenIndex].id)
            try await Task.sleep(for: .milliseconds(100))

            model.back()
            try await waitFor("\(layout.name) Back did not return to Grid") {
                model.state.route == .grid
                    && self.findGridCollectionView(in: window)?.window != nil
                    && self.findDetailZoomViews(in: window).isEmpty
            }
            try await waitFor(
                "\(layout.name) Grid did not scroll photo #\(offscreenIndex) into view"
            ) {
                guard let restored = self.findGridCollectionView(in: window), restored.window != nil
                else { return false }
                return restored.contentOffset.y > 400
                    && self.isItemVisible(at: offscreenPath, in: restored)
            }

            let restoredGrid = try #require(findGridCollectionView(in: window))
            #expect(restoredGrid === grid)
            #expect(isItemVisible(at: offscreenPath, in: restoredGrid))

            // When the active photo is already visible in Grid, returning keeps exact offset.
            let adjacentIndex = offscreenIndex + 1
            let adjacentPath = IndexPath(item: adjacentIndex, section: 0)
            #expect(isItemVisible(at: adjacentPath, in: restoredGrid))
            let exactOffsetBefore = restoredGrid.contentOffset.y

            model.openPhoto(photos[offscreenIndex].id)
            try await waitFor("\(layout.name) Detail did not re-open") {
                model.state.route == .detail
                    && self.findDetailZoomViews(in: window).count == 1
            }
            model.openPhoto(photos[adjacentIndex].id)
            try await Task.sleep(for: .milliseconds(100))
            model.back()
            try await waitFor("\(layout.name) Back did not return from visible photo") {
                model.state.route == .grid
                    && self.findGridCollectionView(in: window)?.window != nil
                    && self.findDetailZoomViews(in: window).isEmpty
            }
            try await Task.sleep(for: .milliseconds(150))

            #expect(abs(restoredGrid.contentOffset.y - exactOffsetBefore) <= 0.5)
        }
    }

    @Test func returningFromDetailOnDuoCoverAndExpandedScrollsToActivePhoto() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        struct DuoCase {
            let name: String
            let isExpanded: Bool
            let isCover: Bool
            let sizeClass: UIUserInterfaceSizeClass
            let frame: CGRect
        }

        let cases = [
            DuoCase(
                name: "Duo Cover",
                isExpanded: false,
                isCover: true,
                sizeClass: .compact,
                frame: CGRect(x: 0, y: 0, width: 466, height: 678)),
            DuoCase(
                name: "Duo Expanded",
                isExpanded: true,
                isCover: false,
                sizeClass: .regular,
                frame: CGRect(x: 0, y: 0, width: 951, height: 669)),
        ]

        for duo in cases {
            let photos = makeSyntheticPhotos(count: 180)
            let model = BrowsingModel(
                library: TestLibrary(photos: photos, groups: []),
                similarGroupsEnabled: false)
            model.openFolder()
            try await waitFor("folder did not open for \(duo.name)") { !model.isFolderOpening }

            let window = UIWindow(windowScene: scene)
            window.frame = duo.frame
            let host = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, true)
                    .environment(\.hasFoldRegion, duo.isExpanded)
                    .environment(\.isDuoExpanded, duo.isExpanded)
                    .environment(\.isDuoCover, duo.isCover))
            host.traitOverrides.horizontalSizeClass = duo.sizeClass
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("\(duo.name) initial Grid did not mount") {
                self.findGridCollectionView(in: window)?.visibleCells.isEmpty == false
            }

            // Open photo #2, advance to off-screen photo #140 in Focus View (Grid dismantled).
            let targetIndex = 140
            let targetPath = IndexPath(item: targetIndex, section: 0)
            model.openPhoto(photos[2].id)
            try await waitFor("\(duo.name) Detail Focus View did not replace Grid") {
                model.state.route == .detail
                    && self.findGridCollectionView(in: window) == nil
                    && self.findDetailZoomViews(in: window).count == 1
            }
            model.openPhoto(photos[targetIndex].id)
            try await Task.sleep(for: .milliseconds(80))

            // Returning to Grid mounts a fresh GridCollectionView with zero initial bounds;
            // once laid out it must scroll photo #140 into view instead of landing at y = 0.
            model.back()
            try await waitFor("\(duo.name) Grid did not scroll photo #\(targetIndex) into view") {
                guard let grid = self.findGridCollectionView(in: window), grid.window != nil else {
                    return false
                }
                return grid.contentOffset.y > 200
                    && self.isItemVisible(at: targetPath, in: grid)
            }

            let recreatedGrid = try #require(findGridCollectionView(in: window))
            #expect(recreatedGrid.contentOffset.y > 200)
            #expect(isItemVisible(at: targetPath, in: recreatedGrid))
        }
    }

    @Test func restoredDetailSessionFollowsCurrentPhotoOnBackAcrossDuoAndPhone() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        struct SessionCase {
            let name: String
            let isExpanded: Bool
            let isCover: Bool
            let usesVertical: Bool
            let sizeClass: UIUserInterfaceSizeClass
            let frame: CGRect
        }

        let cases = [
            SessionCase(
                name: "iPhone",
                isExpanded: false,
                isCover: false,
                usesVertical: false,
                sizeClass: .compact,
                frame: CGRect(x: 0, y: 0, width: 393, height: 852)),
            SessionCase(
                name: "Duo Cover",
                isExpanded: false,
                isCover: true,
                usesVertical: true,
                sizeClass: .compact,
                frame: CGRect(x: 0, y: 0, width: 466, height: 678)),
            SessionCase(
                name: "Duo Expanded",
                isExpanded: true,
                isCover: false,
                usesVertical: true,
                sizeClass: .regular,
                frame: CGRect(x: 0, y: 0, width: 951, height: 669)),
        ]

        for entry in cases {
            let photos = makeSyntheticPhotos(count: 150)
            let targetIndex = 110
            let targetPath = IndexPath(item: targetIndex, section: 0)
            let library = TestLibrary(photos: photos, groups: [])
            let model = BrowsingModel(library: library, similarGroupsEnabled: false)
            model.openFolder()
            try await waitFor("folder did not open") { !model.isFolderOpening }
            // Simulate a session already restored onto an off-screen photo in Detail before Grid mounts.
            model.openPhoto(photos[targetIndex].id)

            let window = UIWindow(windowScene: scene)
            window.frame = entry.frame
            let host = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(SettingsStore.sample)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, entry.usesVertical)
                    .environment(\.hasFoldRegion, entry.isExpanded)
                    .environment(\.isDuoExpanded, entry.isExpanded)
                    .environment(\.isDuoCover, entry.isCover))
            host.traitOverrides.horizontalSizeClass = entry.sizeClass
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("\(entry.name) restored Detail did not mount") {
                model.state.route == .detail
                    && self.findDetailZoomViews(in: window).count == 1
            }
            try await Task.sleep(for: .milliseconds(100))

            model.back()
            try await waitFor(
                "\(entry.name) restored session did not scroll photo #\(targetIndex) on Back"
            ) {
                guard let grid = self.findGridCollectionView(in: window), grid.window != nil else {
                    return false
                }
                return grid.contentOffset.y > 200
                    && self.isItemVisible(at: targetPath, in: grid)
            }
        }
    }

    @Test func freshGridCollectionViewWithZeroInitialBoundsDefersFollowUntilLaidOut()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let photos = makeSyntheticPhotos(count: 120)
        let targetIndex = 99
        let targetPhoto = photos[targetIndex].id
        let display = GridDisplay(photos: photos, groups: [], groupsEnabled: false)

        let box = ZeroBoundsBox()
        box.currentPhoto = targetPhoto

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 760)
        let host = UIHostingController(
            rootView: ZeroBoundsHarness(
                display: display, shown: Set(photos.map(\.id)), box: box))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("GridCollectionView did not mount with zero bounds") {
            self.findGridCollectionView(in: window) != nil
        }
        let collectionView = try #require(findGridCollectionView(in: window))
        #expect(collectionView.bounds.height == 0)
        #expect(collectionView.contentOffset.y == 0)

        // Now give the container real bounds (like Duo Cover / Expanded returning from Detail).
        box.frameSize = CGSize(width: 390, height: 680)
        let targetPath = IndexPath(item: targetIndex, section: 0)
        try await waitFor("deferred follow did not scroll photo into view after layout") {
            collectionView.bounds.height > 600
                && collectionView.contentOffset.y > 200
                && self.isItemVisible(at: targetPath, in: collectionView)
        }
        #expect(isItemVisible(at: targetPath, in: collectionView))

        // Verify user dragging clears any pending follow and never fights manual scrolling.
        box.frameSize = .zero
        try await Task.sleep(for: .milliseconds(80))
        box.currentPhoto = photos[10].id
        try await Task.sleep(for: .milliseconds(80))

        let coordinator = try #require(collectionView.delegate as? GridCollectionView.Coordinator)
        coordinator.scrollViewWillBeginDragging(collectionView)
        box.frameSize = CGSize(width: 390, height: 680)
        try await Task.sleep(for: .milliseconds(150))
        // Still at the previous offset (far down around photo #99), not pulled back to photo #10.
        #expect(collectionView.contentOffset.y > 200)
    }

    @Test func browsingChromePreservesNavigationBarVisibilityAcrossRoutes() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let photos = makeSyntheticPhotos(count: 24)
        let model = BrowsingModel(
            library: TestLibrary(photos: photos, groups: []),
            similarGroupsEnabled: false)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()

        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let host = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(store)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, false)
                    .environment(\.isDuoExpanded, false)
                    .environment(\.isDuoCover, false))
            host.traitOverrides.horizontalSizeClass = .compact
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            // 1. Entry keeps navigation bar hidden.
            try await waitFor("Entry did not mount") {
                model.state.route == .entry
                    && self.findNavigationController(in: host) != nil
            }
            try await Task.sleep(for: .milliseconds(150))
            #expect(!isNavigationBarVisible(in: host, window: window))

            // 2. Grid shows navigation bar.
            model.openFolder()
            try await waitFor("Grid did not mount") {
                model.state.route == .grid
                    && self.findGridCollectionView(in: window)?.window != nil
            }
            try await waitFor("Grid navigation bar did not become visible") {
                self.isNavigationBarVisible(in: host, window: window)
            }

            // 3. Portrait Detail keeps navigation bar visible; landscape tap hides chrome and
            //    second tap restores it.
            model.openPhoto(photos[0].id)
            try await waitFor("Portrait Detail navigation bar not visible") {
                model.state.route == .detail
                    && self.findDetailZoomViews(in: window).count == 1
                    && self.isNavigationBarVisible(in: host, window: window)
            }

            window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
            host.view.frame = window.bounds
            host.traitOverrides.verticalSizeClass = .compact
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await waitFor("Landscape Detail navigation bar not visible") {
                self.isNavigationBarVisible(in: host, window: window)
            }

            let preview = try #require(findDetailZoomViews(in: window).first)
            preview.onChromeToggle?()
            try await waitFor(
                "Landscape Detail tap did not hide navigation bar: \(self.describeNav(in: host, window: window))"
            ) {
                !self.isNavigationBarVisible(in: host, window: window)
            }
            preview.onChromeToggle?()
            try await waitFor(
                "Landscape Detail second tap did not restore navigation bar: \(self.describeNav(in: host, window: window))"
            ) {
                self.isNavigationBarVisible(in: host, window: window)
            }

            // 4. Settings shows navigation bar in compact.
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            host.view.frame = window.bounds
            host.traitOverrides.verticalSizeClass = .regular
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            model.back()
            try await waitFor("Did not return to Grid before Settings") {
                model.state.route == .grid
            }
            model.showSettings()
            try await waitFor("Compact Settings navigation bar did not show") {
                model.state.route == .settings
                    && self.findDetailZoomViews(in: window).isEmpty
                    && self.findGridCollectionView(in: window)?.window == nil
                    && self.isNavigationBarVisible(in: host, window: window)
            }
            model.back()
            try await waitFor("Did not return to Grid from Settings") { model.state.route == .grid }
        }

        // 5. Compare hides the navigation bar inside iPhone landscape BrowseShell.
        do {
            let compareWindow = UIWindow(windowScene: scene)
            compareWindow.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
            let compareHost = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(store)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, false)
                    .environment(\.isDuoExpanded, false)
                    .environment(\.isDuoCover, false))
            compareHost.traitOverrides.horizontalSizeClass = .compact
            compareHost.traitOverrides.verticalSizeClass = .compact
            compareWindow.rootViewController = compareHost
            compareWindow.makeKeyAndVisible()
            compareHost.view.frame = compareWindow.bounds
            compareHost.view.setNeedsLayout()
            compareHost.view.layoutIfNeeded()
            defer {
                compareWindow.isHidden = true
                compareWindow.rootViewController = nil
            }

            model.openPhoto(photos[0].id)
            try await waitFor("Landscape Detail did not mount for Compare") {
                model.state.route == .detail
                    && self.findDetailZoomViews(in: compareWindow).count == 1
            }
            let timeline = DetailTimeline(
                photos: model.photos, groups: model.groups, groupsEnabled: false)
            #expect(model.enterCompareFromDetail(timeline: timeline))
            try await waitFor(
                "Compare did not mount: session=\(model.compareSession != nil) zoomCount=\(self.findDetailZoomViews(in: compareWindow).count) \(self.describeNav(in: compareHost, window: compareWindow))"
            ) {
                model.compareSession != nil
                    && self.findDetailZoomViews(in: compareWindow).count == 2
            }
            try await waitFor(
                "Compare navigation bar did not hide: \(self.describeNav(in: compareHost, window: compareWindow))"
            ) {
                !self.isNavigationBarVisible(in: compareHost, window: compareWindow)
            }
            model.exitCompare()
            model.back()
            try await waitFor("Did not return to Grid after Compare") { model.state.route == .grid }
        }

        // 6. Wide Settings hides outer navigation bar.
        do {
            let wideWindow = UIWindow(windowScene: scene)
            wideWindow.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            let wideHost = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(store)
                    .environment(\.cloveUserInterfaceIdiom, .pad)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, false)
                    .environment(\.isDuoExpanded, false)
                    .environment(\.isDuoCover, false))
            wideHost.traitOverrides.horizontalSizeClass = .regular
            wideHost.traitOverrides.verticalSizeClass = .regular
            wideWindow.rootViewController = wideHost
            wideWindow.makeKeyAndVisible()
            defer {
                wideWindow.isHidden = true
                wideWindow.rootViewController = nil
            }
            model.showSettings()
            try await waitFor("Wide Settings navigation bar did not hide") {
                model.state.route == .settings
                    && !self.isNavigationBarVisible(in: wideHost, window: wideWindow)
            }
        }
    }

    // MARK: - Helpers

    private func makeSyntheticPhotos(count: Int) -> [GridPhoto] {
        let folder = TestLibrary.sampleFolderKey
        let baseDate = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<count).map { index in
            let stem = String(format: "SCR%05d", index)
            let id = PhotoIdentity(
                folderID: folder, relativeFolderPath: "DCIM/100SCR", stem: stem)
            return GridPhoto(
                id: id,
                fileName: "\(stem).ARW",
                time: .known(
                    PhotoTime(
                        captureTime: baseDate.addingTimeInterval(Double(index) * 2),
                        hasUTCOffset: true)),
                marks: PhotoMarks())
        }
    }

    private func isItemVisible(at indexPath: IndexPath, in collectionView: UICollectionView) -> Bool
    {
        let insets = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - insets.top - insets.bottom
        guard visibleHeight > 0,
            let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else { return false }
        let visibleTop = collectionView.contentOffset.y + insets.top
        let visibleBottom =
            collectionView.contentOffset.y + collectionView.bounds.height - insets.bottom
        return attributes.frame.minY >= visibleTop - 0.5
            && attributes.frame.maxY <= visibleBottom + 0.5
    }

    private func isNavigationBarVisible(in host: UIViewController, window: UIWindow) -> Bool {
        if let nav = findNavigationController(in: host) {
            if nav.isNavigationBarHidden || nav.navigationBar.isHidden
                || nav.navigationBar.alpha < 0.01
            {
                return false
            }
            let frame = nav.navigationBar.convert(nav.navigationBar.bounds, to: window)
            return frame.height > 0 && frame.maxY > 0
        }
        return false
    }

    private func describeNav(in host: UIViewController, window: UIWindow) -> String {
        guard let nav = findNavigationController(in: host) else { return "no nav" }
        let frame = nav.navigationBar.convert(nav.navigationBar.bounds, to: window)
        let items =
            (nav.topViewController?.navigationItem.leadingItemGroups.flatMap(\.barButtonItems)
                .count ?? 0)
            + (nav.topViewController?.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
                .count ?? 0)
        return
            "isNavigationBarHidden=\(nav.isNavigationBarHidden) barHidden=\(nav.navigationBar.isHidden) alpha=\(nav.navigationBar.alpha) frame=\(NSCoder.string(for: frame)) items=\(items)"
    }

    private func findNavigationController(in controller: UIViewController)
        -> UINavigationController?
    {
        if let nav = controller as? UINavigationController { return nav }
        for child in controller.children {
            if let found = findNavigationController(in: child) { return found }
        }
        return nil
    }

    private func findGridCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView,
            collection.delegate is GridCollectionView.Coordinator
        {
            return collection
        }
        for child in view.subviews {
            if let found = findGridCollectionView(in: child) { return found }
        }
        return nil
    }

    private func findDetailZoomViews(in view: UIView) -> [DetailZoomContainerView] {
        var matches: [DetailZoomContainerView] = []
        if let zoom = view as? DetailZoomContainerView { matches.append(zoom) }
        for child in view.subviews {
            matches.append(contentsOf: findDetailZoomViews(in: child))
        }
        return matches
    }

    private func waitFor(
        _ message: @autoclosure () -> String,
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record(Comment(rawValue: message()))
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

@MainActor
@Observable
private final class ZeroBoundsBox {
    var frameSize: CGSize = .zero
    var currentPhoto: PhotoIdentity?
}

private struct ZeroBoundsHarness: View {
    let display: GridDisplay
    let shown: Set<PhotoIdentity>
    let box: ZeroBoundsBox

    var body: some View {
        GridCollectionView(
            sections: display.sections,
            currentPhoto: box.currentPhoto,
            groups: [],
            shownPhotos: shown,
            selection: [],
            thumbnails: TestLibrary.sampleThumbnails,
            followsCurrentPhoto: true,
            openPhoto: { _ in },
            openGroup: { _ in },
            beginSelection: { _ in },
            toggleSelection: { _ in }
        )
        .frame(width: box.frameSize.width, height: box.frameSize.height)
        .environment(\.cloveTheme, .light)
    }
}
