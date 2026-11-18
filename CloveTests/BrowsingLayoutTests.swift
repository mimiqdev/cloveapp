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
            rootView: BrowseShell(browsing: model).environment(SettingsStore.sample))
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
