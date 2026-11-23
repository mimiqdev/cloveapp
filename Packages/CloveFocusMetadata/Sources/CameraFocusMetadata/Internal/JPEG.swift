import Foundation

struct JPEGExifSegment: Sendable, Hashable {
    /// Absolute offset of the APP1 marker (the 0xFF byte).
    let app1Offset: Int
    /// Absolute offset of the TIFF header after `Exif\0\0`.
    let tiffOffset: Int
    /// Absolute end of the APP1 segment payload.
    let tiffEnd: Int
}

enum JPEGScanner {
    static func findExifSegment(
        reader: BoundedReader,
        jpegStart: Int,
        jpegEnd: Int,
        limits: FocusMetadataReader.Limits
    ) throws -> JPEGExifSegment? {
        try scanSegments(
            reader: reader,
            jpegStart: jpegStart,
            jpegEnd: jpegEnd,
            limits: limits,
            findSOF: false
        ).exif
    }

    static func findSOFExtent(
        reader: BoundedReader,
        jpegStart: Int,
        jpegEnd: Int,
        limits: FocusMetadataReader.Limits
    ) throws -> PixelExtent? {
        try scanSegments(
            reader: reader,
            jpegStart: jpegStart,
            jpegEnd: jpegEnd,
            limits: limits,
            findSOF: true
        ).sofExtent
    }

    private static func scanSegments(
        reader: BoundedReader,
        jpegStart: Int,
        jpegEnd: Int,
        limits: FocusMetadataReader.Limits,
        findSOF: Bool
    ) throws -> (exif: JPEGExifSegment?, sofExtent: PixelExtent?) {
        guard jpegStart >= 0, jpegEnd <= reader.length, jpegStart <= jpegEnd else {
            throw ParseFailure.outOfBounds
        }
        guard jpegEnd - jpegStart >= 4 else {
            throw ParseFailure.truncated
        }
        let soi = try reader.read(at: jpegStart, count: 2)
        guard soi == [0xFF, 0xD8] else {
            throw ParseFailure.unsupported
        }

        let scanEnd = min(jpegEnd, jpegStart + limits.maximumJPEGScanBytes)
        var cursor = jpegStart + 2
        var segmentCount = 0
        var exifSegment: JPEGExifSegment?
        var sofExtent: PixelExtent?

        while cursor + 1 < scanEnd {
            segmentCount += 1
            guard segmentCount <= 1024 else {
                throw ParseFailure.limitExceeded
            }
            guard try reader.u8(at: cursor) == 0xFF else {
                throw ParseFailure.invalidIFD
            }

            var markerCodeOffset = cursor + 1
            while markerCodeOffset < scanEnd, try reader.u8(at: markerCodeOffset) == 0xFF {
                markerCodeOffset += 1
            }
            guard markerCodeOffset < scanEnd else {
                throw ParseFailure.truncated
            }
            let marker = try reader.u8(at: markerCodeOffset)

            if marker == 0xD8 {
                cursor = markerCodeOffset + 1
                continue
            }
            if marker == 0xD9 || marker == 0xDA {
                break
            }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                cursor = markerCodeOffset + 1
                continue
            }

            guard markerCodeOffset + 3 <= jpegEnd else {
                throw ParseFailure.truncated
            }
            let length = try reader.u16(at: markerCodeOffset + 1, byteOrder: .bigEndian)
            guard length >= 2 else {
                throw ParseFailure.invalidIFD
            }
            let segmentEnd = try BMFFParser.addOffset(markerCodeOffset + 1, Int(length))
            guard segmentEnd <= jpegEnd else {
                throw ParseFailure.outOfBounds
            }
            let payloadStart = markerCodeOffset + 3

            if exifSegment == nil, marker == 0xE1, length >= 8, payloadStart + 6 <= segmentEnd {
                let identifier = try reader.read(at: payloadStart, count: 6)
                if identifier == [0x45, 0x78, 0x69, 0x66, 0x00, 0x00] {
                    exifSegment = JPEGExifSegment(
                        app1Offset: cursor,
                        tiffOffset: payloadStart + 6,
                        tiffEnd: segmentEnd
                    )
                    if !findSOF {
                        return (exifSegment, nil)
                    }
                }
            }

            if findSOF, sofExtent == nil, isSOFMarker(marker), payloadStart + 5 <= segmentEnd {
                let frameHeader = try reader.read(at: payloadStart, count: 5)
                let height = (Int(frameHeader[1]) << 8) | Int(frameHeader[2])
                let width = (Int(frameHeader[3]) << 8) | Int(frameHeader[4])
                sofExtent = PixelExtent(width: width, height: height)
                if exifSegment != nil {
                    return (exifSegment, sofExtent)
                }
            }

            if segmentEnd <= cursor {
                throw ParseFailure.invalidIFD
            }
            cursor = segmentEnd
            if cursor >= scanEnd {
                break
            }
        }
        return (exifSegment, sofExtent)
    }

    private static func isSOFMarker(_ marker: UInt8) -> Bool {
        (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
    }
}
