import Foundation
import Testing

@testable import CloveImaging

@Suite struct ExposureFormattingTests {
    @Test(arguments: [
        (1.0 / 8000, "1/8000 s"), (1.0 / 250, "1/250 s"), (0.5, "1/2 s"),
        (0.6, "0.6 s"), (2.0, "2 s"), (1.3, "1.3 s"), (0.4, "0.4 s"),
        (1.0 / 3.0001, "1/3 s"),
    ])
    func shutterPreservesDecimalExposures(seconds: Double, expected: String) {
        #expect(
            ExposureFormatting.shutter(seconds: seconds, locale: Locale(identifier: "en_US"))
                == expected)
    }

    @Test func exposureNeverGroupsShutterISOOrFocalLength() {
        let information = ImageInformation(
            exposureSeconds: 1.0 / 8000, aperture: 2.8, iso: 12800, focalLengthMillimetres: 1200)
        #expect(
            ExposureFormatting.text(for: information, locale: Locale(identifier: "en_US"))
                == "1/8000 s · ƒ/2.8 · ISO 12800 · 1200 mm")
        #expect(
            ExposureFormatting.text(for: information, locale: Locale(identifier: "de_DE"))
                == "1/8000 s · ƒ/2,8 · ISO 12800 · 1200 mm")
        #expect(
            ExposureFormatting.shutter(seconds: 0.6, locale: Locale(identifier: "de_DE")) == "0,6 s"
        )
    }

    @Test func missingAndInvalidShutterFieldsAreOmitted() {
        #expect(ExposureFormatting.text(for: ImageInformation()) == nil)
        for seconds in [0.0, -1, .nan, .infinity] {
            #expect(ExposureFormatting.shutter(seconds: seconds) == nil)
        }
        #expect(
            ExposureFormatting.text(
                for: ImageInformation(iso: 400), locale: Locale(identifier: "en_US"))
                == "ISO 400")
    }
}
