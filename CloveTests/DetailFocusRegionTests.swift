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
        var navigation: DetailEdgeZone?
        preview.onEdgeTap = { navigation = $0 }
        let swipe = DetailRegionPan()
        swipe.travel = CGPoint(x: -15, y: 0)
        #expect(preview.gestureRecognizerShouldBegin(swipe))
        preview.handleMarkingPan(swipe)
        swipe.sampleState = .changed
        swipe.travel = CGPoint(x: -180, y: 0)
        preview.handleMarkingPan(swipe)
        swipe.sampleState = .ended
        preview.handleMarkingPan(swipe)
        #expect(navigation == .next)
    }

    @Test func earlyAutofocusAppearsWhileFacesArePending() {
        let first = photo("first")
        let autofocus = RegionSharpnessPathResult.regions([makeEvidence(.cameraAutofocus)])
        let faces = RegionSharpnessPathResult.regions([
            makeEvidence(.face, group: 0), makeEvidence(.eye, group: 0),
        ])
        var state = DetailFocusRegionState()
        state.begin(for: first)
        #expect(state.status == "Analyzing focus regions…")
        state.receiveAutofocus(autofocus, for: first)
        #expect(state.regions.count == 1)
        #expect(state.regions[0].kind == .autofocus)
        #expect(state.status == "Analyzing faces…")
        state.finish(makeAnalysis(autofocus: autofocus, faces: faces), for: first)
        #expect(state.regions.count == 3)
        #expect(state.status == nil)
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

    private func makeRegion(
        kind: SharpnessRegionKind = .cameraAutofocus,
        normalized: NormalizedRegion
    ) -> DetailFocusRegion {
        DetailFocusRegion(
            id: "test-region", evidence: makeEvidence(kind, normalized: normalized))
    }

    private func makeEvidence(
        _ kind: SharpnessRegionKind,
        group: Int? = nil,
        normalized: NormalizedRegion = NormalizedRegion(x: 0.24, y: 0.27, width: 0.12, height: 0.16)
    ) -> RegionSharpnessEvidence {
        RegionSharpnessEvidence(
            kind: kind, groupIndex: group, region: normalized,
            score: RegionSharpnessScore(
                tenengradMeanSquare: 1, sampledPixels: 64, sampledWidth: 8, sampledHeight: 8),
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
        if let control = view as? DetailFocusRegionControl { return control }
        for child in view.subviews {
            if let control = findRegionControl(in: child) { return control }
        }
        return nil
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
