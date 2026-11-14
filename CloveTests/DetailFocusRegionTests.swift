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
        #expect(state.status == "Analyzing focus regions…")
        state.receiveAutofocus(autofocus, for: first)
        #expect(state.regions.count == 1)
        #expect(state.regions[0].kind == .autofocus)
        #expect(state.status == "Analyzing faces…")
        state.finish(makeAnalysis(autofocus: autofocus, faces: faces), for: first)
        #expect(state.retainedRegions.count == 3)
        #expect(state.regions.count == 2)
        #expect(state.regions.map(\.kind) == [.autofocus, .eye])
        #expect(state.status == nil)
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
        #expect(state.status == "No AF metadata · No faces")

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
        #expect(state.status?.contains("Tiny focus region unavailable") == true)
    }

    @Test func navigationRejectsEarlyAndFinalResultsForTheOldPhoto() {
        let first = photo("first")
        let second = photo("second")
        let autofocus = RegionSharpnessPathResult.regions([makeEvidence(.cameraAutofocus)])
        var state = DetailFocusRegionState()
        state.begin(for: first)
        state.begin(for: second)
        state.receiveAutofocus(autofocus, for: first)
        state.finish(makeAnalysis(autofocus: autofocus, faces: .regions([])), for: first)
        #expect(state.photo == second)
        #expect(state.regions.isEmpty)
        #expect(state.status == "Analyzing focus regions…")
        state.finish(nil, for: second)
        #expect(state.status == "Analysis unavailable")
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
