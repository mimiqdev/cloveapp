import CoreGraphics
import CoreImage
import Foundation

/// Renders one RAW variant with `CIRAWFilter` and times it to a materialized bitmap.
///
/// `scaleFactor` and `isDraftModeEnabled` are set after the filter opens and before
/// `outputImage` is requested. Both are therefore decode-time requests rather than a
/// downscale applied to an already rendered bitmap, which is what S2 measured. This
/// probe records the requested size, the output size and the time; it does not
/// inspect which internal decoder stage honours either request.
public final class RAWDisplayRenderer: @unchecked Sendable {
    /// One context shared by the `reused` variants. `CIContext` is documented safe to
    /// use from multiple threads, and this probe renders one image at a time; nothing
    /// else in the renderer is stored per render.
    private let reusedContext = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    /// One timed render. Errors are recorded in `timing.error`, not thrown, so a
    /// variant that the decoder does not support still reports a row.
    public func render(url: URL, variant: RAWDisplayVariant) throws -> DisplayRenderTiming {
        try measureDisplay {
            try renderImage(url: url, variant: variant)
        }
    }

    /// The decoded bitmap for a colour comparison. Untimed; timed callers use
    /// ``render(url:variant:)``.
    public func image(url: URL, variant: RAWDisplayVariant) throws -> CGImage {
        try Task.checkCancellation()
        return try renderImage(url: url, variant: variant).image
    }

    private func renderImage(
        url: URL, variant: RAWDisplayVariant
    ) throws -> (image: CGImage, native: CGSize) {
        try Task.checkCancellation()
        guard let filter = CIRAWFilter(imageURL: url) else {
            throw RAWDisplayFailure.rawUnsupported
        }
        let native = filter.nativeSize
        switch variant.scale {
        case .native:
            break
        case .longEdge(let edge):
            guard edge > 0 else { throw RAWDisplayFailure.noNativeSize }
            let nativeLongEdge = max(native.width, native.height)
            // Without a native size the filter cannot be asked for a fraction of it.
            guard nativeLongEdge > 0 else { throw RAWDisplayFailure.noNativeSize }
            filter.scaleFactor = Float(Double(edge) / Double(nativeLongEdge))
        }
        filter.isDraftModeEnabled = variant.draft
        guard let output = filter.outputImage else {
            throw RAWDisplayFailure.rawNoOutput
        }
        let context =
            variant.context == .reused
            ? reusedContext
            : CIContext(options: [.cacheIntermediates: false])
        try Task.checkCancellation()
        guard
            let image = context.createCGImage(
                output, from: output.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else {
            throw RAWDisplayFailure.cannotRender
        }
        return (image, native)
    }
}
