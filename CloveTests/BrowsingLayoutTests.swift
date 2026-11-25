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
        #expect(GridCollectionView.columns(width: 430, regular: false) == 3)
        #expect(GridCollectionView.columns(width: 667, regular: false) >= 4)
        #expect(GridCollectionView.columns(width: 844, regular: false) >= 5)
        #expect(GridCollectionView.columns(width: 932, regular: false) >= 5)

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
