import Foundation
import ImageIO

/// A bounded JPEG-only comparison path. Replaces a standard APP1 XMP packet
/// without rebuilding EXIF, IPTC, thumbnails, maker notes or entropy data.
/// Extended/duplicate XMP is deliberately rejected, not silently discarded.
/// This is verification code, not the C-lane production writer.
enum JPEGPacket {
    private static let signature = Data("http://ns.adobe.com/xap/1.0/\0".utf8)
    private static let extendedSignature = Data("http://ns.adobe.com/xmp/extension/\0".utf8)

    static func nonXMPData(_ data: Data) throws -> Data {
        guard let range = try packetRange(data) else { return data }
        return data.subdata(in: 0..<range.lowerBound)
            + data.subdata(in: range.upperBound..<data.count)
    }

    static func metadata(in data: Data) throws -> CGMutableImageMetadata {
        if let range = try packetRange(data) {
            let packet = data.subdata(
                in: (range.lowerBound + 4 + signature.count)..<range.upperBound)
            // ImageIO's standalone XMP parser rejects some otherwise readable camera
            // packets. Its image-source reader can expose those packets plus EXIF/IPTC.
            let metadata =
                CGImageMetadataCreateFromXMPData(packet as CFData)
                ?? CGImageSourceCreateWithData(data as CFData, nil).flatMap {
                    CGImageSourceCopyMetadataAtIndex($0, 0, nil)
                }
            guard let metadata, let mutable = CGImageMetadataCreateMutableCopy(metadata) else {
                throw MetadataProbeError.invalid("JPEG XMP packet cannot be parsed")
            }
            return mutable
        }
        return CGImageMetadataCreateMutable()
    }

    static func replacingMetadata(in data: Data, with metadata: CGImageMetadata) throws -> Data {
        guard let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data? else {
            throw MetadataProbeError.invalid("Cannot serialize JPEG XMP")
        }
        let length = 2 + signature.count + xmp.count
        guard length <= 65535 else {
            throw MetadataProbeError.invalid("XMP requires unsupported extended JPEG packet")
        }
        var segment = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 255)])
        segment.append(signature)
        segment.append(xmp)
        let range = try packetRange(data) ?? 2..<2
        var result = data.subdata(in: 0..<range.lowerBound)
        result.append(segment)
        result.append(data.subdata(in: range.upperBound..<data.count))
        return result
    }

    private static func packetRange(_ data: Data) throws -> Range<Int>? {
        guard data.count >= 4, data[0] == 0xFF, data[1] == 0xD8 else {
            throw MetadataProbeError.invalid("JPEG packet splice requires a JPEG SOI")
        }
        var cursor = 2
        var range: Range<Int>?
        while cursor < data.count {
            let start = cursor
            guard data[cursor] == 0xFF else {
                throw MetadataProbeError.invalid("Invalid JPEG segment")
            }
            while cursor < data.count && data[cursor] == 0xFF { cursor += 1 }
            guard cursor < data.count else {
                throw MetadataProbeError.invalid("Truncated JPEG marker")
            }
            let marker = data[cursor]
            cursor += 1
            if marker == 0xDA || marker == 0xD9 { return range }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { continue }
            guard cursor + 2 <= data.count else {
                throw MetadataProbeError.invalid("Truncated JPEG length")
            }
            let length = Int(data[cursor]) * 256 + Int(data[cursor + 1])
            guard length >= 2, length <= data.count - cursor else {
                throw MetadataProbeError.invalid("JPEG segment out of bounds")
            }
            let contents = data.subdata(in: (cursor + 2)..<(cursor + length))
            if marker == 0xE1 && contents.starts(with: extendedSignature) {
                throw MetadataProbeError.invalid(
                    "Extended JPEG XMP is outside this probe's support")
            }
            if marker == 0xE1 && contents.starts(with: signature) {
                guard range == nil else {
                    throw MetadataProbeError.invalid("Duplicate JPEG XMP packets")
                }
                range = start..<(cursor + length)
            }
            cursor += length
        }
        throw MetadataProbeError.invalid("JPEG has no SOS/EOI")
    }
}
