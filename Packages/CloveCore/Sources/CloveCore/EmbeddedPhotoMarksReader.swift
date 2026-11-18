import Foundation
import ImageIO

/// Reads embedded XMP and IPTC marks from standalone image files (JPEG, HIF) via ImageIO.
///
/// Standalone photos keep Clove edits in ``CloveMarkStore`` without modifying image bytes, so any
/// mark Clove has not overridden falls back to the metadata embedded in the image itself. Callers
/// on Swift concurrency actors should invoke this off the cooperative thread pool.
public enum EmbeddedPhotoMarksReader: Sendable {
    /// Reads embedded `xmp:Rating`, `xmp:Label`, and `dc:subject` (falling back to
    /// `IPTC:Keywords` when `dc:subject` is absent) from the image at `url`.
    public static func read(at url: URL) -> XMPMarks? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary)
        else {
            return nil
        }

        var rating: XMPRating = .unrated
        var label: ColourLabel = .clear
        var keywords: [String] = []
        var hasDCSubject = false

        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        if let metadata {
            if let ratingText = CGImageMetadataCopyStringValueWithPath(
                metadata, nil, "xmp:Rating" as CFString) as String?
            {
                let trimmed = ratingText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Int(trimmed) {
                    rating = XMPRating(value)
                }
            }
            if let labelText = CGImageMetadataCopyStringValueWithPath(
                metadata, nil, "xmp:Label" as CFString) as String?
            {
                label = ColourLabel(rawValue: labelText)
            }
            if let subjectTag = CGImageMetadataCopyTagWithPath(
                metadata, nil, "dc:subject" as CFString)
            {
                hasDCSubject = true
                keywords = stringValues(from: subjectTag)
            }
        }

        if !hasDCSubject,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
            let rawIPTC = iptc[kCGImagePropertyIPTCKeywords]
        {
            if let array = rawIPTC as? [String] {
                keywords = array
            } else if let single = rawIPTC as? String {
                keywords = [single]
            }
        }

        if metadata == nil && keywords.isEmpty {
            return nil
        }
        return XMPMarks(rating: rating, label: label, keywords: keywords)
    }

    private static func stringValues(from tag: CGImageMetadataTag) -> [String] {
        guard let rawValue = CGImageMetadataTagCopyValue(tag) else { return [] }
        if let text = rawValue as? String {
            return [text]
        }
        guard let items = rawValue as? [Any] else { return [] }
        var values: [String] = []
        values.reserveCapacity(items.count)
        for item in items {
            if let text = item as? String {
                values.append(text)
            } else if CFGetTypeID(item as CFTypeRef) == CGImageMetadataTagGetTypeID() {
                let childTag = unsafeBitCast(item as CFTypeRef, to: CGImageMetadataTag.self)
                if let text = CGImageMetadataTagCopyValue(childTag) as? String {
                    values.append(text)
                }
            }
        }
        return values
    }
}
