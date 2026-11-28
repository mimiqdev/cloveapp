import CloveCore
import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
@Suite("Rejected color label display", .serialized)
struct RejectedColorLabelDisplayTests {
    @Test(arguments: [CloveTheme.light, CloveTheme.dark])
    func markingToolbarRendersRejectAndActiveColorLabelTogetherWhileStarsStayUnrated(
        theme: CloveTheme
    ) async throws {
        let toolbar = MarkingToolbar(
            rating: .unrated,
            label: .yellow,
            isRejected: true,
            identifier: "test.rejected.toolbar",
            onRate: { _ in },
            onReject: {},
            onLabel: { _ in }
        )
        .padding(8)
        .background(Color.clove.bg.stage)
        .environment(\.cloveTheme, theme)

        let renderer = ImageRenderer(content: toolbar)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let pixels = try rgbaPixels(from: image)

        let expectedReject = try renderedColourPixel(Color.clove.reject, theme: theme)
        let expectedYellow = try renderedColourPixel(Color.clove.label.yellow, theme: theme)
        let expectedRatingOn = try renderedColourPixel(Color.clove.rating.on, theme: theme)

        let thirdWidth = image.width / 3
        #expect(
            hasMatchingPixel(
                in: pixels, xRange: 0..<thirdWidth, yRange: 0..<image.height,
                matching: expectedReject))
        #expect(
            !hasMatchingPixel(
                in: pixels, xRange: thirdWidth..<(thirdWidth * 2), yRange: 0..<image.height,
                matching: expectedRatingOn))
        #expect(
            hasMatchingPixel(
                in: pixels, xRange: (thirdWidth * 2)..<image.width, yRange: 0..<image.height,
                matching: expectedYellow))

        // Verify hosted MarkingToolbar opens LabelPicker with .yellow selected when rejected.
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let box = FrameTestBox()

        struct ToolbarHost: View {
            let theme: CloveTheme
            let box: FrameTestBox

            var body: some View {
                MarkingToolbar(
                    rating: .unrated,
                    label: .yellow,
                    isRejected: true,
                    identifier: "test.rejected.toolbar",
                    onRate: { _ in },
                    onReject: {},
                    onLabel: { _ in }
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clove.bg.stage)
                .tapPickerContainer()
                .environment(\.cloveTheme, theme)
                .environment(\.colorScheme, theme.appearance.colorScheme)
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, box.trigger)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { box.tapFrames = $0 }
            }
        }

        let host = UIHostingController(rootView: ToolbarHost(theme: theme, box: box))
        host.overrideUserInterfaceStyle = theme.appearance == .dark ? .dark : .light
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 320)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("MarkingToolbar mounted") {
            box.tapFrames["test.rejected.toolbar"] != nil
        }

        let capsuleFrame = try #require(box.tapFrames["test.rejected.toolbar"])
        try await expectToolbarPixels(
            in: window, frame: capsuleFrame,
            expectedReject: expectedReject,
            expectedRatingOn: expectedRatingOn,
            expectedLabel: expectedYellow,
            context: "Standalone MarkingToolbar (\(theme.rawValue))")

        box.sendTrigger("test.rejected.toolbar.label")
        try await waitFor("LabelPicker opened from rejected MarkingToolbar") {
            guard let pickerFrame = box.tapFrames["test.rejected.toolbar.labels"] else {
                return false
            }
            return abs(pickerFrame.width - 288) <= 2 && abs(pickerFrame.height - 52) <= 2
        }
        let pickerFrame = try #require(box.tapFrames["test.rejected.toolbar.labels"])
        let expectedRing = try renderedColourPixel(Color.clove.text.primary, theme: theme)
        try await expectLabelPickerSelection(
            in: window, pickerFrame: pickerFrame, selectedIndex: 2, expectedRing: expectedRing,
            context: "Standalone LabelPicker (\(theme.rawValue))")
    }

    @Test(arguments: [CloveTheme.light, CloveTheme.dark])
    func comparePaneMarksSummaryRendersRejectAndColorLabelTogetherWithoutStars(
        theme: CloveTheme
    ) throws {
        let expectedReject = try renderedColourPixel(Color.clove.reject, theme: theme)
        let expectedYellow = try renderedColourPixel(Color.clove.label.yellow, theme: theme)
        let expectedGreen = try renderedColourPixel(Color.clove.label.green, theme: theme)
        let expectedRatingOn = try renderedColourPixel(Color.clove.rating.on, theme: theme)

        func renderSummary(_ marks: PhotoMarks) throws -> PixelBuffer {
            let view = ComparePaneMarksSummary(
                marks: marks, language: .english, identifier: "test.pane.marks"
            )
            .padding(6)
            .background(Color.clove.bg.stage)
            .environment(\.cloveTheme, theme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return try rgbaPixels(from: try #require(renderer.cgImage))
        }

        let rejectedWithYellow = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .yellow))
        let rejectedYellowPixels = try renderSummary(rejectedWithYellow)
        #expect(
            hasMatchingPixel(
                in: rejectedYellowPixels,
                xRange: 0..<rejectedYellowPixels.width,
                yRange: 0..<rejectedYellowPixels.height,
                matching: expectedReject))
        #expect(
            hasMatchingPixel(
                in: rejectedYellowPixels,
                xRange: 0..<rejectedYellowPixels.width,
                yRange: 0..<rejectedYellowPixels.height,
                matching: expectedYellow))
        #expect(
            !hasMatchingPixel(
                in: rejectedYellowPixels,
                xRange: 0..<rejectedYellowPixels.width,
                yRange: 0..<rejectedYellowPixels.height,
                matching: expectedRatingOn))
        #expect(
            MarkSummary.text(for: rejectedWithYellow, language: .english) == "Yellow · Rejected")

        let rejectedOnly = PhotoMarks(rating: .rejected, label: .clear)
        let rejectedOnlyPixels = try renderSummary(rejectedOnly)
        #expect(
            hasMatchingPixel(
                in: rejectedOnlyPixels,
                xRange: 0..<rejectedOnlyPixels.width,
                yRange: 0..<rejectedOnlyPixels.height,
                matching: expectedReject))
        #expect(
            !hasMatchingPixel(
                in: rejectedOnlyPixels,
                xRange: 0..<rejectedOnlyPixels.width,
                yRange: 0..<rejectedOnlyPixels.height,
                matching: expectedYellow))
        #expect(
            !hasMatchingPixel(
                in: rejectedOnlyPixels,
                xRange: 0..<rejectedOnlyPixels.width,
                yRange: 0..<rejectedOnlyPixels.height,
                matching: expectedRatingOn))

        let ratedAndGreen = PhotoMarks(
            rating: try #require(Rating(rawValue: 4)), label: ColourLabel(colour: .green))
        let ratedGreenPixels = try renderSummary(ratedAndGreen)
        #expect(
            !hasMatchingPixel(
                in: ratedGreenPixels,
                xRange: 0..<ratedGreenPixels.width,
                yRange: 0..<ratedGreenPixels.height,
                matching: expectedReject))
        #expect(
            hasMatchingPixel(
                in: ratedGreenPixels,
                xRange: 0..<ratedGreenPixels.width,
                yRange: 0..<ratedGreenPixels.height,
                matching: expectedRatingOn))
        #expect(
            hasMatchingPixel(
                in: ratedGreenPixels,
                xRange: 0..<ratedGreenPixels.width,
                yRange: 0..<ratedGreenPixels.height,
                matching: expectedGreen))
    }

    @Test func detailMarkingToolbarDisplaysActiveColorLabelOnRejectedPhotoAcrossAllFourLayouts()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let theme = CloveTheme.light
        let expectedReject = try renderedColourPixel(Color.clove.reject, theme: theme)
        let expectedYellow = try renderedColourPixel(Color.clove.label.yellow, theme: theme)
        let expectedGreen = try renderedColourPixel(Color.clove.label.green, theme: theme)
        let expectedRatingOn = try renderedColourPixel(Color.clove.rating.on, theme: theme)
        let expectedRing = try renderedColourPixel(Color.clove.text.primary, theme: theme)

        let library = ControlledPhotoLibrary(rejected: ["p1"], stems: ["p1", "p2"])
        let p1 = library.identity("p1")
        library.photos[0].marks = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .yellow))

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder opened") {
            !browsing.isFolderOpening && browsing.photos.count == 2
        }
        browsing.openPhoto(p1)

        struct LayoutCase {
            let name: String
            let size: CGSize
            let horizontal: UIUserInterfaceSizeClass
            let vertical: UIUserInterfaceSizeClass
            let idiom: UIUserInterfaceIdiom
            let isDuo: Bool
            let isDuoExpanded: Bool
            let isDuoCover: Bool
            let presentation: DetailPresentation
            let capsuleIdentifier: String
            let labelPickerIdentifier: String
            let expectedContainerFrame: String
            let unexpectedContainerFrame: String?
        }

        let cases: [LayoutCase] = [
            LayoutCase(
                name: "iPhone Portrait",
                size: CGSize(width: 390, height: 844),
                horizontal: .compact, vertical: .regular, idiom: .phone,
                isDuo: false, isDuoExpanded: false, isDuoCover: false,
                presentation: .focus,
                capsuleIdentifier: "clove.detail.capsule",
                labelPickerIdentifier: "clove.detail.labels",
                expectedContainerFrame: "clove.detail.filmstrip",
                unexpectedContainerFrame: "clove.detail.landscapeBottomRow"),
            LayoutCase(
                name: "iPhone Landscape",
                size: CGSize(width: 844, height: 390),
                horizontal: .compact, vertical: .compact, idiom: .phone,
                isDuo: false, isDuoExpanded: false, isDuoCover: false,
                presentation: .focus,
                capsuleIdentifier: "clove.detail.capsule",
                labelPickerIdentifier: "clove.detail.labels",
                expectedContainerFrame: "clove.detail.landscapeBottomRow",
                unexpectedContainerFrame: "clove.detail.bottomBand"),
            LayoutCase(
                name: "iPad Photo Preview",
                size: CGSize(width: 1180, height: 820),
                horizontal: .regular, vertical: .regular, idiom: .pad,
                isDuo: false, isDuoExpanded: false, isDuoCover: false,
                presentation: .photoPreview,
                capsuleIdentifier: "clove.detail.capsule",
                labelPickerIdentifier: "clove.detail.labels",
                expectedContainerFrame: "clove.detail.bottomBand",
                unexpectedContainerFrame: "clove.detail.filmstrip"),
            LayoutCase(
                name: "iPad Focus View",
                size: CGSize(width: 1180, height: 820),
                horizontal: .regular, vertical: .regular, idiom: .pad,
                isDuo: false, isDuoExpanded: false, isDuoCover: false,
                presentation: .focus,
                capsuleIdentifier: "clove.detail.capsule",
                labelPickerIdentifier: "clove.detail.labels",
                expectedContainerFrame: "clove.detail.bottomBand",
                unexpectedContainerFrame: nil),
            LayoutCase(
                name: "Duo Cover",
                size: CGSize(width: 466, height: 678),
                horizontal: .compact, vertical: .regular, idiom: .phone,
                isDuo: true, isDuoExpanded: false, isDuoCover: true,
                presentation: .focus,
                capsuleIdentifier: "clove.duo.capsule",
                labelPickerIdentifier: "clove.duo.labels",
                expectedContainerFrame: "clove.duo.focus",
                unexpectedContainerFrame: "clove.duo.photoPreview"),
            LayoutCase(
                name: "Duo Expanded",
                size: CGSize(width: 951, height: 669),
                horizontal: .regular, vertical: .regular, idiom: .phone,
                isDuo: true, isDuoExpanded: true, isDuoCover: false,
                presentation: .photoPreview,
                capsuleIdentifier: "clove.duo.capsule",
                labelPickerIdentifier: "clove.duo.labels",
                expectedContainerFrame: "clove.duo.photoPreview",
                unexpectedContainerFrame: "clove.duo.focus"),
        ]

        for layoutCase in cases {
            if layoutCase.isDuo {
                guard #available(iOS 27.1, *) else { continue }
            }
            let store = SettingsStore.sample
            store.markGestureGuideSeen()
            store.update { $0.autoAdvance.destination = .stay }
            let box = FrameTestBox()
            let presentationBox = PresentationBox(value: layoutCase.presentation)

            struct DetailHost: View {
                let browsing: BrowsingModel
                let store: SettingsStore
                let layoutCase: LayoutCase
                @Bindable var presentation: PresentationBox
                let box: FrameTestBox

                private var detailScreen: some View {
                    DetailScreen(
                        browsing: browsing,
                        images: SampleDetailImages(),
                        duo: layoutCase.isDuo
                            ? DuoDetailLayout(
                                presentation: $presentation.value,
                                showsGrid: layoutCase.isDuoExpanded)
                            : nil,
                        presentation: layoutCase.isDuo ? nil : $presentation.value
                    )
                }

                var body: some View {
                    NavigationStack {
                        detailScreen
                    }
                    .environment(store)
                    .environment(\.cloveTheme, .light)
                    .environment(\.colorScheme, .light)
                    .environment(\.cloveUserInterfaceIdiom, layoutCase.idiom)
                    .environment(\.isDuoExpanded, layoutCase.isDuoExpanded)
                    .environment(\.isDuoCover, layoutCase.isDuoCover)
                    .environment(\.usesVerticalBrowsingToolbar, layoutCase.isDuo)
                    .environment(\.hasFoldRegion, layoutCase.isDuoExpanded)
                    .environment(\.scenePhase, .active)
                    .environment(\.tapPickerTriggerRequest, box.trigger)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { box.tapFrames = $0 }
                }
            }

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: layoutCase.size)
            let host = UIHostingController(
                rootView: DetailHost(
                    browsing: browsing, store: store, layoutCase: layoutCase,
                    presentation: presentationBox, box: box))
            host.overrideUserInterfaceStyle = .light
            host.traitOverrides.horizontalSizeClass = layoutCase.horizontal
            host.traitOverrides.verticalSizeClass = layoutCase.vertical
            if layoutCase.isDuoCover {
                host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84)
            } else if layoutCase.isDuoExpanded {
                host.additionalSafeAreaInsets = UIEdgeInsets(
                    top: 0, left: 0, bottom: 0, right: 89.5)
            }
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("\(layoutCase.name) MarkingToolbar mounted") {
                box.tapFrames[layoutCase.capsuleIdentifier] != nil
                    && box.tapFrames[layoutCase.expectedContainerFrame] != nil
            }
            if let unexpected = layoutCase.unexpectedContainerFrame {
                #expect(box.tapFrames[unexpected] == nil)
            }

            let capsuleFrame = try #require(box.tapFrames[layoutCase.capsuleIdentifier])
            try await expectToolbarPixels(
                in: window, frame: capsuleFrame,
                expectedReject: expectedReject,
                expectedRatingOn: expectedRatingOn,
                expectedLabel: expectedYellow,
                context: layoutCase.name)

            box.sendTrigger("\(layoutCase.capsuleIdentifier).label")
            try await waitFor("\(layoutCase.name) LabelPicker mounted") {
                guard let pickerFrame = box.tapFrames[layoutCase.labelPickerIdentifier] else {
                    return false
                }
                return abs(pickerFrame.width - 288) <= 2 && abs(pickerFrame.height - 52) <= 2
            }
            let pickerFrame = try #require(box.tapFrames[layoutCase.labelPickerIdentifier])
            try await expectLabelPickerSelection(
                in: window, pickerFrame: pickerFrame, selectedIndex: 2,
                expectedRing: expectedRing, context: layoutCase.name)
            box.sendTrigger("\(layoutCase.capsuleIdentifier).label")
            try await waitFor("\(layoutCase.name) LabelPicker dismissed") {
                box.tapFrames[layoutCase.labelPickerIdentifier] == nil
            }

            if layoutCase.name == "iPhone Portrait" {
                // Updating the colour label on a rejected photo updates the dot while keeping Reject
                // and unrated stars intact.
                browsing.apply(.label(ColourLabel(colour: .green)), to: p1)
                await browsing.drainActions()
                try await Task.sleep(for: .milliseconds(350))
                try await expectToolbarPixels(
                    in: window, frame: capsuleFrame,
                    expectedReject: expectedReject,
                    expectedRatingOn: expectedRatingOn,
                    expectedLabel: expectedGreen,
                    excludedLabel: expectedYellow,
                    context: "\(layoutCase.name) updated to Green")

                browsing.apply(.label(ColourLabel(colour: .yellow)), to: p1)
                await browsing.drainActions()
                try await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    @Test func compareToolbarAndPaneHeaderDisplayActiveColorLabelOnRejectedPhoto() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let theme = CloveTheme.light
        let expectedReject = try renderedColourPixel(Color.clove.reject, theme: theme)
        let expectedYellow = try renderedColourPixel(Color.clove.label.yellow, theme: theme)
        let expectedBlue = try renderedColourPixel(Color.clove.label.blue, theme: theme)
        let expectedRatingOn = try renderedColourPixel(Color.clove.rating.on, theme: theme)
        let expectedRing = try renderedColourPixel(Color.clove.text.primary, theme: theme)

        let library = ControlledPhotoLibrary(rejected: ["p1", "p2"], stems: ["p1", "p2", "p3"])
        let p1 = library.identity("p1")
        library.photos[0].marks = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .yellow))
        library.photos[1].marks = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .blue))

        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportScanFinished()
        try await waitFor("folder opened") { !model.isFolderOpening && model.photos.count == 3 }
        model.openPhoto(p1)
        let timeline = DetailTimeline(
            photos: model.photos, groups: model.groups, groupsEnabled: true)
        #expect(model.enterCompareFromDetail(timeline: timeline))

        let store = SettingsStore.sample
        store.markGestureGuideSeen()
        let box = FrameTestBox()

        struct CompareHost: View {
            let model: BrowsingModel
            let store: SettingsStore
            let theme: CloveTheme
            let box: FrameTestBox

            var body: some View {
                DetailScreen(browsing: model, images: SampleDetailImages())
                    .environment(store)
                    .environment(\.cloveTheme, theme)
                    .environment(\.colorScheme, .light)
                    .environment(\.cloveUserInterfaceIdiom, .pad)
                    .environment(\.scenePhase, .active)
                    .environment(\.tapPickerTriggerRequest, box.trigger)
                    .onPreferenceChange(TapPickerFramesPreferenceKey.self) { box.tapFrames = $0 }
                    .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                        box.headerFrames = $0
                    }
            }
        }

        let host = UIHostingController(
            rootView: CompareHost(model: model, store: store, theme: theme, box: box))
        host.overrideUserInterfaceStyle = .light
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("Compare toolbar and pane headers mounted") {
            box.tapFrames["clove.compare.capsule"] != nil
                && box.headerFrames["clove.compare.paneA.marks"] != nil
                && box.headerFrames["clove.compare.paneB.marks"] != nil
        }

        let paneAMarksFrame = try #require(box.headerFrames["clove.compare.paneA.marks"])
        let paneBMarksFrame = try #require(box.headerFrames["clove.compare.paneB.marks"])
        let capsuleFrame = try #require(box.tapFrames["clove.compare.capsule"])

        let buffer = try await captureWindowBuffer(in: window)
        // Pane A header shows both red Reject glyph and Yellow dot, with no filled star.
        let paneAHasReject = hasMatchingPixel(
            in: buffer, rect: paneAMarksFrame, matching: expectedReject)
        let paneAHasYellow = hasMatchingPixel(
            in: buffer, rect: paneAMarksFrame, matching: expectedYellow)
        let paneAHasStars = hasMatchingPixel(
            in: buffer, rect: paneAMarksFrame, matching: expectedRatingOn)
        #expect(paneAHasReject)
        #expect(paneAHasYellow)
        #expect(!paneAHasStars)

        // Pane B header shows both red Reject glyph and Blue dot, with no filled star.
        let paneBHasReject = hasMatchingPixel(
            in: buffer, rect: paneBMarksFrame, matching: expectedReject)
        let paneBHasBlue = hasMatchingPixel(
            in: buffer, rect: paneBMarksFrame, matching: expectedBlue)
        let paneBHasStars = hasMatchingPixel(
            in: buffer, rect: paneBMarksFrame, matching: expectedRatingOn)
        #expect(paneBHasReject)
        #expect(paneBHasBlue)
        #expect(!paneBHasStars)

        // Challenger B (Blue + Rejected) is active initially.
        try await expectToolbarPixels(
            in: window, frame: capsuleFrame,
            expectedReject: expectedReject,
            expectedRatingOn: expectedRatingOn,
            expectedLabel: expectedBlue,
            excludedLabel: expectedYellow,
            context: "Compare active challenger B")

        box.sendTrigger("clove.compare.capsule.label")
        try await waitFor("Compare LabelPicker opened for B") {
            guard let pickerFrame = box.tapFrames["clove.compare.capsule.labels"] else {
                return false
            }
            return abs(pickerFrame.width - 288) <= 2 && abs(pickerFrame.height - 52) <= 2
        }
        let pickerFrameB = try #require(box.tapFrames["clove.compare.capsule.labels"])
        try await expectLabelPickerSelection(
            in: window, pickerFrame: pickerFrameB, selectedIndex: 4,
            expectedRing: expectedRing, context: "Compare B Blue selected")
        box.sendTrigger("clove.compare.capsule.label")
        try await waitFor("Compare LabelPicker dismissed for B") {
            box.tapFrames["clove.compare.capsule.labels"] == nil
        }

        // Switching to Reference A (Yellow + Rejected) updates toolbar dot to Yellow while keeping
        // Reject red and stars unrated.
        model.selectCompareSide(.reference)
        try await Task.sleep(for: .milliseconds(350))
        try await expectToolbarPixels(
            in: window, frame: capsuleFrame,
            expectedReject: expectedReject,
            expectedRatingOn: expectedRatingOn,
            expectedLabel: expectedYellow,
            excludedLabel: expectedBlue,
            context: "Compare active reference A")

        box.sendTrigger("clove.compare.capsule.label")
        try await waitFor("Compare LabelPicker opened for A") {
            guard let pickerFrame = box.tapFrames["clove.compare.capsule.labels"] else {
                return false
            }
            return abs(pickerFrame.width - 288) <= 2 && abs(pickerFrame.height - 52) <= 2
        }
        let pickerFrameA = try #require(box.tapFrames["clove.compare.capsule.labels"])
        try await expectLabelPickerSelection(
            in: window, pickerFrame: pickerFrameA, selectedIndex: 2,
            expectedRing: expectedRing, context: "Compare A Yellow selected")
        box.sendTrigger("clove.compare.capsule.label")
        try await waitFor("Compare LabelPicker dismissed for A") {
            box.tapFrames["clove.compare.capsule.labels"] == nil
        }
    }

    @Test func gridBatchBarDisplaysSharedColorLabelOnRejectedSelectionAndMixedWhenDiffering()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let theme = CloveTheme.light
        let expectedReject = try renderedColourPixel(Color.clove.reject, theme: theme)
        let expectedYellow = try renderedColourPixel(Color.clove.label.yellow, theme: theme)
        let expectedGreen = try renderedColourPixel(Color.clove.label.green, theme: theme)
        let expectedRatingOn = try renderedColourPixel(Color.clove.rating.on, theme: theme)
        let expectedRing = try renderedColourPixel(Color.clove.text.primary, theme: theme)

        let library = ControlledPhotoLibrary(
            rejected: ["p1", "p2", "p3"], stems: ["p1", "p2", "p3"])
        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        library.photos[0].marks = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .yellow))
        library.photos[1].marks = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .yellow))
        library.photos[2].marks = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .green))

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder opened") {
            !browsing.isFolderOpening && browsing.photos.count == 3
        }
        browsing.setSelection([p1, p2])

        let store = SettingsStore.sample
        let box = FrameTestBox()

        struct BatchHost: View {
            let browsing: BrowsingModel
            let store: SettingsStore
            let theme: CloveTheme
            let box: FrameTestBox

            var body: some View {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    GridBatchBar(browsing: browsing)
                        .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clove.bg.stage)
                .tapPickerContainer()
                .environment(store)
                .environment(\.cloveTheme, theme)
                .environment(\.colorScheme, .light)
                .environment(\.scenePhase, .active)
                .environment(\.tapPickerTriggerRequest, box.trigger)
                .onPreferenceChange(TapPickerFramesPreferenceKey.self) { box.tapFrames = $0 }
            }
        }

        let host = UIHostingController(
            rootView: BatchHost(browsing: browsing, store: store, theme: theme, box: box))
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 320)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("GridBatchBar mounted") {
            box.tapFrames["clove.grid.batch.bar"] != nil
        }

        let barFrame = try #require(box.tapFrames["clove.grid.batch.bar"])
        // Shared yellow label across rejected targets shows Reject + Unrated + Yellow.
        try await expectToolbarPixels(
            in: window, frame: barFrame,
            expectedReject: expectedReject,
            expectedRatingOn: expectedRatingOn,
            expectedLabel: expectedYellow,
            context: "GridBatchBar shared yellow rejected")

        box.sendTrigger("clove.grid.batch.label")
        try await waitFor("GridBatchBar LabelPicker opened (shared yellow)") {
            guard let pickerFrame = box.tapFrames["clove.grid.batch.labels"] else {
                return false
            }
            return abs(pickerFrame.width - 288) <= 2 && abs(pickerFrame.height - 52) <= 2
        }
        let sharedPickerFrame = try #require(box.tapFrames["clove.grid.batch.labels"])
        try await expectLabelPickerSelection(
            in: window, pickerFrame: sharedPickerFrame, selectedIndex: 2,
            expectedRing: expectedRing, context: "GridBatchBar shared yellow picker")
        box.sendTrigger("clove.grid.batch.label")
        try await waitFor("GridBatchBar LabelPicker dismissed") {
            box.tapFrames["clove.grid.batch.labels"] == nil
        }

        // Adding a rejected photo with a green label clears the label dot to neutral/mixed while
        // keeping Reject red and stars unrated.
        browsing.toggleSelection(p3)
        try await Task.sleep(for: .milliseconds(350))

        let mixedBuffer = try await captureWindowBuffer(in: window)
        let rejectFrame = try #require(box.tapFrames["clove.grid.batch.reject"])
        let ratingFrame = try #require(box.tapFrames["clove.grid.batch.rating"])
        let labelFrame = try #require(box.tapFrames["clove.grid.batch.label"])
        let hasReject = hasMatchingPixel(
            in: mixedBuffer, rect: rejectFrame, matching: expectedReject)
        let hasStars = hasMatchingPixel(
            in: mixedBuffer, rect: ratingFrame, matching: expectedRatingOn)
        let hasYellow = hasMatchingPixel(
            in: mixedBuffer, rect: labelFrame, matching: expectedYellow)
        let hasGreen = hasMatchingPixel(
            in: mixedBuffer, rect: labelFrame, matching: expectedGreen)
        #expect(hasReject)
        #expect(!hasStars)
        #expect(!hasYellow)
        #expect(!hasGreen)

        box.sendTrigger("clove.grid.batch.label")
        try await waitFor("GridBatchBar LabelPicker opened (mixed)") {
            guard let pickerFrame = box.tapFrames["clove.grid.batch.labels"] else {
                return false
            }
            return abs(pickerFrame.width - 288) <= 2 && abs(pickerFrame.height - 52) <= 2
        }
        let mixedPickerFrame = try #require(box.tapFrames["clove.grid.batch.labels"])
        try await expectLabelPickerSelection(
            in: window, pickerFrame: mixedPickerFrame, selectedIndex: nil,
            expectedRing: expectedRing, context: "GridBatchBar mixed picker")
        box.sendTrigger("clove.grid.batch.label")
        try await waitFor("GridBatchBar mixed LabelPicker dismissed") {
            box.tapFrames["clove.grid.batch.labels"] == nil
        }
    }

    // MARK: - Helpers

    private func expectToolbarPixels(
        in window: UIWindow,
        frame: CGRect,
        expectedReject: RGBA,
        expectedRatingOn: RGBA,
        expectedLabel: RGBA,
        excludedLabel: RGBA? = nil,
        context: String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let buffer = try await captureWindowBuffer(in: window)
        let thirdWidth = frame.width / 3
        let rejectRect = CGRect(
            x: frame.minX, y: frame.minY, width: thirdWidth, height: frame.height)
        let ratingRect = CGRect(
            x: frame.minX + thirdWidth, y: frame.minY, width: thirdWidth, height: frame.height)
        let labelRect = CGRect(
            x: frame.minX + thirdWidth * 2, y: frame.minY, width: thirdWidth, height: frame.height)

        let hasReject = hasMatchingPixel(in: buffer, rect: rejectRect, matching: expectedReject)
        let hasFilledStar = hasMatchingPixel(
            in: buffer, rect: ratingRect, matching: expectedRatingOn)
        let hasActiveLabel = hasMatchingPixel(in: buffer, rect: labelRect, matching: expectedLabel)

        #expect(
            hasReject,
            Comment(rawValue: "\(context): expected Reject pixels in left third"),
            sourceLocation: sourceLocation)
        #expect(
            !hasFilledStar,
            Comment(rawValue: "\(context): expected stars to stay unrated in middle third"),
            sourceLocation: sourceLocation)
        #expect(
            hasActiveLabel,
            Comment(rawValue: "\(context): expected active color label dot in right third"),
            sourceLocation: sourceLocation)
        if let excludedLabel {
            let hasExcluded = hasMatchingPixel(
                in: buffer, rect: labelRect, matching: excludedLabel)
            #expect(
                !hasExcluded,
                Comment(rawValue: "\(context): unexpected previous color label in right third"),
                sourceLocation: sourceLocation)
        }
    }

    private func expectLabelPickerSelection(
        in window: UIWindow,
        pickerFrame: CGRect,
        selectedIndex: Int?,
        expectedRing: RGBA,
        context: String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        // Wait for the bloom spring and micro animation to settle cleanly.
        try await Task.sleep(for: .milliseconds(350))
        let buffer = try await captureWindowBuffer(in: window)
        let step = LabelPicker.targetExtent + LabelPicker.itemSpacing
        let halfTarget = LabelPicker.containerPadding + LabelPicker.targetExtent / 2

        for index in 0..<LabelPicker.defaultLabels.count {
            let centerX = pickerFrame.minX + halfTarget + CGFloat(index) * step
            let centerY = pickerFrame.midY
            // 24 pt ring has radius 10..12 pt; check along the horizontal midline outside the
            // 16 pt dot (radius 8 pt) against the primaryText ring colour (tolerating glass blend).
            let rightArc = CGRect(x: centerX + 9.5, y: centerY - 2, width: 3.5, height: 4)
            let leftArc = CGRect(x: centerX - 13, y: centerY - 2, width: 3.5, height: 4)
            let hasRing =
                hasMatchingPixel(in: buffer, rect: rightArc, matching: expectedRing, tolerance: 55)
                || hasMatchingPixel(
                    in: buffer, rect: leftArc, matching: expectedRing, tolerance: 55)
            if index == selectedIndex {
                #expect(
                    hasRing,
                    Comment(rawValue: "\(context): expected selection ring on slot \(index)"),
                    sourceLocation: sourceLocation)
            } else {
                #expect(
                    !hasRing,
                    Comment(rawValue: "\(context): unexpected selection ring on slot \(index)"),
                    sourceLocation: sourceLocation)
            }
        }
    }

    private func captureWindowBuffer(in window: UIWindow) async throws -> PixelBuffer {
        window.layoutIfNeeded()
        await Task.yield()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(didDraw)
        return try rgbaPixels(from: try #require(image.cgImage))
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

    private func hasMatchingPixel(
        in buffer: PixelBuffer,
        rect: CGRect,
        matching expected: RGBA,
        tolerance: Int = 20
    ) -> Bool {
        let minX = max(0, Int(floor(rect.minX * 2)))
        let maxX = min(buffer.width, Int(ceil(rect.maxX * 2)))
        let minY = max(0, Int(floor(rect.minY * 2)))
        let maxY = min(buffer.height, Int(ceil(rect.maxY * 2)))
        guard minX < maxX, minY < maxY else { return false }
        return hasMatchingPixel(
            in: buffer, xRange: minX..<maxX, yRange: minY..<maxY,
            matching: expected, tolerance: tolerance)
    }

    private func hasMatchingPixel(
        in buffer: PixelBuffer,
        xRange: Range<Int>,
        yRange: Range<Int>,
        matching expected: RGBA,
        tolerance: Int = 20
    ) -> Bool {
        for y in yRange {
            for x in xRange {
                let actual = buffer.pixel(x: x, y: y)
                if colorsClose(actual, expected, tolerance: tolerance) {
                    return true
                }
            }
        }
        return false
    }

    private func colorsClose(_ actual: RGBA, _ expected: RGBA, tolerance: Int = 20) -> Bool {
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
private final class PresentationBox {
    var value: DetailPresentation

    init(value: DetailPresentation) {
        self.value = value
    }
}

@MainActor
@Observable
private final class FrameTestBox {
    var tapFrames: [String: CGRect] = [:]
    var headerFrames: [String: CGRect] = [:]
    var trigger: TapPickerTriggerRequest?
    private var nonce = 0

    func sendTrigger(_ id: String) {
        nonce += 1
        trigger = TapPickerTriggerRequest(id: id, nonce: nonce)
    }
}
