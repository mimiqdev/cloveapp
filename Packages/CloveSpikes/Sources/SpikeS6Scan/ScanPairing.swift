import Foundation

/// Pairs a RAW and a JPEG that share a base name in the same folder, and leaves
/// everything else as a standalone photo (P0-01 "Scan scope").
public enum ScanPairing {
    /// Turns listed files into grid photos.
    ///
    /// A RAW and a same-name JPEG in one folder become one photo with the RAW as
    /// the primary file. A JPEG, HEIC, or DNG without a partner stays one photo.
    /// Matching is case-insensitive in both the base name and the extension, and
    /// never crosses a folder boundary. Sidecars and other files are ignored.
    ///
    /// - Parameters:
    ///   - entries: Files from ``ScanLister``, in any order.
    ///   - rawExtensions: Extensions treated as the primary file of a pair.
    ///   - jpegExtensions: Extensions that pair with a RAW.
    /// - Returns: Photos ordered by folder, then base name, then primary extension.
    public static func photos(
        from entries: [ScanEntry],
        rawExtensions: Set<String> = ScanRule.rawExtensions,
        jpegExtensions: Set<String> = ScanRule.jpegExtensions
    ) -> [ScannedPhoto] {
        struct Key: Hashable {
            var directory: String
            var baseName: String
        }
        struct Group {
            var raw: [ScanEntry] = []
            var jpeg: [ScanEntry] = []
            var other: [ScanEntry] = []
        }
        var groups: [Key: Group] = [:]
        for entry in entries {
            guard ScanRule.isPhotoFile(entry.relativePath) else { continue }
            let key = Key(directory: entry.relativeDirectory, baseName: entry.baseName.lowercased())
            if ScanRule.hasExtension(entry.relativePath, in: rawExtensions) {
                groups[key, default: Group()].raw.append(entry)
            } else if ScanRule.hasExtension(entry.relativePath, in: jpegExtensions) {
                groups[key, default: Group()].jpeg.append(entry)
            } else {
                groups[key, default: Group()].other.append(entry)
            }
        }

        var photos: [ScannedPhoto] = []
        for (key, group) in groups {
            let raws = group.raw.sorted { $0.relativePath < $1.relativePath }
            let jpegs = group.jpeg.sorted { $0.relativePath < $1.relativePath }
            let others = group.other.sorted { $0.relativePath < $1.relativePath }
            if let raw = raws.first {
                photos.append(
                    ScannedPhoto(
                        primary: raw.url, pairedJPEG: jpegs.first?.url, baseName: raw.baseName,
                        relativeDirectory: key.directory))
                // A second file with the same base name is its own photo, not a
                // silent overwrite of the first.
                for extra in raws.dropFirst() {
                    photos.append(
                        ScannedPhoto(
                            primary: extra.url, baseName: extra.baseName,
                            relativeDirectory: key.directory))
                }
                for extra in jpegs.dropFirst() {
                    photos.append(
                        ScannedPhoto(
                            primary: extra.url, baseName: extra.baseName,
                            relativeDirectory: key.directory))
                }
            } else if let jpeg = jpegs.first {
                photos.append(
                    ScannedPhoto(
                        primary: jpeg.url, baseName: jpeg.baseName,
                        relativeDirectory: key.directory))
                for extra in jpegs.dropFirst() {
                    photos.append(
                        ScannedPhoto(
                            primary: extra.url, baseName: extra.baseName,
                            relativeDirectory: key.directory))
                }
            }
            // HEIC and other standalone formats never pair, even with a same-name
            // JPEG, because no camera writes that combination.
            for entry in others {
                photos.append(
                    ScannedPhoto(
                        primary: entry.url, baseName: entry.baseName,
                        relativeDirectory: key.directory))
            }
        }
        return photos.sorted { left, right in
            if left.relativeDirectory != right.relativeDirectory {
                return left.relativeDirectory < right.relativeDirectory
            }
            if left.baseName.lowercased() != right.baseName.lowercased() {
                return left.baseName.lowercased() < right.baseName.lowercased()
            }
            return left.primary.path < right.primary.path
        }
    }

    /// Drops files that live inside a rejects folder, for the variant that walks
    /// the folder first and filters afterwards.
    ///
    /// - Parameters:
    ///   - entries: Files from a listing that included the rejects folder.
    ///   - folderName: The configured rejects folder name, `_Rejected` by default.
    public static func removingRejected(
        _ entries: [ScanEntry],
        folderName: String = ScanRule.defaultRejectsFolderName
    ) -> [ScanEntry] {
        entries.filter { entry in
            !entry.relativePath.relativeDirectory
                .split(separator: "/")
                .contains(Substring(folderName))
        }
    }
}
