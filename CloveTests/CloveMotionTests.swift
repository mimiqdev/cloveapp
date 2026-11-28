import CloveCore
import CoreGraphics
import SwiftUI
import Testing

@testable import Clove

@MainActor
struct CloveMotionTests {
    @Test func reduceMotionCollapsesCurvesToInstant() {
        #expect(CloveMotion.micro(reduceMotion: false) != nil)
        #expect(CloveMotion.chrome(reduceMotion: false) != nil)
        #expect(CloveMotion.progress(reduceMotion: false) != nil)
        #expect(CloveMotion.focusArrival(reduceMotion: false) != nil)

        #expect(CloveMotion.micro(reduceMotion: true) == nil)
        #expect(CloveMotion.chrome(reduceMotion: true) == nil)
        #expect(CloveMotion.progress(reduceMotion: true) == nil)
        #expect(CloveMotion.focusArrival(reduceMotion: true) == nil)
    }

    @Test func motionTimingConstantsStayNonBlocking() {
        #expect(CloveMotion.microDuration == 0.16)
        #expect(CloveMotion.chromeDuration == 0.19)
        #expect(CloveMotion.progressDuration == 0.22)
        #expect(CloveMotion.focusArrivalDuration == 0.15)
        #expect(CloveMotion.pressScale == 0.95)
        #expect(CloveMotion.pressOpacity == 0.88)
    }

    @Test func shouldAnimateMarkChangeOnlyForSettledPhotoOrStandaloneControl() {
        let folder = FolderIdentity(rawValue: "test")
        let photoA = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "A")
        let photoB = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "B")

        #expect(CloveMotion.shouldAnimateMarkChange(settledPhotoID: photoA, currentPhotoID: photoA))
        #expect(
            !CloveMotion.shouldAnimateMarkChange(settledPhotoID: photoA, currentPhotoID: photoB))
        #expect(
            !CloveMotion.shouldAnimateMarkChange(settledPhotoID: nil, currentPhotoID: photoA))
        #expect(
            CloveMotion.shouldAnimateMarkChange(
                settledPhotoID: nil as PhotoIdentity?, currentPhotoID: nil))
        #expect(
            CloveMotion.shouldAnimateMarkChange(settledPhotoID: photoA, currentPhotoID: nil))
    }

    @Test func bloomAnchorTracksTriggerEdge() {
        // Picker placed above anchor near its right end.
        let topAnchor = CGRect(x: 300, y: 740, width: 36, height: 36)
        let aboveFrame = CGRect(x: 70, y: 678, width: 288, height: 52)
        let abovePoint = TapPickerPlacement.bloomAnchor(for: aboveFrame, anchor: topAnchor)
        #expect(abovePoint.y == 1)
        #expect(abs(abovePoint.x - (318.0 - 70.0) / 288.0) < 0.001)

        // Picker placed below anchor.
        let bottomAnchor = CGRect(x: 100, y: 80, width: 44, height: 44)
        let belowFrame = CGRect(x: 12, y: 134, width: 288, height: 52)
        let belowPoint = TapPickerPlacement.bloomAnchor(
            for: belowFrame, anchor: bottomAnchor, preferredEdge: .bottom)
        #expect(belowPoint.y == 0)

        // Picker placed to the left of vertical rail anchor.
        let railAnchor = CGRect(x: 340, y: 360, width: 44, height: 44)
        let leftFrame = CGRect(x: 278, y: 240, width: 52, height: 288)
        let leftPoint = TapPickerPlacement.bloomAnchor(
            for: leftFrame, anchor: railAnchor, preferredEdge: .leading)
        #expect(leftPoint.x == 1)
        #expect(abs(leftPoint.y - (382.0 - 240.0) / 288.0) < 0.001)

        // Picker placed to the right of anchor.
        let rightFrame = CGRect(x: 394, y: 240, width: 52, height: 288)
        let rightPoint = TapPickerPlacement.bloomAnchor(
            for: rightFrame, anchor: railAnchor, preferredEdge: .trailing)
        #expect(rightPoint.x == 0)

        // Degenerate zero frame falls back to center.
        #expect(
            TapPickerPlacement.bloomAnchor(for: .zero, anchor: topAnchor) == .center)
    }
}
