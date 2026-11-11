import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CloveImaging

@Suite struct ImageInformationTests {
    @Test func readsCaptureLensExposureAndSize() throws {
        let info = ImageInformationParser.parse(
            properties: [
                "{TIFF}": ["Model": "Camera A"],
                "{Exif}": [
                    "DateTimeOriginal": "2026:11:06 14:32:05", "SubsecTimeOriginal": "0042",
                    "BodySerialNumber": "0123", "LensModel": " Lens A ",
                    "ExposureTime": 0.004, "FNumber": 2.8, "ISOSpeedRatings": [400],
                    "FocalLength": 35,
                ],
                "PixelWidth": 8192, "PixelHeight": 5464,
            ], fileSize: 45_100_000)
        #expect(info.camera == "Camera A")
        #expect(info.bodySerial == "0123")
        #expect(info.captureWallTime != nil)
        #expect(info.subseconds == "0042")
        #expect(info.lens == "Lens A")
        #expect(info.exposureSeconds == 0.004)
        #expect(info.aperture == 2.8)
        #expect(info.iso == 400)
        #expect(info.focalLengthMillimetres == 35)
        #expect(info.fileSizeBytes == 45_100_000)
        #expect(info.pixelWidth == 8192)
        #expect(info.pixelHeight == 5464)
    }

    @Test func omitsMissingMalformedAndNonFiniteFields() {
        #expect(
            ImageInformationParser.parse(properties: [:], fileSize: nil)
                == ImageInformation())
        let info = ImageInformationParser.parse(
            properties: [
                "{Exif}": [
                    "LensModel": " ", "ExposureTime": Double.nan, "FNumber": -1,
                    "ISOSpeedRatings": [true], "FocalLength": Double.infinity,
                ],
                "PixelWidth": Double.greatestFiniteMagnitude, "PixelHeight": 1.5,
            ], fileSize: -1)
        #expect(info == ImageInformation())
        let auxiliary = ImageInformationParser.parse(
            properties: ["{ExifAux}": ["LensModel": "Auxiliary lens"]], fileSize: nil)
        #expect(auxiliary.lens == "Auxiliary lens")
    }

    @Test func onDemandReaderReadsGeneratedFileAndHandlesMissingImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("information.jpg")
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyExifDictionary: ["LensModel": "Test lens", "ExposureTime": 0.01]]
                as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let info = try #require(ImageInformationReader().read(url: url))
        #expect(info.lens == "Test lens")
        #expect(info.exposureSeconds == 0.01)
        #expect(info.pixelWidth == 8)
        #expect(info.pixelHeight == 4)
        #expect(info.fileSizeBytes == Int64(try Data(contentsOf: url).count))
        #expect(
            ImageInformationReader().read(url: folder.appendingPathComponent("missing.jpg")) == nil)
    }
}
