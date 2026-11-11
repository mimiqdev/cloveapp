import CoreGraphics
import CoreImage
import Foundation
import LabSupport

/// A colour in CIE L*a*b* (D65), derived from an sRGB pixel.
public struct LabColour: Sendable, Equatable, Hashable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }
}

/// The colour gap between two same-sized images over a bounded pixel lattice.
public struct ColourDifference: Sendable, Equatable {
    /// The metric every number here uses.
    public static let metric = "CIEDE2000"

    public var mean: Double
    public var p95: Double
    public var maximum: Double
    public var samples: Int
    public var width: Int
    public var height: Int

    /// Measurements for the report; `tags` must identify the comparison.
    public func measurements(tags: [String: String]) -> [LabMeasurement] {
        var tags = tags
        tags["metric"] = Self.metric
        tags["samples"] = String(samples)
        tags["width"] = String(width)
        tags["height"] = String(height)
        return [
            LabMeasurement(name: "colour-deltae00-mean", value: mean, unit: "deltaE", tags: tags),
            LabMeasurement(name: "colour-deltae00-p95", value: p95, unit: "deltaE", tags: tags),
            LabMeasurement(
                name: "colour-deltae00-max", value: maximum, unit: "deltaE", tags: tags),
        ]
    }
}

/// Colour conversion and CIEDE2000 comparison, with no dependency on a display.
///
/// CIEDE2000 is used rather than CIE76 because both are cheap here and CIEDE2000 is
/// the current recommendation for small colour differences. Both images are read in
/// sRGB; a larger reference is reduced with CILanczosScaleTransform *after* its
/// render, so this compares colour and a resampling step, not detail or sharpness.
public enum RAWDisplayColour {
    /// Most samples one comparison reads; larger images are sampled on a lattice.
    public static let maximumSamples = 4_096

    /// sRGB (D65) to CIE L*a*b*. Components are clamped to 0...1 first.
    public static func lab(red: Double, green: Double, blue: Double) -> LabColour {
        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)
        // IEC 61966-2-1 primaries to XYZ, then normalised by the D65 white point.
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        let fx = f(x)
        let fy = f(y)
        let fz = f(z)
        return LabColour(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// CIEDE2000 with kL = kC = kH = 1.
    public static func deltaE2000(_ first: LabColour, _ second: LabColour) -> Double {
        let c1 = (first.a * first.a + first.b * first.b).squareRoot()
        let c2 = (second.a * second.a + second.b * second.b).squareRoot()
        let cBar = (c1 + c2) / 2
        let cBar7 = pow(cBar, 7)
        let g = 0.5 * (1 - (cBar7 / (cBar7 + pow(25, 7))).squareRoot())
        let a1 = (1 + g) * first.a
        let a2 = (1 + g) * second.a
        let c1Prime = (a1 * a1 + first.b * first.b).squareRoot()
        let c2Prime = (a2 * a2 + second.b * second.b).squareRoot()
        let h1Prime = hue(a: a1, b: first.b)
        let h2Prime = hue(a: a2, b: second.b)
        let deltaLPrime = second.l - first.l
        let deltaCPrime = c2Prime - c1Prime
        var deltaHuePrime = 0.0
        if c1Prime * c2Prime != 0 {
            deltaHuePrime = h2Prime - h1Prime
            if deltaHuePrime > 180 {
                deltaHuePrime -= 360
            } else if deltaHuePrime < -180 {
                deltaHuePrime += 360
            }
        }
        let deltaHPrime = 2 * (c1Prime * c2Prime).squareRoot() * sin(radians(deltaHuePrime) / 2)
        let lBarPrime = (first.l + second.l) / 2
        let cBarPrime = (c1Prime + c2Prime) / 2
        var hBarPrime = h1Prime + h2Prime
        if c1Prime * c2Prime != 0 {
            if abs(h1Prime - h2Prime) <= 180 {
                hBarPrime = (h1Prime + h2Prime) / 2
            } else if h1Prime + h2Prime < 360 {
                hBarPrime = (h1Prime + h2Prime + 360) / 2
            } else {
                hBarPrime = (h1Prime + h2Prime - 360) / 2
            }
        }
        let t =
            1 - 0.17 * cos(radians(hBarPrime - 30)) + 0.24 * cos(radians(2 * hBarPrime))
            + 0.32 * cos(radians(3 * hBarPrime + 6)) - 0.20 * cos(radians(4 * hBarPrime - 63))
        let deltaTheta = 30 * exp(-pow((hBarPrime - 275) / 25, 2))
        let cBarPrime7 = pow(cBarPrime, 7)
        let rc = 2 * (cBarPrime7 / (cBarPrime7 + pow(25, 7))).squareRoot()
        let sl = 1 + (0.015 * pow(lBarPrime - 50, 2)) / (20 + pow(lBarPrime - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * cBarPrime
        let sh = 1 + 0.015 * cBarPrime * t
        let rt = -sin(radians(2 * deltaTheta)) * rc
        let l = deltaLPrime / sl
        let c = deltaCPrime / sc
        let h = deltaHPrime / sh
        return (l * l + c * c + h * h + rt * c * h).squareRoot()
    }

    /// Compares two same-sized sRGB bitmaps. Returns nil for size or bitmap failure.
    public static func compare(_ first: CGImage, _ second: CGImage) -> ColourDifference? {
        guard first.width > 0, first.width == second.width, first.height == second.height else {
            return nil
        }
        guard let a = pixels(first), let b = pixels(second) else { return nil }
        let step = max(
            1,
            Int((Double(a.width * a.height) / Double(maximumSamples)).squareRoot().rounded(.up)))
        var deltas: [Double] = []
        deltas.reserveCapacity(maximumSamples + 64)
        for y in stride(from: 0, to: a.height, by: step) {
            for x in stride(from: 0, to: a.width, by: step) {
                let offset = y * a.bytesPerRow + x * 4
                let labA = lab(
                    red: Double(a.bytes[offset]) / 255, green: Double(a.bytes[offset + 1]) / 255,
                    blue: Double(a.bytes[offset + 2]) / 255)
                let labB = lab(
                    red: Double(b.bytes[offset]) / 255, green: Double(b.bytes[offset + 1]) / 255,
                    blue: Double(b.bytes[offset + 2]) / 255)
                deltas.append(deltaE2000(labA, labB))
            }
        }
        guard !deltas.isEmpty else { return nil }
        deltas.sort()
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        return ColourDifference(
            mean: mean,
            p95: nearestRank(deltas, fraction: 0.95),
            maximum: deltas[deltas.count - 1],
            samples: deltas.count,
            width: a.width,
            height: a.height
        )
    }

    /// Aspect-preserving reduction to an exact size, so the comparison lattice lines
    /// up with the reduced variant's pixels.
    public static func scaled(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, image.width > 0, image.height > 0 else { return nil }
        if image.width == width, image.height == height { return image }
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let reducedWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let reducedHeight = max(1, Int((Double(image.height) * scale).rounded()))
        // Clamp before scaling so the Lanczos kernel does not average transparent
        // pixels into the border, and crop back to the finite target rectangle.
        filter.setValue(CIImage(cgImage: image).clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        let rect = CGRect(x: 0, y: 0, width: reducedWidth, height: reducedHeight)
        guard let output = filter.outputImage?.cropped(to: rect) else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard
            let reduced = context.createCGImage(
                output, from: output.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { return nil }
        if reduced.width == width, reduced.height == height { return reduced }
        return redraw(reduced, width: width, height: height)
    }

    private static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpace(name: CGColorSpace.sRGB)
                        ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func pixels(
        _ image: CGImage
    ) -> (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpace(name: CGColorSpace.sRGB)
                        ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (bytes, width, height, bytesPerRow) : nil
    }

    /// Nearest-rank percentile over ascending values; the maximum for n = 3 at p90.
    private static func nearestRank(_ sorted: [Double], fraction: Double) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func hue(a: Double, b: Double) -> Double {
        if a == 0, b == 0 { return 0 }
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func linear(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
    }

    private static func f(_ value: Double) -> Double {
        let epsilon = 216.0 / 24_389
        let kappa = 24_389.0 / 27
        return value > epsilon ? pow(value, 1.0 / 3) : (kappa * value + 16) / 116
    }
}
