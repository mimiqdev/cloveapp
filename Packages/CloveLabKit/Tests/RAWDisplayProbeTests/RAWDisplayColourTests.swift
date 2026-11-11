import Testing

@testable import RAWDisplayProbe

@Suite(.serialized)
struct RAWDisplayColourTests {
    /// Sharma, Wu, Dalal (2005), table 1: CIEDE2000 reference pairs.
    @Test func deltaE2000MatchesPublishedReferencePairs() {
        let pairs: [(LabColour, LabColour, Double)] = [
            (LabColour(l: 50, a: 2.6772, b: -79.7751), LabColour(l: 50, a: 0, b: -82.7485), 2.0425),
            (LabColour(l: 50, a: 3.1571, b: -77.2803), LabColour(l: 50, a: 0, b: -82.7485), 2.8615),
            (LabColour(l: 50, a: 2.8361, b: -74.0200), LabColour(l: 50, a: 0, b: -82.7485), 3.4412),
            (
                LabColour(l: 50, a: -1.3802, b: -84.2814), LabColour(l: 50, a: 0, b: -82.7485),
                1.0000
            ),
            (LabColour(l: 50, a: 0, b: 0), LabColour(l: 50, a: -1, b: 2), 2.3669),
        ]
        for (first, second, expected) in pairs {
            #expect(abs(RAWDisplayColour.deltaE2000(first, second) - expected) < 0.0001)
            // The metric is symmetric; the reference values must hold both ways.
            #expect(abs(RAWDisplayColour.deltaE2000(second, first) - expected) < 0.0001)
        }
    }

    @Test func identicalImagesHaveZeroColourDifference() throws {
        let image = try solidImage(width: 16, height: 12, red: 40, green: 90, blue: 200)
        let difference = try #require(RAWDisplayColour.compare(image, image))
        #expect(difference.mean == 0)
        #expect(difference.p95 == 0)
        #expect(difference.maximum == 0)
        #expect(difference.samples > 0)
        #expect(difference.width == 16 && difference.height == 12)
    }

    /// Solid black against solid white: CIEDE2000 is exactly 100 here, because both
    /// colours are achromatic and the lightness weight is 1 at the midpoint.
    @Test func solidBlackAndWhiteDifferByOneHundred() throws {
        let black = try solidImage(width: 8, height: 8)
        let white = try solidImage(width: 8, height: 8, red: 255, green: 255, blue: 255)
        let difference = try #require(RAWDisplayColour.compare(black, white))
        #expect(abs(difference.mean - 100) < 0.001)
        #expect(abs(difference.p95 - 100) < 0.001)
        #expect(abs(difference.maximum - 100) < 0.001)
    }

    @Test func scaledReferenceKeepsTheRequestedSize() throws {
        let image = try solidImage(width: 32, height: 24, red: 200, green: 100, blue: 50)
        let scaled = try #require(RAWDisplayColour.scaled(image, toWidth: 8, height: 6))
        #expect(scaled.width == 8 && scaled.height == 6)
        let same = try solidImage(width: 8, height: 6, red: 200, green: 100, blue: 50)
        let difference = try #require(RAWDisplayColour.compare(scaled, same))
        #expect(difference.mean < 0.5)
    }

    @Test func differentSizesCannotBeCompared() throws {
        let first = try solidImage(width: 8, height: 8)
        let second = try solidImage(width: 8, height: 6)
        #expect(RAWDisplayColour.compare(first, second) == nil)
    }

    @Test func srgbPrimariesLandWhereLabExpectsThem() {
        let white = RAWDisplayColour.lab(red: 1, green: 1, blue: 1)
        #expect(abs(white.l - 100) < 0.01)
        #expect(abs(white.a) < 0.01 && abs(white.b) < 0.01)
        let black = RAWDisplayColour.lab(red: 0, green: 0, blue: 0)
        #expect(abs(black.l) < 0.01)
        let mid = RAWDisplayColour.lab(red: 0.5, green: 0.5, blue: 0.5)
        #expect(mid.l > 50 && mid.l < 55)
    }
}
