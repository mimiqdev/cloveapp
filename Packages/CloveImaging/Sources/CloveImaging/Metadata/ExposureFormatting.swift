import Foundation

/// Pure display formatting for the read-only Info exposure row (handoff Detail).
public enum ExposureFormatting {
    /// Formats exposure metadata without grouping separators, omitting missing fields.
    public static func text(for image: ImageInformation, locale: Locale = .current) -> String? {
        let decimal = FloatingPointFormatStyle<Double>.number
            .grouping(.never).precision(.significantDigits(1...8)).locale(locale)
        var parts: [String] = []
        if let seconds = image.exposureSeconds,
            let shutter = shutter(seconds: seconds, locale: locale)
        {
            parts.append(shutter)
        }
        if let aperture = image.aperture { parts.append("ƒ/\(aperture.formatted(decimal))") }
        if let iso = image.iso {
            parts.append("ISO \(iso.formatted(.number.grouping(.never).locale(locale)))")
        }
        if let focal = image.focalLengthMillimetres {
            parts.append("\(focal.formatted(decimal)) mm")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Uses a reciprocal only at 1/2 s or faster and within 0.1% of an integer denominator.
    /// Other exposures retain decimal seconds, including values between 1/2 s and 1 s.
    public static func shutter(seconds: Double, locale: Locale = .current) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let reciprocal = 1 / seconds
        let denominator = reciprocal.rounded()
        if reciprocal.isFinite, reciprocal >= 2,
            abs(reciprocal - denominator) <= denominator * 0.001
        {
            return
                "1/\(denominator.formatted(.number.grouping(.never).precision(.fractionLength(0)).locale(locale))) s"
        }
        return
            "\(seconds.formatted(.number.grouping(.never).precision(.significantDigits(1...8)).locale(locale))) s"
    }
}
