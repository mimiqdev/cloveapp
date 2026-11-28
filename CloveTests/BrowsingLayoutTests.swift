import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct BrowsingLayoutTests {
    @Test func widthChangesKeepTheFolderPhotoFilterAndSelection() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let photo = try #require(model.photos.last?.id)
        model.setFilter(.subfolder(photo.relativeFolderPath))
        model.toggleSelection(photo)
        model.openPhoto(photo)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: BrowseShell(browsing: model).environment(SettingsStore.sample))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        for route in [BrowserRoute.detail, .settings] {
            if route == .settings {
                model.back()
                model.showSettings()
            }
            let saved = model.state
            for width in [UIUserInterfaceSizeClass.regular, .compact, .regular] {
                host.traitOverrides.horizontalSizeClass = width
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                #expect(model.state == saved)
                #expect(model.filterTitle == photo.relativeFolderPath)
            }
        }
        model.back()
        #expect(model.state.route == .grid)
        #expect(model.state.currentPhoto == photo)
        #expect(model.state.selection == [photo])
        #expect(model.state.filter == .subfolder(photo.relativeFolderPath))
    }

    @Test func detailPresentationDefaultsToPhotoPreviewAndResetsAfterBack() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let first = try #require(model.photos.first?.id)
        let second = try #require(model.photos.dropFirst().first?.id)
        model.openPhoto(first)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: BrowseShell(browsing: model)
                .environment(SettingsStore.sample)
                .environment(\.cloveUserInterfaceIdiom, .pad))
        host.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Regular wide iPad opens Photo Preview (grid collection view present).
        try await Task.sleep(for: .milliseconds(200))
        #expect(hasGridCollection(in: window))

        // Incidental compact transition falls back to Focus View, then restores Photo Preview.
        host.traitOverrides.horizontalSizeClass = .compact
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!hasGridCollection(in: window))

        host.traitOverrides.horizontalSizeClass = .regular
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(hasGridCollection(in: window))

        // Leaving detail and opening another photo starts in Photo Preview again.
        model.back()
        try await Task.sleep(for: .milliseconds(100))
        model.openPhoto(second)
        try await Task.sleep(for: .milliseconds(150))
        #expect(hasGridCollection(in: window))
    }

    @Test func expandedDuoDetailPresentationDefaultsToFocusAndResetsAfterBack() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample())
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        let first = try #require(model.photos.first { $0.id.stem == "mmq02680" }?.id)
        let second = try #require(model.photos.first { $0.id.stem == "mmq02682" }?.id)
        let group = try #require(model.groups.first)

        // 1. Expanded Duo BrowseShell -> GridScreen defaults to Focus View for standalone photos and
        //    group stacks alike.
        do {
            let shellFrames = TestTapPickerFramesBox()
            let shellHost = UIHostingController(
                rootView: BrowseShell(browsing: model)
                    .environment(SettingsStore.sample)
                    .environment(\.isDuoExpanded, true)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, true)
                    .environment(\.hasFoldRegion, true)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                        shellFrames.frames = frames
                    })
            shellHost.traitOverrides.horizontalSizeClass = .regular
            let shellWindow = UIWindow(windowScene: scene)
            shellWindow.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
            shellWindow.rootViewController = shellHost
            shellWindow.makeKeyAndVisible()
            defer {
                shellWindow.isHidden = true
                shellWindow.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(100))
            model.openPhoto(first)
            try await waitFor("expanded Duo standalone photo did not open in Focus View") {
                shellFrames.frames["clove.duo.focus"] != nil
                    && shellFrames.frames["clove.detail.filmstrip"] != nil
                    && !self.hasGridCollection(in: shellWindow)
                    && self.findFilmstripScrollView(in: shellWindow) != nil
            }
            #expect(shellFrames.frames["clove.duo.photoPreview"] == nil)

            model.back()
            try await waitFor("expanded Duo did not return to Grid View") {
                shellFrames.frames["clove.duo.focus"] == nil
                    && self.hasGridCollection(in: shellWindow)
            }

            model.openGroup(group.id)
            try await waitFor("expanded Duo group stack did not open in Focus View") {
                shellFrames.frames["clove.duo.focus"] != nil
                    && shellFrames.frames["clove.detail.filmstrip.expandedGroup"] != nil
                    && !self.hasGridCollection(in: shellWindow)
                    && self.findFilmstripScrollView(in: shellWindow) != nil
            }
            #expect(shellFrames.frames["clove.duo.photoPreview"] == nil)

            model.back()
            try await waitFor("expanded Duo did not return to Grid View after group") {
                shellFrames.frames["clove.duo.focus"] == nil
                    && self.hasGridCollection(in: shellWindow)
            }
        }

        // 2. Starting in Photo Preview (as after toggling sidebar.left) preserves Photo Preview
        //    across Detail photo navigation, then resets to Focus View after Back.
        let resetFrames = TestTapPickerFramesBox()
        let resetHost = UIHostingController(
            rootView: NavigationStack {
                GridScreen(
                    browsing: model,
                    thumbnails: model.thumbnails,
                    initialPresentation: .photoPreview)
            }
            .environment(SettingsStore.sample)
            .environment(\.isDuoExpanded, true)
            .environment(\.usesSystemBrowsingToolbar, true)
            .environment(\.usesVerticalBrowsingToolbar, true)
            .environment(\.hasFoldRegion, true)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                resetFrames.frames = frames
            })
        resetHost.traitOverrides.horizontalSizeClass = .regular
        let resetWindow = UIWindow(windowScene: scene)
        resetWindow.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
        resetWindow.rootViewController = resetHost
        resetWindow.makeKeyAndVisible()
        defer {
            resetWindow.isHidden = true
            resetWindow.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(100))
        model.openPhoto(first)
        try await waitFor("Photo Preview did not mount for initialPresentation .photoPreview") {
            resetFrames.frames["clove.duo.photoPreview"] != nil
                && self.hasGridCollection(in: resetWindow)
        }
        #expect(resetFrames.frames["clove.duo.focus"] == nil)
        #expect(findFilmstripScrollView(in: resetWindow) == nil)

        model.openPhoto(second)
        try await Task.sleep(for: .milliseconds(100))
        #expect(resetFrames.frames["clove.duo.photoPreview"] != nil)
        #expect(resetFrames.frames["clove.duo.focus"] == nil)

        model.back()
        try await waitFor("reset host did not return to Grid View") {
            resetFrames.frames["clove.duo.photoPreview"] == nil
                && self.hasGridCollection(in: resetWindow)
        }

        model.openPhoto(first)
        try await waitFor("reopening after Back did not reset expanded Duo to Focus View") {
            resetFrames.frames["clove.duo.focus"] != nil
                && resetFrames.frames["clove.detail.filmstrip"] != nil
                && !self.hasGridCollection(in: resetWindow)
                && self.findFilmstripScrollView(in: resetWindow) != nil
        }
        #expect(resetFrames.frames["clove.duo.photoPreview"] == nil)
    }

    @Test func phoneIdiomNeverMountsSplitSidebarDuringRegularRotationAndSnapshotTransitions()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let photo = try #require(model.photos.first?.id)
        model.openPhoto(photo)

        let duoBox = TestDuoEnvironmentBox()
        struct HostView: View {
            let model: BrowsingModel
            let duoBox: TestDuoEnvironmentBox
            var body: some View {
                BrowseShell(browsing: model)
                    .environment(SettingsStore.sample)
                    .environment(\.usesSystemBrowsingToolbar, duoBox.usesSystemToolbar)
                    .environment(\.usesVerticalBrowsingToolbar, duoBox.usesVertical)
                    .environment(\.hasFoldRegion, duoBox.hasFoldRegion)
                    .environment(\.isDuoExpanded, duoBox.isDuoExpanded)
                    .environment(\.isDuoCover, duoBox.isDuoCover)
                    .environment(\.scenePhase, duoBox.scenePhase)
            }
        }

        let host = UIHostingController(rootView: HostView(model: model, duoBox: duoBox))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let steps: [(UIUserInterfaceSizeClass, Bool, Bool, Bool, Bool, ScenePhase, BrowserRoute)] =
            [
                (.regular, true, false, true, true, .active, .detail),
                // Portrait unfolded / background snapshot override where vertical edge & fold region clear.
                (.regular, false, false, false, false, .inactive, .detail),
                (.regular, false, false, false, false, .background, .grid),
                // Return to active expanded detail, then compact cover -> regular snapshot churn.
                (.regular, true, false, true, true, .active, .detail),
                (.compact, false, true, true, false, .active, .detail),
                (.regular, false, false, false, false, .inactive, .detail),
                (.regular, false, false, false, false, .active, .grid),
            ]

        for (sizeClass, expanded, cover, vertical, foldRegion, phase, route) in steps {
            if route == .grid, model.state.route != .grid {
                model.back()
            } else if route == .detail, model.state.route != .detail {
                model.openPhoto(photo)
            }
            duoBox.isDuoExpanded = expanded
            duoBox.isDuoCover = cover
            duoBox.usesVertical = vertical
            duoBox.hasFoldRegion = foldRegion
            duoBox.scenePhase = phase
            host.traitOverrides.horizontalSizeClass = sizeClass
            UIView.performWithoutAnimation {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await Task.sleep(for: .milliseconds(80))
            #expect(model.state.route == route)
            #expect(model.state.currentPhoto == photo)
            if UIDevice.current.userInterfaceIdiom == .phone {
                #expect(findSplitViewController(in: host) == nil)
            }
        }
    }

    @Test func fallbackMarkingPopoversDismissOnPhotoLayoutAndScenePhaseTransitions()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let photos = TestLibrary.sample().photos
        let first = try #require(photos.first?.id)
        let second = try #require(photos.dropFirst().first?.id)

        // 1. Photo change dismisses fallback rating popover.
        do {
            let box = TestToolbarHostBox(photoID: first)
            struct HostView: View {
                let box: TestToolbarHostBox
                var body: some View {
                    MarkRatingAction(
                        rating: .unrated,
                        enabledRatings: .all,
                        photoID: box.photoID,
                        onRate: { _ in },
                        fallbackPopoverTrigger: box.popoverTrigger
                    )
                    .disabled(!box.isEnabled)
                    .environment(\.isDuoExpanded, box.isDuoExpanded)
                    .environment(\.isDuoCover, box.isDuoCover)
                    .environment(\.scenePhase, box.scenePhase)
                }
            }

            let host = UIHostingController(rootView: HostView(box: box))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 420, height: 800)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            box.popoverTrigger += 1
            try await waitFor("rating popover presented") {
                self.topPresentedViewController(from: host) != nil
            }
            box.photoID = second
            try await waitFor("rating popover dismissed on photo change") {
                self.topPresentedViewController(from: host) == nil
            }
        }

        // 2. Scene deactivation + snapshot dismisses fallback label popover.
        do {
            let box = TestToolbarHostBox(photoID: first)
            struct HostView: View {
                let box: TestToolbarHostBox
                var body: some View {
                    MarkLabelAction(
                        label: nil,
                        photoID: box.photoID,
                        onPick: { _ in },
                        fallbackPopoverTrigger: box.popoverTrigger
                    )
                    .disabled(!box.isEnabled)
                    .environment(\.isDuoExpanded, box.isDuoExpanded)
                    .environment(\.isDuoCover, box.isDuoCover)
                    .environment(\.scenePhase, box.scenePhase)
                }
            }

            let host = UIHostingController(rootView: HostView(box: box))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 420, height: 800)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            box.popoverTrigger += 1
            try await waitFor("label popover presented") {
                self.topPresentedViewController(from: host) != nil
            }
            box.scenePhase = .inactive
            UIView.performWithoutAnimation {
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await waitFor("label popover dismissed on inactive scene") {
                self.topPresentedViewController(from: host) == nil
            }
        }

        // 3. Size-class / Duo posture change dismisses fallback rating popover.
        do {
            let box = TestToolbarHostBox(photoID: first)
            struct HostView: View {
                let box: TestToolbarHostBox
                var body: some View {
                    MarkRatingAction(
                        rating: .unrated,
                        enabledRatings: .all,
                        photoID: box.photoID,
                        onRate: { _ in },
                        fallbackPopoverTrigger: box.popoverTrigger
                    )
                    .disabled(!box.isEnabled)
                    .environment(\.isDuoExpanded, box.isDuoExpanded)
                    .environment(\.isDuoCover, box.isDuoCover)
                    .environment(\.scenePhase, box.scenePhase)
                }
            }

            let host = UIHostingController(rootView: HostView(box: box))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 420, height: 800)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            box.popoverTrigger += 1
            try await waitFor("rating popover re-presented") {
                self.topPresentedViewController(from: host) != nil
            }
            host.traitOverrides.horizontalSizeClass = .regular
            box.isDuoExpanded = true
            UIView.performWithoutAnimation {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await waitFor("rating popover dismissed on posture change") {
                self.topPresentedViewController(from: host) == nil
            }
        }

        // 4. MarkLabelAction fallback popover dismisses on Duo Cover posture & inactive scene snapshot.
        do {
            let box = TestToolbarHostBox(photoID: first)
            box.isDuoCover = true
            struct HostView: View {
                let box: TestToolbarHostBox
                var body: some View {
                    MarkLabelAction(
                        label: nil,
                        photoID: box.photoID,
                        onPick: { _ in },
                        fallbackPopoverTrigger: box.popoverTrigger
                    )
                    .disabled(!box.isEnabled)
                    .environment(\.isDuoExpanded, box.isDuoExpanded)
                    .environment(\.isDuoCover, box.isDuoCover)
                    .environment(\.scenePhase, box.scenePhase)
                }
            }

            let host = UIHostingController(rootView: HostView(box: box))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 420, height: 800)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(80))
            window.layoutIfNeeded()
            box.popoverTrigger += 1
            try await waitFor("cover label popover presented") {
                self.topPresentedViewController(from: host) != nil
            }
            box.isDuoCover = false
            box.scenePhase = .inactive
            UIView.performWithoutAnimation {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await waitFor("cover label popover dismissed on posture/scene change") {
                self.topPresentedViewController(from: host) == nil
            }
        }
    }

    @Test func ordinaryPhoneLandscapeGridAdaptsColumnsAndPreservesScrollAnchorAcrossRotation()
        async throws
    {
        #expect(GridCollectionView.columns(width: 393, regular: false) == 3)
        #expect(GridCollectionView.columns(width: 430, regular: false) == 3)
        #expect(GridCollectionView.columns(width: 667, regular: false) >= 4)
        #expect(GridCollectionView.columns(width: 734, regular: false) == 6)
        #expect(GridCollectionView.columns(width: 740, regular: false) == 6)
        #expect(GridCollectionView.columns(width: 750, regular: false) == 6)
        #expect(GridCollectionView.columns(width: 844, regular: false) == 6)
        #expect(GridCollectionView.columns(width: 814, regular: true, compactHeight: true) == 6)
        #expect(GridCollectionView.columns(width: 932, regular: false) >= 5)
        // Regular-height iPad widths keep the 140 pt adaptive density.
        #expect(GridCollectionView.columns(width: 584, regular: true) == 4)
        #expect(GridCollectionView.columns(width: 944, regular: true) == 6)
        #expect(GridCollectionView.columns(width: 1116, regular: true) == 7)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }

        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: model, thumbnails: model.thumbnails)
            }
            .environment(SettingsStore.sample)
            .environment(\.cloveUserInterfaceIdiom, .phone))
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        var collectionView: UICollectionView?
        try await waitFor("grid collection did not lay out") {
            collectionView = self.findCollectionView(in: window)
            return collectionView?.visibleCells.isEmpty == false
                && (collectionView?.contentSize.height ?? 0) > 1000
        }
        let grid = try #require(collectionView)
        // Scroll into the middle of the folder in portrait.
        let targetItem = 15
        grid.scrollToItem(at: IndexPath(item: targetItem, section: 0), at: .top, animated: false)
        grid.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let topItemBefore = grid.indexPathsForVisibleItems.min()?.item
        let anchoredItem = try #require(topItemBefore)
        #expect(anchoredItem >= 9)

        // Rotate to Pro Max landscape (where UIKit/traits can report horizontalSizeClass == .regular).
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .compact
        window.frame = CGRect(x: 0, y: 0, width: 932, height: 430)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let visibleInLandscape = Set(grid.indexPathsForVisibleItems.map(\.item))
        #expect(
            visibleInLandscape.contains { abs($0 - anchoredItem) <= 8 },
            "Expected anchored item \(anchoredItem) near visible items \(visibleInLandscape)")

        // Rotate back to portrait and verify anchor remains near the middle, not reset to 0.
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        let visibleBackInPortrait = grid.indexPathsForVisibleItems.map(\.item)
        #expect((visibleBackInPortrait.min() ?? 0) >= 3)
    }

    @Test func ordinaryPhoneLandscapeGridUses44PtHeaderAndSixColumnsAtLandscapeUsableWidths()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }

        let headerFrames = TestHeaderFramesBox()
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: model, thumbnails: model.thumbnails)
            }
            .environment(SettingsStore.sample)
            .environment(\.cloveUserInterfaceIdiom, .phone)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                headerFrames.frames = frames
            })
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .compact

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 750, height: 390)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        var collectionView: UICollectionView?
        try await waitFor("landscape grid header and collection did not lay out") {
            collectionView = self.findCollectionView(in: window)
            return headerFrames.frames["clove.browsing.header"] != nil
                && collectionView?.visibleCells.isEmpty == false
        }

        let landscapeHeader = try #require(headerFrames.frames["clove.browsing.header"])
        #expect(abs(landscapeHeader.height - 44) <= 0.5)

        let grid = try #require(collectionView)
        let row0Cells = grid.visibleCells.filter { cell in
            guard let indexPath = grid.indexPath(for: cell) else { return false }
            return indexPath.section == 0 && indexPath.item < 6
        }
        #expect(row0Cells.count == 6)
        if let firstMinY = row0Cells.first?.frame.minY {
            for cell in row0Cells {
                #expect(abs(cell.frame.minY - firstMinY) <= 0.5)
            }
        }

        // Portrait keeps the 64 pt header and 3-column grid.
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor("portrait grid header did not update") {
            abs((headerFrames.frames["clove.browsing.header"]?.height ?? 0) - 64) <= 0.5
        }
        let portraitCellsRow0 = grid.visibleCells.filter { cell in
            guard let indexPath = grid.indexPath(for: cell) else { return false }
            return indexPath.section == 0 && indexPath.item < 3
        }
        #expect(portraitCellsRow0.count == 3)
        let fourthCell = grid.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
        let firstCell = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        if let firstCell, let fourthCell {
            #expect(fourthCell.frame.minY > firstCell.frame.maxY)
        }
    }

    @Test func compactGridSelectionHeaderFitsNarrowWidthsWithoutOverlap() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for width in [CGFloat(320), CGFloat(375), CGFloat(393)] {
            for language in [
                ResolvedAppLanguage.english, .simplifiedChinese, .traditionalChinese,
            ] {
                let model = BrowsingModel(
                    library: TestLibrary.sample(), similarGroupsEnabled: false)
                model.openFolder()
                let selected = Array(model.photos.prefix(3))
                for photo in selected { model.toggleSelection(photo.id) }
                let fiveStars = try #require(Rating(rawValue: 5))
                model.apply(.rating(fiveStars), to: selected[0].id)
                model.setFilter(.ratedAtLeast(fiveStars))
                let box = TestHeaderFramesBox()

                struct HostView: View {
                    let model: BrowsingModel
                    let language: ResolvedAppLanguage
                    let box: TestHeaderFramesBox
                    var body: some View {
                        GridScreen(browsing: model, thumbnails: model.thumbnails)
                            .environment(SettingsStore.sample)
                            .environment(\.cloveUserInterfaceIdiom, .phone)
                            .environment(\.appLanguage, language)
                            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                                box.frames = frames
                            }
                    }
                }

                let host = UIHostingController(
                    rootView: HostView(model: model, language: language, box: box))
                host.traitOverrides.horizontalSizeClass = .compact
                host.traitOverrides.verticalSizeClass = .regular
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }

                try await waitFor(
                    "grid selection header mounted (\(width), \(language.rawValue))"
                ) {
                    box.frames["clove.grid.selectAll"] != nil
                        && box.frames["clove.grid.batch.count"] != nil
                        && box.frames["clove.grid.batch.hiddenCount"] != nil
                        && box.frames["clove.grid.filter"] != nil
                        && box.frames["clove.grid.batch.done"] != nil
                }

                let selectAllFrame = try #require(box.frames["clove.grid.selectAll"])
                let countFrame = try #require(box.frames["clove.grid.batch.count"])
                let hiddenFrame = try #require(box.frames["clove.grid.batch.hiddenCount"])
                let filterFrame = try #require(box.frames["clove.grid.filter"])
                let doneFrame = try #require(box.frames["clove.grid.batch.done"])

                for frame in [selectAllFrame, countFrame, hiddenFrame, filterFrame, doneFrame] {
                    #expect(frame.width > 0 && frame.height > 0)
                    #expect(frame.minX >= 16 - 1.5)
                    #expect(frame.maxX <= width - 16 + 1.5)
                }

                let titleMinX = min(countFrame.minX, hiddenFrame.minX)
                let titleMaxX = max(countFrame.maxX, hiddenFrame.maxX)
                #expect(selectAllFrame.maxX <= titleMinX + 1.5)
                #expect(titleMaxX <= filterFrame.minX + 1.5)
                #expect(filterFrame.maxX <= doneFrame.minX + 1.5)
            }
        }
    }

    @Test func selectModeHeaderChromeShowsLeadingSelectAllTogglingToDeselectAllAndCompactFilter()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        // 1. Compact iPhone system toolbar: leading Select All/Deselect All + Filter + Done.
        do {
            let model = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
            model.openFolder()
            try await waitFor("folder did not open") { !model.isFolderOpening }
            let first = try #require(model.photos.first?.id)
            model.toggleSelection(first)

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.usesSystemBrowsingToolbar, true))
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("compact select mode toolbar did not mount") {
                self.hasToolbarItem(identifier: "clove.grid.selectAll", in: host, window: window)
                    && self.hasToolbarItem(
                        identifier: "clove.grid.filter", in: host, window: window)
                    && self.hasToolbarItem(
                        identifier: "clove.grid.batch.done", in: host, window: window)
            }
            let partialSnapshot = inspectToolbarState(in: host, window: window)
            #expect(partialSnapshot.leadingIDs == ["clove.grid.selectAll"])
            #expect(partialSnapshot.trailingIDs == ["clove.grid.filter", "clove.grid.batch.done"])
            #expect(!partialSnapshot.contains("clove.grid.selectionOptions"))

            model.selectAllVisible()
            try await Task.sleep(for: .milliseconds(80))
            let allSelectedSnapshot = inspectToolbarState(in: host, window: window)
            #expect(allSelectedSnapshot.leadingIDs == ["clove.grid.selectAll"])
        }

        // 2. Wide iPad system toolbar: leading Select All + trailing Done, no Filter in header.
        do {
            let model = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
            model.openFolder()
            try await waitFor("folder did not open") { !model.isFolderOpening }
            let first = try #require(model.photos.first?.id)
            model.toggleSelection(first)

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 900, height: 820)
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.usesSystemBrowsingToolbar, true))
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("ipad select mode toolbar did not mount") {
                self.hasToolbarItem(identifier: "clove.grid.selectAll", in: host, window: window)
                    && self.hasToolbarItem(
                        identifier: "clove.grid.batch.done", in: host, window: window)
            }
            let padSnapshot = inspectToolbarState(in: host, window: window)
            #expect(padSnapshot.leadingIDs == ["clove.grid.selectAll"])
            #expect(padSnapshot.trailingIDs == ["clove.grid.batch.done"])
            #expect(!padSnapshot.contains("clove.grid.filter"))
            #expect(!padSnapshot.contains("clove.grid.selectionOptions"))
        }
    }

    @Test func batchRenameOrderCompactHeaderFitsNarrowWidthsWithoutOverlap() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for width in [CGFloat(320), CGFloat(375), CGFloat(393)] {
            for language in [
                ResolvedAppLanguage.english, .simplifiedChinese, .traditionalChinese,
            ] {
                let model = BrowsingModel(
                    library: TestLibrary.sample(), similarGroupsEnabled: false)
                model.openFolder()
                for photo in model.photos.prefix(3) { model.toggleSelection(photo.id) }
                let flow = BatchRenameFlow(browsing: model)
                let box = TestHeaderFramesBox()

                struct HostView: View {
                    let flow: BatchRenameFlow
                    let language: ResolvedAppLanguage
                    let box: TestHeaderFramesBox
                    var body: some View {
                        BatchRenameOrderScreen(flow: flow)
                            .environment(SettingsStore.sample)
                            .environment(\.appLanguage, language)
                            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                                box.frames = frames
                            }
                    }
                }

                let host = UIHostingController(
                    rootView: HostView(flow: flow, language: language, box: box))
                host.traitOverrides.horizontalSizeClass = .compact
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }

                try await waitFor(
                    "rename order header mounted (\(width), \(language.rawValue))"
                ) {
                    box.frames["clove.rename.cancel"] != nil
                        && box.frames["clove.rename.order.title"] != nil
                        && box.frames["clove.rename.sort"] != nil
                        && box.frames["clove.rename.next"] != nil
                }

                let cancelFrame = try #require(box.frames["clove.rename.cancel"])
                let titleFrame = try #require(box.frames["clove.rename.order.title"])
                let sortFrame = try #require(box.frames["clove.rename.sort"])
                let nextFrame = try #require(box.frames["clove.rename.next"])

                for frame in [cancelFrame, titleFrame, sortFrame, nextFrame] {
                    #expect(frame.width > 0 && frame.height > 0)
                    #expect(frame.minX >= 16 - 1.5)
                    #expect(frame.maxX <= width - 16 + 1.5)
                }

                #expect(cancelFrame.maxX <= titleFrame.minX + 1.5)
                #expect(titleFrame.maxX <= sortFrame.minX + 1.5)
                #expect(sortFrame.maxX <= nextFrame.minX + 1.5)
            }
        }
    }

    @Test func gridSubtitleShowsPhotoCountAndFiltersInsteadOfFindingSimilarShotsDuringGrouping()
        async throws
    {
        let library = try #require(
            TestLibrary.forLaunch(
                environment: [
                    TestLibrary.launchVariable: "1",
                    "CLOVE_TEST_LIBRARY_OPENING": "grouping",
                ]) as? TestLibrary)
        let model = BrowsingModel(library: library)
        model.openFolder()
        try await waitFor("grouping progress applied to model") {
            model.isFindingSimilarShots
                && model.groupingProgress == .analyzing(completed: 12, total: 24)
                && model.readingProgress == nil
        }

        // Subtitle helper returns real photo count and active filter counts while grouping runs.
        #expect(
            GridScreen.subtitleText(browsing: model, isSelecting: false, isRegular: false)
                == "36 photos")
        #expect(
            GridScreen.subtitleText(browsing: model, isSelecting: false, isRegular: true)
                == "36 photos")

        model.setFilter(.rejected)
        let rejectedCount = model.photos.count
        #expect(
            GridScreen.subtitleText(browsing: model, isSelecting: false, isRegular: false)
                == "Rejected · \(rejectedCount)")
        model.setFilter(.all)

        // Grouping never renders a static 100% top progress line; only scanning shows the line.
        let activeLine = GridScreen.progressLineState(browsing: model, similarGroupsEnabled: true)
        #expect(activeLine.progress == nil)
        #expect(activeLine.tone == .reading)

        // GridScreen mounts preparation indicator beside title during grouping.
        let box = TestHeaderFramesBox()
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: model, thumbnails: model.thumbnails)
            }
            .environment(SettingsStore.sample)
            .environment(\.cloveUserInterfaceIdiom, .phone)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                box.frames = frames
            })
        host.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("grid header laid out during grouping") {
            box.frames["clove.grid.title"] != nil
                && box.frames["clove.grid.preparation"] != nil
        }

        // Pausing via location loss / waitingReason also keeps progress line hidden.
        library.reportLocationLoss(.externalVolumeDisconnected)
        try await waitFor("waiting reason applied to model") {
            model.preparationStatus.waitingReason != nil
        }
        let pausedLine = GridScreen.progressLineState(browsing: model, similarGroupsEnabled: true)
        #expect(pausedLine.progress == nil)
        #expect(pausedLine.tone == .reading)

        // Scanning/reading progress still renders the top ProgressLine with tone .reading.
        let readingLibrary = try #require(
            TestLibrary.forLaunch(
                environment: [
                    TestLibrary.launchVariable: "1",
                    "CLOVE_TEST_LIBRARY_OPENING": "reading",
                ]) as? TestLibrary)
        let readingModel = BrowsingModel(library: readingLibrary)
        readingModel.openFolder()
        try await waitFor("reading progress applied to model") {
            readingModel.readingProgress != nil
        }
        let readingLine = GridScreen.progressLineState(
            browsing: readingModel, similarGroupsEnabled: true)
        let readingProgress = try #require(readingLine.progress)
        #expect(abs(readingProgress - (12.0 / 36.0)) < 0.001)
        #expect(readingLine.tone == .reading)
    }

    @Test func filmstripGridPickerAdaptsAcrossWidthChangesWithoutOscillation() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let folder = FolderIdentity(rawValue: "filmstrip-width-adapt")
        let photos = (1...8).map { index in
            GridPhoto(
                id: PhotoIdentity(
                    folderID: folder, relativeFolderPath: "",
                    stem: String(format: "ADP%03d", index)),
                fileName: String(format: "ADP%03d.ARW", index),
                time: .unavailable,
                marks: PhotoMarks())
        }
        let groupID = GroupID(rawValue: "adapt-group")
        let groups = [BrowsingGroup(id: groupID, members: photos.map(\.id))]
        let timeline = DetailTimeline(photos: photos, groups: groups, groupsEnabled: true)
        let expanded = try #require(timeline.activeGroup(with: groupID))

        let framesBox = TestTapPickerFramesBox()
        let triggerBox = TestPickerTriggerBox()

        struct HostView: View {
            let timeline: DetailTimeline
            let expandedGroup: ActiveBrowsingGroup
            let current: PhotoIdentity
            let triggerBox: TestPickerTriggerBox

            var body: some View {
                VStack {
                    Spacer()
                    DetailFilmstrip(
                        timeline: timeline,
                        expandedGroup: expandedGroup,
                        current: current,
                        thumbnails: TestLibrary.sampleThumbnails,
                        openPhoto: { _ in },
                        selectGroupPhoto: { _ in },
                        expandGroup: { _ in },
                        collapseGroup: {}
                    )
                }
                .environment(\.cloveTheme, .light)
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, triggerBox.trigger)
            }
        }

        let host = UIHostingController(
            rootView: HostView(
                timeline: timeline,
                expandedGroup: expanded,
                current: photos[0].id,
                triggerBox: triggerBox
            )
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                framesBox.frames = frames
            })
        host.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 600)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // At 402 pt (8 members = 453 pt), gridPicker is shown and opens a popover.
        try await waitFor("gridPicker did not appear at narrow width") {
            framesBox.frames["clove.detail.filmstrip.group.gridPicker"] != nil
                && framesBox.frames["clove.detail.filmstrip.group.fold"] != nil
        }
        try await Task.sleep(for: .milliseconds(80))
        triggerBox.sendTrigger("clove.detail.filmstrip.group.gridPicker")
        try await waitFor("popover did not open at narrow width") {
            self.topPresentedViewController(from: host) != nil
        }

        // Widening to 700 pt (8 members fit without scrolling) hides gridPicker & dismisses popover.
        window.frame = CGRect(x: 0, y: 0, width: 700, height: 600)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor("gridPicker did not hide and dismiss at wide width") {
            framesBox.frames["clove.detail.filmstrip.group.gridPicker"] == nil
                && framesBox.frames["clove.detail.filmstrip.group.fold"] != nil
                && self.topPresentedViewController(from: host) == nil
        }

        // Narrowing back to 402 pt restores gridPicker cleanly.
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 600)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor("gridPicker did not reappear when narrowed") {
            framesBox.frames["clove.detail.filmstrip.group.gridPicker"] != nil
        }
    }

    @Test func iPadDetailBackButtonShowsSelectedFilterTitleAcrossNativeAndFallbackToolbars()
        async throws
    {
        #expect(
            DetailMarkingView.resolvedBackTitle(
                isWidePadLayout: true, isDuoExpanded: false, filterTitle: "All") == "All")
        #expect(
            DetailMarkingView.resolvedBackTitle(
                isWidePadLayout: true, isDuoExpanded: false, filterTitle: "Unmarked")
                == "Unmarked")
        #expect(
            DetailMarkingView.resolvedBackTitle(
                isWidePadLayout: false, isDuoExpanded: false, filterTitle: "All") == nil)
        #expect(
            DetailMarkingView.resolvedBackTitle(
                isWidePadLayout: true, isDuoExpanded: true, filterTitle: "All") == nil)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let folder = TestLibrary.sampleFolderKey
        let longSubfolder = "DCIM/101CANON_VERY_LONG_EVENT_FOLDER_NAME_2026"
        let photos = [
            GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: longSubfolder, stem: "p1"),
                fileName: "P1.ARW",
                time: .known(
                    PhotoTime(
                        captureTime: Date(timeIntervalSince1970: 1_760_000_001),
                        hasUTCOffset: true)),
                marks: PhotoMarks()),
            GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "p2"),
                fileName: "P2.ARW",
                time: .known(
                    PhotoTime(
                        captureTime: Date(timeIntervalSince1970: 1_760_000_002),
                        hasUTCOffset: true)),
                marks: PhotoMarks(label: ColourLabel(colour: .red))),
        ]
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let model = BrowsingModel(
            library: TestLibrary(photos: photos, groups: []), similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        model.openPhoto(photos[0].id)

        // 1. iPadOS 27.1+ native system toolbar renders `< {SelectedRowTitle}` cleanly on wide
        //    iPad while keeping iPhone and Duo icon-only.
        if #available(iOS 27.1, *) {
            struct NativeDetailHost: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let idiom: UIUserInterfaceIdiom
                let isDuoExpanded: Bool
                let duo: DuoDetailLayout?

                var body: some View {
                    NavigationStack {
                        DetailScreen(browsing: browsing, duo: duo)
                    }
                    .environment(store)
                    .environment(\.cloveUserInterfaceIdiom, idiom)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.isDuoExpanded, isDuoExpanded)
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            let padHost = UIHostingController(
                rootView: NativeDetailHost(
                    browsing: model, store: store, idiom: .pad, isDuoExpanded: false, duo: nil))
            padHost.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = padHost
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "native iPad detail nav bar did not lay out: \(self.describeNavBar(in: window))"
            ) {
                guard let navBar = self.findNavigationBar(in: window) else { return false }
                return !(navBar.topItem?.leadingItemGroups.isEmpty ?? true)
                    && self.leadingBarItemFrame(in: navBar, index: 0, relativeTo: window) != nil
            }
            let navBar = try #require(findNavigationBar(in: window))
            let shortBackFrame = try #require(
                leadingBarItemFrame(in: navBar, index: 0, relativeTo: window))
            #expect(shortBackFrame.width > 20 && shortBackFrame.width < 110)

            model.setFilter(.unmarked)
            try await waitFor(
                "native iPad detail nav bar did not widen for Unmarked: \(self.describeNavBar(in: window))"
            ) {
                guard
                    let frame = self.leadingBarItemFrame(
                        in: navBar, index: 0, relativeTo: window)
                else { return false }
                return frame.width > shortBackFrame.width + 15
            }

            model.setFilter(.subfolder(longSubfolder))
            try await waitFor(
                "native iPad detail nav bar did not cap long back title width: \(self.describeNavBar(in: window))"
            ) {
                guard
                    let frame = self.leadingBarItemFrame(
                        in: navBar, index: 0, relativeTo: window)
                else { return false }
                return frame.width > shortBackFrame.width + 40 && frame.width <= 190
            }
            let longBackFrame = try #require(
                leadingBarItemFrame(in: navBar, index: 0, relativeTo: window))
            if let centerFrame = centerBarGroupFrame(in: navBar, relativeTo: window) {
                #expect(longBackFrame.maxX <= centerFrame.minX + 2)
            }

            // Ordinary iPhone (even regular width in Pro Max landscape) keeps icon-only Back.
            model.setFilter(.unmarked)
            let phoneHost = UIHostingController(
                rootView: NativeDetailHost(
                    browsing: model, store: store, idiom: .phone, isDuoExpanded: false, duo: nil))
            phoneHost.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = phoneHost
            phoneHost.view.setNeedsLayout()
            phoneHost.view.layoutIfNeeded()
            try await waitFor(
                "native iPhone detail nav bar did not lay out: \(self.describeNavBar(in: window))"
            ) {
                guard let phoneNavBar = self.findNavigationBar(in: window),
                    let frame = self.leadingBarItemFrame(
                        in: phoneNavBar, index: 0, relativeTo: window)
                else { return false }
                return frame.width <= 60
            }

            // Duo expanded keeps icon-only Back in BrowsingToolbar.
            let duoPresentation = Binding.constant(DetailPresentation.focus)
            let duoHost = UIHostingController(
                rootView: NativeDetailHost(
                    browsing: model,
                    store: store,
                    idiom: .phone,
                    isDuoExpanded: true,
                    duo: DuoDetailLayout(
                        presentation: duoPresentation,
                        showsGrid: true)))
            duoHost.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = duoHost
            duoHost.view.setNeedsLayout()
            duoHost.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            if let duoNavBar = findNavigationBar(in: window),
                let duoBackFrame = leadingBarItemFrame(
                    in: duoNavBar, index: 0, relativeTo: window)
            {
                #expect(duoBackFrame.width <= 60)
            }
        }

        // 2. Fallback BrowsingHeader on wide iPad also renders `< {SelectedRowTitle}`.
        model.setFilter(.unmarked)
        let fallbackFrames = TestHeaderFramesBox()
        let fallbackWindow = UIWindow(windowScene: scene)
        fallbackWindow.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let fallbackHost = UIHostingController(
            rootView: DetailScreen(browsing: model)
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.usesSystemBrowsingToolbar, false)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    fallbackFrames.frames = frames
                })
        fallbackHost.traitOverrides.horizontalSizeClass = .regular
        fallbackWindow.rootViewController = fallbackHost
        fallbackWindow.makeKeyAndVisible()
        defer {
            fallbackWindow.isHidden = true
            fallbackWindow.rootViewController = nil
        }
        try await waitFor("fallback wide iPad detail header did not render Unmarked back title") {
            guard let backFrame = fallbackFrames.frames["clove.nav.back"] else { return false }
            return backFrame.width > 60 && backFrame.width <= 165
        }
    }

    @Test func iPadSidebarUses280WidthProminentTitleCasingAnd10PtDots() async throws {
        #expect(BrowseShell.idealSidebarWidth == 280)
        #expect(FolderSidebar.labelDotSize == 10)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let folder = TestLibrary.sampleFolderKey
        let photos = [
            GridPhoto(
                id: PhotoIdentity(
                    folderID: folder, relativeFolderPath: "DCIM/100CANON", stem: "p1"),
                fileName: "P1.ARW",
                time: .known(
                    PhotoTime(
                        captureTime: Date(timeIntervalSince1970: 1_760_000_001),
                        hasUTCOffset: true)),
                marks: PhotoMarks(
                    rating: try #require(Rating(rawValue: 4)),
                    label: ColourLabel(colour: .red),
                    keywords: ["portrait"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-1M2", lens: "FE 50mm F1.2 GM", focalLengthMillimetres: 50)),
            GridPhoto(
                id: PhotoIdentity(
                    folderID: folder, relativeFolderPath: "DCIM/101CANON", stem: "p2"),
                fileName: "P2.ARW",
                time: .known(
                    PhotoTime(
                        captureTime: Date(timeIntervalSince1970: 1_760_000_002),
                        hasUTCOffset: true)),
                marks: PhotoMarks(label: ColourLabel(colour: .green), keywords: ["street"]),
                metadata: PhotoFilterMetadata(
                    camera: "ILCE-7M4", lens: "FE 35mm F1.4 GM", focalLengthMillimetres: 35)),
        ]
        let group = BrowsingGroup(
            id: GroupID(rawValue: "g1"), members: [photos[0].id, photos[1].id])
        let model = BrowsingModel(library: TestLibrary(photos: photos, groups: [group]))
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }

        // 1. BrowseShell regular iPad split view sets sidebar column width to 280 pt.
        let shellWindow = UIWindow(windowScene: scene)
        shellWindow.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let shellHost = UIHostingController(
            rootView: BrowseShell(browsing: model)
                .environment(SettingsStore.sample)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.usesSystemBrowsingToolbar, true))
        shellHost.traitOverrides.horizontalSizeClass = .regular
        shellWindow.rootViewController = shellHost
        shellWindow.makeKeyAndVisible()
        defer {
            shellWindow.isHidden = true
            shellWindow.rootViewController = nil
        }

        try await waitFor("iPad BrowseShell sidebar did not lay out") {
            guard let split = self.findSplitViewController(in: shellHost) else { return false }
            return abs(split.primaryColumnWidth - 280) <= 2
        }
        let split = try #require(findSplitViewController(in: shellHost))
        #expect(abs(split.primaryColumnWidth - 280) <= 2)

        // 2. FolderSidebar retains `<` back button with 22 pt bold folder title, updated section
        //    casing, metadata sections, and 10 x 10 pt color label dots.
        let sidebarFrames = TestHeaderFramesBox()
        let sidebarWindow = UIWindow(windowScene: scene)
        sidebarWindow.frame = CGRect(x: 0, y: 0, width: 280, height: 1400)
        let sidebarHost = UIHostingController(
            rootView: FolderSidebar(browsing: model)
                .environment(SettingsStore.sample)
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    sidebarFrames.frames = frames
                })
        sidebarWindow.rootViewController = sidebarHost
        sidebarWindow.makeKeyAndVisible()
        defer {
            sidebarWindow.isHidden = true
            sidebarWindow.rootViewController = nil
        }

        try await waitFor(
            "FolderSidebar content did not mount (frames=\(sidebarFrames.frames.keys.sorted()))"
        ) {
            sidebarHost.view.setNeedsLayout()
            sidebarHost.view.layoutIfNeeded()
            return sidebarFrames.frames["clove.nav.back"] != nil
                && sidebarFrames.frames["clove.sidebar.folderTitle"] != nil
                && sidebarFrames.frames["clove.sidebar.label.red.dot"] != nil
        }

        let backFrame = try #require(sidebarFrames.frames["clove.nav.back"])
        let titleFrame = try #require(sidebarFrames.frames["clove.sidebar.folderTitle"])
        #expect(backFrame.minX >= 0 && backFrame.maxX <= 280)
        // 22 pt bold title (`title2.bold()`) renders taller than 17 pt `.headline`.
        #expect(titleFrame.height >= 24)
        #expect(titleFrame.maxX <= 280)

        let redDotFrame = try #require(sidebarFrames.frames["clove.sidebar.label.red.dot"])
        #expect(abs(redDotFrame.width - 10) <= 0.5)
        #expect(abs(redDotFrame.height - 10) <= 0.5)
    }

    @Test func iPadGridHeaderUsesLeading20PtBoldTitleWhileKeepingCompactAndSelectHeaders()
        async throws
    {
        #expect(GridScreen.usesLeadingRegularHeader(isRegular: true, isSelecting: false))
        #expect(!GridScreen.usesLeadingRegularHeader(isRegular: true, isSelecting: true))
        #expect(!GridScreen.usesLeadingRegularHeader(isRegular: false, isSelecting: false))

        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }

        struct GridHost: View {
            let browsing: BrowsingModel
            let idiom: UIUserInterfaceIdiom
            let isDuoExpanded: Bool

            var body: some View {
                NavigationStack {
                    GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                }
                .environment(SettingsStore.sample)
                .environment(\.cloveUserInterfaceIdiom, idiom)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.isDuoExpanded, isDuoExpanded)
            }
        }

        // 1. Regular-width iPad Grid (non-selecting): leading-aligned `.topBarLeading` item,
        //    never centered `.principal`, preserving subtitle and Select mode header.
        let padWindow = UIWindow(windowScene: scene)
        padWindow.frame = CGRect(x: 0, y: 0, width: 900, height: 820)
        let padHost = UIHostingController(
            rootView: GridHost(browsing: model, idiom: .pad, isDuoExpanded: false))
        padHost.traitOverrides.horizontalSizeClass = .regular
        padWindow.rootViewController = padHost
        padWindow.makeKeyAndVisible()
        defer {
            padWindow.isHidden = true
            padWindow.rootViewController = nil
        }

        try await waitFor(
            "iPad Grid nav bar leading header did not mount: \(self.describeNavBar(in: padWindow))"
        ) {
            guard let navBar = self.findNavigationBar(in: padWindow) else { return false }
            return !(navBar.topItem?.leadingItemGroups.isEmpty ?? true)
                && (navBar.topItem?.centerItemGroups.isEmpty ?? true)
                && self.leadingBarItemFrame(in: navBar, index: 0, relativeTo: padWindow) != nil
        }

        let padNavBar = try #require(findNavigationBar(in: padWindow))
        let padHeaderFrame = try #require(
            leadingBarItemFrame(in: padNavBar, index: 0, relativeTo: padWindow))
        #expect(padHeaderFrame.midX < padWindow.bounds.width * 0.35)
        // Two-line `.title3.bold()` (~24 pt) + `.caption` subtitle (~14 pt) sits taller than
        // `.subheadline` single-line height, and wide enough for `"36 photos"` without truncating.
        #expect(padHeaderFrame.height >= 34)
        #expect(padHeaderFrame.width >= 50)

        // Select mode switches back to the centered `.principal` selection header (`N selected`).
        let firstPhoto = try #require(model.photos.first?.id)
        model.toggleSelection(firstPhoto)
        try await waitFor(
            "iPad Grid select header did not switch to centered principal header: \(self.describeNavBar(in: padWindow))"
        ) {
            guard
                let titleFrame = self.centerBarGroupFrame(
                    in: padNavBar, relativeTo: padWindow)
            else { return false }
            let leadingVisible = self.barButtonSubviews(in: padNavBar, relativeTo: padWindow)
                .filter { $0.frame.midX < padWindow.bounds.width * 0.35 }
            return leadingVisible.isEmpty
                && abs(titleFrame.midX - padWindow.bounds.midX) < 80
        }
        model.clearSelection()

        // 2. iPhone Grid keeps centered `.principal` folder title.
        let phoneWindow = UIWindow(windowScene: scene)
        phoneWindow.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let phoneHost = UIHostingController(
            rootView: GridHost(browsing: model, idiom: .phone, isDuoExpanded: false))
        phoneHost.traitOverrides.horizontalSizeClass = .compact
        phoneWindow.rootViewController = phoneHost
        phoneWindow.makeKeyAndVisible()
        defer {
            phoneWindow.isHidden = true
            phoneWindow.rootViewController = nil
        }

        try await waitFor(
            "iPhone Grid nav bar center header did not mount: \(self.describeNavBar(in: phoneWindow))"
        ) {
            guard let navBar = self.findNavigationBar(in: phoneWindow) else { return false }
            return self.centerBarGroupFrame(in: navBar, relativeTo: phoneWindow) != nil
        }
        let phoneNavBar = try #require(findNavigationBar(in: phoneWindow))
        let phoneTitleFrame = try #require(
            centerBarGroupFrame(in: phoneNavBar, relativeTo: phoneWindow))
        #expect(abs(phoneTitleFrame.midX - phoneWindow.bounds.midX) < 60)
    }

    @Test func expandedDuoDetailDockPlacesGridToggleBetweenBackAndToolsCapsule() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = TestLibrary.sample()
        let model = BrowsingModel(library: library)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        let photo = try #require(model.photos.first?.id)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        model.openPhoto(photo)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let headerFrames = TestHeaderFramesBox()

        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(
                    browsing: model,
                    thumbnails: model.thumbnails,
                    initialPresentation: .focus)
            }
            .environment(store)
            .environment(\.cloveUserInterfaceIdiom, .phone)
            .environment(\.isDuoExpanded, true)
            .environment(\.usesSystemBrowsingToolbar, true)
            .environment(\.usesVerticalBrowsingToolbar, true)
            .environment(\.hasFoldRegion, true)
            .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                headerFrames.frames = frames
            })
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor(
            "expanded Duo Detail toolbar items did not mount: \(self.describeToolbarState(in: host, window: window))"
        ) {
            self.hasToolbarItem(identifier: "clove.nav.back", in: host, window: window)
                && self.hasToolbarItem(
                    identifier: "clove.detail.gridToggle", in: host, window: window)
                && self.hasToolbarItem(identifier: "clove.detail.filter", in: host, window: window)
                && headerFrames.frames["clove.detail.photoCornerOverlay"] != nil
                && headerFrames.frames["clove.detail.info"] != nil
                && headerFrames.frames["clove.detail.fileName"] != nil
                && headerFrames.frames["clove.detail.zoom"] != nil
        }

        let snapshot = inspectToolbarState(in: host, window: window)
        // Expanded Duo Detail toolbar carries strictly 3 buttons (< / Grid / Filter); More, Move
        // Rejects, Undo, Info, Focus, and Compare are absent from the system toolbar (#458).
        #expect(!snapshot.contains("clove.grid.more"))
        #expect(!snapshot.contains("clove.grid.filter"))
        #expect(!snapshot.contains("clove.grid.moveRejects"))
        #expect(!snapshot.contains("clove.duo.undo"))
        #expect(!snapshot.contains("clove.detail.undo"))
        #expect(headerFrames.frames["clove.duo.undo"] == nil)
        #expect(headerFrames.frames["clove.detail.undo"] == nil)
        #expect(headerFrames.frames["clove.grid.more"] == nil)
        #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.info" })
        #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.compare" })
        #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.focusToggle" })
        #expect(!snapshot.contains("clove.detail.preparation"))
        #expect(snapshot.bottomToolbarIDs.isEmpty)
        let cornerOverlayFrame = try #require(
            headerFrames.frames["clove.detail.photoCornerOverlay"],
            Comment(rawValue: "missing corner overlay in \(snapshot.description)"))
        let cornerInfoFrame = try #require(
            headerFrames.frames["clove.detail.info"],
            Comment(rawValue: "missing corner info in \(snapshot.description)"))
        #expect(cornerOverlayFrame.width > 0 && cornerOverlayFrame.height > 0)
        #expect(cornerInfoFrame.width >= 44 && cornerInfoFrame.height >= 44)

        let backFrame = try #require(
            snapshot.frame(for: "clove.nav.back"),
            Comment(rawValue: "missing back in \(snapshot.description)"))
        let toggleFrame = try #require(
            snapshot.frame(for: "clove.detail.gridToggle"),
            Comment(rawValue: "missing gridToggle in \(snapshot.description)"))
        let filterFrame = try #require(
            snapshot.frame(for: "clove.detail.filter"),
            Comment(rawValue: "missing filter in \(snapshot.description)"))

        if host.traitCollection.verticalBarEdge != .unspecified {
            #expect(snapshot.frame(for: "clove.duo.undo") == nil)
            #expect(snapshot.frame(for: "clove.detail.undo") == nil)
            #expect(
                backFrame.maxY < toggleFrame.minY,
                Comment(rawValue: "expected Back above gridToggle: \(snapshot.description)"))
            // Back -> photoGridToggle -> standalone Filter are separated controls (~22-23pt gap).
            #expect(
                toggleFrame.minY - backFrame.maxY >= 18,
                Comment(
                    rawValue:
                        "expected standalone gap between Back and gridToggle: \(snapshot.description)"
                ))
            #expect(
                toggleFrame.maxY < filterFrame.minY,
                Comment(rawValue: "expected gridToggle above Filter: \(snapshot.description)"))
            #expect(
                filterFrame.minY - toggleFrame.maxY >= 18,
                Comment(
                    rawValue:
                        "expected standalone gap between gridToggle and Filter: \(snapshot.description)"
                ))

            #expect(snapshot.leadingIDs == ["clove.nav.back"])
            let toggleIdx = try #require(
                snapshot.trailingRawTokens.firstIndex(of: "clove.detail.gridToggle"))
            let filterIdx = try #require(
                snapshot.trailingRawTokens.firstIndex(of: "clove.detail.filter"))
            #expect(toggleIdx < filterIdx)
            #expect(snapshot.trailingRawTokens[toggleIdx..<filterIdx].contains("<spacer>"))
            #expect(!snapshot.trailingRawTokens[filterIdx...].contains("<spacer>"))
            #expect(snapshot.trailingIDs == ["clove.detail.gridToggle", "clove.detail.filter"])
        } else {
            #expect(snapshot.frame(for: "clove.duo.undo") == nil)
            #expect(snapshot.frame(for: "clove.detail.undo") == nil)
            #expect(
                snapshot.leadingIDs == ["clove.nav.back", "clove.detail.gridToggle"],
                Comment(rawValue: "unexpected leadingIDs: \(snapshot.description)"))
            #expect(backFrame.maxX <= toggleFrame.minX + 2)
            #expect(toggleFrame.maxX < filterFrame.minX)
            #expect(snapshot.trailingIDs == ["clove.detail.filter"])
            let navBar = try #require(findNavigationBar(in: window))
            let trailingRawCount =
                navBar.topItem?.trailingItemGroups.flatMap(\.barButtonItems).count ?? 0
            #expect(snapshot.rawLeadingItemCount == 2)
            #expect(trailingRawCount == 1)
        }

        // Non-system BrowsingHeader fallback omits Undo, More, and Move Rejects for Expanded Duo
        // while keeping Back, centered tappable filename Info (>= 44 pt), Filter, and bottom pill.
        let fallbackFrames = TestHeaderFramesBox()
        let fallbackWindow = UIWindow(windowScene: scene)
        fallbackWindow.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let fallbackHost = UIHostingController(
            rootView: DetailScreen(browsing: model)
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.usesSystemBrowsingToolbar, false)
                .environment(\.hasFoldRegion, true)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    fallbackFrames.frames = frames
                })
        fallbackHost.traitOverrides.horizontalSizeClass = .regular
        fallbackWindow.rootViewController = fallbackHost
        fallbackWindow.makeKeyAndVisible()
        defer {
            fallbackWindow.isHidden = true
            fallbackWindow.rootViewController = nil
        }
        try await waitFor("fallback detail header did not mount") {
            fallbackFrames.frames["clove.nav.back"] != nil
                && fallbackFrames.frames["clove.detail.info"] != nil
                && fallbackFrames.frames["clove.detail.fileName"] != nil
                && fallbackFrames.frames["clove.detail.filter"] != nil
                && fallbackFrames.frames["clove.detail.focusToggle"] != nil
                && fallbackFrames.frames["clove.detail.compare"] != nil
        }
        #expect(fallbackFrames.frames["clove.detail.undo"] == nil)
        #expect(fallbackFrames.frames["clove.duo.undo"] == nil)
        #expect(fallbackFrames.frames["clove.grid.more"] == nil)
        #expect(fallbackFrames.frames["clove.grid.moveRejects"] == nil)
        if let fBack = fallbackFrames.frames["clove.nav.back"],
            let fFocus = fallbackFrames.frames["clove.detail.focusToggle"],
            let fCompare = fallbackFrames.frames["clove.detail.compare"],
            let fInfo = fallbackFrames.frames["clove.detail.info"],
            let fFilter = fallbackFrames.frames["clove.detail.filter"]
        {
            #expect(fBack.maxX <= fInfo.minX)
            #expect(fInfo.width >= 44 && fInfo.height >= 44)
            #expect(fInfo.maxX <= fFilter.minX + 1)
            #expect(fFocus.minY > fBack.maxY)
            #expect(fCompare.minY > fBack.maxY)
            #expect(fFocus.maxX <= fCompare.minX + 2)
        }
    }

    @Test func expandedDuoPortrait669x951DetailAndGridTopBarsFitWithoutOverflow() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let folder = TestLibrary.sampleFolderKey
        let longFileName =
            "2026-11-26_Kyoto_Autumn_Morning_Session_Ultra_Wide_Long_Filename_DSC04821.CR3"
        let photos = [
            GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "p1"),
                fileName: longFileName,
                time: .unavailable,
                marks: PhotoMarks()),
            GridPhoto(
                id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "p2"),
                fileName: "IMG_4822.CR3",
                time: .unavailable,
                marks: PhotoMarks(rating: .rejected)),
        ]
        let library = TestLibrary(photos: photos, groups: [])
        let model = BrowsingModel(library: library, similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        #expect(model.rejectedPhotoCount == 1)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()

        // 1. Expanded Duo Portrait Detail (669x951) in both Focus View and Photo Preview, plus a
        //    439x951 Live-Activity-reduced top-bar width check (669 - 230 pt Live Activity reserve).
        model.openPhoto(photos[0].id)
        for (width, presentation) in [
            (CGFloat(669), DetailPresentation.focus),
            (CGFloat(669), DetailPresentation.photoPreview),
            (CGFloat(439), DetailPresentation.focus),
        ] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 951)
            let headerFrames = TestHeaderFramesBox()
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(
                        browsing: model,
                        thumbnails: model.thumbnails,
                        initialPresentation: presentation)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, false)
                .environment(\.hasFoldRegion, true)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    headerFrames.frames = frames
                })
            host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
            host.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClass.regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "Portrait Duo Detail (\(width), \(presentation)) did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                let state = self.inspectToolbarState(in: host, window: window)
                return state.frame(for: "clove.nav.back") != nil
                    && state.frame(for: "clove.detail.gridToggle") != nil
                    && state.frame(for: "clove.detail.filter") != nil
                    && self.findNavigationBar(in: window).flatMap {
                        self.centerBarGroupFrame(in: $0, relativeTo: window)
                    } != nil
                    && headerFrames.frames["clove.detail.info"] != nil
                    && headerFrames.frames["clove.detail.fileName"] != nil
                    && headerFrames.frames["clove.detail.zoom"] != nil
            }

            let snapshot = inspectToolbarState(in: host, window: window)
            let navBar = try #require(findNavigationBar(in: window))
            let titleFrame = try #require(centerBarGroupFrame(in: navBar, relativeTo: window))
            let infoFrame = try #require(headerFrames.frames["clove.detail.info"])
            let backFrame = try #require(snapshot.frame(for: "clove.nav.back"))
            let toggleFrame = try #require(snapshot.frame(for: "clove.detail.gridToggle"))
            let filterFrame = try #require(snapshot.frame(for: "clove.detail.filter"))

            #expect(snapshot.leadingIDs == ["clove.nav.back", "clove.detail.gridToggle"])
            #expect(snapshot.trailingIDs == ["clove.detail.filter"])
            #expect(snapshot.bottomToolbarIDs.isEmpty)
            #expect(!snapshot.contains("clove.grid.more"))
            #expect(!snapshot.contains("clove.grid.moveRejects"))
            #expect(!snapshot.contains("clove.duo.undo"))
            #expect(!snapshot.contains("clove.detail.undo"))
            #expect(headerFrames.frames["clove.duo.undo"] == nil)
            #expect(headerFrames.frames["clove.detail.undo"] == nil)
            #expect(headerFrames.frames["clove.grid.more"] == nil)
            #expect(headerFrames.frames["clove.detail.photoCornerOverlay"] == nil)
            #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.compare" })
            #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.focusToggle" })
            #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.info" })

            #expect(infoFrame.width >= 44 && infoFrame.height >= 44)
            #expect(titleFrame.width > 0 && titleFrame.height > 0)
            #expect(backFrame.maxX <= toggleFrame.minX + 2)
            #expect(toggleFrame.maxX <= infoFrame.minX + 2)
            #expect(infoFrame.maxX <= filterFrame.minX + 2)

            // No system overflow (`...`) in top bar: exactly 2 leading items + 1 trailing item.
            let leadingRawCount =
                navBar.topItem?.leadingItemGroups.flatMap(\.barButtonItems).count ?? 0
            let trailingRawCount =
                navBar.topItem?.trailingItemGroups.flatMap(\.barButtonItems).count ?? 0
            #expect(leadingRawCount == 2)
            #expect(trailingRawCount == 1)
            #expect(
                barButtonSubviews(in: navBar, relativeTo: window).count
                    >= 3)
        }
        model.back()

        // 2. Expanded Duo Portrait Grid (669x951 and 439x951 Live-Activity-reduced top bar):
        //    Back leading, [Filter, More] trailing, Move Rejects floating bottom-right, no Undo,
        //    and zero duplicate system overflow (`...`).
        for width in [CGFloat(669), CGFloat(439)] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 951)
            let headerFrames = TestHeaderFramesBox()
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, false)
                .environment(\.hasFoldRegion, true)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    headerFrames.frames = frames
                })
            host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
            host.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClass.regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "Portrait Duo Grid (\(width)) did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                let state = self.inspectToolbarState(in: host, window: window)
                return state.frame(for: "clove.nav.back") != nil
                    && state.frame(for: "clove.grid.filter") != nil
                    && state.frame(for: "clove.grid.more") != nil
                    && headerFrames.frames["clove.grid.moveRejects"] != nil
            }

            let snapshot = inspectToolbarState(in: host, window: window)
            let navBar = try #require(findNavigationBar(in: window))
            let filterFrame = try #require(snapshot.frame(for: "clove.grid.filter"))
            let moreFrame = try #require(snapshot.frame(for: "clove.grid.more"))
            let moveRejectsFrame = try #require(headerFrames.frames["clove.grid.moveRejects"])

            #expect(snapshot.leadingIDs == ["clove.nav.back"])
            #expect(snapshot.trailingIDs == ["clove.grid.filter", "clove.grid.more"])
            #expect(snapshot.bottomToolbarIDs.isEmpty)
            #expect(!snapshot.contains("clove.duo.undo"))
            #expect(!snapshot.contains("clove.detail.undo"))
            #expect(!snapshot.entries.contains { $0.identifier == "clove.grid.moveRejects" })
            #expect(filterFrame.maxX <= moreFrame.minX + 2)
            #expect(moveRejectsFrame.minY > window.bounds.height * 0.7)
            #expect(moveRejectsFrame.minX > window.bounds.width * 0.65)
            #expect(
                (navBar.topItem?.leadingItemGroups.flatMap(\.barButtonItems).count ?? 0) == 1)
            #expect(
                (navBar.topItem?.trailingItemGroups.flatMap(\.barButtonItems).count ?? 0) == 2)
        }

        // 3. Portrait Duo Grid Select mode (669x951): hides Back, shows Select All leading and
        //    [Filter, Done] trailing without Undo, Move Rejects, or overflow.
        model.toggleSelection(photos[0].id)
        defer { model.clearSelection() }
        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 669, height: 951)
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, false)
                .environment(\.hasFoldRegion, true))
            host.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClass.regular
            host.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClass.regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "Portrait Duo Grid Select mode did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                let state = self.inspectToolbarState(in: host, window: window)
                return state.frame(for: "clove.grid.selectAll") != nil
                    && state.frame(for: "clove.grid.filter") != nil
                    && state.frame(for: "clove.grid.batch.done") != nil
            }
            let selectSnapshot = inspectToolbarState(in: host, window: window)
            #expect(selectSnapshot.leadingIDs == ["clove.grid.selectAll"])
            #expect(selectSnapshot.trailingIDs == ["clove.grid.filter", "clove.grid.batch.done"])
            #expect(selectSnapshot.bottomToolbarIDs.isEmpty)
            #expect(!selectSnapshot.contains("clove.nav.back"))
            #expect(!selectSnapshot.contains("clove.duo.undo"))
            #expect(!selectSnapshot.contains("clove.detail.undo"))
            #expect(!selectSnapshot.contains("clove.grid.moveRejects"))
        }
    }

    @Test func duoCoverGridDockPlacesMoreInHeaderBackMoveRejectsTopFilterBottomAndOmitsUndo()
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample())
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        #expect(model.rejectedPhotoCount > 0)
        let store = SettingsStore.sample

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        let host = UIHostingController(
            rootView: NavigationStack {
                GridScreen(browsing: model, thumbnails: model.thumbnails)
            }
            .environment(store)
            .environment(\.cloveUserInterfaceIdiom, .phone)
            .environment(\.isDuoCover, true)
            .environment(\.isDuoExpanded, false)
            .environment(\.usesSystemBrowsingToolbar, true)
            .environment(\.usesVerticalBrowsingToolbar, true))
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor(
            "Duo Cover Grid controls did not mount: \(self.describeToolbarState(in: host, window: window))"
        ) {
            self.hasToolbarItem(identifier: "clove.nav.back", in: host, window: window)
                && self.hasToolbarItem(
                    identifier: "clove.grid.moveRejects", in: host, window: window)
                && self.hasToolbarItem(identifier: "clove.grid.more", in: host, window: window)
                && self.hasToolbarItem(identifier: "clove.grid.filter", in: host, window: window)
        }

        let snapshot = inspectToolbarState(in: host, window: window)
        // Undo is never shown on Duo Cover Grid.
        #expect(!snapshot.contains("clove.duo.undo"))
        #expect(!snapshot.contains("clove.detail.undo"))
        #expect(!snapshot.contains("clove.grid.undo"))

        let backFrame = try #require(
            snapshot.frame(for: "clove.nav.back"),
            Comment(rawValue: "missing back in \(snapshot.description)"))
        let moveRejectsFrame = try #require(
            snapshot.frame(for: "clove.grid.moveRejects"),
            Comment(rawValue: "missing moveRejects in \(snapshot.description)"))
        let moreFrame = try #require(
            snapshot.frame(for: "clove.grid.more"),
            Comment(rawValue: "missing more in \(snapshot.description)"))
        let filterFrame = try #require(
            snapshot.frame(for: "clove.grid.filter"),
            Comment(rawValue: "missing filter in \(snapshot.description)"))

        if host.traitCollection.verticalBarEdge != .unspecified {
            let navBar = try #require(findNavigationBar(in: window))
            let navBarFrame = navBar.convert(navBar.bounds, to: window)
            // More sits in the top horizontal header (to the left of the vertical dock).
            #expect(
                moreFrame.maxX <= backFrame.minX + 2,
                Comment(rawValue: "expected More left of dock: \(snapshot.description)"))
            #expect(
                moreFrame.midY <= navBarFrame.maxY + 4,
                Comment(
                    rawValue: "expected More in top horizontal header: \(snapshot.description)"))
            // Back + Move Rejects sit at the top of the right dock; Filter sits at the bottom.
            #expect(
                backFrame.maxY < moveRejectsFrame.minY,
                Comment(rawValue: "expected Back above Move Rejects: \(snapshot.description)"))
            #expect(
                moveRejectsFrame.maxY + 120 < filterFrame.minY,
                Comment(
                    rawValue:
                        "expected Move Rejects at top, Filter at bottom: \(snapshot.description)"
                ))
            #expect(
                filterFrame.midY > window.bounds.height * 0.65,
                Comment(rawValue: "expected Filter in lower dock: \(snapshot.description)"))
            #expect(abs(backFrame.midX - filterFrame.midX) <= 8)
            #expect(abs(moveRejectsFrame.midX - filterFrame.midX) <= 8)
        } else {
            #expect(
                snapshot.leadingIDs == ["clove.nav.back", "clove.grid.moveRejects"],
                Comment(rawValue: "unexpected leadingIDs: \(snapshot.description)"))
            #expect(snapshot.trailingIDs == ["clove.grid.more", "clove.grid.filter"])
            #expect(backFrame.maxX <= moveRejectsFrame.minX + 2)
            #expect(moveRejectsFrame.maxX < moreFrame.minX)
            #expect(moreFrame.maxX <= filterFrame.minX + 2)
        }

        // Cover Select mode keeps selection controls and Filter working cleanly with no Undo/Move Rejects.
        let firstPhoto = try #require(model.photos.first?.id)
        model.toggleSelection(firstPhoto)
        try await waitFor(
            "Duo Cover Select mode controls did not mount: \(self.describeToolbarState(in: host, window: window))"
        ) {
            self.hasToolbarItem(identifier: "clove.grid.selectAll", in: host, window: window)
                && self.hasToolbarItem(
                    identifier: "clove.grid.batch.done", in: host, window: window)
                && self.hasToolbarItem(identifier: "clove.grid.filter", in: host, window: window)
                && !self.hasAnyToolbarIdentifier(
                    "clove.grid.moveRejects", in: host, window: window)
        }
        let selectSnapshot = inspectToolbarState(in: host, window: window)
        #expect(!selectSnapshot.contains("clove.duo.undo"))
        #expect(!selectSnapshot.contains("clove.detail.undo"))
        #expect(!selectSnapshot.contains("clove.grid.undo"))
        #expect(!selectSnapshot.contains("clove.grid.moveRejects"))
        if host.traitCollection.verticalBarEdge != .unspecified,
            let navBar = findNavigationBar(in: window),
            let selectAllFrame = selectSnapshot.frame(for: "clove.grid.selectAll"),
            let doneFrame = selectSnapshot.frame(for: "clove.grid.batch.done"),
            let selectFilterFrame = selectSnapshot.frame(for: "clove.grid.filter")
        {
            let navBarFrame = navBar.convert(navBar.bounds, to: window)
            #expect(selectAllFrame.midY <= navBarFrame.maxY + 4)
            #expect(doneFrame.midY <= navBarFrame.maxY + 4)
            #expect(selectFilterFrame.midY > window.bounds.height * 0.65)
        }
        model.clearSelection()

        // Non-system BrowsingHeader fallback on Duo Cover Grid also omits Undo and exposes Move Rejects, Filter, More.
        let fallbackFrames = TestHeaderFramesBox()
        let fallbackWindow = UIWindow(windowScene: scene)
        fallbackWindow.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        let fallbackHost = UIHostingController(
            rootView: GridScreen(browsing: model, thumbnails: model.thumbnails)
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoCover, true)
                .environment(\.isDuoExpanded, false)
                .environment(\.usesSystemBrowsingToolbar, false)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    fallbackFrames.frames = frames
                })
        fallbackHost.traitOverrides.horizontalSizeClass = .compact
        fallbackWindow.rootViewController = fallbackHost
        fallbackWindow.makeKeyAndVisible()
        defer {
            fallbackWindow.isHidden = true
            fallbackWindow.rootViewController = nil
        }
        try await waitFor("fallback Duo Cover Grid did not mount") {
            fallbackFrames.frames["clove.nav.back"] != nil
                && fallbackFrames.frames["clove.grid.filter"] != nil
        }
        let fallbackSnapshot = inspectToolbarState(in: fallbackHost, window: fallbackWindow)
        #expect(!fallbackSnapshot.contains("clove.duo.undo"))
        #expect(!fallbackSnapshot.contains("clove.detail.undo"))
        #expect(!fallbackSnapshot.contains("clove.grid.undo"))
    }

    @Test func expandedDuoGridAndPhoneAndIPadGridsPreserveExistingToolbarLayouts() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample())
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        let store = SettingsStore.sample

        // 1. Expanded Duo Grid keeps Back, Filter + More, and Undo + Move Rejects unchanged.
        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true))
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "expanded Duo Grid controls did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                self.hasToolbarItem(identifier: "clove.nav.back", in: host, window: window)
                    && self.hasToolbarItem(
                        identifier: "clove.grid.filter", in: host, window: window)
                    && self.hasToolbarItem(identifier: "clove.grid.more", in: host, window: window)
                    && self.hasToolbarItem(
                        identifier: "clove.grid.moveRejects", in: host, window: window)
            }
            let snapshot = inspectToolbarState(in: host, window: window)
            if host.traitCollection.verticalBarEdge == .unspecified {
                #expect(snapshot.leadingIDs == ["clove.nav.back"])
                #expect(
                    snapshot.trailingIDs == [
                        "clove.grid.filter", "clove.grid.more", "clove.detail.undo",
                        "clove.grid.moveRejects",
                    ])
            } else {
                #expect(snapshot.contains("clove.duo.undo"))
                let filterFrame = try #require(snapshot.frame(for: "clove.grid.filter"))
                let moreFrame = try #require(snapshot.frame(for: "clove.grid.more"))
                let undoFrame = try #require(snapshot.frame(for: "clove.duo.undo"))
                let moveRejectsFrame = try #require(snapshot.frame(for: "clove.grid.moveRejects"))
                #expect(filterFrame.maxY < moreFrame.minY)
                #expect(moreFrame.minY - filterFrame.maxY <= 16)
                #expect(moreFrame.maxY < undoFrame.minY)
                #expect(undoFrame.maxY < moveRejectsFrame.minY)
                #expect(moveRejectsFrame.minY - undoFrame.maxY <= 16)
                #expect(filterFrame.midY < window.bounds.height * 0.5)
            }
        }

        // 2. iPhone Grid keeps Back, Filter, More, and no Undo.
        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, false)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true))
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "iPhone Grid controls did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                self.hasToolbarItem(identifier: "clove.nav.back", in: host, window: window)
                    && self.hasToolbarItem(
                        identifier: "clove.grid.filter", in: host, window: window)
                    && self.hasToolbarItem(identifier: "clove.grid.more", in: host, window: window)
            }
            let snapshot = inspectToolbarState(in: host, window: window)
            #expect(snapshot.leadingIDs == ["clove.nav.back"])
            #expect(snapshot.trailingIDs == ["clove.grid.filter", "clove.grid.more"])
            #expect(snapshot.bottomToolbarIDs.isEmpty)
            #expect(!snapshot.contains("clove.duo.undo"))
            #expect(!snapshot.contains("clove.detail.undo"))
            #expect(!snapshot.contains("clove.grid.undo"))
        }

        // 3. iPad Grid keeps Move Rejects + More and omits Filter, Back, Undo.
        do {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 900, height: 820)
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.isDuoExpanded, false)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true))
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "iPad Grid controls did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                self.hasToolbarItem(
                    identifier: "clove.grid.moveRejects", in: host, window: window)
                    && self.hasToolbarItem(identifier: "clove.grid.more", in: host, window: window)
            }
            let snapshot = inspectToolbarState(in: host, window: window)
            #expect(!snapshot.contains("clove.grid.filter"))
            #expect(!snapshot.contains("clove.nav.back"))
            #expect(!snapshot.contains("clove.duo.undo"))
            #expect(!snapshot.contains("clove.detail.undo"))
            #expect(!snapshot.contains("clove.grid.undo"))
        }

        // 4. Native iPad Detail keeps navigationTools (Back + photoGridToggle) and Filter without
        // top Focus/Compare/standalone Info (#462, #463).
        do {
            let photo = try #require(model.photos.first?.id)
            model.openPhoto(photo)
            defer { model.back() }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            let host = UIHostingController(
                rootView: NavigationStack {
                    DetailScreen(browsing: model)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.isDuoExpanded, false)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true))
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            if host.traitCollection.verticalBarEdge == .unspecified {
                try await waitFor(
                    "iPad Detail navigation tools did not mount: \(self.describeToolbarState(in: host, window: window))"
                ) {
                    let state = self.inspectToolbarState(in: host, window: window)
                    return state.rawLeadingItemCount == 2
                        && (state.contains("clove.grid.filter")
                            || state.contains("clove.detail.filter"))
                        && !state.entries.contains { $0.identifier == "clove.detail.info" }
                        && !state.contains("clove.detail.compare")
                        && !state.contains("clove.detail.focusToggle")
                        && !state.contains("clove.detail.undo")
                        && !state.contains("clove.duo.undo")
                }
                let navBar = try #require(findNavigationBar(in: window))
                let titleFrame = try #require(centerBarGroupFrame(in: navBar, relativeTo: window))
                #expect(titleFrame.width >= 44 && titleFrame.height >= 44)
            }
        }

        // 5. Native iPhone Detail exposes Filter without permanent Undo or standalone Info,
        //    and live filter updates in Detail handle matching, non-matching, and empty results.
        do {
            let photo = try #require(model.photos.first?.id)
            model.openPhoto(photo)
            defer {
                model.clearAllFilters()
                model.back()
            }
            let frames = TestHeaderFramesBox()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let host = UIHostingController(
                rootView: NavigationStack {
                    DetailScreen(browsing: model)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, false)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames.frames = $0 })
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "iPhone Detail toolbar did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                let state = self.inspectToolbarState(in: host, window: window)
                return state.rawLeadingItemCount == 2
                    && state.leadingIDs.first == "clove.nav.back"
                    && (state.contains("clove.grid.filter")
                        || state.contains("clove.detail.filter"))
                    && !state.contains("clove.detail.undo")
                    && !state.contains("clove.duo.undo")
                    && !state.entries.contains { $0.identifier == "clove.detail.info" }
            }
            let navBar = try #require(findNavigationBar(in: window))
            let titleFrame = try #require(centerBarGroupFrame(in: navBar, relativeTo: window))
            #expect(titleFrame.width >= 44 && titleFrame.height >= 44)

            // Filtering to Rejected snaps Detail live onto a matching photo, and an unmatched
            // filter combination displays empty-filtered Detail cleanly without crashing.
            model.setFilter(.rejected)
            try await waitFor("Detail did not snap onto matching filtered photo") {
                model.state.currentPhoto != nil
                    && model.photos.contains(where: { $0.id == model.state.currentPhoto })
            }
            let five = try #require(Rating(rawValue: 5))
            model.setFilter(.ratedAtLeast(five))
            model.setLabelFilter(.purple)
            model.toggleCameraFilter("NonExistentCameraModel")
            try await waitFor("Detail empty filtered state did not render") {
                model.photos.isEmpty
                    && (self.inspectToolbarState(in: host, window: window)
                        .contains("clove.detail.empty")
                        || self.inspectToolbarState(in: host, window: window)
                            .contains("clove.detail.empty.clearFilters")
                        || !self.inspectToolbarState(in: host, window: window)
                            .contains("clove.detail.focusToggle"))
            }
            model.clearAllFilters()
            try await waitFor("Detail did not restore after clearing filters") {
                let state = self.inspectToolbarState(in: host, window: window)
                return !model.photos.isEmpty
                    && model.state.currentPhoto != nil
                    && state.rawLeadingItemCount == 2
                    && (state.contains("clove.grid.filter")
                        || state.contains("clove.detail.filter"))
                    && !state.contains("clove.detail.undo")
            }
        }

        // 6. Duo Cover Detail uses strictly 3 right-rail buttons (Back, Focus regions, Filter),
        // empty bottom rail, top-left DetailPhotoCornerOverlay, and centered bottom MarkingToolbar
        // below DetailFilmstrip (#469).
        do {
            let photo = try #require(model.photos.first?.id)
            model.openPhoto(photo)
            defer { model.back() }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
            let headerFrames = TestHeaderFramesBox()
            let tapFrames = TestHeaderFramesBox()
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(browsing: model, thumbnails: model.thumbnails)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoCover, true)
                .environment(\.isDuoExpanded, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    headerFrames.frames = frames
                }
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    tapFrames.frames = frames
                })
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "Duo Cover Detail controls did not mount: \(self.describeToolbarState(in: host, window: window, leadingBarHostIdentifier: "clove.detail.focusToggle"))"
            ) {
                let state = self.inspectToolbarState(
                    in: host, window: window, leadingBarHostIdentifier: "clove.detail.focusToggle")
                return state.contains("clove.nav.back")
                    && state.contains("clove.detail.focusToggle")
                    && state.contains("clove.detail.filter")
                    && !state.contains("clove.duo.undo")
                    && !state.contains("clove.detail.undo")
                    && headerFrames.frames["clove.detail.photoCornerOverlay"] != nil
                    && headerFrames.frames["clove.detail.info"] != nil
                    && headerFrames.frames["clove.detail.fileName"] != nil
                    && headerFrames.frames["clove.detail.zoom"] != nil
                    && tapFrames.frames["clove.detail.filmstrip"] != nil
                    && tapFrames.frames["clove.duo.capsule"] != nil
            }
            let snapshot = inspectToolbarState(
                in: host, window: window, leadingBarHostIdentifier: "clove.detail.focusToggle")
            #expect(!snapshot.contains("clove.duo.undo"))
            #expect(!snapshot.contains("clove.detail.undo"))
            #expect(!snapshot.contains("clove.grid.filter"))
            #expect(!snapshot.contains("clove.grid.more"))
            #expect(!snapshot.contains("clove.grid.moveRejects"))
            #expect(!snapshot.contains("clove.detail.gridToggle"))
            #expect(!snapshot.contains("clove.detail.inspectionPill"))
            #expect(!snapshot.contains("clove.duo.rating"))
            #expect(!snapshot.contains("clove.duo.reject"))
            #expect(!snapshot.contains("clove.duo.label"))
            #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.compare" })
            #expect(!snapshot.entries.contains { $0.identifier == "clove.detail.info" })
            #expect(snapshot.bottomToolbarIDs.isEmpty)

            let backFrame = try #require(
                snapshot.frame(for: "clove.nav.back"),
                Comment(rawValue: "missing back in \(snapshot.description)"))
            let focusFrame = try #require(
                snapshot.frame(for: "clove.detail.focusToggle"),
                Comment(rawValue: "missing focusToggle in \(snapshot.description)"))
            let filterFrame = try #require(
                snapshot.frame(for: "clove.detail.filter"),
                Comment(rawValue: "missing filter in \(snapshot.description)"))
            if host.traitCollection.verticalBarEdge != .unspecified {
                #expect(snapshot.leadingIDs == ["clove.nav.back"])
                #expect(
                    snapshot.trailingIDs == ["clove.detail.focusToggle", "clove.detail.filter"])
                #expect(backFrame.maxY < focusFrame.minY)
                #expect(focusFrame.minY - backFrame.maxY >= 18)
                #expect(focusFrame.maxY < filterFrame.minY)
                #expect(filterFrame.minY - focusFrame.maxY >= 18)
            } else {
                #expect(snapshot.leadingIDs == ["clove.nav.back", "clove.detail.focusToggle"])
                #expect(snapshot.trailingIDs == ["clove.detail.filter"])
            }

            let cornerOverlayFrame = try #require(
                headerFrames.frames["clove.detail.photoCornerOverlay"])
            let cornerInfoFrame = try #require(headerFrames.frames["clove.detail.info"])
            let stripFrame = try #require(tapFrames.frames["clove.detail.filmstrip"])
            let capsuleFrame = try #require(tapFrames.frames["clove.duo.capsule"])
            #expect(cornerOverlayFrame.width > 0 && cornerOverlayFrame.height > 0)
            #expect(cornerInfoFrame.width >= 44 && cornerInfoFrame.height >= 44)
            #expect(abs(capsuleFrame.width - 168) <= 1)
            #expect(abs(capsuleFrame.height - 48) <= 1)
            #expect(capsuleFrame.minY >= stripFrame.maxY + 7)
            #expect(abs(capsuleFrame.midX - stripFrame.midX) <= 2)
        }
    }

    @Test func filterMenuMountsNativeBarMenuAcrossSystemToolbarLayouts() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = TestLibrary.forLaunch(environment: [
            TestLibrary.launchVariable: "1",
            TestLibrary.metadataSamplesVariable: "1",
        ])
        let model = BrowsingModel(library: library)
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        let photo = try #require(model.photos.first?.id)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()

        enum LayoutKind {
            case expandedDuoDetail
            case portraitDuoDetail
            case duoCoverDetail
            case phoneHorizontalDetail
            case phoneHorizontalGrid
            case expandedDuoGrid
            case iPadDetail
        }

        let cases:
            [(
                name: String, kind: LayoutKind, size: CGSize, idiom: UIUserInterfaceIdiom,
                horizontal: UIUserInterfaceSizeClass, isDuoExpanded: Bool, isDuoCover: Bool,
                usesVerticalToolbar: Bool, hasFoldRegion: Bool, expectedFilterID: String
            )] = [
                (
                    "expandedDuoDetail", .expandedDuoDetail, CGSize(width: 951, height: 669),
                    .phone, .regular, true, false, true, true, "clove.detail.filter"
                ),
                (
                    "portraitDuoDetail", .portraitDuoDetail, CGSize(width: 669, height: 951),
                    .phone, .regular, true, false, false, true, "clove.detail.filter"
                ),
                (
                    "duoCoverDetail", .duoCoverDetail, CGSize(width: 466, height: 678),
                    .phone, .compact, false, true, true, false, "clove.detail.filter"
                ),
                (
                    "phoneHorizontalDetail", .phoneHorizontalDetail,
                    CGSize(width: 393, height: 852),
                    .phone, .compact, false, false, false, false, "clove.detail.filter"
                ),
                (
                    "phoneHorizontalGrid", .phoneHorizontalGrid, CGSize(width: 393, height: 852),
                    .phone, .compact, false, false, false, false, "clove.grid.filter"
                ),
                (
                    "expandedDuoGrid", .expandedDuoGrid, CGSize(width: 951, height: 669),
                    .phone, .regular, true, false, true, true, "clove.grid.filter"
                ),
                (
                    "iPadDetail", .iPadDetail, CGSize(width: 1024, height: 768),
                    .pad, .regular, false, false, false, false, "clove.detail.filter"
                ),
            ]

        for entry in cases {
            model.clearAllFilters()
            if entry.kind == .phoneHorizontalGrid || entry.kind == .expandedDuoGrid {
                if model.state.route != .grid { model.back() }
            } else {
                model.openPhoto(photo)
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: entry.size)
            let host = UIHostingController(
                rootView: NavigationStack {
                    if entry.kind == .phoneHorizontalDetail || entry.kind == .iPadDetail {
                        DetailScreen(browsing: model)
                    } else {
                        GridScreen(
                            browsing: model,
                            thumbnails: model.thumbnails,
                            initialPresentation: .focus)
                    }
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, entry.idiom)
                .environment(\.isDuoExpanded, entry.isDuoExpanded)
                .environment(\.isDuoCover, entry.isDuoCover)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, entry.usesVerticalToolbar)
                .environment(\.hasFoldRegion, entry.hasFoldRegion)
                .environment(\.scenePhase, .active))
            host.traitOverrides.horizontalSizeClass = entry.horizontal
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "\(entry.name) filter item did not mount: \(self.describeToolbarState(in: host, window: window))"
            ) {
                self.hasToolbarItem(
                    identifier: entry.expectedFilterID, in: host, window: window)
            }

            let barItem = toolbarBarButtonItem(
                identifier: entry.expectedFilterID, in: host, window: window)
            let filterItem = try #require(
                barItem,
                Comment(
                    rawValue:
                        "\(entry.name) missing UIBarButtonItem for \(entry.expectedFilterID): \(describeToolbarState(in: host, window: window))"
                ))
            #expect(
                filterItem.menu != nil,
                Comment(rawValue: "\(entry.name) Filter bar item did not attach a native UIMenu"))
            #expect(
                topPresentedViewController(from: host) == nil,
                Comment(rawValue: "\(entry.name) unexpectedly presented a custom popover"))
        }
    }

    private func toolbarBarButtonItem(
        identifier: String, in host: UIViewController, window: UIWindow
    ) -> UIBarButtonItem? {
        let navBar = findNavigationBar(in: window)
        let navItem =
            navBar?.topItem ?? findNavigationController(in: host)?.topViewController?.navigationItem
        let topVC = findNavigationController(in: host)?.topViewController
        let allItems =
            (navItem?.leadingItemGroups.flatMap(\.barButtonItems) ?? [])
            + (navItem?.trailingItemGroups.flatMap(\.barButtonItems) ?? [])
            + (topVC?.toolbarItems ?? [])
        return allItems.first {
            $0.accessibilityIdentifier == identifier
                || ((identifier == "clove.detail.filter" || identifier == "clove.grid.filter")
                    && ($0.title == "Filter" || $0.accessibilityLabel == "Filter"))
        }
    }

    private func triggerToolbarButton(
        identifier: String, expectedFrame: CGRect, in host: UIViewController, window: UIWindow
    ) throws {
        let navBar = findNavigationBar(in: window)
        let navItem =
            navBar?.topItem ?? findNavigationController(in: host)?.topViewController?.navigationItem
        let topVC = findNavigationController(in: host)?.topViewController
        let allItems =
            (navItem?.leadingItemGroups.flatMap(\.barButtonItems) ?? [])
            + (navItem?.trailingItemGroups.flatMap(\.barButtonItems) ?? [])
            + (topVC?.toolbarItems ?? [])
        if let item = allItems.first(where: {
            $0.accessibilityIdentifier == identifier
                || ((identifier == "clove.detail.filter" || identifier == "clove.grid.filter")
                    && ($0.title == "Filter" || $0.accessibilityLabel == "Filter"))
        }) {
            if let action = item.action, let target = item.target {
                UIApplication.shared.sendAction(action, to: target, from: item, for: nil)
                return
            }
            if let primaryAction = item.primaryAction {
                primaryAction.performWithSender(item, target: nil)
                return
            }
        }
        func findControl(in view: UIView) -> UIControl? {
            if let control = view as? UIControl {
                let frame = control.convert(control.bounds, to: window)
                if control.accessibilityIdentifier == identifier
                    || abs(frame.midX - expectedFrame.midX) < 4
                        && abs(frame.midY - expectedFrame.midY) < 4
                {
                    return control
                }
            }
            for child in view.subviews {
                if let found = findControl(in: child) { return found }
            }
            return nil
        }
        if let control = findControl(in: window) {
            control.sendActions(for: .touchUpInside)
            return
        }
        Issue.record(
            Comment(
                rawValue:
                    "Could not trigger toolbar item '\(identifier)': \(describeToolbarState(in: host, window: window))"
            ))
    }

    @Test func expandedDuoCompareLandscapeAndPortraitToolbarsFitWithoutCustomTopBar() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample())
        model.openFolder()
        try await waitFor("folder did not open") { !model.isFolderOpening }
        let first = try #require(model.photos.first?.id)
        model.openPhoto(first)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))
        let store = SettingsStore.sample
        store.markGestureGuideSeen()

        // 1. Duo Landscape (951x669): no custom 52 pt topBar, native 4-button vertical right rail
        // (< leading; Focus, Sync, Set as A trailing) matching Duo Detail rhythm, empty bottom rail,
        // no permanent Undo button, no bottom A/B badge, Set as A omitted from bottom bar, and no
        // bottom-bar control crossing the vertical hinge.
        do {
            let foldRange: ClosedRange<CGFloat> = 466...485
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
            let headerFrames = TestHeaderFramesBox()
            let tapFrames = TestTapPickerFramesBox()
            let host = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(
                        browsing: model,
                        thumbnails: model.thumbnails,
                        initialPresentation: .focus)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.duoVerticalDivisionRange, foldRange)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                    headerFrames.frames = frames
                }
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    tapFrames.frames = frames
                })
            host.traitOverrides.horizontalSizeClass = .regular
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor(
                "Duo Landscape Compare toolbar did not mount: \(self.describeToolbarState(in: host, window: window, isCompare: true))"
            ) {
                let state = self.inspectToolbarState(in: host, window: window, isCompare: true)
                return state.frame(for: "clove.compare.done") != nil
                    && state.frame(for: "clove.compare.focusRegions") != nil
                    && state.frame(for: "clove.compare.syncToggle") != nil
                    && state.frame(for: "clove.compare.setAsA") != nil
                    && tapFrames.frames["clove.compare.filmstrip"] != nil
                    && tapFrames.frames["clove.compare.prev"] != nil
                    && tapFrames.frames["clove.compare.next"] != nil
                    && tapFrames.frames["clove.compare.capsule"] != nil
            }

            let snapshot = inspectToolbarState(in: host, window: window, isCompare: true)
            #expect(model.compareSession != nil)
            #expect(headerFrames.frames["clove.compare.topBar"] == nil)
            #expect(headerFrames.frames["clove.compare.title"] == nil)
            #expect(!snapshot.contains("clove.compare.undo"))
            #expect(tapFrames.frames["clove.compare.undo"] == nil)
            #expect(headerFrames.frames["clove.compare.undo"] == nil)
            #expect(!snapshot.contains("clove.compare.activeSideBadge"))
            #expect(tapFrames.frames["clove.compare.activeSideBadge"] == nil)
            #expect(tapFrames.frames["clove.compare.setAsA"] == nil)
            #expect(snapshot.bottomToolbarIDs.isEmpty)

            // Native Button(label, systemImage:) items produce UIKit bar button items without BarItemHost customView.
            let navItem =
                findNavigationBar(in: window)?.topItem
                ?? findNavigationController(in: host)?.topViewController?.navigationItem
            let allBarItems =
                (navItem?.leadingItemGroups.flatMap(\.barButtonItems) ?? [])
                + (navItem?.trailingItemGroups.flatMap(\.barButtonItems) ?? [])
            #expect(allBarItems.allSatisfy { $0.customView == nil })
            let trailingItems = navItem?.trailingItemGroups.flatMap(\.barButtonItems) ?? []
            let setAsAItem = try #require(
                trailingItems.first {
                    $0.accessibilityIdentifier == "clove.compare.setAsA"
                        || $0.accessibilityLabel == "Set as A"
                        || $0.title == "Set as A"
                })
            #expect(setAsAItem.isEnabled)

            let doneFrame = try #require(snapshot.frame(for: "clove.compare.done"))
            let focusFrame = try #require(snapshot.frame(for: "clove.compare.focusRegions"))
            let syncFrame = try #require(snapshot.frame(for: "clove.compare.syncToggle"))
            let setAsAFrame = try #require(snapshot.frame(for: "clove.compare.setAsA"))

            for frame in [doneFrame, focusFrame, syncFrame, setAsAFrame] {
                #expect(frame.width > 0 && frame.height > 0)
                #expect(window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
            }

            if host.traitCollection.verticalBarEdge != .unspecified {
                let railContainer = findVerticalBarView(in: window) ?? findNavigationBar(in: window)
                let railView = try #require(railContainer)
                let railFrame = railView.convert(railView.bounds, to: window)
                #expect(railFrame.width > 0 && railFrame.height > 0)
                for frame in [doneFrame, focusFrame, syncFrame, setAsAFrame] {
                    #expect(railFrame.insetBy(dx: -1, dy: -1).contains(frame))
                }
                #expect(doneFrame.maxY < focusFrame.minY)
                #expect(focusFrame.minY - doneFrame.maxY >= 18)
                #expect(focusFrame.maxY < syncFrame.minY)
                #expect(syncFrame.minY - focusFrame.maxY >= 18)
                #expect(syncFrame.maxY < setAsAFrame.minY)
                #expect(setAsAFrame.minY - syncFrame.maxY >= 18)
                #expect(snapshot.leadingIDs == ["clove.compare.done"])
                let focusIdx = try #require(
                    snapshot.trailingRawTokens.firstIndex(of: "clove.compare.focusRegions"))
                let syncIdx = try #require(
                    snapshot.trailingRawTokens.firstIndex(of: "clove.compare.syncToggle"))
                let setAsAIdx = try #require(
                    snapshot.trailingRawTokens.firstIndex(of: "clove.compare.setAsA"))
                #expect(focusIdx < syncIdx)
                #expect(syncIdx < setAsAIdx)
                #expect(snapshot.trailingRawTokens[focusIdx..<syncIdx].contains("<spacer>"))
                #expect(snapshot.trailingRawTokens[syncIdx..<setAsAIdx].contains("<spacer>"))
                #expect(!snapshot.trailingRawTokens[setAsAIdx...].contains("<spacer>"))
                #expect(
                    snapshot.trailingIDs == [
                        "clove.compare.focusRegions",
                        "clove.compare.syncToggle",
                        "clove.compare.setAsA",
                    ])
            } else {
                #expect(snapshot.leadingIDs == ["clove.compare.done"])
                #expect(
                    snapshot.trailingIDs == [
                        "clove.compare.focusRegions",
                        "clove.compare.syncToggle",
                        "clove.compare.setAsA",
                    ])
            }

            // Side-by-side panes gain topBar height and stay clear of the hinge.
            let panes = findComparePanes(in: window).sorted {
                $0.convert($0.bounds, to: window).minX < $1.convert($1.bounds, to: window).minX
            }
            #expect(panes.count == 2)
            let paneAWindowFrame = panes[0].convert(panes[0].bounds, to: window)
            let paneBWindowFrame = panes[1].convert(panes[1].bounds, to: window)
            let compareOriginX = paneAWindowFrame.minX - 8
            let windowFoldMinX = compareOriginX + foldRange.lowerBound
            let windowFoldMaxX = compareOriginX + foldRange.upperBound
            #expect(paneAWindowFrame.maxX <= windowFoldMinX - 4 + 0.5)
            #expect(paneBWindowFrame.minX >= windowFoldMaxX + 4 - 0.5)
            if host.traitCollection.verticalBarEdge != .unspecified {
                for pane in panes {
                    let frame = pane.convert(pane.bounds, to: window)
                    #expect(frame.minY < 70)
                }
            }

            // Bottom bar keeps filmstrip left of hinge and only [‹] [›] + MarkingToolbar right of hinge.
            let filmstripFrame = try #require(tapFrames.frames["clove.compare.filmstrip"])
            let prevFrame = try #require(tapFrames.frames["clove.compare.prev"])
            let nextFrame = try #require(tapFrames.frames["clove.compare.next"])
            let capsuleFrame = try #require(tapFrames.frames["clove.compare.capsule"])
            #expect(filmstripFrame.maxX <= windowFoldMinX - 4 + 0.5)
            #expect(filmstripFrame.maxX <= paneAWindowFrame.maxX + 0.5)
            #expect(prevFrame.minX >= windowFoldMaxX + 4 - 0.5)
            #expect(prevFrame.minX >= paneBWindowFrame.minX - 0.5)
            #expect(prevFrame.maxX <= nextFrame.minX)
            #expect(nextFrame.maxX <= capsuleFrame.minX)
            #expect(capsuleFrame.maxX <= window.bounds.width - compareOriginX - 8 + 0.5)

            // Triggering Set as A from the toolbar rail promotes challenger B to reference A.
            let initialChallenger = try #require(model.compareSession?.challenger)
            try triggerToolbarButton(
                identifier: "clove.compare.setAsA", expectedFrame: setAsAFrame, in: host,
                window: window)
            try await waitFor("toolbar Set as A did not promote challenger") {
                model.compareSession?.reference == initialChallenger
            }
        }

        // 1b. Tight Duo Landscape (~270 pt usable width right of hinge inside CompareView's 755 pt
        // content area) fits [‹] [›] + MarkingToolbar without crossing the hinge, and Fixed-Pair
        // mode keeps Set as A disabled in the rail.
        do {
            let foldRange: ClosedRange<CGFloat> = 466...485
            let tightWindow = UIWindow(windowScene: scene)
            tightWindow.frame = CGRect(x: 0, y: 0, width: 795, height: 669)
            let tapFrames = TestTapPickerFramesBox()
            let tightHost = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(
                        browsing: model,
                        thumbnails: model.thumbnails,
                        initialPresentation: .focus)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.duoVerticalDivisionRange, foldRange)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    tapFrames.frames = frames
                })
            tightHost.traitOverrides.horizontalSizeClass = .regular
            tightHost.traitOverrides.verticalSizeClass = .regular
            tightWindow.rootViewController = tightHost
            tightWindow.makeKeyAndVisible()
            defer {
                tightWindow.isHidden = true
                tightWindow.rootViewController = nil
            }

            try await waitFor("Tight Duo Landscape Compare did not mount") {
                let state = self.inspectToolbarState(
                    in: tightHost, window: tightWindow, isCompare: true)
                return state.frame(for: "clove.compare.setAsA") != nil
                    && self.findComparePanes(in: tightWindow).count == 2
                    && tapFrames.frames["clove.compare.filmstrip"] != nil
                    && tapFrames.frames["clove.compare.prev"] != nil
                    && tapFrames.frames["clove.compare.next"] != nil
                    && tapFrames.frames["clove.compare.capsule"] != nil
            }

            let tightSnapshot = inspectToolbarState(
                in: tightHost, window: tightWindow, isCompare: true)
            #expect(
                tightSnapshot.trailingIDs == [
                    "clove.compare.focusRegions",
                    "clove.compare.syncToggle",
                    "clove.compare.setAsA",
                ])
            #expect(tapFrames.frames["clove.compare.setAsA"] == nil)
            #expect(tapFrames.frames["clove.compare.activeSideBadge"] == nil)
            #expect(!tightSnapshot.contains("clove.compare.activeSideBadge"))

            let tightPanes = findComparePanes(in: tightWindow).sorted {
                $0.convert($0.bounds, to: tightWindow).minX
                    < $1.convert($1.bounds, to: tightWindow).minX
            }
            #expect(tightPanes.count == 2)
            let tightPaneAFrame = tightPanes[0].convert(tightPanes[0].bounds, to: tightWindow)
            let tightPaneBFrame = tightPanes[1].convert(tightPanes[1].bounds, to: tightWindow)
            let tightOriginX = tightPaneAFrame.minX - 8
            let tightFoldMinX = tightOriginX + foldRange.lowerBound
            let tightFoldMaxX = tightOriginX + foldRange.upperBound

            let tightStrip = try #require(tapFrames.frames["clove.compare.filmstrip"])
            let tightPrev = try #require(tapFrames.frames["clove.compare.prev"])
            let tightNext = try #require(tapFrames.frames["clove.compare.next"])
            let tightCapsule = try #require(tapFrames.frames["clove.compare.capsule"])
            #expect(tightStrip.maxX <= tightFoldMinX - 4 + 0.5)
            #expect(tightStrip.maxX <= tightPaneAFrame.maxX + 0.5)
            #expect(tightPrev.minX >= tightFoldMaxX + 4 - 0.5)
            #expect(tightPrev.minX >= tightPaneBFrame.minX - 0.5)
            #expect(tightPrev.maxX <= tightNext.minX)
            #expect(tightNext.maxX <= tightCapsule.minX)
            #expect(tightCapsule.maxX <= tightWindow.bounds.width - tightOriginX - 8 + 0.5)

            // Switch to fixed-pair mode (!canPromoteChallenger): Set as A stays in the rail and is disabled.
            let second = try #require(model.photos.dropFirst().first?.id)
            #expect(model.enterComparePair(first: first, second: second))
            try await waitFor("Fixed-pair Duo Compare did not hide stepping controls") {
                tapFrames.frames["clove.compare.prev"] == nil
                    && tapFrames.frames["clove.compare.filmstrip"] == nil
                    && tapFrames.frames["clove.compare.capsule"] != nil
            }
            let fixedSnapshot = inspectToolbarState(
                in: tightHost, window: tightWindow, isCompare: true)
            #expect(
                fixedSnapshot.trailingIDs == [
                    "clove.compare.focusRegions",
                    "clove.compare.syncToggle",
                    "clove.compare.setAsA",
                ])
            let navItem =
                findNavigationBar(in: tightWindow)?.topItem
                ?? findNavigationController(in: tightHost)?.topViewController?.navigationItem
            let trailingItems = navItem?.trailingItemGroups.flatMap(\.barButtonItems) ?? []
            let disabledSetAsA = try #require(
                trailingItems.first {
                    $0.accessibilityIdentifier == "clove.compare.setAsA"
                        || $0.accessibilityLabel == "Set as A"
                        || $0.title == "Set as A"
                })
            #expect(!disabledSetAsA.isEnabled)
            let fixedCapsule = try #require(tapFrames.frames["clove.compare.capsule"])
            #expect(fixedCapsule.minX >= tightFoldMaxX + 4 - 0.5)
            #expect(fixedCapsule.maxX <= tightWindow.bounds.width - tightOriginX - 8 + 0.5)

            // Restore stepping mode for narrow-hinge & Duo Portrait checks below.
            model.exitCompare()
            model.openPhoto(first)
            let restoredTimeline = DetailTimeline(
                photos: model.photos, groups: model.groups, groupsEnabled: true)
            #expect(model.enterCompareFromDetail(timeline: restoredTimeline))
        }

        // 1c. Narrow trailing-pane Duo Landscape (Compare content width 740 pt -> 780x669 window
        // with 20 pt horizontal container margins and foldRange 466...485 -> challengerWidth ≈ 243 pt):
        // ViewThatFits switches stepping controls to compact diameter so [‹] [›] + MarkingToolbar
        // stay unclipped and strictly right of the hinge without touching it.
        do {
            let foldRange: ClosedRange<CGFloat> = 466...485
            let narrowWindow = UIWindow(windowScene: scene)
            narrowWindow.frame = CGRect(x: 0, y: 0, width: 780, height: 669)
            let tapFrames = TestTapPickerFramesBox()
            let narrowHost = UIHostingController(
                rootView: NavigationStack {
                    GridScreen(
                        browsing: model,
                        thumbnails: model.thumbnails,
                        initialPresentation: .focus)
                }
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.isDuoExpanded, true)
                .environment(\.isDuoCover, false)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.duoVerticalDivisionRange, foldRange)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    tapFrames.frames = frames
                })
            narrowHost.traitOverrides.horizontalSizeClass = .regular
            narrowHost.traitOverrides.verticalSizeClass = .regular
            narrowWindow.rootViewController = narrowHost
            narrowWindow.makeKeyAndVisible()
            defer {
                narrowWindow.isHidden = true
                narrowWindow.rootViewController = nil
            }

            try await waitFor("Narrow Duo Landscape Compare did not mount") {
                self.findComparePanes(in: narrowWindow).count == 2
                    && tapFrames.frames["clove.compare.filmstrip"] != nil
                    && tapFrames.frames["clove.compare.prev"] != nil
                    && tapFrames.frames["clove.compare.next"] != nil
                    && tapFrames.frames["clove.compare.capsule"] != nil
            }

            let narrowPanes = findComparePanes(in: narrowWindow).sorted {
                $0.convert($0.bounds, to: narrowWindow).minX
                    < $1.convert($1.bounds, to: narrowWindow).minX
            }
            #expect(narrowPanes.count == 2)
            let narrowPaneAFrame = narrowPanes[0].convert(narrowPanes[0].bounds, to: narrowWindow)
            let narrowPaneBFrame = narrowPanes[1].convert(narrowPanes[1].bounds, to: narrowWindow)
            let narrowOriginX = narrowPaneAFrame.minX - 8
            let compareMaxX = narrowWindow.bounds.width - narrowOriginX
            let compareContentWidth = compareMaxX - narrowOriginX
            #expect(abs(compareContentWidth - 740) <= 2)
            let windowFoldMinX = narrowOriginX + foldRange.lowerBound
            let windowFoldMaxX = narrowOriginX + foldRange.upperBound

            let narrowStrip = try #require(tapFrames.frames["clove.compare.filmstrip"])
            let prevFrame = try #require(tapFrames.frames["clove.compare.prev"])
            let nextFrame = try #require(tapFrames.frames["clove.compare.next"])
            let capsuleFrame = try #require(tapFrames.frames["clove.compare.capsule"])
            #expect(narrowStrip.maxX <= windowFoldMinX - 4 + 0.5)
            #expect(prevFrame.width >= 31.5 && prevFrame.width <= 32.5)
            #expect(nextFrame.width >= 31.5 && nextFrame.width <= 32.5)
            #expect(capsuleFrame.width >= 167.5)
            #expect(prevFrame.minX >= windowFoldMaxX + 4 - 0.5)
            #expect(prevFrame.minX >= narrowPaneBFrame.minX - 0.5)
            #expect(prevFrame.maxX <= nextFrame.minX)
            #expect(nextFrame.maxX <= capsuleFrame.minX)
            #expect(capsuleFrame.maxX <= compareMaxX - 8 + 0.5)
        }

        // 2. Duo Portrait (669x951): Compare is unsupported, rotating/mounting an active Compare
        //    session exits back to Focus View on activePhoto (preserving marks and scope) with
        //    the non-blocking "Rotate to landscape to compare" toast that auto-dismisses cleanly
        //    (~2 s), while manual exit and Duo Cover fold do not show it, and Focus View & Grid
        //    Compare entry points remain hidden/disabled.
        #expect(
            !CompareLayoutPolicy(
                availableWidth: 669, availableHeight: 951, isRegularWidth: true,
                isCompactHeight: false, isDuoExpanded: true, isDuoCover: false
            ).supportsCompare)

        do {
            // 2a. Rotating an active Duo Landscape Compare session (entered from Photo Preview and
            //     carrying a live mark on active challenger) into Duo Portrait exits to Focus View
            //     on activePhoto and shows the auto-dismissing non-blocking rotate toast.
            let foldRange: ClosedRange<CGFloat> = 466...485
            let duoBox = TestDuoEnvironmentBox()
            duoBox.usesSystemToolbar = true
            duoBox.usesVertical = true
            duoBox.hasFoldRegion = true
            duoBox.isDuoExpanded = true
            duoBox.isDuoCover = false

            let targetPhoto = try #require(model.compareSession?.activePhoto)
            let fourStars = try #require(Rating(rawValue: 4))
            model.apply(MarkChange(rating: fourStars), to: targetPhoto)

            let headerFrames = TestHeaderFramesBox()
            let tapFrames = TestTapPickerFramesBox()
            struct DuoRotationCompareHost: View {
                let model: BrowsingModel
                let store: SettingsStore
                let duoBox: TestDuoEnvironmentBox
                let foldRange: ClosedRange<CGFloat>
                let headerFrames: TestHeaderFramesBox
                let tapFrames: TestTapPickerFramesBox

                var body: some View {
                    NavigationStack {
                        GridScreen(
                            browsing: model,
                            thumbnails: model.thumbnails,
                            initialPresentation: .photoPreview)
                    }
                    .environment(store)
                    .environment(\.cloveUserInterfaceIdiom, .phone)
                    .environment(\.isDuoExpanded, duoBox.isDuoExpanded)
                    .environment(\.isDuoCover, duoBox.isDuoCover)
                    .environment(\.usesSystemBrowsingToolbar, duoBox.usesSystemToolbar)
                    .environment(\.usesVerticalBrowsingToolbar, duoBox.usesVertical)
                    .environment(\.hasFoldRegion, duoBox.hasFoldRegion)
                    .environment(
                        \.duoVerticalDivisionRange, duoBox.usesVertical ? foldRange : nil
                    )
                    .onPreferenceChange(HeaderControlFramesPreferenceKey.self) { frames in
                        headerFrames.frames = frames
                    }
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                        tapFrames.frames = frames
                    }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
            let host = UIHostingController(
                rootView: DuoRotationCompareHost(
                    model: model, store: store, duoBox: duoBox, foldRange: foldRange,
                    headerFrames: headerFrames, tapFrames: tapFrames))
            host.traitOverrides.horizontalSizeClass = .regular
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("Duo Landscape Compare did not mount before rotation") {
                self.findComparePanes(in: window).count == 2
                    && tapFrames.frames["clove.compare.capsule"] != nil
            }

            // Rotate into unfolded Duo Portrait (669x951).
            duoBox.usesVertical = false
            window.frame = CGRect(x: 0, y: 0, width: 669, height: 951)
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            try await waitFor("Duo Portrait rotate-exit did not return to Focus View with toast") {
                model.compareSession == nil
                    && self.findComparePanes(in: window).count == 1
                    && tapFrames.frames["clove.compare.capsule"] == nil
                    && tapFrames.frames["clove.duo.focus"] != nil
                    && tapFrames.frames["clove.detail.compareRotateToast"] != nil
                    && tapFrames.frames["clove.detail.inspectionPill"] != nil
                    && tapFrames.frames["clove.detail.filmstrip"] != nil
            }

            #expect(model.state.route == .detail)
            #expect(model.state.currentPhoto == targetPhoto)
            #expect(model.placedPhoto(for: targetPhoto)?.marks.rating == fourStars)
            #expect(tapFrames.frames["clove.duo.photoPreview"] == nil)

            let toastFrame = try #require(tapFrames.frames["clove.detail.compareRotateToast"])
            let pillFrame = try #require(tapFrames.frames["clove.detail.inspectionPill"])
            let stripFrame = try #require(tapFrames.frames["clove.detail.filmstrip"])
            let capsuleFrame = try #require(tapFrames.frames["clove.duo.capsule"])
            #expect(!toastFrame.intersects(pillFrame))
            #expect(!toastFrame.intersects(stripFrame))
            #expect(!toastFrame.intersects(capsuleFrame))
            #expect(toastFrame.minX >= pillFrame.maxX + 11.5)
            #expect(toastFrame.width >= 150 && toastFrame.height >= 44)

            // Toast is hit-test transparent (.allowsHitTesting(false)) so stage gestures pass through.
            let preview = try #require(findDetailZoomPreview(in: window))
            let hit = try #require(
                window.hitTest(CGPoint(x: toastFrame.midX, y: toastFrame.midY), with: nil))
            #expect(hit.isDescendant(of: preview))

            // Focus View inspection pill hides Compare completely in Duo Portrait (44 x 44 pt Focus).
            let focusSnapshot = inspectToolbarState(in: host, window: window)
            #expect(!focusSnapshot.entries.contains { $0.identifier == "clove.detail.compare" })
            #expect(tapFrames.frames["clove.detail.compare"] == nil)
            #expect(headerFrames.frames["clove.detail.compare"] == nil)
            let focusToggleFrame = try #require(tapFrames.frames["clove.detail.focusToggle"])
            #expect(abs(pillFrame.width - 44) <= 1.5 && abs(pillFrame.height - 44) <= 1.5)
            #expect(
                abs(focusToggleFrame.width - 44) <= 1.5
                    && abs(focusToggleFrame.height - 44) <= 1.5)
            if let focusAlpha = effectiveRenderedOpacity(atCenterOf: focusToggleFrame, in: window) {
                #expect(focusAlpha > 0.9)
            }

            // Auto-dismisses cleanly after ~2 seconds.
            try await waitFor(
                "Duo Portrait compare rotate toast did not auto-dismiss",
                timeout: .seconds(4)
            ) {
                tapFrames.frames["clove.detail.compareRotateToast"] == nil
            }

            // 2b. Mounting an active Compare session directly in Duo Portrait (669x951) exits to
            //     Focus View with the rotate toast, and re-entering Compare / navigating clears it.
            let directTimeline = DetailTimeline(
                photos: model.photos, groups: model.groups, groupsEnabled: true)
            #expect(model.enterCompareFromDetail(timeline: directTimeline))
            let mountedTarget = try #require(model.compareSession?.activePhoto)

            try await waitFor("Direct Duo Portrait Compare mount did not exit with toast") {
                model.compareSession == nil
                    && model.state.currentPhoto == mountedTarget
                    && tapFrames.frames["clove.detail.compareRotateToast"] != nil
            }

            let otherPhoto = try #require(model.photos.first { $0.id != mountedTarget }?.id)
            model.openPhoto(otherPhoto)
            try await waitFor(
                "Navigating to another photo did not clear rotate toast",
                timeout: .milliseconds(800)
            ) {
                model.state.currentPhoto == otherPhoto
                    && tapFrames.frames["clove.detail.compareRotateToast"] == nil
            }

            // 2c. Manual exit in Duo Landscape does NOT trigger the rotate toast.
            duoBox.usesVertical = true
            window.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let manualTimeline = DetailTimeline(
                photos: model.photos, groups: model.groups, groupsEnabled: true)
            #expect(model.enterCompareFromDetail(timeline: manualTimeline))
            try await waitFor("Duo Landscape Compare did not mount before manual exit") {
                self.findComparePanes(in: window).count == 2
            }
            model.exitCompare()
            try await waitFor("Manual exit did not return to Focus View") {
                model.compareSession == nil && tapFrames.frames["clove.duo.focus"] != nil
            }
            try await Task.sleep(for: .milliseconds(100))
            #expect(tapFrames.frames["clove.detail.compareRotateToast"] == nil)

            // 2d. Folding to Duo Cover does NOT trigger the rotate toast.
            let coverTimeline = DetailTimeline(
                photos: model.photos, groups: model.groups, groupsEnabled: true)
            #expect(model.enterCompareFromDetail(timeline: coverTimeline))
            try await waitFor("Duo Landscape Compare did not mount before cover fold") {
                self.findComparePanes(in: window).count == 2
            }
            duoBox.isDuoExpanded = false
            duoBox.isDuoCover = true
            duoBox.hasFoldRegion = false
            duoBox.usesVertical = true
            window.frame = CGRect(x: 0, y: 0, width: 412, height: 915)
            host.traitOverrides.horizontalSizeClass = .compact
            host.traitOverrides.verticalSizeClass = .regular
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await waitFor("Cover fold did not exit Compare") {
                model.compareSession == nil
            }
            try await Task.sleep(for: .milliseconds(100))
            #expect(tapFrames.frames["clove.detail.compareRotateToast"] == nil)

            // 2e. Grid two-photo selection in unfolded Duo Portrait (669x951) hides Compare capsule.
            model.back()
            let second = try #require(model.photos.dropFirst().first)
            model.toggleSelection(first)
            model.toggleSelection(second.id)
            defer { model.clearSelection() }
            duoBox.isDuoExpanded = true
            duoBox.isDuoCover = false
            duoBox.hasFoldRegion = true
            duoBox.usesVertical = false
            window.frame = CGRect(x: 0, y: 0, width: 669, height: 951)
            host.traitOverrides.horizontalSizeClass = .regular
            host.traitOverrides.verticalSizeClass = .regular
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await waitFor("Duo Portrait Grid batch bar did not mount") {
                tapFrames.frames["clove.grid.batch.bar"] != nil
                    && tapFrames.frames["clove.grid.batch.actions"] != nil
            }
            #expect(tapFrames.frames["clove.grid.batch.compare"] == nil)
        }
    }

    private func findDetailZoomPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let found = findDetailZoomPreview(in: child) { return found }
        }
        return nil
    }

    private func effectiveRenderedOpacity(atCenterOf rect: CGRect, in window: UIWindow) -> CGFloat?
    {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        func walk(_ view: UIView, inherited: CGFloat) -> [CGFloat] {
            let viewInWindow = view.convert(view.bounds, to: window)
            guard viewInWindow.contains(point) else { return [] }
            let local = inherited * view.alpha
            var matches = view.subviews.flatMap { walk($0, inherited: local) }
            if abs(viewInWindow.width - rect.width) <= 4,
                abs(viewInWindow.height - rect.height) <= 4
            {
                matches.append(local)
            }
            return matches
        }
        return walk(window, inherited: 1).min()
    }

    private func findComparePanes(in view: UIView) -> [DetailZoomContainerView] {
        var found: [DetailZoomContainerView] = []
        if let pane = view as? DetailZoomContainerView {
            found.append(pane)
        }
        for child in view.subviews {
            found.append(contentsOf: findComparePanes(in: child))
        }
        return found
    }

    private struct ToolbarSnapshot {
        struct Entry {
            let identifier: String
            let groupIndex: Int
            let frame: CGRect?
        }

        let leadingGroupIDs: [[String]]
        let trailingGroupIDs: [[String]]
        let bottomToolbarIDs: [String]
        let trailingRawTokens: [String]
        let rawLeadingItemCount: Int
        let entries: [Entry]
        let overlayIdentifiers: [String: CGRect]
        let debugSummary: String

        var leadingIDs: [String] { leadingGroupIDs.flatMap { $0 } }
        var trailingIDs: [String] { trailingGroupIDs.flatMap { $0 } }

        func contains(_ identifier: String) -> Bool {
            entries.contains { $0.identifier == identifier }
                || overlayIdentifiers[identifier] != nil
        }

        func frame(for identifier: String) -> CGRect? {
            if let entryFrame = entries.first(where: { $0.identifier == identifier })?.frame {
                return entryFrame
            }
            return overlayIdentifiers[identifier]
        }

        func groupIndex(for identifier: String) -> Int? {
            entries.first(where: { $0.identifier == identifier })?.groupIndex
        }

        func groupIDs(containing identifier: String) -> [String]? {
            (leadingGroupIDs + trailingGroupIDs + [bottomToolbarIDs]).first {
                $0.contains(identifier)
            }
        }

        var description: String { debugSummary }
    }

    private func findNavigationController(in controller: UIViewController)
        -> UINavigationController?
    {
        if let nav = controller as? UINavigationController { return nav }
        for child in controller.children {
            if let nav = findNavigationController(in: child) { return nav }
        }
        return nil
    }

    private func hasToolbarItem(
        identifier: String, in host: UIViewController, window: UIWindow, isCompare: Bool = false
    ) -> Bool {
        inspectToolbarState(in: host, window: window, isCompare: isCompare).frame(for: identifier)
            != nil
    }

    private func hasAnyToolbarIdentifier(
        _ identifier: String, in host: UIViewController, window: UIWindow, isCompare: Bool = false
    ) -> Bool {
        inspectToolbarState(in: host, window: window, isCompare: isCompare).contains(identifier)
    }

    private func describeToolbarState(
        in host: UIViewController,
        window: UIWindow,
        leadingBarHostIdentifier: String = "clove.detail.gridToggle",
        isCompare: Bool = false
    ) -> String {
        inspectToolbarState(
            in: host, window: window, leadingBarHostIdentifier: leadingBarHostIdentifier,
            isCompare: isCompare
        ).description
    }

    private func inspectToolbarState(
        in host: UIViewController,
        window: UIWindow,
        leadingBarHostIdentifier: String = "clove.detail.gridToggle",
        isCompare: Bool = false
    ) -> ToolbarSnapshot {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let navBar = findNavigationBar(in: window)
        let navItem =
            navBar?.topItem ?? findNavigationController(in: host)?.topViewController?.navigationItem
        let topVC = findNavigationController(in: host)?.topViewController
        let leadingGroups = navItem?.leadingItemGroups ?? []
        let centerGroups = navItem?.centerItemGroups ?? []
        let trailingGroups = navItem?.trailingItemGroups ?? []
        let bottomItems = topVC?.toolbarItems ?? []
        let usesVerticalBar =
            if #available(iOS 27.1, *) {
                host.traitCollection.verticalBarEdge != .unspecified
            } else {
                false
            }

        var rawBarViews: [(view: UIView, frame: CGRect)] = []
        var barButtonViews: [(view: UIView, frame: CGRect)] = []
        func collectBarViews(_ view: UIView) {
            let typeName = String(describing: type(of: view))
            let frame = view.convert(view.bounds, to: window)
            if frame.width > 0 && frame.height > 0 {
                if typeName.contains("ButtonBarButton") {
                    barButtonViews.append((view, frame))
                }
                if typeName.contains("ButtonBarButton") || typeName.contains("BarItemHost")
                    || typeName.contains("UIHostingView") || typeName.contains("VerticalBar")
                    || typeName.contains("Toolbar") || view is UIControl
                    || !(view.accessibilityIdentifier?.isEmpty ?? true)
                {
                    rawBarViews.append((view, frame))
                }
            }
            for child in view.subviews {
                collectBarViews(child)
            }
        }
        collectBarViews(window)

        var overlayIdentifiers: [String: CGRect] = [:]
        func collectIdentified(_ view: UIView) {
            if let id = view.accessibilityIdentifier, !id.isEmpty {
                let frame = view.convert(view.bounds, to: window)
                if frame.width > 0 && frame.height > 0 {
                    overlayIdentifiers[id] = frame
                }
            }
            if let elements = view.accessibilityElements {
                for element in elements {
                    if let identification = element as? UIAccessibilityIdentification,
                        let id = identification.accessibilityIdentifier, !id.isEmpty
                    {
                        let accFrame = (element as? NSObject)?.accessibilityFrame ?? .zero
                        let frame =
                            (accFrame.width > 0 && accFrame.height > 0)
                            ? window.convert(accFrame, from: nil)
                            : view.convert(view.bounds, to: window)
                        if frame.width > 0 && frame.height > 0 {
                            overlayIdentifiers[id] = frame
                        }
                    }
                    if let nested = element as? UIView {
                        collectIdentified(nested)
                    }
                }
            }
            for child in view.subviews {
                collectIdentified(child)
            }
        }
        collectIdentified(window)

        func firstIdentifiedDescendant(in view: UIView) -> String? {
            if let id = view.accessibilityIdentifier, !id.isEmpty { return id }
            if let elements = view.accessibilityElements {
                for element in elements {
                    if let identification = element as? UIAccessibilityIdentification,
                        let id = identification.accessibilityIdentifier, !id.isEmpty
                    {
                        return id
                    }
                    if let nested = element as? UIView,
                        let id = firstIdentifiedDescendant(in: nested)
                    {
                        return id
                    }
                }
            }
            for child in view.subviews {
                if let id = firstIdentifiedDescendant(in: child) { return id }
            }
            return nil
        }

        func firstAccessibilityLabelDescendant(in view: UIView) -> String? {
            if let label = view.accessibilityLabel, !label.isEmpty { return label }
            if let elements = view.accessibilityElements {
                for element in elements {
                    if let obj = element as? NSObject, let label = obj.accessibilityLabel,
                        !label.isEmpty
                    {
                        return label
                    }
                    if let nested = element as? UIView,
                        let label = firstAccessibilityLabelDescendant(in: nested)
                    {
                        return label
                    }
                }
            }
            for child in view.subviews {
                if let label = firstAccessibilityLabelDescendant(in: child) { return label }
            }
            return nil
        }

        let isDetailScreen =
            overlayIdentifiers["clove.detail.preview"] != nil
            || overlayIdentifiers["clove.detail.empty"] != nil
            || overlayIdentifiers["clove.duo.focus"] != nil
            || overlayIdentifiers["clove.duo.photoPreview"] != nil

        func knownIdentifier(forText text: String) -> String? {
            if isCompare {
                switch text {
                case "Done", "Back": return "clove.compare.done"
                case "Focus regions": return "clove.compare.focusRegions"
                case "Sync On", "Sync Off": return "clove.compare.syncToggle"
                case "Set as A": return "clove.compare.setAsA"
                default: return nil
                }
            }
            switch text {
            case "Back": return "clove.nav.back"
            case "Filter": return isDetailScreen ? "clove.detail.filter" : "clove.grid.filter"
            case "More": return "clove.grid.more"
            case "Compare": return "clove.detail.compare"
            case "Info": return "clove.detail.info"
            case "Undo": return usesVerticalBar ? "clove.duo.undo" : "clove.detail.undo"
            case "Reject", "Rejected": return "clove.duo.reject"
            case "Move rejects": return "clove.grid.moveRejects"
            case "Done": return "clove.grid.batch.done"
            case "Select All", "Deselect All", "Select all", "Deselect all":
                return "clove.grid.selectAll"
            case "Hide photo grid", "Show photo grid": return "clove.detail.gridToggle"
            case "Focus regions": return "clove.detail.focusToggle"
            default:
                if text.hasPrefix("Rating") { return "clove.duo.rating" }
                if text.hasPrefix("Label") { return "clove.duo.label" }
                return nil
            }
        }

        func itemIdentifier(_ item: UIBarButtonItem, isLeading: Bool, indexInTrailing: Int = 0)
            -> String?
        {
            if let id = item.accessibilityIdentifier, !id.isEmpty { return id }
            if let custom = item.customView {
                if let id = firstIdentifiedDescendant(in: custom) { return id }
                if let label = firstAccessibilityLabelDescendant(in: custom),
                    let mapped = knownIdentifier(forText: label)
                {
                    return mapped
                }
            }
            for text in [item.accessibilityLabel, item.title].compactMap({ $0 }) where !text.isEmpty
            {
                if let mapped = knownIdentifier(forText: text) { return mapped }
            }
            if let custom = item.customView,
                String(describing: type(of: custom)).contains("BarItemHost")
            {
                if isLeading { return leadingBarHostIdentifier }
                if isDetailScreen {
                    // Expanded Duo Detail puts photoGridToggle first; Duo Cover Detail puts Focus
                    // regions first (both via standaloneDockTool) before spacer & Filter.
                    return indexInTrailing == 0
                        ? leadingBarHostIdentifier : "clove.detail.focusToggle"
                }
                return "clove.grid.filter"
            }
            return nil
        }

        let navBarMaxY = navBar.map { $0.convert($0.bounds, to: window).maxY } ?? 120
        let horizontalBarButtons =
            barButtonViews
            .filter { $0.frame.minY <= navBarMaxY + 8 }
            .sorted { $0.frame.minX < $1.frame.minX }
        let verticalBarButtons =
            usesVerticalBar
            ? barButtonViews
                .filter { $0.frame.minY > navBarMaxY + 8 }
                .sorted { $0.frame.minY < $1.frame.minY }
            : []

        let trailingFlatItems = trailingGroups.flatMap(\.barButtonItems)
        let trailingIndexMap: [ObjectIdentifier: Int] = Dictionary(
            trailingFlatItems.enumerated().map {
                (ObjectIdentifier($0.element), $0.offset)
            },
            uniquingKeysWith: { first, _ in first })
        func resolvedIdentifier(_ item: UIBarButtonItem, isLeading: Bool) -> String? {
            itemIdentifier(
                item, isLeading: isLeading,
                indexInTrailing: trailingIndexMap[ObjectIdentifier(item)] ?? 0)
        }

        let navItems: [(item: UIBarButtonItem, isLeading: Bool)] =
            leadingGroups.flatMap(\.barButtonItems).map { ($0, true) }
            + trailingGroups.flatMap(\.barButtonItems).map { ($0, false) }
        let navPlainItems = navItems.filter {
            $0.item.customView == nil
                && resolvedIdentifier($0.item, isLeading: $0.isLeading) != nil
        }
        let allItemsInOrder: [(item: UIBarButtonItem, isLeading: Bool)] =
            navItems + bottomItems.map { ($0, false) }
        let allPlainItems = allItemsInOrder.filter {
            $0.item.customView == nil && resolvedIdentifier($0.item, isLeading: $0.isLeading) != nil
        }

        let horizontalOnlyIDs: Set<String> = [
            "clove.grid.more", "clove.grid.selectAll", "clove.grid.batch.done",
        ]
        var plainItemFrames: [ObjectIdentifier: CGRect] = [:]
        if !usesVerticalBar {
            if navPlainItems.count == horizontalBarButtons.count {
                for (entry, barView) in zip(navPlainItems, horizontalBarButtons) {
                    plainItemFrames[ObjectIdentifier(entry.item)] = barView.frame
                }
            }
            let bottomPlainItems = bottomItems.filter {
                $0.customView == nil && resolvedIdentifier($0, isLeading: false) != nil
            }
            let bottomBarButtons =
                barButtonViews
                .filter { $0.frame.minY > navBarMaxY + 8 }
                .sorted { $0.frame.minX < $1.frame.minX }
            if bottomPlainItems.count == bottomBarButtons.count {
                for (item, barView) in zip(bottomPlainItems, bottomBarButtons) {
                    plainItemFrames[ObjectIdentifier(item)] = barView.frame
                }
            }
        } else if horizontalBarButtons.isEmpty {
            if allPlainItems.count == verticalBarButtons.count {
                for (entry, barView) in zip(allPlainItems, verticalBarButtons) {
                    plainItemFrames[ObjectIdentifier(entry.item)] = barView.frame
                }
            }
        } else {
            let horizItems = allPlainItems.filter {
                resolvedIdentifier($0.item, isLeading: $0.isLeading).map(horizontalOnlyIDs.contains)
                    ?? false
            }
            let vertItems = allPlainItems.filter {
                !(resolvedIdentifier($0.item, isLeading: $0.isLeading).map(
                    horizontalOnlyIDs.contains)
                    ?? false)
            }
            if horizItems.count == horizontalBarButtons.count {
                for (entry, barView) in zip(horizItems, horizontalBarButtons) {
                    plainItemFrames[ObjectIdentifier(entry.item)] = barView.frame
                }
            }
            if vertItems.count == verticalBarButtons.count {
                for (entry, barView) in zip(vertItems, verticalBarButtons) {
                    plainItemFrames[ObjectIdentifier(entry.item)] = barView.frame
                }
            }
        }

        func frameForBarItem(_ item: UIBarButtonItem, isLeading: Bool) -> CGRect? {
            if let matched = plainItemFrames[ObjectIdentifier(item)] {
                return matched
            }
            if let id = resolvedIdentifier(item, isLeading: isLeading) {
                if let found = overlayIdentifiers[id] { return found }
                if let match = rawBarViews.first(where: { $0.view.accessibilityIdentifier == id }) {
                    return match.frame
                }
            }
            if let custom = item.customView {
                let frame = custom.convert(custom.bounds, to: window)
                if frame.width > 0 && frame.height > 0 { return frame }
            }
            let labels = [item.accessibilityLabel, item.title].compactMap { $0 }.filter {
                !$0.isEmpty
            }
            for label in labels {
                if let match = rawBarViews.first(where: { $0.view.accessibilityLabel == label }) {
                    return match.frame
                }
            }
            return nil
        }

        func describeRawItem(_ item: UIBarButtonItem) -> String {
            let customFrame =
                item.customView.map {
                    NSCoder.string(for: $0.convert($0.bounds, to: window))
                } ?? "-"
            let customLabel = item.customView.flatMap(firstAccessibilityLabelDescendant) ?? "-"
            let customID = item.customView.flatMap(firstIdentifiedDescendant) ?? "-"
            return
                "id=\(item.accessibilityIdentifier ?? "-")/lbl=\(item.accessibilityLabel ?? "-")/ttl=\(item.title ?? "-")/cv=\(item.customView.map { String(describing: type(of: $0)) } ?? "-")/cid=\(customID)/clbl=\(customLabel)/cf=\(customFrame)"
        }

        var entries: [ToolbarSnapshot.Entry] = []
        var groupIdx = 0
        var leadingGroupIDs: [[String]] = []
        for group in leadingGroups {
            let ids = group.barButtonItems.compactMap { resolvedIdentifier($0, isLeading: true) }
            if !ids.isEmpty {
                leadingGroupIDs.append(ids)
            }
            for item in group.barButtonItems {
                if let id = resolvedIdentifier(item, isLeading: true) {
                    entries.append(
                        ToolbarSnapshot.Entry(
                            identifier: id, groupIndex: groupIdx,
                            frame: frameForBarItem(item, isLeading: true)))
                }
            }
            if !ids.isEmpty { groupIdx += 1 }
        }
        var trailingGroupIDs: [[String]] = []
        var trailingRawTokens: [String] = []
        for group in trailingGroups {
            let ids = group.barButtonItems.compactMap { resolvedIdentifier($0, isLeading: false) }
            for item in group.barButtonItems {
                if let id = resolvedIdentifier(item, isLeading: false) {
                    trailingRawTokens.append(id)
                    entries.append(
                        ToolbarSnapshot.Entry(
                            identifier: id, groupIndex: groupIdx,
                            frame: frameForBarItem(item, isLeading: false)))
                } else if item.customView == nil {
                    trailingRawTokens.append("<spacer>")
                }
            }
            if !ids.isEmpty {
                trailingGroupIDs.append(ids)
                groupIdx += 1
            }
        }
        var bottomIDs: [String] = []
        for item in bottomItems {
            if let id = resolvedIdentifier(item, isLeading: false) {
                bottomIDs.append(id)
                entries.append(
                    ToolbarSnapshot.Entry(
                        identifier: id, groupIndex: groupIdx,
                        frame: frameForBarItem(item, isLeading: false)))
            }
        }

        let barViewDebug = rawBarViews.map {
            "\(String(describing: type(of: $0.view)))(\($0.view.accessibilityIdentifier ?? "-")/\($0.view.accessibilityLabel ?? "-"))@\(NSCoder.string(for: $0.frame))"
        }
        let edgeValue =
            if #available(iOS 27.1, *) {
                host.traitCollection.verticalBarEdge.rawValue
            } else {
                -1
            }
        let rawLeading = leadingGroups.map { $0.barButtonItems.map(describeRawItem) }
        let rawCenter = centerGroups.map { $0.barButtonItems.map(describeRawItem) }
        let rawTrailing = trailingGroups.map { $0.barButtonItems.map(describeRawItem) }
        let rawBottom = bottomItems.map(describeRawItem)
        let summary =
            "verticalEdge=\(edgeValue) navBar=\(navBar != nil) leading=\(leadingGroupIDs) trailing=\(trailingGroupIDs) bottom=\(bottomIDs) trailingTokens=\(trailingRawTokens) rawL=\(rawLeading) rawC=\(rawCenter) rawT=\(rawTrailing) rawB=\(rawBottom) ids=\(overlayIdentifiers.keys.sorted()) views=\(barViewDebug)"
        return ToolbarSnapshot(
            leadingGroupIDs: leadingGroupIDs,
            trailingGroupIDs: trailingGroupIDs,
            bottomToolbarIDs: bottomIDs,
            trailingRawTokens: trailingRawTokens,
            rawLeadingItemCount: leadingGroups.flatMap(\.barButtonItems).count,
            entries: entries,
            overlayIdentifiers: overlayIdentifiers,
            debugSummary: summary)
    }

    private func leadingBarItemFrame(
        in navBar: UINavigationBar, index: Int, relativeTo window: UIWindow
    ) -> CGRect? {
        let items = navBar.topItem?.leadingItemGroups.flatMap(\.barButtonItems) ?? []
        if items.indices.contains(index), let custom = items[index].customView {
            return custom.convert(custom.bounds, to: window)
        }
        let leadingButtons = barButtonSubviews(in: navBar, relativeTo: window)
            .filter { $0.frame.midX < window.bounds.midX }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard leadingButtons.indices.contains(index) else { return nil }
        return leadingButtons[index].frame
    }

    private func centerBarGroupFrame(in navBar: UINavigationBar, relativeTo window: UIWindow)
        -> CGRect?
    {
        if let titleView = navBar.topItem?.titleView {
            return titleView.convert(titleView.bounds, to: window)
        }
        let centerItems = navBar.topItem?.centerItemGroups.flatMap(\.barButtonItems) ?? []
        if let custom = centerItems.first?.customView {
            return custom.convert(custom.bounds, to: window)
        }
        let candidates = barButtonSubviews(in: navBar, relativeTo: window)
            .filter { abs($0.frame.midX - window.bounds.midX) < window.bounds.width * 0.25 }
        return candidates.first?.frame
    }

    private func barButtonSubviews(
        in navBar: UINavigationBar, relativeTo window: UIWindow
    ) -> [(view: UIView, frame: CGRect)] {
        var result: [(UIView, CGRect)] = []
        func walk(_ view: UIView) {
            let typeName = String(describing: type(of: view))
            if typeName.contains("ButtonBarButton") || typeName.contains("UIHostingView")
                || view is UIControl
            {
                let frame = view.convert(view.bounds, to: window)
                if frame.width > 0 && frame.height > 0 {
                    result.append((view, frame))
                }
            }
            for child in view.subviews {
                walk(child)
            }
        }
        walk(navBar)
        return result
    }

    private func describeNavBar(in window: UIWindow) -> String {
        guard let navBar = findNavigationBar(in: window) else { return "no navBar" }
        let leading = navBar.topItem?.leadingItemGroups.flatMap(\.barButtonItems).count ?? 0
        let center = navBar.topItem?.centerItemGroups.flatMap(\.barButtonItems).count ?? 0
        let trailing = navBar.topItem?.trailingItemGroups.flatMap(\.barButtonItems).count ?? 0
        let titleViewDesc =
            navBar.topItem?.titleView.map {
                "\(type(of: $0))=\(NSCoder.string(for: $0.convert($0.bounds, to: window)))"
            } ?? "nil"
        let buttons = barButtonSubviews(in: navBar, relativeTo: window).map {
            "\(type(of: $0.view))=\(NSCoder.string(for: $0.frame))"
        }
        return
            "leading=\(leading) center=\(center) trailing=\(trailing) titleView=\(titleViewDesc) views=\(buttons)"
    }

    private func findNavigationBar(in view: UIView) -> UINavigationBar? {
        if let navBar = view as? UINavigationBar { return navBar }
        for child in view.subviews {
            if let navBar = findNavigationBar(in: child) { return navBar }
        }
        return nil
    }

    private func findVerticalBarView(in view: UIView) -> UIView? {
        if String(describing: type(of: view)).contains("VerticalBar"),
            view.bounds.width > 0, view.bounds.height > 0
        {
            return view
        }
        for child in view.subviews {
            if let found = findVerticalBarView(in: child) { return found }
        }
        return nil
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for child in view.subviews {
            if let collection = findCollectionView(in: child) { return collection }
        }
        return nil
    }

    private func hasGridCollection(in view: UIView) -> Bool {
        if view is UICollectionView { return true }
        return view.subviews.contains { hasGridCollection(in: $0) }
    }

    private func findFilmstripScrollView(in view: UIView) -> UIScrollView? {
        if view is DetailZoomContainerView { return nil }
        if let scrollView = view as? UIScrollView, !(view is UICollectionView) {
            return scrollView
        }
        for child in view.subviews {
            if let found = findFilmstripScrollView(in: child) { return found }
        }
        return nil
    }

    private func findSplitViewController(in controller: UIViewController) -> UISplitViewController?
    {
        if let split = controller as? UISplitViewController { return split }
        for child in controller.children {
            if let split = findSplitViewController(in: child) { return split }
        }
        return nil
    }

    private func topPresentedViewController(from controller: UIViewController) -> UIViewController?
    {
        if let presented = controller.presentedViewController { return presented }
        for child in controller.children {
            if let presented = topPresentedViewController(from: child) { return presented }
        }
        return nil
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
private final class TestToolbarHostBox {
    var photoID: PhotoIdentity
    var isDuoExpanded = false
    var isDuoCover = false
    var isEnabled = true
    var scenePhase: ScenePhase = .active
    var popoverTrigger = 0

    init(photoID: PhotoIdentity) {
        self.photoID = photoID
    }
}

@MainActor
@Observable
private final class TestDuoEnvironmentBox {
    var usesSystemToolbar = true
    var usesVertical = true
    var hasFoldRegion = true
    var isDuoExpanded = true
    var isDuoCover = false
    var scenePhase: ScenePhase = .active
}

@MainActor
@Observable
private final class TestHeaderFramesBox {
    var frames: [String: CGRect] = [:]
}

@MainActor
@Observable
private final class TestTapPickerFramesBox {
    var frames: [String: CGRect] = [:]
}

@MainActor
@Observable
private final class TestPickerTriggerBox {
    var trigger: TapPickerTriggerRequest?
    private var counter = 0

    func sendTrigger(_ id: String) {
        counter += 1
        trigger = TapPickerTriggerRequest(id: id, nonce: counter)
    }
}
