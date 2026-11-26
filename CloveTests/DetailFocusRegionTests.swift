import CloveCore
import CloveImaging
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct DetailFocusRegionTests {
    @Test func normalizedRegionUsesTheFittedPhotoRatherThanTheStage() {
        let region = makeRegion(
            normalized: NormalizedRegion(x: 0.25, y: 0.5, width: 0.1, height: 0.2))
        let fitted = CGRect(x: 0, y: 100, width: 400, height: 200)
        let rect = region.rect(in: fitted)
        #expect(rect.origin.x == 100)
        #expect(rect.origin.y == 200)
        #expect(rect.width == 40)
        #expect(rect.height == 40)
    }

    @Test func overlayTracksTheImageViewAcrossZoomPanAndResize() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        preview.setImage(try testPixels(width: 3000, height: 2000))
        let region = makeRegion(
            normalized: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16))
        preview.setFocusRegions([region])
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        let control = try #require(findRegionControl(in: preview))
        let imageView = try #require(control.superview as? UIImageView)
        #expect(control.center.x == 120)
        #expect(control.center.y == 260)
        #expect(control.frame.width >= 44)
        #expect(control.frame.height >= 44)

        preview.apply(DetailZoomCommand(id: 1, kind: .scale(2, anchor: region.centre)))
        let scrollView = try #require(preview.subviews.compactMap { $0 as? UIScrollView }.first)
        scrollView.setContentOffset(CGPoint(x: 120, y: 80), animated: false)
        // The control is the image view's child, so UIKit applies the scroll view's zoom and
        // content offset to both the pixels and the rectangle as one transform.
        #expect(control.superview === imageView)
        #expect(control.center.x == 120)
        #expect(control.center.y == 260)

        preview.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        // The resized fit is 600×400; the normalized centre stays at 30%, 35%.
        #expect(control.center.x == 180)
        #expect(control.center.y == 140)
    }

    @Test func resizePreservesZoomAnchorInsteadOfSnappingToCentre() async throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 551, height: 492))
        preview.setImage(
            try testPixels(width: 1616, height: 1078),
            fullResolutionPixels: CGSize(width: 3000, height: 2000))
        preview.setNeedsLayout()
        preview.layoutIfNeeded()

        let region = makeRegion(
            normalized: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16))
        preview.apply(DetailZoomCommand(id: 1, kind: .scale(1.814, anchor: region.centre)))
        let initial = try #require(preview.zoomSnapshot)
        #expect(abs(initial.anchor.x - 0.30) < 0.02)
        #expect(abs(initial.anchor.y - 0.35) < 0.02)

        // Hiding the Duo Focus marking toolbar grows preview height while width stays fixed.
        preview.frame = CGRect(x: 0, y: 0, width: 551, height: 556)
        preview.setNeedsLayout()
        preview.layoutIfNeeded()

        // The #272 retarget defers off layoutSubviews onto the next main-queue turn (#283).
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        let resized = try #require(preview.zoomSnapshot)
        #expect(abs(resized.anchor.x - 0.30) < 0.02)
        #expect(abs(resized.anchor.y - 0.35) < 0.02)
    }

    @Test func verticalMarkingSwipeBeginningOverExpandedEyeTargetStillMarks() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        preview.setImage(try testPixels(width: 3000, height: 2000))
        let eye = makeRegion(
            kind: .eye,
            normalized: NormalizedRegion(x: 0.5, y: 0.5, width: 0.005, height: 0.005))
        preview.setFocusRegions([eye])
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        let control = try #require(findRegionControl(in: preview))
        #expect(control.frame.width >= 44 && control.frame.height >= 44)
        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
        #expect(
            preview.gestureRecognizer(
                pan, shouldReceive: DetailRegionTouch(view: control)))
        var marked: Rating?
        preview.onMarkingSwipe = { marked = $0 }
        let swipe = DetailRegionPan()
        swipe.travel = CGPoint(x: 0, y: -15)
        #expect(preview.gestureRecognizerShouldBegin(swipe))
        preview.handleMarkingPan(swipe)
        swipe.sampleState = .changed
        swipe.travel = CGPoint(x: 0, y: -130)
        preview.handleMarkingPan(swipe)
        swipe.sampleState = .ended
        preview.handleMarkingPan(swipe)
        #expect(marked != nil)
    }

    @Test func horizontalNavigationSwipeBeginningOverARegionStillNavigates() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        preview.hasNext = true
        preview.setImage(try testPixels(width: 3000, height: 2000))
        preview.setFocusRegions([
            makeRegion(normalized: NormalizedRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        ])
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        let control = try #require(findRegionControl(in: preview))
        let pan = try #require(
            preview.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
        #expect(
            preview.gestureRecognizer(
                pan, shouldReceive: DetailRegionTouch(view: control)))
        var stepped: Int?
        preview.onStep = { stepped = $0 }
        let swipe = DetailRegionPan()
        swipe.travel = CGPoint(x: -15, y: 0)
        #expect(preview.gestureRecognizerShouldBegin(swipe))
        preview.handleMarkingPan(swipe)
        swipe.sampleState = .changed
        swipe.travel = CGPoint(x: -180, y: 0)
        preview.handleMarkingPan(swipe)
        swipe.sampleState = .ended
        preview.handleMarkingPan(swipe)
        #expect(stepped == 1)
    }

    @Test func earlyAutofocusAppearsWhileFacesArePending() {
        let first = photo("first")
        let autofocus = RegionSharpnessPathResult.regions([makeEvidence(.cameraAutofocus)])
        let faces = RegionSharpnessPathResult.regions([
            makeEvidence(
                .face, group: 0,
                normalized: NormalizedRegion(x: 0.58, y: 0.20, width: 0.22, height: 0.32)),
            makeEvidence(
                .eye, group: 0,
                normalized: NormalizedRegion(x: 0.64, y: 0.29, width: 0.04, height: 0.04)),
        ])
        var state = DetailFocusRegionState()
        state.begin(for: first)
        #expect(state.resultIndicators.isEmpty)
        state.receiveAutofocus(autofocus, for: first)
        #expect(state.regions.count == 1)
        #expect(state.regions[0].kind == .autofocus)
        #expect(state.resultIndicators.isEmpty)
        state.finish(makeAnalysis(autofocus: autofocus, faces: faces), for: first)
        #expect(state.retainedRegions.count == 3)
        #expect(state.regions.count == 2)
        #expect(state.regions.map(\.kind) == [.autofocus, .eye])
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(face: .detected, missingAutofocusMetadata: false))

        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))
        state.begin(for: first)
        state.receiveAutofocus(noAF, for: first)
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(face: nil, missingAutofocusMetadata: true))
    }

    @Test func perPersonSelectionChoosesOneDeterministicEyeOrFallsBackToFace() {
        let photoID = photo("multi-person")
        // Person 0: two usable eyes with lower score on left eye; deterministic geometric tie-break
        // (left/top eye) must win and never flip based on sharpness score.
        let p0Face = makeEvidence(
            .face, group: 0,
            normalized: NormalizedRegion(x: 0.1, y: 0.2, width: 0.22, height: 0.32),
            tenengradMeanSquare: 10)
        let p0LeftEye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.14, y: 0.30, width: 0.04, height: 0.04),
            tenengradMeanSquare: 5)
        let p0RightEye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.23, y: 0.30, width: 0.04, height: 0.04),
            tenengradMeanSquare: 500)

        // Person 1: face usable, eye unavailable -> falls back to Person 1's face frame.
        let p1Face = makeEvidence(
            .face, group: 1,
            normalized: NormalizedRegion(x: 0.42, y: 0.22, width: 0.20, height: 0.30),
            tenengradMeanSquare: 40)
        let p1TinyEye = RegionSharpnessEvidence(
            kind: .eye, groupIndex: 1,
            region: NormalizedRegion(x: 0.48, y: 0.32, width: 0.005, height: 0.005),
            score: nil, unavailableBecause: .regionTooSmall)

        // Person 2: face only, no eyes -> shows Person 2's face frame.
        let p2Face = makeEvidence(
            .face, group: 2,
            normalized: NormalizedRegion(x: 0.70, y: 0.22, width: 0.20, height: 0.30),
            tenengradMeanSquare: 35)

        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))

        var state = DetailFocusRegionState()
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: noAF,
                faces: .regions([p0Face, p0RightEye, p0LeftEye, p1Face, p1TinyEye, p2Face])),
            for: photoID)

        #expect(state.retainedRegions.count == 6)
        let presented = state.regions
        #expect(presented.count == 3)
        #expect(presented[0].kind == .eye)
        #expect(presented[0].groupIndex == 0)
        #expect(presented[0].region == p0LeftEye.region)
        #expect(presented[1].kind == .face)
        #expect(presented[1].groupIndex == 1)
        #expect(presented[2].kind == .face)
        #expect(presented[2].groupIndex == 2)
        // Re-evaluating preserves the exact same eye choice.
        #expect(state.regions.map(\.id) == presented.map(\.id))
    }

    @Test func localAutofocusOverlapSuppressesOnlyCollidingSubjectAndRespectsEyeMarkerSize() {
        let photoID = photo("af-overlap")
        let af = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.20, y: 0.25, width: 0.08, height: 0.08))
        // Person 0 eye marker overlaps AF -> Person 0 omitted locally.
        let p0Face = makeEvidence(
            .face, group: 0,
            normalized: NormalizedRegion(x: 0.18, y: 0.18, width: 0.20, height: 0.30))
        let p0Eye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.22, y: 0.27, width: 0.04, height: 0.04))
        // Person 1 has a large measurement ROI (0.14 wide, edge at 0.30) whose compact centred
        // eye marker (width <= 0.04, centred at 0.37) is separated from AF (maxX 0.28 + 0.015 = 0.295).
        let p1Face = makeEvidence(
            .face, group: 1,
            normalized: NormalizedRegion(x: 0.32, y: 0.18, width: 0.22, height: 0.30))
        let p1LargeROIEye = makeEvidence(
            .eye, group: 1,
            normalized: NormalizedRegion(x: 0.30, y: 0.23, width: 0.14, height: 0.14))

        var state = DetailFocusRegionState()
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: .regions([af]),
                faces: .regions([p0Face, p0Eye, p1Face, p1LargeROIEye])),
            for: photoID)

        let presented = state.regions
        #expect(presented.count == 2)
        #expect(presented[0].kind == .autofocus)
        #expect(presented[1].kind == .eye)
        #expect(presented[1].groupIndex == 1)

        // Unavailable AF must not suppress an actionable analysis marker.
        let tinyAF = RegionSharpnessEvidence(
            kind: .cameraAutofocus, groupIndex: nil,
            region: NormalizedRegion(x: 0.22, y: 0.27, width: 0.005, height: 0.005),
            score: nil, unavailableBecause: .regionTooSmall)
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: .regions([tinyAF]), faces: .regions([p0Face, p0Eye])),
            for: photoID)
        #expect(state.regions.map(\.kind) == [.autofocus, .eye])
    }

    @Test func toggleOffHidesRegionsAcrossLateCallbacksAndNavigationAndFocusedInspectionFilters() {
        let first = photo("first")
        let second = photo("second")
        let af = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.20, y: 0.20, width: 0.10, height: 0.10))
        let face = makeEvidence(
            .face, group: 0,
            normalized: NormalizedRegion(x: 0.60, y: 0.20, width: 0.20, height: 0.30))
        let eye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.64, y: 0.28, width: 0.04, height: 0.04))

        let browsing = BrowsingModel(library: TestLibrary.sample())
        #expect(browsing.showsFocusRegions)
        browsing.showsFocusRegions = false

        var state = DetailFocusRegionState()
        state.begin(for: first)
        state.receiveAutofocus(.regions([af]), for: first)
        #expect(state.regions(visible: browsing.showsFocusRegions, inspectedRegionID: nil).isEmpty)

        state.finish(
            makeAnalysis(autofocus: .regions([af]), faces: .regions([face, eye])), for: first)
        #expect(state.regions(visible: browsing.showsFocusRegions, inspectedRegionID: nil).isEmpty)
        #expect(!browsing.showsFocusRegions)

        state.begin(for: second)
        state.finish(makeAnalysis(autofocus: .regions([af]), faces: .regions([])), for: second)
        #expect(state.regions(visible: browsing.showsFocusRegions, inspectedRegionID: nil).isEmpty)

        browsing.showsFocusRegions = true
        state.begin(for: first)
        state.finish(
            makeAnalysis(autofocus: .regions([af]), faces: .regions([face, eye])), for: first)
        let allPresented = state.regions(
            visible: browsing.showsFocusRegions, inspectedRegionID: nil)
        #expect(allPresented.count == 2)
        let inspected = state.regions(
            visible: browsing.showsFocusRegions, inspectedRegionID: allPresented[1].id)
        #expect(inspected.map(\.id) == [allPresented[1].id])

        // Verify UIKit stage also removes all subviews and accessibility targets when toggled off.
        let stage = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        stage.setFocusRegions(allPresented)
        #expect(findAllRegionControls(in: stage).count == 2)
        #expect((stage.accessibilityElements?.count ?? 0) == 3)
        stage.setFocusRegions([])
        #expect(findAllRegionControls(in: stage).isEmpty)
        #expect((stage.accessibilityElements?.count ?? 0) == 1)
    }

    @Test func cameraStyleRenderingKeepsNoFillAndStableScreenGeometryAcrossZoom() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        preview.setImage(try testPixels(width: 3000, height: 2000))
        let af = makeRegion(
            id: "clove.detail.region.af.0", kind: .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16))
        let eye = makeRegion(
            id: "clove.detail.region.face.1-0", kind: .eye,
            normalized: NormalizedRegion(x: 0.625, y: 0.29, width: 0.08, height: 0.08))
        preview.setFocusRegions([af, eye], inspectedRegionID: af.id)
        preview.setNeedsLayout()
        preview.layoutIfNeeded()

        let controls = findAllRegionControls(in: preview)
        #expect(controls.count == 2)
        let afControl = try #require(controls.first { $0.region.id == af.id })
        let eyeControl = try #require(controls.first { $0.region.id == eye.id })

        #expect(!afControl.hasFill)
        #expect(!eyeControl.hasFill)
        #expect(
            abs(afControl.primaryStrokeWidth - DetailFocusRegionControl.selectedScreenStrokeWidth)
                < 0.01)
        #expect(
            abs(eyeControl.primaryStrokeWidth - DetailFocusRegionControl.normalScreenStrokeWidth)
                < 0.01)
        #expect(
            abs(eyeControl.visualFrameInSuperview.width - DetailFocusRegionControl.eyeScreenSide)
                < 0.01)
        #expect(
            abs(eyeControl.visualFrameInSuperview.height - DetailFocusRegionControl.eyeScreenSide)
                < 0.01)
        #expect(
            eyeControl.frame.width >= DetailFocusRegionControl.minimumActionableScreenTarget - 0.01)
        #expect(
            eyeControl.frame.height >= DetailFocusRegionControl.minimumActionableScreenTarget - 0.01
        )

        preview.apply(DetailZoomCommand(id: 1, kind: .scale(3, anchor: eye.centre)))
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        // At 3x scrollView zoom, local stroke width and visual eye size scale down by 3x so
        // screen-space stroke (~1.5pt / ~1.25pt), eye square (~16pt), and hit target (>=44pt)
        // stay constant.
        #expect(
            abs(
                afControl.primaryStrokeWidth * 3
                    - DetailFocusRegionControl.selectedScreenStrokeWidth) < 0.05)
        #expect(
            abs(
                eyeControl.primaryStrokeWidth * 3 - DetailFocusRegionControl.normalScreenStrokeWidth
            ) < 0.05)
        #expect(
            abs(
                eyeControl.visualFrameInSuperview.width * 3 - DetailFocusRegionControl.eyeScreenSide
            ) < 0.1)
        #expect(
            eyeControl.frame.width * 3 >= DetailFocusRegionControl.minimumActionableScreenTarget
                - 0.5)
    }

    @Test func competingExpandedTargetsResolveDeterministicallyToNearestVisualCentre() throws {
        let preview = DetailZoomContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        preview.setImage(try testPixels(width: 3000, height: 2000))
        let leftEye = makeRegion(
            id: "left", kind: .eye,
            normalized: NormalizedRegion(x: 0.45, y: 0.50, width: 0.02, height: 0.02))
        let rightEye = makeRegion(
            id: "right", kind: .eye,
            normalized: NormalizedRegion(x: 0.51, y: 0.50, width: 0.02, height: 0.02))
        preview.setFocusRegions([leftEye, rightEye])
        preview.setNeedsLayout()
        preview.layoutIfNeeded()

        let controls = findAllRegionControls(in: preview)
        let left = try #require(controls.first { $0.region.id == "left" })
        let right = try #require(controls.first { $0.region.id == "right" })
        let imageView = try #require(left.superview)

        let nearerLeft = CGPoint(x: left.center.x + 2, y: left.center.y)
        let nearerRight = CGPoint(x: right.center.x - 2, y: right.center.y)
        #expect(imageView.hitTest(nearerLeft, with: nil) === left)
        #expect(imageView.hitTest(nearerRight, with: nil) === right)
    }

    @Test func unavailableAndTinyRegionsAreExplicitAndNotActionable() {
        let identity = photo("unsupported")
        let noMetadata = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))
        var state = DetailFocusRegionState()
        state.begin(for: identity)
        state.finish(
            makeAnalysis(autofocus: noMetadata, faces: .unavailable(.noFacesDetected)),
            for: identity)
        #expect(state.regions.isEmpty)
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(
                    face: .noFacesDetected, missingAutofocusMetadata: true))

        let tiny = RegionSharpnessEvidence(
            kind: .cameraAutofocus, groupIndex: nil,
            region: NormalizedRegion(x: 0.1, y: 0.1, width: 0.001, height: 0.001),
            score: nil, unavailableBecause: .regionTooSmall)
        state.begin(for: identity)
        state.receiveAutofocus(.regions([tiny]), for: identity)
        state.finish(
            makeAnalysis(autofocus: .regions([tiny]), faces: .unavailable(.noFacesDetected)),
            for: identity)
        #expect(state.regions.count == 1)
        #expect(!state.regions[0].isActionable)
        #expect(state.regions[0].unavailableAccessibilityDescription?.contains("too small") == true)
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(
                    face: .noFacesDetected, missingAutofocusMetadata: false))
    }

    @Test func navigationRejectsEarlyAndFinalResultsForTheOldPhoto() {
        let first = photo("first")
        let second = photo("second")
        let autofocus = RegionSharpnessPathResult.regions([makeEvidence(.cameraAutofocus)])
        let noMetadata = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))
        var state = DetailFocusRegionState()
        state.begin(for: first)
        state.finish(
            makeAnalysis(autofocus: noMetadata, faces: .unavailable(.noFacesDetected)),
            for: first)
        #expect(!state.resultIndicators.isEmpty)

        // Switching photos clears indicators immediately and rejects stale callbacks.
        state.begin(for: second)
        #expect(state.resultIndicators.isEmpty)
        state.receiveAutofocus(noMetadata, for: first)
        state.finish(makeAnalysis(autofocus: autofocus, faces: .regions([])), for: first)
        #expect(state.photo == second)
        #expect(state.regions.isEmpty)
        #expect(state.resultIndicators.isEmpty)
        state.finish(nil, for: second)
        #expect(state.resultIndicators.isEmpty)
    }

    @Test func resultIndicatorsHandleSuppressedFacesFailuresCancellationsAndCoexistence() {
        let photoID = photo("indicator-rules")
        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))

        // 1. Face/eye evidence completely suppressed on-photo by overlapping AF still shows
        // the positive face indicator.
        let af = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.20, y: 0.20, width: 0.20, height: 0.20))
        let suppressedFace = makeEvidence(
            .face, group: 0,
            normalized: NormalizedRegion(x: 0.22, y: 0.22, width: 0.16, height: 0.16))
        let suppressedEye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.25, y: 0.26, width: 0.04, height: 0.04))

        var state = DetailFocusRegionState()
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: .regions([af]), faces: .regions([suppressedFace, suppressedEye])),
            for: photoID)
        #expect(state.regions.map(\.kind) == [.autofocus])
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(face: .detected, missingAutofocusMetadata: false))
        #expect(state.resultIndicators(visible: false).isEmpty)

        // 2. Eye-only result counts as face/eye detection; missing AF coexists with positive face.
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: noAF, faces: .regions([suppressedEye])),
            for: photoID)
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(face: .detected, missingAutofocusMetadata: true))

        // 3. Empty regions, faceDetectionFailed, previewFailed stay quiet for their paths.
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: .unavailable(.previewFailed(.cannotOpen)),
                faces: .regions([])),
            for: photoID)
        #expect(state.resultIndicators.isEmpty)

        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: noAF,
                faces: .unavailable(.faceDetectionFailed("vision-error"))),
            for: photoID)
        #expect(
            state.resultIndicators
                == DetailFocusResultIndicators(face: nil, missingAutofocusMetadata: true))

        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: .unavailable(.previewFailed(.noUsablePreview)),
                faces: .unavailable(.previewFailed(.noUsablePreview))),
            for: photoID)
        #expect(state.resultIndicators.isEmpty)

        // 4. Cancellation after early noAF result suppresses everything cleanly.
        state.begin(for: photoID)
        state.receiveAutofocus(noAF, for: photoID)
        #expect(state.resultIndicators.missingAutofocusMetadata)
        state.finish(nil, for: photoID)
        #expect(state.resultIndicators.isEmpty)
    }

    @Test func resultIndicatorSymbolsExistOnIOSAndRenderNonEmptyPixels() throws {
        #expect(UIImage(systemName: DetailFocusFaceIndicator.detected.systemImageName) != nil)
        #expect(
            UIImage(systemName: DetailFocusFaceIndicator.noFacesDetected.systemImageName) != nil)
        #expect(UIImage(systemName: "viewfinder") != nil)

        let glyphRenderer = ImageRenderer(
            content: SlashedViewfinderGlyph().foregroundStyle(Color.white).padding(4))
        glyphRenderer.scale = 2
        let glyphImage = try #require(glyphRenderer.cgImage)
        #expect(hasVisiblePixels(in: glyphImage))

        let indicators = DetailFocusResultIndicators(
            face: .detected, missingAutofocusMetadata: true)
        let viewRenderer = ImageRenderer(
            content: DetailFocusResultIndicatorsView(
                indicators: indicators, usesPhotoBacking: true, language: .english))
        viewRenderer.scale = 2
        let badgeImage = try #require(viewRenderer.cgImage)
        #expect(hasVisiblePixels(in: badgeImage))
    }

    @Test func resultIndicatorsBackingGeometryFitsCompactlyAndPassesThroughHits() {
        let oneIcon = DetailFocusResultIndicators(face: .detected, missingAutofocusMetadata: false)
        let twoIcons = DetailFocusResultIndicators(
            face: .noFacesDetected, missingAutofocusMetadata: true)
        let empty = DetailFocusResultIndicators(face: nil, missingAutofocusMetadata: false)

        #expect(
            !DetailFocusResultIndicators.coversPhotoPixels(
                indicators: empty, scale: 1, imagePixels: CGSize(width: 3000, height: 2000),
                viewSize: CGSize(width: 400, height: 600)))

        // Portrait photo fills iPhone stage -> badge covers photo pixels.
        #expect(
            DetailFocusResultIndicators.coversPhotoPixels(
                indicators: oneIcon, scale: 1, imagePixels: CGSize(width: 2000, height: 3000),
                viewSize: CGSize(width: 400, height: 600)))

        // Landscape photo centered inside tall portrait stage -> top-leading corner is matte.
        #expect(
            !DetailFocusResultIndicators.coversPhotoPixels(
                indicators: twoIcons, scale: 1, imagePixels: CGSize(width: 3000, height: 2000),
                viewSize: CGSize(width: 400, height: 600)))

        // Portrait photo centered inside wide landscape iPad/Duo viewport -> leading corner is matte.
        #expect(
            !DetailFocusResultIndicators.coversPhotoPixels(
                indicators: twoIcons, scale: 1, imagePixels: CGSize(width: 2000, height: 3000),
                viewSize: CGSize(width: 700, height: 600)))

        // Zooming past fit scale assumes photo pixels occupy the corner.
        #expect(
            DetailFocusResultIndicators.coversPhotoPixels(
                indicators: twoIcons, scale: 1.5, imagePixels: CGSize(width: 3000, height: 2000),
                viewSize: CGSize(width: 400, height: 600)))

        let overlay = DetailFocusResultIndicatorsView(
            indicators: twoIcons, usesPhotoBacking: true, language: .english)
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear
        let measured = host.sizeThatFits(in: CGSize(width: 400, height: 400))
        #expect(measured == CGSize(width: 48, height: 22))

        let singleHost = UIHostingController(
            rootView: DetailFocusResultIndicatorsView(
                indicators: oneIcon, usesPhotoBacking: true, language: .english))
        singleHost.view.backgroundColor = .clear
        #expect(
            singleHost.sizeThatFits(in: CGSize(width: 400, height: 400))
                == CGSize(width: 22, height: 22))
    }

    @Test func resultIndicatorsRenderIndividual22PtPhotoSquaresAndSecondaryUnboxedTint() throws {
        #expect(DetailFocusResultIndicatorsView.tileSize == 22)
        #expect(DetailFocusResultIndicatorsView.tileCornerRadius == 5)
        #expect(DetailFocusResultIndicatorsView.tileGap == 4)
        #expect(DetailFocusResultIndicatorsView.photoBackingOpacity == 0.68)

        let twoIcons = DetailFocusResultIndicators(
            face: .detected, missingAutofocusMetadata: true)
        let oneIcon = DetailFocusResultIndicators(
            face: .noFacesDetected, missingAutofocusMetadata: false)
        #expect(
            DetailFocusResultIndicatorsView.layoutSize(for: oneIcon)
                == CGSize(width: 22, height: 22))
        #expect(
            DetailFocusResultIndicatorsView.layoutSize(for: twoIcons)
                == CGSize(width: 48, height: 22))

        for theme in [CloveTheme.light, CloveTheme.dark, CloveTheme.nord] {
            let expectedSecondary = try renderedColourPixel(
                Color.clove.text.secondary, theme: theme)
            let expectedPrimary = try renderedColourPixel(Color.clove.text.primary, theme: theme)
            let expectedFocusOutline = try renderedColourPixel(
                Color.clove.focus.outline, theme: theme)

            // 1. Boxed over photo pixels: two independent 22 × 22 rounded squares (r = 5),
            //    #000 @ 68% scrim, 4 pt transparent gap, white focus-outline glyphs.
            let boxedRenderer = ImageRenderer(
                content: DetailFocusResultIndicatorsView(
                    indicators: twoIcons, usesPhotoBacking: true, language: .english
                )
                .environment(\.cloveTheme, theme))
            boxedRenderer.scale = 2
            let boxedImage = try #require(boxedRenderer.cgImage)
            #expect(boxedImage.width == 96)
            #expect(boxedImage.height == 44)
            let boxedPixels = try rgbaPixels(from: boxedImage)

            // Rounded corner (r = 5): outermost corner is transparent; inside corner edge is #000 @ 68%.
            #expect(boxedPixels.pixel(x: 0, y: 0).a == 0)
            #expect(boxedPixels.pixel(x: 43, y: 0).a == 0)
            #expect(boxedPixels.pixel(x: 52, y: 0).a == 0)
            #expect(boxedPixels.pixel(x: 95, y: 43).a == 0)

            let scrimSamples = [(5, 5), (38, 5), (57, 5), (90, 38)]
            for (sx, sy) in scrimSamples {
                let px = boxedPixels.pixel(x: sx, y: sy)
                #expect(px.r == 0 && px.g == 0 && px.b == 0)
                #expect(abs(Int(px.a) - 173) <= 4)
            }

            // 4 pt gap (x = 44..<52 at 2x) stays completely transparent across full height.
            for y in 0..<44 {
                for x in 45..<51 {
                    #expect(boxedPixels.pixel(x: x, y: y).a == 0)
                }
            }

            // White focus-outline glyph pixels appear inside both tiles.
            let hasWhiteFaceGlyph = (8..<36).contains { y in
                (8..<36).contains { x in
                    let px = boxedPixels.pixel(x: x, y: y)
                    return px.a == 255 && colorsClose(px, expectedFocusOutline, tolerance: 8)
                }
            }
            let hasWhiteAFGlyph = (8..<36).contains { y in
                (60..<88).contains { x in
                    let px = boxedPixels.pixel(x: x, y: y)
                    return px.a == 255 && colorsClose(px, expectedFocusOutline, tolerance: 8)
                }
            }
            #expect(hasWhiteFaceGlyph)
            #expect(hasWhiteAFGlyph)

            // 2. Unboxed over stage background: no backing pixels, glyphs tinted in text/secondary.
            let unboxedRenderer = ImageRenderer(
                content: DetailFocusResultIndicatorsView(
                    indicators: twoIcons, usesPhotoBacking: false, language: .english
                )
                .environment(\.cloveTheme, theme))
            unboxedRenderer.scale = 2
            let unboxedImage = try #require(unboxedRenderer.cgImage)
            #expect(unboxedImage.width == 96)
            #expect(unboxedImage.height == 44)
            let unboxedPixels = try rgbaPixels(from: unboxedImage)

            for (sx, sy) in scrimSamples {
                #expect(unboxedPixels.pixel(x: sx, y: sy).a == 0)
            }

            let unboxedOpaqueSamples = (8..<36).flatMap { y in
                (8..<36).compactMap { x -> RGBA? in
                    let px = unboxedPixels.pixel(x: x, y: y)
                    return px.a > 20 ? px : nil
                }
            }
            #expect(!unboxedOpaqueSamples.isEmpty)
            #expect(
                unboxedOpaqueSamples.contains {
                    colorsClose($0, expectedSecondary, tolerance: 10)
                })
            #expect(
                !unboxedOpaqueSamples.contains {
                    colorsClose($0, expectedPrimary, tolerance: 10)
                })
        }
    }

    @Test func doubleTapPolicyPrefersInspectedThenAutofocusThenNearestPresentedRegion() {
        let photoID = photo("double-tap-policy")
        let af = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16))
        let p0Face = makeEvidence(
            .face, group: 0,
            normalized: NormalizedRegion(x: 0.58, y: 0.20, width: 0.22, height: 0.32))
        let p0Eye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.625, y: 0.29, width: 0.05, height: 0.05))
        let p1Face = makeEvidence(
            .face, group: 1,
            normalized: NormalizedRegion(x: 0.75, y: 0.50, width: 0.15, height: 0.20))

        var state = DetailFocusRegionState()
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(
                autofocus: .regions([af]),
                faces: .regions([p0Face, p0Eye, p1Face])),
            for: photoID)

        // Single AF wins over eye/face even when tapping much closer to Person 0's eye.
        let nearEye = UnitPoint(x: 0.66, y: 0.32)
        #expect(
            state.preferredDoubleTapRegion(at: nearEye, visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.af.0")

        // An already-inspected region takes highest priority over AF.
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.1, y: 0.1), visible: true,
                inspectedRegionID: "clove.detail.region.face.2-1")?.id
                == "clove.detail.region.face.2-1")

        // Session toggle Off suppresses region selection so double-tap zooms to the tap point.
        #expect(
            state.preferredDoubleTapRegion(at: nearEye, visible: false, inspectedRegionID: nil)
                == nil)

        // Without AF, multiple people resolve deterministically: nearest to tap, then first presented.
        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: noAF, faces: .regions([p0Face, p0Eye, p1Face])),
            for: photoID)
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.80, y: 0.60), visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.face.2-1")

        // Symmetric two-person midpoint breaks ties deterministically by presentation order.
        let leftPerson = makeEvidence(
            .face, group: 0,
            normalized: NormalizedRegion(x: 0.15, y: 0.40, width: 0.10, height: 0.20))
        let rightPerson = makeEvidence(
            .face, group: 1,
            normalized: NormalizedRegion(x: 0.75, y: 0.40, width: 0.10, height: 0.20))
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: noAF, faces: .regions([leftPerson, rightPerson])),
            for: photoID)
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.50, y: 0.50), visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.face.0-0")
    }

    @Test func doubleTapPolicySkipsUnavailableRegionsAndHandlesMultipleAutofocusRegions() {
        let photoID = photo("double-tap-unavailable")
        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))
        var state = DetailFocusRegionState()
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: noAF, faces: .unavailable(.noFacesDetected)),
            for: photoID)
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.5, y: 0.5), visible: true, inspectedRegionID: nil) == nil)

        // Only tiny unavailable AF -> falls back to tap point (nil).
        let tinyAF = RegionSharpnessEvidence(
            kind: .cameraAutofocus, groupIndex: nil,
            region: NormalizedRegion(x: 0.1, y: 0.1, width: 0.005, height: 0.005),
            score: nil, unavailableBecause: .regionTooSmall)
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: .regions([tinyAF]), faces: .unavailable(.noFacesDetected)),
            for: photoID)
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.1, y: 0.1), visible: true, inspectedRegionID: nil) == nil)

        // Tiny unavailable AF + actionable eye -> picks the actionable eye.
        let eye = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.60, y: 0.30, width: 0.05, height: 0.05))
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: .regions([tinyAF]), faces: .regions([eye])),
            for: photoID)
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.1, y: 0.1), visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.face.0-0")

        // Multiple actionable AF regions -> picks the AF region nearest to the tap point.
        let leftAF = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.15, y: 0.45, width: 0.10, height: 0.10))
        let rightAF = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.75, y: 0.45, width: 0.10, height: 0.10))
        state.begin(for: photoID)
        state.finish(
            makeAnalysis(autofocus: .regions([leftAF, rightAF]), faces: .regions([eye])),
            for: photoID)
        #expect(
            state.preferredDoubleTapRegion(
                at: UnitPoint(x: 0.78, y: 0.50), visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.af.1")
    }

    @Test func doubleTapStageConversionUsesCentreForBlankSpaceAndRealPointInsidePhoto() throws {
        // Portrait photo inside a wide stage (pillarboxed left and right).
        let portraitStage = DetailZoomContainerView(
            frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        portraitStage.setImage(try testPixels(width: 2000, height: 3000))
        portraitStage.setNeedsLayout()
        portraitStage.layoutIfNeeded()

        let portraitRect = portraitStage.imageRectAtFit()
        #expect(portraitRect.minX > 100)
        #expect(portraitStage.bounds.maxX - portraitRect.maxX > 100)

        let leftBlank = portraitStage.doubleTapLocation(at: CGPoint(x: 20, y: 250))
        #expect(leftBlank.imagePoint == nil)
        #expect(leftBlank.zoomAnchor == .center)
        #expect(leftBlank.proximityAnchor.x == 0)
        #expect(abs(leftBlank.proximityAnchor.y - 0.5) < 0.001)

        let rightBlank = portraitStage.doubleTapLocation(at: CGPoint(x: 580, y: 250))
        #expect(rightBlank.imagePoint == nil)
        #expect(rightBlank.zoomAnchor == .center)
        #expect(rightBlank.proximityAnchor.x == 1)
        #expect(abs(rightBlank.proximityAnchor.y - 0.5) < 0.001)

        let insideNearLeft = portraitStage.doubleTapLocation(
            at: CGPoint(x: portraitRect.minX + 4, y: 250))
        #expect(insideNearLeft.imagePoint != nil)
        #expect(insideNearLeft.zoomAnchor.x > 0 && insideNearLeft.zoomAnchor.x < 0.05)

        let insideNearRight = portraitStage.doubleTapLocation(
            at: CGPoint(x: portraitRect.maxX - 4, y: 250))
        #expect(insideNearRight.imagePoint != nil)
        #expect(insideNearRight.zoomAnchor.x > 0.95 && insideNearRight.zoomAnchor.x < 1)

        var delivered: [DetailDoubleTapLocation] = []
        portraitStage.onDoubleTap = { delivered.append($0) }
        portraitStage.doubleTap(at: CGPoint(x: 20, y: 250))
        #expect(delivered == [leftBlank])

        portraitStage.setDoubleTapEnabled(false)
        portraitStage.doubleTap(at: CGPoint(x: 580, y: 250))
        #expect(delivered.count == 1)

        // Landscape photo inside a tall stage (letterboxed top and bottom).
        let landscapeStage = DetailZoomContainerView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        landscapeStage.setImage(try testPixels(width: 3000, height: 2000))
        landscapeStage.setNeedsLayout()
        landscapeStage.layoutIfNeeded()

        let landscapeRect = landscapeStage.imageRectAtFit()
        #expect(landscapeRect.minY > 100)
        #expect(landscapeStage.bounds.maxY - landscapeRect.maxY > 100)

        let topBlank = landscapeStage.doubleTapLocation(at: CGPoint(x: 120, y: 40))
        #expect(topBlank.imagePoint == nil)
        #expect(topBlank.zoomAnchor == .center)
        #expect(abs(topBlank.proximityAnchor.x - 0.3) < 0.001)
        #expect(topBlank.proximityAnchor.y == 0)

        let bottomBlank = landscapeStage.doubleTapLocation(at: CGPoint(x: 320, y: 560))
        #expect(bottomBlank.imagePoint == nil)
        #expect(bottomBlank.zoomAnchor == .center)
        #expect(abs(bottomBlank.proximityAnchor.x - 0.8) < 0.001)
        #expect(bottomBlank.proximityAnchor.y == 1)

        let insideNearTop = landscapeStage.doubleTapLocation(
            at: CGPoint(x: 120, y: landscapeRect.minY + 4))
        #expect(insideNearTop.imagePoint != nil)
        #expect(insideNearTop.zoomAnchor.y > 0 && insideNearTop.zoomAnchor.y < 0.05)

        // Multiple regions still break ties using the blank tap's clamped proximity anchor.
        let photoID = photo("blank-area-tie-break")
        let leftAF = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.15, y: 0.45, width: 0.10, height: 0.10))
        let rightAF = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.75, y: 0.45, width: 0.10, height: 0.10))
        var regionState = DetailFocusRegionState()
        regionState.begin(for: photoID)
        regionState.finish(
            makeAnalysis(autofocus: .regions([leftAF, rightAF]), faces: .regions([])),
            for: photoID)
        #expect(
            regionState.preferredDoubleTapRegion(
                at: leftBlank.proximityAnchor, visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.af.0")
        #expect(
            regionState.preferredDoubleTapRegion(
                at: rightBlank.proximityAnchor, visible: true, inspectedRegionID: nil)?.id
                == "clove.detail.region.af.1")
    }

    @Test func scorelessEvidenceIsActionableAndNormalizedGeometryPreservesUnavailability() {
        let valid = DetailFocusRegion(
            id: "clove.detail.region.af.0",
            evidence: RegionSharpnessEvidence(
                kind: .cameraAutofocus,
                groupIndex: nil,
                region: NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16),
                score: nil,
                unavailableBecause: nil))
        #expect(valid.isActionable)
        #expect(valid.unavailableReason == nil)

        let tiny = DetailFocusRegion(
            id: "clove.detail.region.face.0-0",
            evidence: RegionSharpnessEvidence(
                kind: .eye,
                groupIndex: 0,
                region: NormalizedRegion(x: 0.5, y: 0.5, width: 0.002, height: 0.004),
                score: nil,
                unavailableBecause: nil))
        #expect(!tiny.isActionable)
        #expect(tiny.unavailableReason == RegionScoreUnavailable.regionTooSmall.rawValue)

        let outside = DetailFocusRegion(
            id: "clove.detail.region.af.1",
            evidence: RegionSharpnessEvidence(
                kind: .cameraAutofocus,
                groupIndex: nil,
                region: NormalizedRegion(x: 1.2, y: 0.2, width: 0.1, height: 0.1),
                score: nil,
                unavailableBecause: nil))
        #expect(!outside.isActionable)
        #expect(outside.unavailableReason == RegionScoreUnavailable.regionOutsideImage.rawValue)

        let partialTiny = DetailFocusRegion(
            id: "clove.detail.region.af.2",
            evidence: RegionSharpnessEvidence(
                kind: .cameraAutofocus,
                groupIndex: nil,
                region: NormalizedRegion(x: 0.999, y: 0.5, width: 0.1, height: 0.1),
                score: nil,
                unavailableBecause: nil))
        #expect(!partialTiny.isActionable)
        #expect(partialTiny.unavailableReason == RegionScoreUnavailable.regionTooSmall.rawValue)

        let partialValid = DetailFocusRegion(
            id: "clove.detail.region.af.3",
            evidence: RegionSharpnessEvidence(
                kind: .cameraAutofocus,
                groupIndex: nil,
                region: NormalizedRegion(x: -0.05, y: 0.5, width: 0.1, height: 0.1),
                score: nil,
                unavailableBecause: nil))
        #expect(partialValid.isActionable)
    }

    @Test func focusTrackingStateHandlesTransitionsAsyncAndManualPanThresholds() {
        let photoA = photo("group-a")
        let photoB = photo("group-b")
        let photoC = photo("group-c")
        let anchorA = DetailZoomAnchor(x: 0.30, y: 0.35)
        let afB = makeEvidence(
            .cameraAutofocus,
            normalized: NormalizedRegion(x: 0.64, y: 0.56, width: 0.12, height: 0.16))
        let eyeB = makeEvidence(
            .eye, group: 0,
            normalized: NormalizedRegion(x: 0.15, y: 0.20, width: 0.05, height: 0.05))
        let noAF = RegionSharpnessPathResult.unavailable(
            .noAutofocusMetadata(
                AutofocusMetadataEvidence(inspected: [], cameraMake: "Test", exifOrientation: 1)))

        var tracking = DetailFocusTrackingState()
        #expect(!tracking.isTracking)
        #expect(tracking.pendingRecenter == nil)

        // 1. Focus-region zoom enables tracking; stepping with no regions ready records pending.
        tracking.beginTracking()
        #expect(tracking.isTracking)
        tracking.preparePhotoTransition(
            to: photoB, keepsPosition: true, hasZoomedState: true, referenceAnchor: anchorA)
        #expect(tracking.pendingRecenter?.photo == photoB)

        // If pixels are not shown yet, async arrival does not prematurely consume pending recenter.
        var regionsB = DetailFocusRegionState()
        regionsB.begin(for: photoB)
        regionsB.receiveAutofocus(.regions([afB]), for: photoB)
        #expect(
            tracking.resolveAsyncRecenter(
                for: photoB, isFinalResult: false, focusRegions: regionsB, showsFocusRegions: true,
                isShowingPhoto: false, isZoomedFullResolution: true) == .ignore)
        #expect(tracking.pendingRecenter?.photo == photoB)

        // Once pixels arrive, opening resolves directly to AF and satisfies pending recenter.
        let openingB = tracking.resolveOpening(
            for: photoB, fallbackAnchor: anchorA, focusRegions: regionsB, showsFocusRegions: true)
        guard case .focusRegion(let openedRegion) = openingB else {
            Issue.record("Expected opening to resolve immediately to photoB AF region")
            return
        }
        #expect(openedRegion.id == "clove.detail.region.af.0")
        #expect(tracking.pendingRecenter == nil)

        // 2. Async AF miss leaves pending active so finish can still center on eye/face.
        tracking.preparePhotoTransition(
            to: photoB, keepsPosition: true, hasZoomedState: true, referenceAnchor: anchorA)
        var delayedEyeB = DetailFocusRegionState()
        delayedEyeB.begin(for: photoB)
        delayedEyeB.receiveAutofocus(noAF, for: photoB)
        #expect(
            tracking.resolveAsyncRecenter(
                for: photoB, isFinalResult: false, focusRegions: delayedEyeB,
                showsFocusRegions: true, isShowingPhoto: true, isZoomedFullResolution: true)
                == .ignore)
        #expect(tracking.pendingRecenter?.photo == photoB)

        delayedEyeB.finish(
            makeAnalysis(autofocus: noAF, faces: .regions([eyeB])), for: photoB)
        let eyeResult = tracking.resolveAsyncRecenter(
            for: photoB, isFinalResult: true, focusRegions: delayedEyeB, showsFocusRegions: true,
            isShowingPhoto: true, isZoomedFullResolution: true)
        guard case .recenter(let recenteredEye) = eyeResult else {
            Issue.record("Expected finish to recenter onto eye region")
            return
        }
        #expect(recenteredEye.id == "clove.detail.region.face.0-0")
        #expect(tracking.pendingRecenter == nil)
        #expect(tracking.isTracking)

        // 3. No actionable regions on finish clears inspection while keeping tracking alive for C.
        tracking.preparePhotoTransition(
            to: photoC, keepsPosition: true, hasZoomedState: true, referenceAnchor: anchorA)
        var emptyC = DetailFocusRegionState()
        emptyC.begin(for: photoC)
        emptyC.finish(
            makeAnalysis(autofocus: noAF, faces: .unavailable(.noFacesDetected)), for: photoC)
        #expect(
            tracking.resolveAsyncRecenter(
                for: photoC, isFinalResult: true, focusRegions: emptyC, showsFocusRegions: true,
                isShowingPhoto: true, isZoomedFullResolution: true)
                == .clearInspectionKeepAnchor)
        #expect(tracking.pendingRecenter == nil)
        #expect(tracking.isTracking)

        // 4. Leaving Group Focus clears tracking.
        tracking.preparePhotoTransition(
            to: photoA, keepsPosition: false, hasZoomedState: true, referenceAnchor: anchorA)
        #expect(!tracking.isTracking)
        #expect(tracking.pendingRecenter == nil)

        // 5. Edge-clamped focus region with zero user movement does not count as manual pan,
        //    while panning past 6 content points clears even on high-res scales.
        let viewSize = CGSize(width: 1024, height: 768)
        let imagePixels = CGSize(width: 8192, height: 5464)
        let cornerTarget = DetailZoomAnchor(x: 0.04, y: 0.04)
        let scale: CGFloat = 4.0
        let clampedExpected = DetailFocusTrackingState.expectedViewportAnchor(
            for: cornerTarget, scale: scale, imagePixels: imagePixels, viewSize: viewSize)
        #expect(clampedExpected.x > 0.10)
        #expect(
            !DetailFocusTrackingState.didManuallyPan(
                snapshot: DetailZoomSnapshot(scale: scale, anchor: clampedExpected),
                fromTargetAnchor: cornerTarget, imagePixels: imagePixels, viewSize: viewSize))
        let tinyJitter = DetailZoomAnchor(
            x: clampedExpected.x + 2 / (1024 * scale), y: clampedExpected.y)
        #expect(
            !DetailFocusTrackingState.didManuallyPan(
                snapshot: DetailZoomSnapshot(scale: scale, anchor: tinyJitter),
                fromTargetAnchor: cornerTarget, imagePixels: imagePixels, viewSize: viewSize))
        let realPan = DetailZoomAnchor(
            x: clampedExpected.x + 12 / (1024 * scale), y: clampedExpected.y)
        #expect(
            DetailFocusTrackingState.didManuallyPan(
                snapshot: DetailZoomSnapshot(scale: scale, anchor: realPan),
                fromTargetAnchor: cornerTarget, imagePixels: imagePixels, viewSize: viewSize))
    }

    private func makeRegion(
        id: String = "test-region",
        kind: SharpnessRegionKind = .cameraAutofocus,
        group: Int? = nil,
        normalized: NormalizedRegion
    ) -> DetailFocusRegion {
        DetailFocusRegion(
            id: id, evidence: makeEvidence(kind, group: group, normalized: normalized))
    }

    private func makeEvidence(
        _ kind: SharpnessRegionKind,
        group: Int? = nil,
        normalized: NormalizedRegion = NormalizedRegion(
            x: 0.24, y: 0.27, width: 0.12, height: 0.16),
        tenengradMeanSquare: Double = 1
    ) -> RegionSharpnessEvidence {
        RegionSharpnessEvidence(
            kind: kind, groupIndex: group, region: normalized,
            score: RegionSharpnessScore(
                tenengradMeanSquare: tenengradMeanSquare, sampledPixels: 64,
                sampledWidth: 8, sampledHeight: 8),
            unavailableBecause: nil)
    }

    private func makeAnalysis(
        autofocus: RegionSharpnessPathResult,
        faces: RegionSharpnessPathResult
    ) -> RegionSharpnessAnalysis {
        RegionSharpnessAnalysis(
            autofocus: autofocus, faces: faces, acquisitionFailure: nil,
            timings: RegionSharpnessTimings())
    }

    private func photo(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(
            folderID: FolderIdentity(rawValue: "focus-tests"), relativeFolderPath: "", stem: stem)
    }

    private func testPixels(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    private func hasVisiblePixels(in image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for offset in stride(from: 3, to: bytes.count, by: 4) {
            if bytes[offset] > 0 { return true }
        }
        return false
    }

    private func findRegionControl(in view: UIView) -> DetailFocusRegionControl? {
        findAllRegionControls(in: view).first
    }

    private func findAllRegionControls(in view: UIView) -> [DetailFocusRegionControl] {
        var found: [DetailFocusRegionControl] = []
        if let control = view as? DetailFocusRegionControl { found.append(control) }
        for child in view.subviews {
            found.append(contentsOf: findAllRegionControls(in: child))
        }
        return found
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

private final class DetailRegionPan: UIPanGestureRecognizer {
    var travel: CGPoint = .zero
    var sampleState: UIGestureRecognizer.State = .began

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { travel }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}

private final class DetailRegionTouch: UITouch {
    private let touchedRegion: UIView

    init(view: UIView) {
        touchedRegion = view
        super.init()
    }

    override var view: UIView? { touchedRegion }

    override func location(in view: UIView?) -> CGPoint { touchedRegion.center }
}
