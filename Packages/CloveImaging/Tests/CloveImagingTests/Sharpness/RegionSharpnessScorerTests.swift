import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// Generated pixel scenes for the scorer and coordinate tests: no camera binaries, so these
/// never depend on the shared fixture cache (#208).
enum SharpnessScene {
    /// A vertical checkerboard with the given cell size — strong Sobel gradients everywhere.
    static func checkerboard(width: Int, height: Int, cell: Int) -> CGImage {
        image(width: width, height: height) { context in
            for y in 0..<height {
                for x in 0..<width {
                    let on = ((x / cell) + (y / cell)).isMultiple(of: 2)
                    context.setFillColor(
                        CGColor(gray: on ? 0.9 : 0.1, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    /// A flat image — zero gradients.
    static func flat(width: Int, height: Int) -> CGImage {
        image(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A scene sharp on one half and flat on the other, so one image holds both answers.
    /// The cells are 2 px: a perfect 1-px checkerboard sits at the Sobel kernel's Nyquist
    /// frequency and measures as flat, which is a property of the kernel, not the image.
    static func halfSharp(width: Int = 256, height: Int = 128) -> CGImage {
        image(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for x in 0..<(width / 2) {
                for y in 0..<height {
                    let on = (x / 2 + y / 2).isMultiple(of: 2)
                    context.setFillColor(CGColor(gray: on ? 0.9 : 0.1, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private static func image(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context else { fatalError("Cannot create a test bitmap") }
        draw(context)
        guard let image = context.makeImage() else { fatalError("Cannot render a test scene") }
        return image
    }
}

@Suite struct RegionSharpnessScorerTests {
    let scorer = RegionSharpnessScorer()

    @Test func texturedRegionScoresHigherThanFlatRegion() throws {
        let whole = NormalizedRegion(x: 0, y: 0, width: 1, height: 1)
        let textured = try #require(
            scorer.score(
                image: SharpnessScene.checkerboard(width: 64, height: 64, cell: 4), region: whole))
        let flat = try #require(
            scorer.score(image: SharpnessScene.flat(width: 64, height: 64), region: whole))
        #expect(textured.tenengradMeanSquare > flat.tenengradMeanSquare + 100)
        #expect(flat.tenengradMeanSquare < 1)
        // A flat region's measure is exactly zero: no gradient anywhere.
        #expect(flat.tenengradMeanSquare == 0)
    }

    @Test func sharpHalfScoresHigherThanFlatHalfOfTheSameImage() throws {
        let image = SharpnessScene.halfSharp()
        let leftHalf = NormalizedRegion(x: 0, y: 0, width: 0.5, height: 1)
        let rightHalf = NormalizedRegion(x: 0.5, y: 0, width: 0.5, height: 1)
        let sharp = try #require(scorer.score(image: image, region: leftHalf))
        let smooth = try #require(scorer.score(image: image, region: rightHalf))
        #expect(sharp.tenengradMeanSquare > smooth.tenengradMeanSquare + 100)
    }

    @Test func regionsTooSmallForTheKernelReturnNil() {
        let image = SharpnessScene.checkerboard(width: 64, height: 64, cell: 2)
        // 2×2 and smaller regions cannot hold the 3×3 kernel's interior.
        #expect(
            scorer.score(
                image: image, region: NormalizedRegion(x: 0, y: 0, width: 0.02, height: 0.02))
                == nil)
        #expect(
            scorer.score(
                image: image, region: NormalizedRegion(x: 0.5, y: 0.5, width: 0.01, height: 0.01))
                == nil)
        // A 4×4 region is the smallest measurable shape.
        #expect(
            scorer.score(
                image: image, region: NormalizedRegion(x: 0, y: 0, width: 0.0625, height: 0.0625))
                != nil)
    }

    @Test func regionOutsideTheImageReturnsNil() {
        let image = SharpnessScene.flat(width: 32, height: 32)
        // Entirely outside the frame.
        #expect(
            scorer.score(
                image: image, region: NormalizedRegion(x: 1.2, y: 1.2, width: 0.1, height: 0.1))
                == nil)
        // Degenerate.
        #expect(
            scorer.score(
                image: image, region: NormalizedRegion(x: 0.5, y: 0.5, width: 0, height: 0)) == nil)
    }

    @Test func largeRegionsAreDownsampledToTheBudget() throws {
        // A large checkerboard whose cells stay visible after downsampling; the scene is
        // 2048² rather than full-camera size because the test builds it pixel by pixel.
        let image = SharpnessScene.checkerboard(width: 2048, height: 2048, cell: 32)
        let score = try #require(
            scorer.score(image: image, region: NormalizedRegion(x: 0, y: 0, width: 1, height: 1)))
        #expect(
            score.sampledWidth * score.sampledHeight <= RegionSharpnessScorer.maximumSampledPixels)
        #expect(score.sampledWidth <= 512 && score.sampledHeight <= 512)
        #expect(score.tenengradMeanSquare > 0)
    }

    @Test func scoringIsDeterministic() throws {
        let image = SharpnessScene.checkerboard(width: 128, height: 128, cell: 8)
        let region = NormalizedRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let first = try #require(scorer.score(image: image, region: region))
        let second = try #require(scorer.score(image: image, region: region))
        #expect(first == second)
    }
}

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
        let point = displayPoint(x: centerX, y: centerY, orientation: orientation)
        return point
    }
}
