import CloveCore
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct TapPickerTests {
    // MARK: - Geometry

    @Test func ratingAndLabelPickerMatchReferenceDimensions() {
        #expect(RatingPicker.preferredSize(for: .horizontal) == CGSize(width: 288, height: 52))
        #expect(RatingPicker.preferredSize(for: .vertical) == CGSize(width: 52, height: 288))
        #expect(
            LabelPicker.preferredSize(for: .horizontal, count: 6) == CGSize(width: 288, height: 52)
        )
        #expect(
            LabelPicker.preferredSize(for: .vertical, count: 6) == CGSize(width: 52, height: 288))
    }

    // MARK: - Adaptive placement

    @Test func placementDefaultsToHorizontalAboveAnchorAndClampsWithinSafeArea() {
        let horizontal = RatingPicker.preferredSize(for: .horizontal)
        let vertical = RatingPicker.preferredSize(for: .vertical)
        let container = CGSize(width: 390, height: 844)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        // Right-edge label button inside DetailMarkCapsule.
        let anchor = CGRect(x: 322, y: 740, width: 36, height: 36)

        let placement = TapPickerPlacement.resolve(
            anchor: anchor,
            containerSize: container,
            safeAreaInsets: insets,
            horizontalSize: horizontal,
            verticalSize: vertical,
            preferredEdge: .top)

        #expect(placement.axis == .horizontal)
        #expect(placement.frame.size == horizontal)
        #expect(placement.frame.maxY <= anchor.minY)
        #expect(placement.frame.maxX <= container.width - 12)
        #expect(placement.frame.minX >= 12)
    }

    @Test func placementFallsBackToVerticalWhenHorizontalDoesNotFitSafeWidth() {
        let container = CGSize(width: 320, height: 700)
        // Extended 8-colour picker (382.4 pt wide) does not fit inside a 320 pt pane.
        let horizontal = LabelPicker.preferredSize(for: .horizontal, count: 8)
        let vertical = LabelPicker.preferredSize(for: .vertical, count: 8)
        let anchor = CGRect(x: 250, y: 610, width: 36, height: 36)

        let placement = TapPickerPlacement.resolve(
            anchor: anchor,
            containerSize: container,
            horizontalSize: horizontal,
            verticalSize: vertical,
            preferredEdge: .top)

        #expect(placement.axis == .vertical)
        #expect(placement.frame.size == vertical)
        #expect(placement.frame.minX >= 12)
        #expect(placement.frame.maxX <= container.width - 12)
        #expect(placement.frame.minY >= 12)
        #expect(placement.frame.maxY <= anchor.minY)
    }

    @Test func placementUsesVerticalAndClearsDuoSecondaryRailOnVerticalEdges() {
        let horizontal = RatingPicker.preferredSize(for: .horizontal)
        let vertical = RatingPicker.preferredSize(for: .vertical)
        let container = CGSize(width: 400, height: 780)
        let insets = EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 64)
        let anchor = CGRect(x: 280, y: 360, width: 44, height: 44)

        let placement = TapPickerPlacement.resolve(
            anchor: anchor,
            containerSize: container,
            safeAreaInsets: insets,
            horizontalSize: horizontal,
            verticalSize: vertical,
            preferredEdge: .trailing)

        #expect(placement.axis == .vertical)
        #expect(placement.frame.size == vertical)
        #expect(placement.frame.maxX <= container.width - insets.trailing - 12)
    }

    // MARK: - Controller

    @Test func controllerTogglesSwitchesAndDismisses() {
        let controller = TapPickerController()
        let anchor = CGRect(x: 100, y: 500, width: 44, height: 44)
        let hSize = RatingPicker.preferredSize(for: .horizontal)
        let vSize = RatingPicker.preferredSize(for: .vertical)

        controller.toggle(
            id: "rating", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        #expect(controller.isPresented(id: "rating"))

        // Tapping same trigger toggles closed.
        controller.toggle(
            id: "rating", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        #expect(!controller.isPresented)

        // Switching from rating to label replaces active presentation cleanly.
        controller.toggle(
            id: "rating", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        controller.toggle(
            id: "label", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        #expect(controller.isPresented(id: "label"))
        #expect(!controller.isPresented(id: "rating"))

        controller.updateAnchor(id: "label", anchor: CGRect(x: 150, y: 500, width: 44, height: 44))
        #expect(controller.active?.anchor.minX == 150)

        controller.dismiss()
        #expect(!controller.isPresented)
    }

    // MARK: - Hosted placement regressions

    @Test func duoExpandedFocusViewAndPhotoPreviewPlaceTapPickersWithinPhotoPane() async throws {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        var capsuleFramesByPresentation: [DetailPresentation: CGRect] = [:]
        for (presentation, paneIdentifier) in [
            (DetailPresentation.photoPreview, "clove.duo.photoPreview"),
            (DetailPresentation.focus, "clove.duo.focus"),
        ] {
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            let target = try #require(browsing.photos.first { $0.fileName == "MMQ02680.ARW" })
            let box = TapPickerTestBox()

            struct HostView: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let presentation: DetailPresentation
                let box: TapPickerTestBox

                var body: some View {
                    NavigationStack {
                        GridScreen(
                            browsing: browsing,
                            thumbnails: browsing.thumbnails,
                            initialPresentation: presentation)
                    }
                    .environment(store)
                    .environment(\.isDuoExpanded, true)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, true)
                    .environment(\.hasFoldRegion, true)
                    .environment(\.scenePhase, .active)
                    .environment(\.tapPickerTriggerRequest, box.trigger)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                        box.frames = frames
                    }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
            let host = UIHostingController(
                rootView: HostView(
                    browsing: browsing, store: store, presentation: presentation, box: box))
            host.traitOverrides.horizontalSizeClass = .regular
            // Simulate the 89.5 pt vertical toolbar trailing safe area on physical unfolded Duo.
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 89.5)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(100))
            browsing.openPhoto(target.id)

            try await waitFor("\(paneIdentifier) mounted") {
                box.frames[paneIdentifier] != nil && box.frames["clove.duo.capsule"] != nil
            }
            let capsuleFrame = try #require(box.frames["clove.duo.capsule"])
            capsuleFramesByPresentation[presentation] = capsuleFrame

            try await verifyPickers(
                box: box,
                paneIdentifier: paneIdentifier,
                capsuleIdentifier: "clove.duo.capsule",
                ratingButtonIdentifier: "clove.duo.capsule.rating",
                ratingPickerIdentifier: "clove.duo.capsule.stars",
                labelButtonIdentifier: "clove.duo.capsule.label",
                labelPickerIdentifier: "clove.duo.labels",
                expectedDockLeftEdge: window.frame.width - 89.5)
        }

        let previewCapsule = try #require(capsuleFramesByPresentation[.photoPreview])
        let focusCapsule = try #require(capsuleFramesByPresentation[.focus])
        expectSameMarkingCapsuleFrame(previewCapsule, focusCapsule)
    }

    @Test(arguments: [CloveTheme.light, CloveTheme.dark])
    func duoExpandedMarkingCapsuleAlignsAcrossPresentationsAndTracks(theme: CloveTheme)
        async throws
    {
        guard #available(iOS 27.1, *) else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }
        let group = try #require(browsing.groups.first)
        let standalone = try #require(browsing.photos.first { $0.fileName == "MMQ02680.ARW" })
        let lastPhoto = try #require(browsing.photos.last)
        browsing.openPhoto(standalone.id)

        let box = TapPickerTestBox()
        let presentationBox = PresentationStateBox(value: .photoPreview)

        struct LiveDuoHost: View {
            let browsing: BrowsingModel
            let store: SettingsStore
            let theme: CloveTheme
            @Bindable var presentation: PresentationStateBox
            let box: TapPickerTestBox

            var body: some View {
                NavigationStack {
                    DetailScreen(
                        browsing: browsing,
                        duo: DuoDetailLayout(
                            presentation: $presentation.value,
                            filter: AnyView(EmptyView()),
                            more: AnyView(EmptyView()),
                            bottom: AnyView(EmptyView()),
                            showsGrid: true))
                }
                .environment(store)
                .environment(\.cloveTheme, theme)
                .environment(\.colorScheme, theme == .dark ? .dark : .light)
                .environment(\.isDuoExpanded, true)
                .environment(\.usesSystemBrowsingToolbar, true)
                .environment(\.usesVerticalBrowsingToolbar, true)
                .environment(\.hasFoldRegion, true)
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, box.trigger)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    box.frames = frames
                }
            }
        }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
        let host = UIHostingController(
            rootView: LiveDuoHost(
                browsing: browsing, store: store, theme: theme, presentation: presentationBox,
                box: box))
        host.traitOverrides.horizontalSizeClass = .regular
        host.overrideUserInterfaceStyle = theme == .dark ? .dark : .light
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 89.5)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let dockLeftEdge = window.frame.width - 89.5

        // 1. Start in Photo Preview.
        try await waitFor("initial Photo Preview mounted (\(theme.rawValue))") {
            box.frames["clove.duo.photoPreview"] != nil
                && box.frames["clove.duo.capsule"] != nil
        }
        try await Task.sleep(for: .milliseconds(100))
        let previewPane = try #require(box.frames["clove.duo.photoPreview"])
        let initialPreviewCapsule = try #require(box.frames["clove.duo.capsule"])
        let previewStageInPreview = try #require(findZoomPreview(in: window))
        let previewStageFrameInPreview = previewStageInPreview.convert(
            previewStageInPreview.bounds, to: window)
        #expect(abs(initialPreviewCapsule.width - 168) <= 0.5)
        #expect(abs(initialPreviewCapsule.height - 48) <= 0.5)
        #expect(
            abs((previewStageFrameInPreview.maxX - 16) - initialPreviewCapsule.maxX) <= 0.5,
            Comment(
                rawValue:
                    "previewStage=\(previewStageFrameInPreview) previewPane=\(previewPane) capsule=\(initialPreviewCapsule)"
            ))
        #expect(initialPreviewCapsule.maxX <= previewPane.maxX - 16 + 0.5)
        #expect(initialPreviewCapsule.maxX <= dockLeftEdge - 16 + 0.5)
        #expect(initialPreviewCapsule.minY >= previewStageFrameInPreview.maxY - 0.5)
        try await verifyPickers(
            box: box,
            paneIdentifier: "clove.duo.photoPreview",
            capsuleIdentifier: "clove.duo.capsule",
            ratingButtonIdentifier: "clove.duo.capsule.rating",
            ratingPickerIdentifier: "clove.duo.capsule.stars",
            labelButtonIdentifier: "clove.duo.capsule.label",
            labelPickerIdentifier: "clove.duo.labels",
            expectedDockLeftEdge: dockLeftEdge)

        // 2. Switch dynamically to Focus View (Timeline).
        presentationBox.value = .focus
        try await waitFor("Focus View Timeline mounted (\(theme.rawValue))") {
            box.frames["clove.duo.focus"] != nil
                && box.frames["clove.duo.capsule"] != nil
                && box.frames["clove.detail.filmstrip"] != nil
                && box.frames["clove.detail.filmstrip.timeline"] != nil
        }
        try await Task.sleep(for: .milliseconds(150))
        let focusPane = try #require(box.frames["clove.duo.focus"])
        let focusTimelineCapsule = try #require(box.frames["clove.duo.capsule"])
        let filmstripFrame = try #require(box.frames["clove.detail.filmstrip"])
        let timelineTrackFrame = try #require(box.frames["clove.detail.filmstrip.timeline"])
        let focusStage = try #require(findZoomPreview(in: window))
        let focusStageFrame = focusStage.convert(focusStage.bounds, to: window)
        expectSameMarkingCapsuleFrame(initialPreviewCapsule, focusTimelineCapsule)
        #expect(abs(focusTimelineCapsule.midY - filmstripFrame.midY) <= 1.0)
        #expect(abs(focusTimelineCapsule.midY - timelineTrackFrame.midY) <= 1.0)
        #expect(filmstripFrame.maxX <= focusTimelineCapsule.minX)
        #expect(abs((focusTimelineCapsule.minX - filmstripFrame.maxX) - 6) <= 1.0)
        #expect(
            abs((focusStageFrame.maxX - 16) - focusTimelineCapsule.maxX) <= 0.5,
            Comment(
                rawValue:
                    "focusStage=\(focusStageFrame) focusPane=\(focusPane) capsule=\(focusTimelineCapsule)"
            ))
        #expect(focusTimelineCapsule.maxX <= focusPane.maxX - 16 + 0.5)
        #expect(focusTimelineCapsule.minY >= focusStageFrame.maxY - 0.5)
        try await verifyPickers(
            box: box,
            paneIdentifier: "clove.duo.focus",
            capsuleIdentifier: "clove.duo.capsule",
            ratingButtonIdentifier: "clove.duo.capsule.rating",
            ratingPickerIdentifier: "clove.duo.capsule.stars",
            labelButtonIdentifier: "clove.duo.capsule.label",
            labelPickerIdentifier: "clove.duo.labels",
            expectedDockLeftEdge: dockLeftEdge)

        // Scroll Timeline to the last photo and ensure the trailing reservation stays single/clear.
        browsing.openPhoto(lastPhoto.id)
        try await waitFor("timeline scrolled to last photo (\(theme.rawValue))") {
            guard let strip = box.frames["clove.detail.filmstrip"],
                let track = box.frames["clove.detail.filmstrip.timeline"],
                let capsule = box.frames["clove.duo.capsule"]
            else { return false }
            return abs((strip.maxX - track.maxX) - 10) <= 1.5
                && strip.maxX <= capsule.minX
        }
        let filmstripAtEnd = try #require(box.frames["clove.detail.filmstrip"])
        let timelineAtEnd = try #require(box.frames["clove.detail.filmstrip.timeline"])
        let capsuleAtEnd = try #require(box.frames["clove.duo.capsule"])
        expectSameMarkingCapsuleFrame(initialPreviewCapsule, capsuleAtEnd)
        #expect(filmstripAtEnd.maxX <= capsuleAtEnd.minX)
        #expect(timelineAtEnd.maxX <= capsuleAtEnd.minX)
        #expect(abs((filmstripAtEnd.maxX - timelineAtEnd.maxX) - 10) <= 1.5)

        // Chrome toggle hides both filmstrip and capsule, then restores the same capsule frame.
        focusStage.onChromeToggle?()
        try await waitFor("chrome toggle hides capsule and filmstrip (\(theme.rawValue))") {
            box.frames["clove.duo.capsule"] == nil
                && box.frames["clove.detail.filmstrip"] == nil
        }
        focusStage.onChromeToggle?()
        try await waitFor("chrome toggle restores capsule and filmstrip (\(theme.rawValue))") {
            box.frames["clove.duo.capsule"] != nil
                && box.frames["clove.detail.filmstrip"] != nil
        }
        try await Task.sleep(for: .milliseconds(100))
        let restoredCapsule = try #require(box.frames["clove.duo.capsule"])
        expectSameMarkingCapsuleFrame(initialPreviewCapsule, restoredCapsule)

        // 3. Enter Group Focus inside Focus View and verify tray & fold cap centering/clearance.
        browsing.openGroup(group.id, on: group.members[0])
        try await waitFor("Focus View Group Focus mounted (\(theme.rawValue))") {
            box.frames["clove.detail.filmstrip.expandedGroup"] != nil
                && box.frames["clove.detail.filmstrip.group.fold"] != nil
        }
        try await Task.sleep(for: .milliseconds(250))
        let groupCapsule = try #require(box.frames["clove.duo.capsule"])
        let groupTrayFrame = try #require(box.frames["clove.detail.filmstrip.expandedGroup"])
        let foldCapFrame = try #require(box.frames["clove.detail.filmstrip.group.fold"])
        let groupFilmstripFrame = try #require(box.frames["clove.detail.filmstrip"])
        expectSameMarkingCapsuleFrame(initialPreviewCapsule, groupCapsule)
        #expect(abs(groupCapsule.midY - groupTrayFrame.midY) <= 1.0)
        #expect(abs((groupTrayFrame.maxY - 3) - foldCapFrame.maxY) <= 1.0)
        #expect(foldCapFrame.minY >= groupTrayFrame.minY - 0.5)
        #expect(abs(groupCapsule.midY - groupFilmstripFrame.midY) <= 1.0)
        #expect(groupFilmstripFrame.maxX <= groupCapsule.minX)
        #expect(groupTrayFrame.maxX <= groupCapsule.minX)
        #expect(foldCapFrame.maxX <= groupCapsule.minX)

        // 4. Switch dynamically back to Photo Preview.
        presentationBox.value = .photoPreview
        try await waitFor("returned to Photo Preview (\(theme.rawValue))") {
            box.frames["clove.duo.photoPreview"] != nil
                && box.frames["clove.duo.focus"] == nil
                && box.frames["clove.duo.capsule"] != nil
        }
        try await Task.sleep(for: .milliseconds(150))
        let returnedPreviewCapsule = try #require(box.frames["clove.duo.capsule"])
        expectSameMarkingCapsuleFrame(initialPreviewCapsule, returnedPreviewCapsule)
        try await verifyPickers(
            box: box,
            paneIdentifier: "clove.duo.photoPreview",
            capsuleIdentifier: "clove.duo.capsule",
            ratingButtonIdentifier: "clove.duo.capsule.rating",
            ratingPickerIdentifier: "clove.duo.capsule.stars",
            labelButtonIdentifier: "clove.duo.capsule.label",
            labelPickerIdentifier: "clove.duo.labels",
            expectedDockLeftEdge: dockLeftEdge)
    }

    @Test func nestedTapPickerContainersIsolateHorizontallyOffsetInnerHost() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let box = TapPickerTestBox()

        struct NestedHost: View {
            let box: TapPickerTestBox

            var body: some View {
                HStack(spacing: 0) {
                    ZStack(alignment: .bottomTrailing) {
                        Color.clear
                        MarkingToolbar(
                            rating: .unrated,
                            label: nil,
                            isRejected: false,
                            identifier: "test.outer",
                            onRate: { _ in },
                            onReject: {},
                            onLabel: { _ in }
                        )
                        .padding(16)
                    }
                    .frame(width: 460, height: 600)

                    ZStack(alignment: .bottomTrailing) {
                        Color.clear
                        MarkingToolbar(
                            rating: .unrated,
                            label: nil,
                            isRejected: false,
                            identifier: "test.inner",
                            onRate: { _ in },
                            onReject: {},
                            onLabel: { _ in }
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }
                    .frame(width: 450.5, height: 600)
                    .horizontalContainerContentMarginsIfAvailable()
                    .tapPickerContainer()
                    .reportTapPickerFrame("test.inner.pane")
                }
                .frame(width: 910.5, height: 600)
                .tapPickerContainer()
                .reportTapPickerFrame("test.outer.pane")
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, box.trigger)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    box.frames = frames
                }
            }
        }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let host = UIHostingController(rootView: NestedHost(box: box))
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 89.5)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("nested host mounted") {
            box.frames["test.inner.pane"] != nil
                && box.frames["test.inner"] != nil
                && box.frames["test.outer.pane"] != nil
                && box.frames["test.outer"] != nil
        }

        let innerPaneFrame = try #require(box.frames["test.inner.pane"])
        let innerCapsuleFrame = try #require(box.frames["test.inner"])
        let outerPaneFrame = try #require(box.frames["test.outer.pane"])
        let outerCapsuleFrame = try #require(box.frames["test.outer"])
        #expect(abs(innerPaneFrame.minX - (outerPaneFrame.minX + 460)) < 2)

        for (buttonID, pickerID) in [
            ("test.inner.rating", "test.inner.stars"),
            ("test.inner.label", "test.inner.labels"),
        ] {
            box.sendTrigger(buttonID)
            try await waitFor("inner picker \(pickerID) visible") {
                box.frames[pickerID] != nil
            }
            let pickerFrame = try #require(box.frames[pickerID])
            #expect(pickerFrame.width > pickerFrame.height)
            #expect(pickerFrame.maxY <= innerCapsuleFrame.minY + 1)
            #expect(pickerFrame.minX >= innerPaneFrame.minX + 12 - 1.5)
            #expect(pickerFrame.maxX <= innerPaneFrame.maxX - 12 + 1.5)
            // Must clamp to 12 pt inside inner pane, not shift left by 460 pt or 89.5 pt.
            #expect(abs((innerPaneFrame.maxX - 12) - pickerFrame.maxX) < 2)
            box.sendTrigger(buttonID)
            try await waitFor("inner picker \(pickerID) dismissed") {
                box.frames[pickerID] == nil
            }
        }

        // Verify outer container still places its own picker within outer pane.
        box.sendTrigger("test.outer.rating")
        try await waitFor("outer picker visible") {
            box.frames["test.outer.stars"] != nil
        }
        let outerPickerFrame = try #require(box.frames["test.outer.stars"])
        #expect(outerPickerFrame.width > outerPickerFrame.height)
        #expect(outerPickerFrame.maxY <= outerCapsuleFrame.minY + 1)
        #expect(outerPickerFrame.minX >= outerPaneFrame.minX + 12 - 1.5)
        #expect(outerPickerFrame.maxX <= outerPaneFrame.maxX - 12 + 1.5)
        box.sendTrigger("test.outer.rating")
        try await waitFor("outer picker dismissed") {
            box.frames["test.outer.stars"] == nil
        }
    }

    @Test func compactDetailAndGridBatchBarPlaceTapPickersInsideSafeBounds() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        // 1. Standard compact Detail.
        do {
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            let target = try #require(browsing.photos.first { $0.fileName == "MMQ02680.ARW" })
            let box = TapPickerTestBox()

            struct HostView: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let box: TapPickerTestBox

                var body: some View {
                    BrowseShell(browsing: browsing)
                        .environment(store)
                        .environment(\.scenePhase, .active)
                        .environment(\.tapPickerTriggerRequest, box.trigger)
                        .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                            box.frames = frames
                        }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            let host = UIHostingController(
                rootView: HostView(browsing: browsing, store: store, box: box))
            host.traitOverrides.horizontalSizeClass = .compact
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(100))
            browsing.openPhoto(target.id)

            try await waitFor("compact detail capsule mounted") {
                box.frames["clove.detail.capsule"] != nil
            }

            let capsuleFrame = try #require(box.frames["clove.detail.capsule"])
            for (buttonID, pickerID) in [
                ("clove.detail.capsule.rating", "clove.detail.capsule.stars"),
                ("clove.detail.capsule.label", "clove.detail.labels"),
            ] {
                box.sendTrigger(buttonID)
                try await waitFor("compact detail picker \(pickerID) visible") {
                    box.frames[pickerID] != nil
                }
                let pickerFrame = try #require(box.frames[pickerID])
                let detailSafeWidth = host.view.safeAreaLayoutGuide.layoutFrame.width - 24
                if detailSafeWidth >= 288 {
                    #expect(pickerFrame.width > pickerFrame.height)
                } else {
                    #expect(pickerFrame.height > pickerFrame.width)
                }
                #expect(pickerFrame.maxY <= capsuleFrame.minY + 1)
                #expect(pickerFrame.minX >= 12 - 1.5)
                #expect(pickerFrame.maxX <= window.frame.width - 12 + 1.5)
                box.sendTrigger(buttonID)
                try await waitFor("compact detail picker \(pickerID) dismissed") {
                    box.frames[pickerID] == nil
                }
            }
        }

        // 2. GridBatchBar in compact GridScreen.
        do {
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            let first = try #require(browsing.photos.first)
            let second = try #require(browsing.photos.dropFirst().first)
            let box = TapPickerTestBox()

            struct HostView: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let box: TapPickerTestBox

                var body: some View {
                    NavigationStack {
                        GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                    }
                    .environment(store)
                    .environment(\.scenePhase, .active)
                    .environment(\.tapPickerTriggerRequest, box.trigger)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                        box.frames = frames
                    }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            let host = UIHostingController(
                rootView: HostView(browsing: browsing, store: store, box: box))
            host.traitOverrides.horizontalSizeClass = .compact
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await Task.sleep(for: .milliseconds(100))
            browsing.toggleSelection(first.id)
            browsing.toggleSelection(second.id)

            try await waitFor("grid batch bar mounted") {
                box.frames["clove.grid.batch"] != nil
            }
            // Allow the batch bar's 220 ms chrome slide-in transition to settle before measuring.
            try await Task.sleep(for: .milliseconds(300))

            let batchFrame = try #require(box.frames["clove.grid.batch"])
            for (buttonID, pickerID) in [
                ("clove.grid.batch.rating", "clove.grid.batch.stars"),
                ("clove.grid.batch.label", "clove.grid.batch.labels"),
            ] {
                box.sendTrigger(buttonID)
                try await waitFor("batch picker \(pickerID) visible") {
                    box.frames[pickerID] != nil
                }
                let pickerFrame = try #require(box.frames[pickerID])
                let batchSafeWidth = host.view.safeAreaLayoutGuide.layoutFrame.width - 24
                if batchSafeWidth >= 288 {
                    #expect(pickerFrame.width > pickerFrame.height)
                } else {
                    #expect(pickerFrame.height > pickerFrame.width)
                }
                #expect(pickerFrame.maxY <= batchFrame.minY + 1)
                #expect(pickerFrame.minX >= 12 - 1.5)
                #expect(pickerFrame.maxX <= window.frame.width - 12 + 1.5)
                box.sendTrigger(buttonID)
                try await waitFor("batch picker \(pickerID) dismissed") {
                    box.frames[pickerID] == nil
                }
            }
        }
    }

    @Test func gridBatchBarFitsNarrowWidthsAcrossLanguagesAndRespectsDisabledEligibility()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        for language in [
            ResolvedAppLanguage.english, .simplifiedChinese, .traditionalChinese,
        ] {
            let library = TestLibrary.sample()
            let browsing = BrowsingModel(library: library)
            browsing.openFolder()
            let box = TapPickerTestBox()

            struct HostView: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let language: ResolvedAppLanguage
                let box: TapPickerTestBox

                var body: some View {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        GridBatchBar(
                            browsing: browsing,
                            cells: GridDisplay(
                                photos: browsing.photos, groups: browsing.groups,
                                groupsEnabled: true
                            ).cells
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tapPickerContainer()
                    .environment(store)
                    .environment(\.appLanguage, language)
                    .environment(\.scenePhase, .active)
                    .environment(\.tapPickerTriggerRequest, box.trigger)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                        box.frames = frames
                    }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
            let host = UIHostingController(
                rootView: HostView(
                    browsing: browsing, store: store, language: language, box: box))
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("narrow grid batch bar mounted (\(language.rawValue))") {
                box.frames["clove.grid.batch"] != nil
                    && box.frames["clove.grid.batch.actions"] != nil
            }

            let bar = try #require(box.frames["clove.grid.batch"])
            let reject = try #require(box.frames["clove.grid.batch.reject"])
            let rating = try #require(box.frames["clove.grid.batch.rating"])
            let label = try #require(box.frames["clove.grid.batch.label"])
            let actions = try #require(box.frames["clove.grid.batch.actions"])

            #expect(abs(bar.height - 48) < 1)
            #expect(bar.minX >= 16 - 1.5)
            #expect(bar.maxX <= 320 - 16 + 1.5)
            #expect((52...56).contains(reject.width))
            #expect((52...56).contains(rating.width))
            #expect((52...56).contains(label.width))
            #expect(actions.width >= 44)
            #expect(abs(actions.height - 48) < 1)
            #expect(actions.minX >= label.maxX - 0.5)

            // With zero targets selected, the bar remains visible and rating trigger does not open.
            #expect(browsing.batchTargets.isEmpty)
            box.sendTrigger("clove.grid.batch.rating")
            try await Task.sleep(for: .milliseconds(120))
            #expect(box.frames["clove.grid.batch.stars"] == nil)

            // Selecting a photo enables triggers and opens picker cleanly above the bar.
            let first = try #require(browsing.photos.first)
            browsing.toggleSelection(first.id)
            try await Task.sleep(for: .milliseconds(60))
            box.sendTrigger("clove.grid.batch.rating")
            try await waitFor("stars picker opens when batch targets exist") {
                box.frames["clove.grid.batch.stars"] != nil
            }
            box.sendTrigger("clove.grid.batch.rating")
            try await waitFor("stars picker closes") {
                box.frames["clove.grid.batch.stars"] == nil
            }

            // Losing mark permission disables picker triggers while keeping the bar visible.
            library.reportLocationLoss(.externalVolumeDisconnected)
            try await waitFor("location loss disables marking") {
                !browsing.canMark
            }
            box.sendTrigger("clove.grid.batch.rating")
            try await Task.sleep(for: .milliseconds(120))
            #expect(box.frames["clove.grid.batch.stars"] == nil)
            #expect(box.frames["clove.grid.batch"] != nil)
        }
    }

    @Test func gridBatchBarStaysHiddenOnDuoDetailAndContainmentHoldsInPadSplit() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        // 1. Duo expanded Detail hides the grid selection toolbar while keeping selection intact.
        if #available(iOS 27.1, *) {
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            let first = try #require(browsing.photos.first)
            browsing.toggleSelection(first.id)
            let box = TapPickerTestBox()

            struct DuoHost: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let box: TapPickerTestBox

                var body: some View {
                    NavigationStack {
                        GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                    }
                    .environment(store)
                    .environment(\.isDuoExpanded, true)
                    .environment(\.usesSystemBrowsingToolbar, true)
                    .environment(\.usesVerticalBrowsingToolbar, true)
                    .environment(\.hasFoldRegion, true)
                    .environment(\.scenePhase, .active)
                    .environment(\.tapPickerTriggerRequest, box.trigger)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                        box.frames = frames
                    }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
            let host = UIHostingController(
                rootView: DuoHost(browsing: browsing, store: store, box: box))
            host.traitOverrides.horizontalSizeClass = .regular
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 89.5)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("duo grid batch bar mounted") {
                box.frames["clove.grid.batch"] != nil
            }
            browsing.openPhoto(first.id)
            try await waitFor("duo detail capsule mounted and grid batch hidden") {
                box.frames["clove.duo.capsule"] != nil && box.frames["clove.grid.batch"] == nil
            }
            browsing.back()
            try await waitFor("duo grid batch bar returns after Back") {
                box.frames["clove.grid.batch"] != nil
            }
        }

        // 2. iPad split detail column contains GridBatchBar and its pickers without sidebar overlap.
        do {
            let browsing = BrowsingModel(library: TestLibrary.sample())
            browsing.openFolder()
            let first = try #require(browsing.photos.first)
            browsing.toggleSelection(first.id)
            let box = TapPickerTestBox()

            struct PadHost: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let box: TapPickerTestBox

                var body: some View {
                    BrowseShell(browsing: browsing)
                        .environment(store)
                        .environment(\.cloveUserInterfaceIdiom, .pad)
                        .environment(\.scenePhase, .active)
                        .environment(\.tapPickerTriggerRequest, box.trigger)
                        .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                            box.frames = frames
                        }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            let host = UIHostingController(
                rootView: PadHost(browsing: browsing, store: store, box: box))
            host.traitOverrides.horizontalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("ipad split batch bar mounted") {
                box.frames["clove.grid.batch"] != nil
            }
            try await Task.sleep(for: .milliseconds(300))
            let batchFrame = try #require(box.frames["clove.grid.batch"])
            #expect(batchFrame.minX >= 220)
            #expect(batchFrame.maxX <= 1024 - 16 + 1.5)

            box.sendTrigger("clove.grid.batch.rating")
            try await waitFor("ipad split batch picker visible") {
                box.frames["clove.grid.batch.stars"] != nil
            }
            let pickerFrame = try #require(box.frames["clove.grid.batch.stars"])
            #expect(pickerFrame.maxY <= batchFrame.minY + 1)
            #expect(pickerFrame.minX >= 220)
            #expect(pickerFrame.maxX <= 1024 - 12 + 1.5)
        }
    }

    @Test func outsideTapDismisserAndSafeAreasDoNotShiftPickerFrame() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let box = TapPickerTestBox()

        struct SafeAreaHost: View {
            let box: TapPickerTestBox

            var body: some View {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        MarkingToolbar(
                            rating: .unrated,
                            label: nil,
                            isRejected: false,
                            identifier: "test.safe",
                            onRate: { _ in },
                            onReject: {},
                            onLabel: { _ in }
                        )
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.clear.ignoresSafeArea())
                .tapPickerContainer()
                .reportTapPickerFrame("test.safe.pane")
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, box.trigger)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    box.frames = frames
                }
            }
        }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 703.5)
        let host = UIHostingController(rootView: SafeAreaHost(box: box))
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 20, bottom: 34, right: 89.5)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("safe-area host mounted") {
            box.frames["test.safe.pane"] != nil && box.frames["test.safe"] != nil
        }

        let paneFrame = try #require(box.frames["test.safe.pane"])
        let capsuleFrame = try #require(box.frames["test.safe"])

        for (buttonID, pickerID) in [
            ("test.safe.rating", "test.safe.stars"),
            ("test.safe.label", "test.safe.labels"),
        ] {
            box.sendTrigger(buttonID)
            try await waitFor("safe-area picker \(pickerID) visible") {
                box.frames[pickerID] != nil
            }
            let pickerFrame = try #require(box.frames[pickerID])
            #expect(pickerFrame.width > pickerFrame.height)
            #expect(abs((capsuleFrame.minY - 10) - pickerFrame.maxY) < 2)
            #expect(abs((paneFrame.maxX - 12) - pickerFrame.maxX) < 2)
            box.sendTrigger(buttonID)
            try await waitFor("safe-area picker \(pickerID) dismissed") {
                box.frames[pickerID] == nil
            }
        }
    }

    // MARK: - Behavioral rules

    @Test func clearRatingKeepsLabelAndClearsRejectWhileClearLabelKeepsStars() {
        let rules = MarkingInputRules()
        let ratedAndLabeled = PhotoMarks(
            rating: Rating(rawValue: 4) ?? .unrated,
            label: ColourLabel(colour: .blue))

        if case .mark(let clearRating, _) = rules.result(
            forRating: .unrated, marks: ratedAndLabeled)
        {
            let updated = ratedAndLabeled.applying(clearRating)
            #expect(updated.rating == .unrated)
            #expect(updated.label == ColourLabel(colour: .blue))
        } else {
            Issue.record("Expected Clear rating to produce a mark")
        }

        if case .mark(let clearLabel, _) = rules.result(forLabel: .clear, marks: ratedAndLabeled) {
            let updated = ratedAndLabeled.applying(clearLabel)
            #expect(updated.rating == (Rating(rawValue: 4) ?? .unrated))
            #expect(updated.label == .clear)
        } else {
            Issue.record("Expected Clear label to produce a mark")
        }

        let rejectedAndLabeled = PhotoMarks(
            rating: .rejected,
            label: ColourLabel(colour: .green))
        if case .mark(let clearReject, _) = rules.result(
            forRating: .unrated, marks: rejectedAndLabeled)
        {
            let updated = rejectedAndLabeled.applying(clearReject)
            #expect(updated.rating == .unrated)
            #expect(!updated.isRejected)
            #expect(updated.label == ColourLabel(colour: .green))
        } else {
            Issue.record("Expected Clear rating to clear Reject without touching label")
        }
    }

    @Test func enabledRatingsGateNewMarksButStillAllowClearingCurrentOrZero() {
        let oddRatings =
            EnabledRatings(
                EnabledRatings.all.levels.enumerated()
                    .filter { $0.offset.isMultiple(of: 2) }
                    .map(\.element)
            ) ?? .all
        var settings = AppSettings()
        settings.enabledRatings = oddRatings
        let rules = MarkingInputRules(settings: settings)
        let externalFourStars = PhotoMarks(rating: Rating(rawValue: 4) ?? .unrated)

        // Disabled level 2 does nothing.
        #expect(
            rules.result(forRating: Rating(rawValue: 2) ?? .unrated, marks: externalFourStars)
                == .noChange)

        // Tapping Clear (0) clears an externally applied disabled rating cleanly.
        if case .mark(let change, _) = rules.result(
            for: .rating(.unrated), marks: externalFourStars)
        {
            #expect(externalFourStars.applying(change).rating == .unrated)
        } else {
            Issue.record("Expected explicit 0 to clear externally applied disabled rating")
        }
    }

    @Test func batchSetOnlyAppliesSelectedValueAndMixedClearTouchesOnlyMarkedPhotos() {
        let folder = FolderIdentity(rawValue: "test")
        let p1 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "A"),
            fileName: "A.ARW",
            time: .unavailable,
            marks: PhotoMarks(
                rating: Rating(rawValue: 3) ?? .unrated, label: ColourLabel(colour: .red)))
        let p2 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "B"),
            fileName: "B.ARW",
            time: .unavailable,
            marks: PhotoMarks(rating: Rating(rawValue: 5) ?? .unrated, label: .clear))

        // Setting 3 stars on mixed [3, 5] only updates p2 (never toggles p1 off).
        let ratePlan = BatchMarkPlan(
            action: .rating(Rating(rawValue: 3) ?? .unrated), photos: [p1, p2])
        #expect(ratePlan.photos == [p2.id])

        // Clearing labels on mixed [Red, Clear] only writes to p1 and keeps p1's 3-star rating.
        let clearLabelPlan = BatchMarkPlan(action: .label(.clear), photos: [p1, p2])
        #expect(clearLabelPlan.photos == [p1.id])
        #expect(clearLabelPlan.items.first?.change == MarkChange(label: .clear))

        // Clearing ratings on mixed [3, 5] writes .unrated to both while keeping labels untouched.
        let clearRatingPlan = BatchMarkPlan(action: .rating(.unrated), photos: [p1, p2])
        #expect(clearRatingPlan.photos == [p1.id, p2.id])
    }

    // MARK: - Helpers

    private func verifyPickers(
        box: TapPickerTestBox,
        paneIdentifier: String,
        capsuleIdentifier: String,
        ratingButtonIdentifier: String,
        ratingPickerIdentifier: String,
        labelButtonIdentifier: String,
        labelPickerIdentifier: String,
        expectedDockLeftEdge: CGFloat
    ) async throws {
        let paneFrame = try #require(box.frames[paneIdentifier])
        let capsuleFrame = try #require(box.frames[capsuleIdentifier])
        #expect(paneFrame.maxX <= expectedDockLeftEdge + 1.5)

        for (buttonID, pickerID) in [
            (ratingButtonIdentifier, ratingPickerIdentifier),
            (labelButtonIdentifier, labelPickerIdentifier),
        ] {
            box.sendTrigger(buttonID)
            try await waitFor("picker \(pickerID) visible") {
                box.frames[pickerID] != nil
            }
            let pickerFrame = try #require(box.frames[pickerID])
            #expect(pickerFrame.width > pickerFrame.height)
            #expect(pickerFrame.maxY <= capsuleFrame.minY + 1)
            #expect(pickerFrame.minX >= paneFrame.minX + 12 - 1.5)
            #expect(pickerFrame.maxX <= paneFrame.maxX - 12 + 1.5)
            #expect(pickerFrame.maxX <= expectedDockLeftEdge - 12 + 1.5)
            // Verify picker clamps to 12 pt inside pane's right edge rather than double-subtracting.
            #expect(abs((paneFrame.maxX - 12) - pickerFrame.maxX) < 2)
            box.sendTrigger(buttonID)
            try await waitFor("picker \(pickerID) dismissed") {
                box.frames[pickerID] == nil
            }
        }
    }

    private func expectSameMarkingCapsuleFrame(
        _ first: CGRect,
        _ second: CGRect,
        tolerance: CGFloat = 0.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(first.minX - second.minX) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(first.maxX - second.maxX) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(first.minY - second.minY) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(first.midY - second.midY) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(first.maxY - second.maxY) <= tolerance, sourceLocation: sourceLocation)
    }

    private func findZoomPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let preview = findZoomPreview(in: child) { return preview }
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
private final class PresentationStateBox {
    var value: DetailPresentation

    init(value: DetailPresentation) {
        self.value = value
    }
}

@MainActor
@Observable
private final class TapPickerTestBox {
    var frames: [String: CGRect] = [:]
    var trigger: TapPickerTriggerRequest?
    private var nonce = 0

    func sendTrigger(_ id: String) {
        nonce += 1
        trigger = TapPickerTriggerRequest(id: id, nonce: nonce)
    }
}

private extension View {
    @ViewBuilder
    func horizontalContainerContentMarginsIfAvailable() -> some View {
        if #available(iOS 27.1, *) {
            contentMargins(for: .container, edges: .horizontal)
        } else {
            self
        }
    }
}
