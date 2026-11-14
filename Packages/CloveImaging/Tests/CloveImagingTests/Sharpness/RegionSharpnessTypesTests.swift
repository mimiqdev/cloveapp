import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

@Suite struct NormalizedRegionOrientationTests {
    let region = NormalizedRegion(x: 0.2, y: 0.1, width: 0.3, height: 0.2)

    @Test func identityAndHalfTurns() {
        let identity = region.oriented(forExifOrientation: 1)
        #expect(identity == region)
        // 180°: the rectangle moves to the opposite corner, size unchanged.
        let rotated = region.oriented(forExifOrientation: 3)
        #expect(abs(rotated.width - region.width) < 1e-9)
        #expect(abs(rotated.height - region.height) < 1e-9)
        #expect(abs(rotated.x + rotated.width - (1 - region.x)) < 1e-9)
        #expect(abs(rotated.y + rotated.height - (1 - region.y)) < 1e-9)
    }

    @Test func quarterTurnsSwapAxes() {
        // 90° CW (display): a wide rectangle becomes tall.
        let rotated = region.oriented(forExifOrientation: 6)
        #expect(abs(rotated.width - region.height) < 1e-9)
        #expect(abs(rotated.height - region.width) < 1e-9)
        // The center point is preserved by an in-frame rotation about the frame center.
        #expect(
            abs(
                rotated.centerX
                    - NormalizedRegion.centerAfterRotation(
                        centerX: region.centerX, centerY: region.centerY, orientation: 6
                    ).0) < 1e-9)
    }

    @Test func rotationsPreserveTheCenterOfTheFrame() {
        // A dead-center region stays dead-center under every orientation, which is the
        // invariant the Apple SubjectArea fixture's center point must keep (orientation 6).
        let centered = NormalizedRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        for orientation in 1...8 {
            let oriented = centered.oriented(forExifOrientation: orientation)
            #expect(abs(oriented.centerX - 0.5) < 1e-9, "orientation \(orientation)")
            #expect(abs(oriented.centerY - 0.5) < 1e-9, "orientation \(orientation)")
        }
    }

    @Test func pixelRectScalesAndClips() {
        let size = CGSize(width: 1000, height: 500)
        let rect = NormalizedRegion(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
            .pixelRect(in: size)
        #expect(rect == CGRect(x: 100, y: 100, width: 500, height: 200))
        // A region hanging off the frame is clipped to the frame.
        let clipped = NormalizedRegion(x: 0.95, y: 0.95, width: 0.2, height: 0.2)
            .pixelRect(in: size)
        #expect(clipped == CGRect(x: 950, y: 475, width: 50, height: 25))
        // No overlap at all.
        #expect(
            NormalizedRegion(x: 1.5, y: 1.5, width: 0.2, height: 0.2).pixelRect(in: size) == nil)
    }

    @Test func displayPointMatchesEveryExifOrientation() {
        // The eight cases of the storage-to-display map, written out so the mapping stays
        // auditable against EXIF's definition.
        let cases: [Int: (Double, Double, Double, Double)] = [
            1: (0.25, 0.25, 0.75, 0.75),
            2: (0.75, 0.25, 0.25, 0.75),
            3: (0.75, 0.75, 0.25, 0.25),
            4: (0.25, 0.75, 0.75, 0.25),
            5: (0.25, 0.25, 0.75, 0.75),
            6: (0.75, 0.25, 0.25, 0.75),
            7: (0.75, 0.75, 0.25, 0.25),
            8: (0.25, 0.75, 0.75, 0.25),
        ]
        for (orientation, expected) in cases {
            let first = NormalizedRegion.displayPoint(x: 0.25, y: 0.25, orientation: orientation)
            let last = NormalizedRegion.displayPoint(x: 0.75, y: 0.75, orientation: orientation)
            #expect(first.0 == expected.0 && first.1 == expected.1, "orientation \(orientation)")
            #expect(last.0 == expected.2 && last.1 == expected.3, "orientation \(orientation)")
        }
    }
}

extension NormalizedRegion {
    static func centerAfterRotation(centerX: Double, centerY: Double, orientation: Int) -> (
        Double, Double
    ) {
        displayPoint(x: centerX, y: centerY, orientation: orientation)
    }
}
