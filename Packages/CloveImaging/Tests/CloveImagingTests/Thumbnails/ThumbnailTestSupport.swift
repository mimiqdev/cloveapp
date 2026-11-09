import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CloveImaging

struct ThumbnailTestDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: url) }

    func image(
        name: String = "photo.jpg", type: UTType = .jpeg, orientation: Int = 1,
        embedded: Bool = false, width: Int = 1200, height: Int = 800
    ) throws -> URL {
        let file = url.appendingPathComponent(name)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                file as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image,
            [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationEmbedThumbnail: embedded,
            ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return file
    }

    func cache(
        memory: Int = 64 * 1024 * 1024, disk: Int = 256 * 1024 * 1024,
        version: Int = 1
    ) throws -> ThumbnailCache {
        var configuration = ThumbnailCache.Configuration()
        configuration.memoryBytes = memory
        configuration.diskBytes = disk
        configuration.pipelineVersion = version
        return try ThumbnailCache(
            directory: url.appendingPathComponent("cache"), configuration: configuration)
    }
}

func thumbnailRequest(_ source: URL, pixels: Int = 400) throws -> ThumbnailRequest {
    ThumbnailRequest(
        source: source, revision: try .read(from: source), targetPixels: pixels,
        locationIdentity: "test-folder")
}

func availableThumbnail(_ result: ThumbnailResult) throws -> Thumbnail {
    guard case .available(let thumbnail) = result else {
        Issue.record("Expected usable pixels, got \(result)")
        throw CocoaError(.fileReadCorruptFile)
    }
    return thumbnail
}
