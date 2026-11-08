import CoreGraphics
import Foundation
import ImageIO

public struct MetadataSnapshot: Codable, Equatable, Sendable {
    public var fileBytes: Int
    public var fileSHA256: String
    public var payloads: [PayloadDigest]
    public var makerNotes: [PayloadDigest]
    public var jpegNonXMPBytes: PayloadDigest?
    public var jpegEXIFPreviews: [PayloadDigest]
    public var decodedPixels: PayloadDigest?
    public var decodeError: String?
    public var imageCount: Int
    public var metadata: [String: String]
    public var properties: [String: String]

    public static func read(_ url: URL) throws -> MetadataSnapshot {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let source = try MetadataWriter.source(url)
        var pixelDigest: PayloadDigest?
        var decodeError: String?
        do {
            pixelDigest = try pixels(source)
        } catch {
            decodeError = String(describing: error)
        }
        var properties: [String: String] = [:]
        if let dictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) {
            flatten(dictionary, path: "properties", into: &properties)
        }
        var metadata: [String: String] = [:]
        if let xmp = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(
                xmp, nil, [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
            ) { path, tag in
                metadata[path as String] = canonicalTag(tag)
                return true
            }
        }
        return MetadataSnapshot(
            fileBytes: data.count,
            fileSHA256: PayloadDigest.hash(data),
            payloads: try PayloadEvidence.read(data, extension: url.pathExtension),
            makerNotes: try PayloadEvidence.makerNotes(data, extension: url.pathExtension),
            jpegNonXMPBytes: ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
                ? try PayloadDigest(
                    role: "JPEG/all-bytes-except-standard-XMP", data: JPEGPacket.nonXMPData(data))
                : nil,
            jpegEXIFPreviews: ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
                ? try PayloadEvidence.jpegEXIFPreviews(data) : [],
            decodedPixels: pixelDigest,
            decodeError: decodeError,
            imageCount: CGImageSourceGetCount(source),
            metadata: metadata,
            properties: properties
        )
    }

    /// Existing properties are checked separately from new marks; all changed paths are exported.
    public func changedPaths(comparedTo before: MetadataSnapshot) -> [String] {
        let old = before.properties.merging(before.metadata) { first, _ in first }
        let new = properties.merging(metadata) { first, _ in first }
        return Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
    }

    public func lostOrChangedExistingMetadata(comparedTo before: MetadataSnapshot) -> [String] {
        let intended = Set([
            "xmp:Rating", "xmp:Label", "clove:Reject", "properties.{IPTC}.StarRating",
        ])
        let old = before.properties.merging(before.metadata) { first, _ in first }
        let new = properties.merging(metadata) { first, _ in first }
        return old.keys.filter { !intended.contains($0) && old[$0] != new[$0] }.sorted()
    }

    public var preservationSeedPresent: Bool {
        let text = metadata.values.joined(separator: "\n")
        return text.contains("keep-me") && text.contains("nested-value")
            && text.contains("S4 other-app caption") && text.contains("S4 keyword")
            && metadata.keys.contains("other:Nested")
    }

    public func contains(_ marks: EmbeddedMarks) -> Bool {
        func value(_ path: String) -> String? {
            metadata[path]?.components(separatedBy: "|value=").last
        }
        return value("xmp:Rating") == String(marks.rating)
            && value("xmp:Label") == marks.label
            && value("clove:Reject")?.lowercased() == (marks.rejected ? "true" : "false")
    }

    private static func pixels(_ source: CGImageSource) throws -> PayloadDigest {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw MetadataProbeError.invalid("ImageIO raster decode unavailable") }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= 20000, height <= 20000 else {
            throw MetadataProbeError.invalid("Raster dimensions outside spike safety bound")
        }
        var data = Data(count: width * height * 4)
        let rendered = data.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw MetadataProbeError.invalid("Cannot render RGBA raster") }
        return PayloadDigest(role: "ImageIO/sRGB8/RGBA/\(width)x\(height)", data: data)
    }

    private static func canonicalTag(_ tag: CGImageMetadataTag) -> String {
        let namespace = CGImageMetadataTagCopyNamespace(tag) as String? ?? ""
        let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
        let qualifiers = (CGImageMetadataTagCopyQualifiers(tag) as? [CGImageMetadataTag] ?? []).map(
            canonicalTag
        ).sorted()
        return
            "\(namespace)|\(name)|\(CGImageMetadataTagGetType(tag).rawValue)|q=\(qualifiers)|value=\(canonical(CGImageMetadataTagCopyValue(tag)))"
    }

    private static func canonical(_ value: Any?) -> String {
        guard let value else { return "null" }
        if CFGetTypeID(value as CFTypeRef) == CGImageMetadataTagGetTypeID() {
            // Core Foundation's runtime type check above establishes the tag type.
            return canonicalTag(unsafeBitCast(value as CFTypeRef, to: CGImageMetadataTag.self))
        }
        if let data = value as? Data { return "bytes:\(data.count):\(PayloadDigest.hash(data))" }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().map { "\($0)=\(canonical(dictionary[$0]))" }.joined(
                separator: ";")
        }
        if let array = value as? [Any] {
            return "[" + array.map { canonical($0) }.joined(separator: ",") + "]"
        }
        return String(describing: value)
    }

    private static func flatten(_ value: Any, path: String, into result: inout [String: String]) {
        if let dictionary = value as? [String: Any], !dictionary.isEmpty {
            for (key, child) in dictionary { flatten(child, path: "\(path).\(key)", into: &result) }
        } else {
            result[path] = canonical(value)
        }
    }
}
