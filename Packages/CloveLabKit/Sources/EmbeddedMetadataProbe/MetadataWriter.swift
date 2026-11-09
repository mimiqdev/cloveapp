import Foundation
import ImageIO
import SpikeSupport

public enum EmbeddedWriteMethod: String, Codable, Sendable, CaseIterable {
    case copyImageSource
    case decodeAndAddImageAndMetadata
    case jpegXMPPacketSplice
}

/// Spike-only namespace, pending G1/S3's production namespace decision.
public struct EmbeddedMarks: Sendable {
    public var rating: Int
    public var label: String
    public var rejected: Bool

    public init(rating: Int = 3, label: String = "Green", rejected: Bool = true) {
        self.rating = rating
        self.label = label
        self.rejected = rejected
    }
}

public enum MetadataWriter {
    public static let cloveNamespace = "urn:clove:spike:s4:1.0/"

    /// Writes a sibling temporary file then atomically renames it over `url`.
    /// Failure before rename leaves the original untouched; temp cleanup always runs.
    /// This spike measures local rename atomicity, not power-loss durability or provider coordination.
    @discardableResult
    public static func write(
        to url: URL, method: EmbeddedWriteMethod, marks: EmbeddedMarks = EmbeddedMarks()
    ) throws -> Double {
        let clock = Stopwatch()
        if method == .jpegXMPPacketSplice {
            let original = try Data(contentsOf: url)
            let metadata = try JPEGPacket.metadata(in: original)
            try setMarks(marks, on: metadata)
            try AtomicReplacement.write(to: url) { temporary in
                try JPEGPacket.replacingMetadata(in: original, with: metadata).write(to: temporary)
            }
            return clock.seconds * 1000
        }
        let source = try source(url)
        let metadata: CGMutableImageMetadata
        if method == .copyImageSource {
            // Supply only the delta. Even with this minimal input, native JPEG
            // copying normalizes some existing EXIF rationals and GPS coordinates.
            metadata = CGImageMetadataCreateMutable()
        } else {
            guard
                let copy = CGImageMetadataCreateMutableCopy(
                    CGImageSourceCopyMetadataAtIndex(source, 0, nil)
                        ?? CGImageMetadataCreateMutable())
            else { throw MetadataProbeError.invalid("Cannot copy source metadata") }
            metadata = copy
        }
        try setMarks(marks, on: metadata)
        try write(to: url, source: source, method: method, metadata: metadata)
        return clock.seconds * 1000
    }

    /// Adds nested unknown XMP, IPTC/DC caption and keywords, and requests GPS.
    /// GPS lands on JPEG but not on the HEIC control; existing JPEG GPS is checked separately.
    public static func seedPreservationControl(at url: URL) throws {
        let xml = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:exif="http://ns.adobe.com/exif/1.0/"
            xmlns:other="urn:other-app:s4:unknown/" xmp:Rating="1" xmp:Label="Red"
            exif:GPSLatitude="51,30.0N" exif:GPSLongitude="0,7.0W" other:Scalar="keep-me">
            <dc:description><rdf:Alt><rdf:li xml:lang="x-default">S4 other-app caption</rdf:li></rdf:Alt></dc:description>
            <dc:subject><rdf:Bag><rdf:li>S4 keyword</rdf:li><rdf:li>second keyword</rdf:li></rdf:Bag></dc:subject>
            <other:Nested rdf:parseType="Resource"><other:Child>nested-value</other:Child>
            <other:List><rdf:Seq><rdf:li>first</rdf:li><rdf:li>second</rdf:li></rdf:Seq></other:List>
            </other:Nested></rdf:Description></rdf:RDF></x:xmpmeta>
            """
        guard let metadata = CGImageMetadataCreateFromXMPData(Data(xml.utf8) as CFData) else {
            throw MetadataProbeError.invalid("Cannot parse preservation seed XMP")
        }
        if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
            let original = try Data(contentsOf: url)
            let merged = try JPEGPacket.metadata(in: original)
            var mergedAll = true
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                guard let namespace = CGImageMetadataTagCopyNamespace(tag),
                    let prefix = CGImageMetadataTagCopyPrefix(tag),
                    CGImageMetadataRegisterNamespaceForPrefix(merged, namespace, prefix, nil),
                    CGImageMetadataSetTagWithPath(merged, nil, path, tag)
                else { mergedAll = false; return true }
                return true
            }
            guard mergedAll else { throw MetadataProbeError.invalid("Cannot merge JPEG seed XMP") }
            try AtomicReplacement.write(to: url) { temporary in
                try JPEGPacket.replacingMetadata(in: original, with: merged).write(to: temporary)
            }
        } else {
            // A native seed can normalize/discard camera metadata before the measured write.
            try write(to: url, source: source(url), method: .copyImageSource, metadata: metadata)
        }
    }

    static func source(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MetadataProbeError.invalid("ImageIO cannot open \(url.lastPathComponent)")
        }
        return source
    }

    private static func setMarks(_ marks: EmbeddedMarks, on metadata: CGMutableImageMetadata) throws
    {
        guard (-1...5).contains(marks.rating),
            CGImageMetadataRegisterNamespaceForPrefix(
                metadata, "http://ns.adobe.com/xap/1.0/" as CFString, "xmp" as CFString, nil),
            CGImageMetadataRegisterNamespaceForPrefix(
                metadata, cloveNamespace as CFString, "clove" as CFString, nil),
            CGImageMetadataSetValueWithPath(
                metadata, nil, "xmp:Rating" as CFString, String(marks.rating) as CFString),
            CGImageMetadataSetValueWithPath(
                metadata, nil, "xmp:Label" as CFString, marks.label as CFString),
            CGImageMetadataSetValueWithPath(
                metadata, nil, "clove:Reject" as CFString,
                (marks.rejected ? "True" : "False") as CFString)
        else {
            throw MetadataProbeError.invalid("Cannot set rating/label/Reject metadata")
        }
    }

    private static func write(
        to url: URL, source: CGImageSource, method: EmbeddedWriteMethod, metadata: CGImageMetadata
    ) throws {
        guard let type = CGImageSourceGetType(source) else {
            throw MetadataProbeError.invalid("ImageIO source has no type")
        }
        try AtomicReplacement.write(to: url) { temporary in
            guard
                let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil)
            else {
                throw MetadataProbeError.invalid("ImageIO has no destination for \(type)")
            }
            switch method {
            case .copyImageSource:
                var error: Unmanaged<CFError>?
                let options =
                    [
                        kCGImageDestinationMetadata: metadata,
                        kCGImageDestinationMergeMetadata: true,
                    ] as CFDictionary
                guard CGImageDestinationCopyImageSource(destination, source, options, &error) else {
                    let detail =
                        error.map { String(describing: $0.takeRetainedValue()) }
                        ?? "no CFError returned"
                    throw MetadataProbeError.invalid("CopyImageSource failed: \(detail)")
                }
            // The copy function writes the destination itself. Do not finalize it again.
            case .jpegXMPPacketSplice:
                throw MetadataProbeError.invalid(
                    "JPEG packet splice does not use an ImageIO destination")
            case .decodeAndAddImageAndMetadata:
                guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw MetadataProbeError.invalid("ImageIO decode failed")
                }
                CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw MetadataProbeError.invalid("AddImageAndMetadata finalize failed")
                }
            }
        }
    }
}
