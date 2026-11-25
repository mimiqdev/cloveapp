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

        // 4. DuoMarkControls label popover dismisses on posture & inactive scene snapshot.
        if #available(iOS 27.1, *) {
            let box = TestToolbarHostBox(photoID: first)
            box.isDuoCover = true
            struct HostView: View {
                let box: TestToolbarHostBox
                var body: some View {
                    NavigationStack {
                        Color.clear
                            .toolbar {
                                DuoMarkControls(
                                    photoID: box.photoID,
                                    marks: PhotoMarks(),
                                    settings: AppSettings(),
                                    previewRating: nil,
                                    canMark: box.isEnabled,
                                    showsStars: .constant(false),
                                    dragRating: .constant(nil),
                                    rate: { _ in },
                                    label: { _ in },
                                    toggleReject: {},
                                    markingBegan: {},
                                    labelPopoverTrigger: box.popoverTrigger)
                            }
                    }
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
            try await waitFor("duo label popover presented") {
                self.topPresentedViewController(from: host) != nil
            }
            box.isDuoCover = false
            box.scenePhase = .inactive
            UIView.performWithoutAnimation {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = window.snapshotView(afterScreenUpdates: true)
            }
            try await waitFor("duo label popover dismissed on posture/scene change") {
                self.topPresentedViewController(from: host) == nil
            }
        }
    }

    @Test func preparationAndFilterPopoversSurviveDetailAndSnapshotTransitions() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = TestLibrary.forLaunch(
            environment: [
                TestLibrary.launchVariable: "1",
                TestLibrary.preparationVariable: "preparing",
            ])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = try #require(model.photos.first?.id)
        let duoBox = TestDuoEnvironmentBox()

        struct HostView: View {
            let model: BrowsingModel
            let duoBox: TestDuoEnvironmentBox
            var body: some View {
                NavigationStack {
                    GridScreen(
                        browsing: model,
                        thumbnails: model.thumbnails,
                        filterPopoverTrigger: duoBox.filterPopoverTrigger)
                }
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
        host.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(80))
        window.layoutIfNeeded()
        duoBox.filterPopoverTrigger += 1
        try await waitFor("grid filter popover presented") {
            self.topPresentedViewController(from: host) != nil
        }
        duoBox.isDuoExpanded = false
        duoBox.usesVertical = false
        duoBox.hasFoldRegion = false
        model.openPhoto(photo)
        duoBox.scenePhase = .inactive
        UIView.performWithoutAnimation {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            _ = window.snapshotView(afterScreenUpdates: true)
        }
        try await waitFor("grid filter popover dismissed on route/snapshot change") {
            self.topPresentedViewController(from: host) == nil
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

    @Test func gridFilterPopoverDismissesOnOrientationChange() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = BrowsingModel(library: TestLibrary.sample())
        model.openFolder()
        let box = TestDuoEnvironmentBox()
        box.isDuoExpanded = false
        box.usesVertical = false
        box.hasFoldRegion = false

        struct HostView: View {
            let model: BrowsingModel
            let box: TestDuoEnvironmentBox
            var body: some View {
                NavigationStack {
                    GridScreen(
                        browsing: model,
                        thumbnails: model.thumbnails,
                        filterPopoverTrigger: box.filterPopoverTrigger)
                }
                .environment(SettingsStore.sample)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.scenePhase, .active)
            }
        }

        let host = UIHostingController(rootView: HostView(model: model, box: box))
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

        try await Task.sleep(for: .milliseconds(80))
        window.layoutIfNeeded()
        box.filterPopoverTrigger += 1
        try await waitFor("grid filter popover presented") {
            self.topPresentedViewController(from: host) != nil
        }

        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .compact
        window.frame = CGRect(x: 0, y: 0, width: 932, height: 430)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitFor("grid filter popover dismissed on orientation change") {
            self.topPresentedViewController(from: host) == nil
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
                    box.frames["clove.grid.batch.count"] != nil
                        && box.frames["clove.grid.batch.hiddenCount"] != nil
                        && box.frames["clove.grid.filter"] != nil
                        && box.frames["clove.grid.selectionOptions"] != nil
                        && box.frames["clove.grid.batch.done"] != nil
                }

                let countFrame = try #require(box.frames["clove.grid.batch.count"])
                let hiddenFrame = try #require(box.frames["clove.grid.batch.hiddenCount"])
                let filterFrame = try #require(box.frames["clove.grid.filter"])
                let optionsFrame = try #require(box.frames["clove.grid.selectionOptions"])
                let doneFrame = try #require(box.frames["clove.grid.batch.done"])

                for frame in [countFrame, hiddenFrame, filterFrame, optionsFrame, doneFrame] {
                    #expect(frame.width > 0 && frame.height > 0)
                    #expect(frame.minX >= 16 - 1.5)
                    #expect(frame.maxX <= width - 16 + 1.5)
                }

                let titleMaxX = max(countFrame.maxX, hiddenFrame.maxX)
                #expect(titleMaxX <= filterFrame.minX + 1.5)
                #expect(filterFrame.maxX <= optionsFrame.minX + 1.5)
                #expect(optionsFrame.maxX <= doneFrame.minX + 1.5)
            }
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
                        filter: AnyView(EmptyView()),
                        more: AnyView(EmptyView()),
                        bottom: AnyView(EmptyView()),
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
        _ message: String,
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record(Comment(rawValue: message))
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
    var filterPopoverTrigger = 0
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
