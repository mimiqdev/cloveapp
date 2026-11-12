import CoreGraphics
import Foundation
import ImageIO

/// The production ``RegionSharpnessReading``: metadata through ImageIO, pixels through the
/// app's existing detail pipeline, so the analysis decodes nothing on its own route (#208).
///
/// One high-resolution acquisition per photo is the detail pipeline's own rule — its render
/// lane serializes and holds one native image — and preview reads ride the embedded-preview
/// lane, so the analysis reuses the same bounded execution the viewer already has (G1
/// "Scheduling and cache") instead of adding a competing budget.
public struct DetailRegionSharpnessReading: RegionSharpnessReading {
    private let details: DetailPipeline

    public init(details: DetailPipeline) {
        self.details = details
    }

    public func properties(of url: URL) async -> ImageProperties? {
        await withTaskExecutorPreference(ImageWorkExecutor.utility) {
            autoreleasepool {
                guard
                    let source = CGImageSourceCreateWithURL(
                        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                    let properties = CGImageSourceCopyPropertiesAtIndex(
                        source, 0, [kCGImageSourceShouldCache: false] as CFDictionary
                    ) as? [String: Any]
                else { return nil }
                return ImageProperties(properties)
            }
        }
    }

    /// Face detection reads the photo's fit pixels through the preview lane. The request is
    /// display-sized, which the pipeline serves from an embedded preview or camera preview.
    public func preview(_ request: RegionSharpnessRequest) async -> Result<
        CGImage, RegionImageFailure
    > {
        await read(request, wantsNativeResolution: false)
    }

    /// Every region's pixels come from one full-resolution read through the render lane: a
    /// camera companion's raster, the RAW's native render, whichever the pipeline's modes
    /// produce for this set (#208).
    public func highResolution(
        _ request: RegionSharpnessRequest
    ) async -> Result<CGImage, RegionImageFailure> {
        await read(request, wantsNativeResolution: true)
    }

    private func read(
        _ request: RegionSharpnessRequest, wantsNativeResolution: Bool
    ) async -> Result<CGImage, RegionImageFailure> {
        let detail = DetailRequest(
            raw: request.raw, jpeg: request.jpeg, heif: request.heif,
            displayPixels: wantsNativeResolution
                ? DetailPixelLimit.maximumEdge : RegionSharpnessAnalyzer.previewPixels,
            wantsNativeResolution: wantsNativeResolution,
            locationIdentity: request.locationIdentity)
        do {
            let result = try await details.image(for: detail)
            guard case .available(let image) = result else {
                return .failure(Self.failure(of: result))
            }
            return .success(image.image)
        } catch let error as DetailPipelineError {
            return .failure(Self.failure(of: error))
        } catch is CancellationError {
            return .failure(.closed)
        } catch {
            return .failure(.noUsablePreview)
        }
    }

    private static func failure(of result: DetailResult) -> RegionImageFailure {
        guard case .unavailable(let failure) = result else {
            return .noUsablePreview
        }
        return Self.failure(of: failure)
    }

    private static func failure(of failure: DetailFailure) -> RegionImageFailure {
        switch failure {
        case .cannotOpen: return .cannotOpen
        case .noUsablePreview: return .noUsablePreview
        case .sourceChanged: return .noUsablePreview
        }
    }

    private static func failure(of error: DetailPipelineError) -> RegionImageFailure {
        switch error {
        case .queueFull: return .queueFull
        case .closed: return .closed
        }
    }
}
