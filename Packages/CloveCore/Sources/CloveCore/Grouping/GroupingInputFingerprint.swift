import CryptoKit
import Foundation

/// The canonical digest of the photos grouping can use, part of the cache key
/// (PRD Similar groups rules: groups are cached only in Clove).
///
/// The caller's ``GroupingInputRevision`` only reflects what the caller noticed. A folder can
/// change without it: a copied-in photo, a capture time that resolves differently, or a serial
/// read late. So the grouper also fingerprints the eligible inputs themselves and the cache
/// needs both to match.
///
/// The digest covers each eligible photo's identity, capture instant at full precision, camera
/// body key (model and serial) and file name, in identity order. It deliberately leaves out
/// ineligible photos, because they never enter a group; adding one cannot change a result.
/// Every field is written with a big-endian byte-count prefix, so no spelling of a path, name
/// or serial can make two different input sets encode the same bytes.
enum GroupingInputFingerprint {
    /// A lowercase hex SHA-256 over the eligible photos, in identity order.
    static func digest(of photos: [GroupingPhoto]) -> String {
        let canonical = canonicalBytes(of: photos)
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    /// The bytes the digest is taken over, kept separate so the encoding reads in one place.
    private static func canonicalBytes(of photos: [GroupingPhoto]) -> Data {
        let eligible = photos.filter(\.isEligibleForGrouping).sorted {
            GroupingRuns.identityPrecedes($0.id, $1.id)
        }
        var canonical = Data()
        for photo in eligible {
            append(photo.id.folderID.rawValue, to: &canonical)
            append(photo.id.relativeFolderPath, to: &canonical)
            append(photo.id.stem, to: &canonical)
            appendInstant(photo, to: &canonical)
            append(photo.body?.model ?? "", to: &canonical)
            append(photo.body?.serial ?? "", to: &canonical)
            append(photo.fileName, to: &canonical)
        }
        return canonical
    }

    /// One length-prefixed UTF-8 field.
    private static func append(_ field: String, to canonical: inout Data) {
        var length = UInt64(field.utf8.count).bigEndian
        withUnsafeBytes(of: &length) { canonical.append(contentsOf: $0) }
        canonical.append(contentsOf: field.utf8)
    }

    /// The instant's full-precision bit pattern, so no rounding can hide a change.
    private static func appendInstant(_ photo: GroupingPhoto, to canonical: inout Data) {
        guard let instant = photo.instant else {
            canonical.append(0)
            return
        }
        canonical.append(1)
        var bits = instant.timeIntervalSinceReferenceDate.bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { canonical.append(contentsOf: $0) }
    }
}
