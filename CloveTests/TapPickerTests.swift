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
        #expect(LabelPicker.targetExtent == 44)
        #expect(LabelPicker.dotExtent == 16)
        #expect(LabelPicker.selectionRingExtent == 24)
        #expect(LabelPicker.selectionRingLineWidth == 2)
    }

    @Test func labelPickerDraws16PtDotsAnd24PtSelectionRingsInside44PtTargets() throws {
        let theme = CloveTheme.light
        let expectedGreen = try renderedColourPixel(Color.clove.label.green, theme: theme)
        let expectedRed = try renderedColourPixel(Color.clove.label.red, theme: theme)
        let expectedRing = try renderedColourPixel(Color.clove.text.primary, theme: theme)

        for axis in [Axis.horizontal, Axis.vertical] {
            let picker = LabelPicker(selection: .green, onPick: { _ in }, axis: axis)
                .environment(\.cloveTheme, theme)
            let expectedSize = LabelPicker.preferredSize(for: axis, count: 6)
            let host = UIHostingController(rootView: picker)
            host.safeAreaRegions = []
            #expect(host.sizeThatFits(in: CGSize(width: 500, height: 500)) == expectedSize)

            let renderer = ImageRenderer(content: picker)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(expectedSize.width * 2))
            #expect(image.height == Int(expectedSize.height * 2))
            let pixels = try rgbaPixels(from: image)

            let step = LabelPicker.targetExtent + LabelPicker.itemSpacing
            let halfTarget = LabelPicker.containerPadding + LabelPicker.targetExtent / 2

            func slotCenter(index: Int) -> CGPoint {
                let major = halfTarget + CGFloat(index) * step
                return axis == .horizontal
                    ? CGPoint(x: major, y: halfTarget)
                    : CGPoint(x: halfTarget, y: major)
            }

            // Index 1 is `.red` (unselected): sample glass background outside the 16 pt dot.
            let redCenter = slotCenter(index: 1)
            let rx = Int((redCenter.x * 2).rounded())
            let ry = Int((redCenter.y * 2).rounded())
            let glassBackground = pixels.pixel(x: rx + 28, y: ry)

            // Index 3 is `.green` (0: None, 1: Red, 2: Yellow, 3: Green).
            let greenCenter = slotCenter(index: 3)
            let cx = Int((greenCenter.x * 2).rounded())
            let cy = Int((greenCenter.y * 2).rounded())

            // Inside 16 pt dot (radius <= 7 pt = 14 px): filled green.
            #expect(colorsClose(pixels.pixel(x: cx, y: cy), expectedGreen))
            #expect(colorsClose(pixels.pixel(x: cx + 12, y: cy), expectedGreen))
            // 9 pt from center (18 px): clear gap between 16 pt dot and 24 pt ring (inner edge 10 pt).
            #expect(colorsClose(pixels.pixel(x: cx + 18, y: cy), glassBackground))
            // 11 pt from center (22 px): 2 pt selection ring at 24 pt outer diameter (10..12 pt).
            #expect(colorsClose(pixels.pixel(x: cx + 22, y: cy), expectedRing))
            // 14 pt from center (28 px): outside 24 pt ring (the old 34 pt ring was at 15..17 pt).
            #expect(colorsClose(pixels.pixel(x: cx + 28, y: cy), glassBackground))

            // Index 1 `.red` (unselected): 16 pt fill with no selection ring at 11 pt.
            #expect(colorsClose(pixels.pixel(x: rx, y: ry), expectedRed))
            #expect(colorsClose(pixels.pixel(x: rx + 12, y: ry), expectedRed))
            #expect(colorsClose(pixels.pixel(x: rx + 18, y: ry), glassBackground))
            #expect(colorsClose(pixels.pixel(x: rx + 22, y: ry), glassBackground))

            // Index 0 is None (`circle.slash`): unselected here, so no ring at 11 pt and non-empty
            // glyph pixels inside the 16 pt area.
            let noneCenter = slotCenter(index: 0)
            let nx = Int((noneCenter.x * 2).rounded())
            let ny = Int((noneCenter.y * 2).rounded())
            #expect(colorsClose(pixels.pixel(x: nx + 22, y: ny), glassBackground))
            var hasNoneGlyphPixels = false
            for dy in -18...18 {
                for dx in -18...18
                where !colorsClose(pixels.pixel(x: nx + dx, y: ny + dy), glassBackground) {
                    hasNoneGlyphPixels = true
                }
            }
            #expect(hasNoneGlyphPixels)
            // Verify `circle.slash` clears the inner edge of the 24 pt ring (radius 10 pt = 20 px).
            #expect(colorsClose(pixels.pixel(x: nx + 19, y: ny), glassBackground))
            #expect(colorsClose(pixels.pixel(x: nx, y: ny + 19), glassBackground))
        }

        // Selected None (`selection == nil`) shows the 24 pt ring around `circle.slash` without
        // overlapping the ring; mixed shows no ring on any slot.
        let noneSelectedRenderer = ImageRenderer(
            content: LabelPicker(selection: nil) { _ in }.environment(\.cloveTheme, theme))
        noneSelectedRenderer.scale = 2
        let noneSelectedPixels = try rgbaPixels(from: try #require(noneSelectedRenderer.cgImage))
        let noneCenterPx = Int(
            ((LabelPicker.containerPadding + LabelPicker.targetExtent / 2) * 2).rounded())
        let noneGlass = noneSelectedPixels.pixel(x: noneCenterPx + 28, y: noneCenterPx)
        #expect(
            colorsClose(
                noneSelectedPixels.pixel(x: noneCenterPx + 22, y: noneCenterPx), expectedRing))
        #expect(!colorsClose(noneGlass, expectedRing))

        let mixedRenderer = ImageRenderer(
            content: LabelPicker(selection: nil, isMixed: true) { _ in }
                .environment(\.cloveTheme, theme))
        mixedRenderer.scale = 2
        let mixedPixels = try rgbaPixels(from: try #require(mixedRenderer.cgImage))
        let mixedGlass = mixedPixels.pixel(x: noneCenterPx + 28, y: noneCenterPx)
        #expect(colorsClose(mixedPixels.pixel(x: noneCenterPx + 22, y: noneCenterPx), mixedGlass))
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
        let presentationBox = PresentationStateBox(value: .focus)

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

        // 1. Start in Focus View (Timeline, the default expanded Duo presentation).
        try await waitFor("initial Focus View Timeline mounted (\(theme.rawValue))") {
            box.frames["clove.duo.focus"] != nil
                && box.frames["clove.duo.capsule"] != nil
                && box.frames["clove.detail.filmstrip"] != nil
                && box.frames["clove.detail.filmstrip.timeline"] != nil
        }
        try await Task.sleep(for: .milliseconds(150))
        let focusPane = try #require(box.frames["clove.duo.focus"])
        let initialFocusCapsule = try #require(box.frames["clove.duo.capsule"])
        let filmstripFrame = try #require(box.frames["clove.detail.filmstrip"])
        let timelineTrackFrame = try #require(box.frames["clove.detail.filmstrip.timeline"])
        let focusStage = try #require(findZoomPreview(in: window))
        let focusStageFrame = focusStage.convert(focusStage.bounds, to: window)
        #expect(abs(initialFocusCapsule.width - 168) <= 0.5)
        #expect(abs(initialFocusCapsule.height - 48) <= 0.5)
        #expect(abs(initialFocusCapsule.midY - filmstripFrame.midY) <= 1.0)
        #expect(abs(initialFocusCapsule.midY - timelineTrackFrame.midY) <= 1.0)
        #expect(filmstripFrame.maxX <= initialFocusCapsule.minX)
        #expect(abs((initialFocusCapsule.minX - filmstripFrame.maxX) - 6) <= 1.0)
        #expect(
            abs((focusStageFrame.maxX - 16) - initialFocusCapsule.maxX) <= 0.5,
            Comment(
                rawValue:
                    "focusStage=\(focusStageFrame) focusPane=\(focusPane) capsule=\(initialFocusCapsule)"
            ))
        #expect(initialFocusCapsule.maxX <= focusPane.maxX - 16 + 0.5)
        #expect(initialFocusCapsule.maxX <= dockLeftEdge - 16 + 0.5)
        #expect(initialFocusCapsule.minY >= focusStageFrame.maxY - 0.5)
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
        expectSameMarkingCapsuleFrame(initialFocusCapsule, capsuleAtEnd)
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
        expectSameMarkingCapsuleFrame(initialFocusCapsule, restoredCapsule)

        // 2. Enter Group Focus inside Focus View and verify tray & fold cap centering/clearance.
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
        expectSameMarkingCapsuleFrame(initialFocusCapsule, groupCapsule)
        #expect(box.frames["clove.detail.filmstrip.group.gridPicker"] == nil)
        #expect(
            abs(foldCapFrame.width - DetailFilmstrip.Metrics.standard.groupActionButtonSize) <= 0.5)
        #expect(
            abs(foldCapFrame.height - DetailFilmstrip.Metrics.standard.groupActionButtonSize) <= 0.5
        )
        #expect(abs(groupCapsule.midY - groupTrayFrame.midY) <= 1.0)
        #expect(
            abs(
                (groupTrayFrame.maxY - DetailFilmstrip.Metrics.standard.thumbnailHeight / 2)
                    - foldCapFrame.midY) <= 1.0)
        #expect(foldCapFrame.minY >= groupTrayFrame.minY - 0.5)
        #expect(foldCapFrame.maxY <= groupTrayFrame.maxY + 0.5)
        #expect(abs(groupCapsule.midY - groupFilmstripFrame.midY) <= 1.0)
        #expect(groupFilmstripFrame.maxX <= groupCapsule.minX)
        #expect(groupTrayFrame.maxX <= groupCapsule.minX)
        #expect(foldCapFrame.maxX <= groupCapsule.minX)

        // 3. Switch dynamically to Photo Preview and verify identical capsule alignment & pickers.
        presentationBox.value = .photoPreview
        try await waitFor("Photo Preview mounted (\(theme.rawValue))") {
            box.frames["clove.duo.photoPreview"] != nil
                && box.frames["clove.duo.focus"] == nil
                && box.frames["clove.duo.capsule"] != nil
                && box.frames["clove.detail.filmstrip"] == nil
        }
        try await Task.sleep(for: .milliseconds(150))
        let previewPane = try #require(box.frames["clove.duo.photoPreview"])
        let previewCapsule = try #require(box.frames["clove.duo.capsule"])
        let previewStage = try #require(findZoomPreview(in: window))
        let previewStageFrame = previewStage.convert(previewStage.bounds, to: window)
        expectSameMarkingCapsuleFrame(initialFocusCapsule, previewCapsule)
        #expect(
            abs((previewStageFrame.maxX - 16) - previewCapsule.maxX) <= 0.5,
            Comment(
                rawValue:
                    "previewStage=\(previewStageFrame) previewPane=\(previewPane) capsule=\(previewCapsule)"
            ))
        #expect(previewCapsule.maxX <= previewPane.maxX - 16 + 0.5)
        #expect(previewCapsule.maxX <= dockLeftEdge - 16 + 0.5)
        #expect(previewCapsule.minY >= previewStageFrame.maxY - 0.5)
        try await verifyPickers(
            box: box,
            paneIdentifier: "clove.duo.photoPreview",
            capsuleIdentifier: "clove.duo.capsule",
            ratingButtonIdentifier: "clove.duo.capsule.rating",
            ratingPickerIdentifier: "clove.duo.capsule.stars",
            labelButtonIdentifier: "clove.duo.capsule.label",
            labelPickerIdentifier: "clove.duo.labels",
            expectedDockLeftEdge: dockLeftEdge)

        // 4. Switch dynamically back to Focus View.
        presentationBox.value = .focus
        try await waitFor("returned to Focus View (\(theme.rawValue))") {
            box.frames["clove.duo.focus"] != nil
                && box.frames["clove.duo.photoPreview"] == nil
                && box.frames["clove.duo.capsule"] != nil
                && box.frames["clove.detail.filmstrip.expandedGroup"] != nil
        }
        try await Task.sleep(for: .milliseconds(150))
        let returnedFocusCapsule = try #require(box.frames["clove.duo.capsule"])
        expectSameMarkingCapsuleFrame(initialFocusCapsule, returnedFocusCapsule)
        try await verifyPickers(
            box: box,
            paneIdentifier: "clove.duo.focus",
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
                    && box.frames["clove.grid.batch.bar"] != nil
                    && box.frames["clove.grid.batch.actions"] != nil
            }

            let bar = try #require(box.frames["clove.grid.batch"])
            let markingCapsule = try #require(box.frames["clove.grid.batch.bar"])
            let reject = try #require(box.frames["clove.grid.batch.reject"])
            let rating = try #require(box.frames["clove.grid.batch.rating"])
            let label = try #require(box.frames["clove.grid.batch.label"])
            let actions = try #require(box.frames["clove.grid.batch.actions"])

            #expect(abs(bar.height - 48) < 1)
            #expect(abs(markingCapsule.width - 168) < 1)
            #expect(abs(markingCapsule.height - 48) < 1)
            #expect(bar.minX >= 16 - 1.5)
            #expect(bar.maxX <= 320 - 16 + 1.5)
            #expect((52...56).contains(reject.width))
            #expect((52...56).contains(rating.width))
            #expect((52...56).contains(label.width))
            #expect(abs(actions.width - 110) < 1)
            #expect(abs(actions.height - 48) < 1)
            #expect(abs(actions.minX - markingCapsule.maxX - 8) < 1)
            #expect(box.frames["clove.grid.batch.compare"] == nil)

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

    @Test func gridBatchBarSplitsMarkingAndActionsCapsulesAndShowsConditionalCompareCapsule()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample

        // 1. Direct GridBatchBar with showsCompare: true renders three separate capsules separated by 8 pt gaps.
        do {
            let browsing = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
            browsing.openFolder()
            for photo in browsing.photos.prefix(2) { browsing.toggleSelection(photo.id) }
            let box = TapPickerTestBox()

            struct BarHost: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let box: TapPickerTestBox
                var showsCompare: Bool

                var body: some View {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        GridBatchBar(
                            browsing: browsing,
                            showsCompare: showsCompare,
                            onCompare: {}
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tapPickerContainer()
                    .environment(store)
                    .environment(\.scenePhase, .active)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { box.frames = $0 }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 700, height: 420)
            let host = UIHostingController(
                rootView: BarHost(
                    browsing: browsing, store: store, box: box, showsCompare: true))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("batch bar with Compare mounted") {
                box.frames["clove.grid.batch.bar"] != nil
                    && box.frames["clove.grid.batch.actions"] != nil
                    && box.frames["clove.grid.batch.compare"] != nil
            }

            let markingCapsule = try #require(box.frames["clove.grid.batch.bar"])
            let actionsCapsule = try #require(box.frames["clove.grid.batch.actions"])
            let compareCapsule = try #require(box.frames["clove.grid.batch.compare"])

            #expect(abs(markingCapsule.width - 168) < 1)
            #expect(abs(markingCapsule.height - 48) < 1)
            #expect(abs(actionsCapsule.width - 110) < 1)
            #expect(abs(actionsCapsule.height - 48) < 1)
            #expect(abs(compareCapsule.height - 48) < 1)
            #expect(abs(actionsCapsule.minX - markingCapsule.maxX - 8) < 1)
            #expect(abs(compareCapsule.minX - actionsCapsule.maxX - 8) < 1)
        }

        // 2. GridScreen shows Compare capsule only for 2 visible targets on compare-capable layouts.
        do {
            let browsing = BrowsingModel(library: TestLibrary.sample(), similarGroupsEnabled: false)
            browsing.openFolder()
            let box = TapPickerTestBox()

            struct GridCompareHost: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let box: TapPickerTestBox
                var isDuoCover = false

                var body: some View {
                    GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                        .environment(store)
                        .environment(\.cloveUserInterfaceIdiom, .phone)
                        .environment(\.isDuoCover, isDuoCover)
                        .environment(\.scenePhase, .active)
                        .onPreferenceChange(TapPickerFramesPreferenceKey.self) { box.frames = $0 }
                }
            }

            let window = UIWindow(windowScene: scene)
            // Portrait iPhone with 2 selected: Compare remains hidden.
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            let host = UIHostingController(
                rootView: GridCompareHost(browsing: browsing, store: store, box: box))
            host.traitOverrides.horizontalSizeClass = .compact
            host.traitOverrides.verticalSizeClass = .regular
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            let first = try #require(browsing.photos.first)
            let second = try #require(browsing.photos.dropFirst().first)
            let third = try #require(browsing.photos.dropFirst(2).first)
            browsing.toggleSelection(first.id)
            browsing.toggleSelection(second.id)

            try await waitFor("portrait batch bar mounted") {
                box.frames["clove.grid.batch.bar"] != nil
                    && box.frames["clove.grid.batch.actions"] != nil
            }
            #expect(box.frames["clove.grid.batch.compare"] == nil)

            // Landscape iPhone with 2 selected: Compare capsule mounts beside Actions.
            window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
            host.traitOverrides.verticalSizeClass = .compact
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            try await waitFor("landscape Compare capsule mounted for 2 selected") {
                box.frames["clove.grid.batch.compare"] != nil
            }

            // Selecting a 3rd photo hides Compare again.
            browsing.toggleSelection(third.id)
            try await waitFor("Compare capsule hidden when 3 photos selected") {
                box.frames["clove.grid.batch.compare"] == nil
            }
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
            let second = try #require(browsing.photos.dropFirst().first)
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
            try await waitFor("duo detail opens Focus View and hides grid batch bar") {
                box.frames["clove.duo.focus"] != nil
                    && box.frames["clove.duo.photoPreview"] == nil
                    && box.frames["clove.detail.filmstrip"] != nil
                    && box.frames["clove.duo.capsule"] != nil
                    && box.frames["clove.grid.batch"] == nil
            }
            browsing.back()
            try await waitFor("duo grid batch bar returns after Back") {
                box.frames["clove.grid.batch"] != nil
            }
            browsing.openPhoto(second.id)
            try await waitFor("reopening another photo in Duo opens Focus View by default") {
                box.frames["clove.duo.focus"] != nil
                    && box.frames["clove.duo.photoPreview"] == nil
                    && box.frames["clove.detail.filmstrip"] != nil
                    && box.frames["clove.duo.capsule"] != nil
            }
            browsing.back()
            try await waitFor("duo grid batch bar returns after second Back") {
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

    @Test func widePadDetailPlacesHorizontalPickersAboveBottomRightToolbarAndFallsBackVertically()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let store = SettingsStore.sample
        let browsing = BrowsingModel(library: TestLibrary.sample())
        browsing.openFolder()
        let standalone = try #require(browsing.photos.first { $0.fileName == "MMQ02680.ARW" })
        browsing.openPhoto(standalone.id)

        let presentationBox = PresentationStateBox(value: .photoPreview)
        let box = TapPickerTestBox()

        struct PadDetailHost: View {
            let browsing: BrowsingModel
            let store: SettingsStore
            @Bindable var presentation: PresentationStateBox
            let box: TapPickerTestBox
            @State private var settingsStore: SettingsStore = {
                let configured = SettingsStore.sample
                configured.markGestureGuideSeen()
                return configured
            }()

            var body: some View {
                DetailScreen(
                    browsing: browsing, images: SampleDetailImages(),
                    presentation: $presentation.value
                )
                .environment(settingsStore)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, box.trigger)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { frames in
                    box.frames = frames
                }
            }
        }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let host = UIHostingController(
            rootView: PadDetailHost(
                browsing: browsing, store: store, presentation: presentationBox, box: box))
        host.traitOverrides.horizontalSizeClass = .regular
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 21, right: 0)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("iPad Photo Preview capsule mounted") {
            box.frames["clove.detail.capsule"] != nil
                && box.frames["clove.detail.bottomBand"] != nil
                && self.findZoomPreview(in: window) != nil
        }
        let preview = try #require(findZoomPreview(in: window))
        let photoPreviewCapsule = try #require(box.frames["clove.detail.capsule"])
        let photoPreviewBand = try #require(box.frames["clove.detail.bottomBand"])
        let safeBottomY = host.view.safeAreaLayoutGuide.layoutFrame.maxY
        #expect(box.frames["clove.detail.rail"] == nil)
        #expect(abs(photoPreviewCapsule.width - 168) <= 1)
        #expect(abs(photoPreviewCapsule.height - 48) <= 1)
        #expect(abs((window.frame.maxX - 24) - photoPreviewCapsule.maxX) <= 1.5)
        #expect(abs((safeBottomY - 10) - photoPreviewCapsule.maxY) <= 1.5)
        #expect(abs(photoPreviewBand.height - 84) <= 1.5)

        let stageBeforePhotoPreviewPickers = preview.convert(preview.bounds, to: window)
        for (buttonID, pickerID) in [
            ("clove.detail.capsule.rating", "clove.detail.capsule.stars"),
            ("clove.detail.capsule.label", "clove.detail.labels"),
        ] {
            box.sendTrigger(buttonID)
            try await waitFor("iPad Photo Preview picker \(pickerID) visible") {
                box.frames[pickerID] != nil
            }
            let pickerFrame = try #require(box.frames[pickerID])
            #expect(pickerFrame.width > pickerFrame.height)
            #expect(abs(pickerFrame.width - 288) <= 2)
            #expect(abs(pickerFrame.height - 52) <= 2)
            #expect(abs((photoPreviewCapsule.minY - 12) - pickerFrame.maxY) <= 1.5)
            #expect(abs((window.frame.maxX - 16) - pickerFrame.maxX) <= 1.5)
            let stageDuringPicker = preview.convert(preview.bounds, to: window)
            #expect(abs(stageDuringPicker.height - stageBeforePhotoPreviewPickers.height) <= 1)
            #expect(abs(stageDuringPicker.minY - stageBeforePhotoPreviewPickers.minY) <= 1)
            box.sendTrigger(buttonID)
            try await waitFor("iPad Photo Preview picker \(pickerID) dismissed") {
                box.frames[pickerID] == nil
            }
        }

        // Switching to Focus View keeps MarkingToolbar stationary and preserves horizontal pickers.
        presentationBox.value = .focus
        try await waitFor("iPad Focus View band mounted") {
            box.frames["clove.detail.filmstrip"] != nil
                && abs((box.frames["clove.detail.bottomBand"]?.height ?? 0) - 78) <= 1.5
        }
        let focusCapsule = try #require(box.frames["clove.detail.capsule"])
        let focusBand = try #require(box.frames["clove.detail.bottomBand"])
        let filmstrip = try #require(box.frames["clove.detail.filmstrip"])
        expectSameMarkingCapsuleFrame(photoPreviewCapsule, focusCapsule, tolerance: 1)
        #expect(abs(focusBand.height - 78) <= 1.5)
        #expect(abs((focusCapsule.minX - filmstrip.maxX) - 24) <= 1.5)

        let stageBeforeFocusPickers = preview.convert(preview.bounds, to: window)
        for (buttonID, pickerID) in [
            ("clove.detail.capsule.rating", "clove.detail.capsule.stars"),
            ("clove.detail.capsule.label", "clove.detail.labels"),
        ] {
            box.sendTrigger(buttonID)
            try await waitFor("iPad Focus View picker \(pickerID) visible") {
                box.frames[pickerID] != nil
            }
            let pickerFrame = try #require(box.frames[pickerID])
            #expect(pickerFrame.width > pickerFrame.height)
            #expect(abs(pickerFrame.width - 288) <= 2)
            #expect(abs(pickerFrame.height - 52) <= 2)
            #expect(abs((focusCapsule.minY - 12) - pickerFrame.maxY) <= 1.5)
            #expect(abs((window.frame.maxX - 16) - pickerFrame.maxX) <= 1.5)
            let stageDuringPicker = preview.convert(preview.bounds, to: window)
            #expect(abs(stageDuringPicker.height - stageBeforeFocusPickers.height) <= 1)
            box.sendTrigger(buttonID)
            try await waitFor("iPad Focus View picker \(pickerID) dismissed") {
                box.frames[pickerID] == nil
            }
        }

        // Constrained horizontal width falls back to vertical 52 × 288 pickers cleanly.
        window.frame = CGRect(x: 0, y: 0, width: 310, height: 820)
        try await waitFor("narrowed iPad capsule settled") {
            guard let narrowed = box.frames["clove.detail.capsule"] else { return false }
            return narrowed.maxX <= 310
        }
        for (buttonID, pickerID) in [
            ("clove.detail.capsule.rating", "clove.detail.capsule.stars"),
            ("clove.detail.capsule.label", "clove.detail.labels"),
        ] {
            box.sendTrigger(buttonID)
            try await waitFor("narrowed vertical picker \(pickerID) visible") {
                box.frames[pickerID] != nil
            }
            let pickerFrame = try #require(box.frames[pickerID])
            #expect(pickerFrame.height > pickerFrame.width)
            #expect(abs(pickerFrame.width - 52) <= 2)
            #expect(abs(pickerFrame.height - 288) <= 2)
            box.sendTrigger(buttonID)
            try await waitFor("narrowed vertical picker \(pickerID) dismissed") {
                box.frames[pickerID] == nil
            }
        }
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

    private func renderedColourPixel(_ style: CloveColour, theme: CloveTheme) throws -> RGBA {
        let swatch = Rectangle()
            .fill(style)
            .frame(width: 8, height: 8)
            .environment(\.cloveTheme, theme)
        let renderer = ImageRenderer(content: swatch)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return try rgbaPixels(from: image).pixel(x: 4, y: 4)
    }

    private func rgbaPixels(from image: CGImage) throws -> PixelBuffer {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try #require(
            CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelBuffer(width: width, height: height, bytes: bytes)
    }

    private func colorsClose(_ actual: RGBA, _ expected: RGBA, tolerance: Int = 10) -> Bool {
        abs(Int(actual.r) - Int(expected.r)) <= tolerance
            && abs(Int(actual.g) - Int(expected.g)) <= tolerance
            && abs(Int(actual.b) - Int(expected.b)) <= tolerance
            && abs(Int(actual.a) - Int(expected.a)) <= tolerance
    }
}

private struct RGBA {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(x: Int, y: Int) -> RGBA {
        let offset = (y * width + x) * 4
        return RGBA(
            r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
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
