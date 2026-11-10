import CryptoKit
import Foundation

extension GroupingInputRevision {
    /// The token a folder's group cache is keyed by, from what the scan read about its files
    /// (PRD Similar groups rules).
    ///
    /// C9's own input fingerprint already covers each eligible photo's identity, file name, capture
    /// instant and camera body. A file replaced in place keeps every one of those and changes its
    /// pixels, so the token also covers the primary-file revision the scan prefetched — the size
    /// and modification date (G1's scan row) — together with the caller's feature token, which
    /// names the preview and feature revision a result came from. A stored result then never
    /// outlives a changed file or a changed feature pipeline, and a restored folder groups again
    /// instead of showing older groups (PRD P0-11, PRD Similar groups rules).
    public static func scanned(
        _ sets: [ScannedPhotoSet], feature: String
    ) -> GroupingInputRevision {
        var canonical = Data()
        GroupingRevisionCanonical.append(feature, to: &canonical)
        for set in sets.sorted(by: { GroupingRuns.identityPrecedes($0.id, $1.id) }) {
            GroupingRevisionCanonical.append(set.id.folderID.rawValue, to: &canonical)
            GroupingRevisionCanonical.append(set.id.relativeFolderPath, to: &canonical)
            GroupingRevisionCanonical.append(set.id.stem, to: &canonical)
            // The primary file is the first member, and the RAW for a RAW set (G1 decision 1).
            let primary = set.imageFiles.first
            GroupingRevisionCanonical.append(String(primary?.size ?? -1), to: &canonical)
            GroupingRevisionCanonical.append(
                String(primary?.modificationDate?.timeIntervalSince1970.bitPattern ?? 0),
                to: &canonical)
        }
        let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return GroupingInputRevision(rawValue: digest)
    }
}

/// The byte encoding the revision digest is taken over.
///
/// Every field is written with a big-endian byte-count prefix, so no spelling of a path, a name or
/// a date can make two different folders encode the same bytes.
private enum GroupingRevisionCanonical {
    static func append(_ field: String, to canonical: inout Data) {
        var length = UInt64(field.utf8.count).bigEndian
        withUnsafeBytes(of: &length) { canonical.append(contentsOf: $0) }
        canonical.append(contentsOf: field.utf8)
    }
}
