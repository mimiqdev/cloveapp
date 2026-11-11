import CoreGraphics
import Foundation
import PreviewProbe

/// One embedded-preview request's result, mapped from the preview probe so the stub
/// engine in tests does not need that module's result type.
public struct EmbeddedPreviewTiming: Sendable {
    public var milliseconds: Double
    public var width: Int
    public var height: Int
    public var error: String?

    public init(milliseconds: Double, width: Int, height: Int, error: String? = nil) {
        self.milliseconds = milliseconds
        self.width = width
        self.height = height
        self.error = error
    }
}

/// The synchronous work a suite run performs. Tests replace this with a stub that
/// finishes instantly, so loop bounds and cancellation are exercised without timing
/// real decodes.
public protocol RAWDisplayMeasuring: Sendable {
    func renderRAW(url: URL, variant: RAWDisplayVariant) throws -> DisplayRenderTiming
    func renderCameraPreview(url: URL, variant: CameraPreviewVariant) throws
        -> DisplayRenderTiming
    func rawImage(url: URL, variant: RAWDisplayVariant) throws -> CGImage
    func cameraPreviewImage(url: URL, variant: CameraPreviewVariant) throws -> CGImage
    /// The embedded preview route Clove Lab's preview probe uses: both thumbnail
    /// creation flags false, so a HIF is never fully decoded.
    func embeddedPreview(url: URL, maxPixel: Int) throws -> EmbeddedPreviewTiming
    func embeddedPreviewImage(url: URL, maxPixel: Int) throws -> CGImage
}

/// Core Image and ImageIO through the probe's own renderers, plus the preview
/// probe's embedded-preview measurement.
public struct LiveRAWDisplayMeasuring: RAWDisplayMeasuring {
    private let rawRenderer: RAWDisplayRenderer
    private let cameraRenderer: CameraPreviewRenderer

    public init(
        rawRenderer: RAWDisplayRenderer = RAWDisplayRenderer(),
        cameraRenderer: CameraPreviewRenderer = CameraPreviewRenderer()
    ) {
        self.rawRenderer = rawRenderer
        self.cameraRenderer = cameraRenderer
    }

    public func renderRAW(url: URL, variant: RAWDisplayVariant) throws -> DisplayRenderTiming {
        try rawRenderer.render(url: url, variant: variant)
    }

    public func renderCameraPreview(
        url: URL, variant: CameraPreviewVariant
    ) throws -> DisplayRenderTiming {
        try cameraRenderer.render(url: url, variant: variant)
    }

    public func rawImage(url: URL, variant: RAWDisplayVariant) throws -> CGImage {
        try rawRenderer.image(url: url, variant: variant)
    }

    public func cameraPreviewImage(url: URL, variant: CameraPreviewVariant) throws -> CGImage {
        try cameraRenderer.image(url: url, variant: variant)
    }

    public func embeddedPreview(url: URL, maxPixel: Int) throws -> EmbeddedPreviewTiming {
        let result = try PreviewMeasurement.measure(
            url: url, request: .init(method: .embeddedOnly, maxPixel: maxPixel))
        return EmbeddedPreviewTiming(
            milliseconds: result.milliseconds, width: result.width, height: result.height,
            error: result.error)
    }

    public func embeddedPreviewImage(url: URL, maxPixel: Int) throws -> CGImage {
        try PreviewMeasurement.image(
            url: url, request: .init(method: .embeddedOnly, maxPixel: maxPixel))
    }
}
