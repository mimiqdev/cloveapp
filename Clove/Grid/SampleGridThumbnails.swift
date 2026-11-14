import CloveCore
import UIKit

/// Generated tiles for the test library: no files, no decoding (PRD P0-03).
///
/// The test library stands in for a scanned folder, so its grid draws a generated tile per
/// photo identity instead of reading an image. A tile is deterministic by identity and cached,
/// so a run shows stable pictures and touches no file, permission or security scope.
///
/// Design placeholder: the visual design replaces these flat tiles with its thumbnail styling.
@MainActor
final class SampleGridThumbnails: GridThumbnailSource {
    private let companions: [PhotoIdentity: GridCompanions]
    private let unavailable: Set<PhotoIdentity>
    private var tiles: [PhotoIdentity: CGImage] = [:]

    /// Builds the sample tiles, naming the sample sets' companions and the sample photo whose
    /// file cannot produce a preview (PRD Grid, PRD Scan scope).
    init(
        companions: [PhotoIdentity: GridCompanions] = [:],
        unavailable: Set<PhotoIdentity> = []
    ) {
        self.companions = companions
        self.unavailable = unavailable
    }

    /// The companions the test library gives this photo, none unless the sample names some.
    func companions(for photo: PhotoIdentity) -> GridCompanions {
        companions[photo] ?? GridCompanions()
    }

    /// Returns an already-generated tile synchronously when warm.
    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? {
        if unavailable.contains(photo) { return .unavailable }
        if let tile = tiles[photo] { return .image(tile) }
        return nil
    }

    /// Draws one photo's tile, or reports the sample's unreadable photo (PRD Scan scope).
    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority) async
        -> GridThumbnailOutcome
    {
        guard !unavailable.contains(photo) else { return .unavailable }
        if let tile = tiles[photo] { return .image(tile) }
        let tile = drawTile(for: photo)
        tiles[photo] = tile
        return .image(tile)
    }

    /// One 400 px tile in a hue derived from the photo's identity (G1 preview row size).
    private func drawTile(for photo: PhotoIdentity) -> CGImage {
        let size = CGSize(width: 400, height: 400)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let hue = Self.hue(for: photo.stem)
            UIColor(hue: hue, saturation: 0.32, brightness: 0.82, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // A pair of bands, so neighbouring tiles are distinguishable at cell size.
            UIColor(hue: hue, saturation: 0.42, brightness: 0.62, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: 44))
            UIColor(white: 1, alpha: 0.28).setFill()
            context.fill(
                CGRect(x: size.width * 0.18, y: size.height * 0.28, width: 120, height: 120))
        }
        guard let tile = image.cgImage else {
            preconditionFailure("the sample tile renderer must produce a Core Graphics image")
        }
        return tile
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
