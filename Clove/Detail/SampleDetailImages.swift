import CloveCore
import CloveImaging
import UIKit

/// Generated detail pixels for the test library: no files, no decoding (PRD P0-04).
///
/// The test library stands in for a scanned folder, so its detail view draws generated images
/// instead of reading a RAW. The preview is the long edge G1's detail row expects from the
/// owner's HIF embedded preview (1616 px), and the "native" image is a larger raster, so a
/// double-tap to 100% and a pinch past the preview go through the same quality change the real
/// pipeline produces. One sample photo answers with a preview only, which gives the view a
/// "preview only" note to show, and the sample's unreadable photo answers unavailable, so no
/// blank image is ever presented as loaded (PRD Scan scope).
///
/// Design placeholder: the tiles are flat generated pictures rather than test photographs.
@MainActor
final class SampleDetailImages: DetailImageSource {
    /// The generated preview's long edge: G1's detail row starts with the 1616 px HIF preview.
    static let previewLongEdge = 1616

    /// The generated full render's long edge: enough to inspect at 100% on a phone.
    static let fullLongEdge = 3000

    /// How many generated previews stay in memory, so browsing the sample cannot grow without
    /// bound. The filmstrip draws grid thumbnails, not these images.
    private static let previewCacheLimit = 8

    /// At most two full renders stay in memory, the same one-image-at-a-time budget G1 gives
    /// the real pipeline (its single native render is held outside the preview cache).
    private static let fullCacheLimit = 2

    private let unavailable: Set<PhotoIdentity>
    private let previewOnly: Set<PhotoIdentity>
    private var previews: [PhotoIdentity: DetailImage] = [:]
    private var previewOrder: [PhotoIdentity] = []
    private var fulls: [PhotoIdentity: DetailImage] = [:]
    private var fullOrder: [PhotoIdentity] = []

    /// Builds the sample source, naming the photos with no image and with a preview only.
    init(
        unavailable: Set<PhotoIdentity> = [], previewOnly: Set<PhotoIdentity> = []
    ) {
        self.unavailable = unavailable
        self.previewOnly = previewOnly
    }

    /// Answers the preview for a fit view and the larger render for a zoom that needs it.
    ///
    /// The preview is what a fit view shows, so it never renders; a pinch past its pixels or a
    /// double-tap to 100% asks for the full raster. A preview-only photo reports
    /// ``DetailLimitation/noHigherResolution`` with the pixels it has, the same answer I2 gives
    /// for a HIF that is never fully decoded (G1 "Preview, detail (I2)").
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        guard !unavailable.contains(photo) else { return .unavailable(.cannotOpen) }
        switch request.need {
        case .preview:
            return .image(preview(for: photo))
        case .morePixels, .fullResolution:
            guard !previewOnly.contains(photo) else {
                return .image(limited(preview(for: photo), by: .noHigherResolution))
            }
            return .image(full(for: photo))
        }
    }

    /// The sample has nothing to prefetch: every image is generated on demand.
    func prefetch(_ photos: [PhotoIdentity], displayPixels: Int) async {}

    /// The sample never queues speculative work.
    func cancelPrefetch() async {}

    /// The photo's 1616 px preview, generated once and kept in a small cache.
    private func preview(for photo: PhotoIdentity) -> DetailImage {
        if let image = previews[photo] { return image }
        let image = render(photo, longEdge: Self.previewLongEdge, quality: .preview)
        previews[photo] = image
        previewOrder.append(photo)
        if previewOrder.count > Self.previewCacheLimit {
            previews[previewOrder.removeFirst()] = nil
        }
        return image
    }

    /// The photo's larger render, held only for the photos the view recently asked for.
    private func full(for photo: PhotoIdentity) -> DetailImage {
        if let image = fulls[photo] { return image }
        let image = render(photo, longEdge: Self.fullLongEdge, quality: .nativeRAW)
        fulls[photo] = image
        fullOrder.append(photo)
        if fullOrder.count > Self.fullCacheLimit {
            fulls[fullOrder.removeFirst()] = nil
        }
        return image
    }

    /// A deterministic 3:2 picture whose fine lines and target make 100% inspection visible.
    private func render(
        _ photo: PhotoIdentity, longEdge: Int, quality: DetailQuality
    ) -> DetailImage {
        let size = CGSize(width: CGFloat(longEdge), height: CGFloat(longEdge) * 2 / 3)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let hue = Self.hue(for: photo.stem)
            UIColor(hue: hue, saturation: 0.3, brightness: 0.78, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Two bands and a fine grid: the lines are one image pixel wide, so 100% shows
            // whether the view is really at native resolution.
            UIColor(hue: hue, saturation: 0.45, brightness: 0.5, alpha: 1).setFill()
            context.fill(
                CGRect(x: 0, y: size.height * 0.12, width: size.width, height: size.height * 0.1))
            UIColor(white: 1, alpha: 0.22).setFill()
            for x in stride(from: 0.0, to: Double(size.width), by: 48) {
                context.fill(CGRect(x: x, y: 0, width: 1, height: size.height))
            }
            for y in stride(from: 0.0, to: Double(size.height), by: 48) {
                context.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
            }

            // A focus target in the middle, where a double-tap lands.
            let target = CGRect(
                x: size.width * 0.5 - size.height * 0.18, y: size.height * 0.34,
                width: size.height * 0.36, height: size.height * 0.36)
            UIColor.white.withAlphaComponent(0.6).setStroke()
            for ring in 1...3 {
                let inset = CGFloat(ring - 1) * 8
                let path = UIBezierPath(
                    ovalIn: target.insetBy(dx: inset, dy: inset))
                path.lineWidth = 3
                path.stroke()
            }

            let text = NSAttributedString(
                string: photo.stem.uppercased(),
                attributes: [
                    .font: UIFont.monospacedSystemFont(
                        ofSize: size.width * 0.06, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: size.height * 0.82))
        }
        guard let pixels = rendered.cgImage else {
            preconditionFailure("the sample detail renderer must produce a Core Graphics image")
        }
        return DetailImage(
            image: pixels, source: Self.source(for: photo), quality: quality)
    }

    /// The same pixels with a shortfall attached, because I2's `limited` is internal.
    private func limited(_ image: DetailImage, by limitation: DetailLimitation) -> DetailImage {
        DetailImage(
            image: image.image, source: image.source, quality: image.quality,
            limitation: image.limitation ?? limitation)
    }

    /// A stable source identity for generated pixels, with no file behind it.
    private static func source(for photo: PhotoIdentity) -> DetailSource {
        DetailSource(
            url: URL(
                fileURLWithPath:
                    "/clove.test-library/\(photo.relativeFolderPath)/\(photo.stem).ARW"),
            revision: ThumbnailRevision(size: 0, modificationTime: .distantPast))
    }

    /// A stable hue in 0..<1 for one stem, the same across launches and devices.
    private static func hue(for stem: String) -> CGFloat {
        var value: UInt32 = 2_166_136_261
        for scalar in stem.unicodeScalars {
            value = (value ^ scalar.value) &* 16_777_619
        }
        return CGFloat(value % 360) / 360
    }
}
