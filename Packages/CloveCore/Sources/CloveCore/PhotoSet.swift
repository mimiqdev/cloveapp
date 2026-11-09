import Foundation

/// Invalid inputs to a single photo set; discovering competing files is the scanner's job.
/// These checks enforce PRD scan scope and How marks reach disk, rules 2–3 and 6.
public enum PhotoSetError: Error, Equatable, Sendable {
    /// A logical photo must contain at least one image (PRD P0-01).
    case missingImage
    /// A file does not have the format of its supplied slot (PRD Supported files).
    case invalidFile(URL)
    /// Images must share a directory and a case-insensitively matching stem (PRD scan scope).
    case mismatchedMember(URL)
    /// A resolved sidecar must replace the RAW extension in the same folder (G1 sidecar naming).
    case invalidSidecar(URL)
}

/// One logical photo assembled by the caller, with RAW > JPEG > HIF primary precedence.
/// G1 decision 1 and PRD P0-01: companions share the primary's folder and stem.
/// Unsupported JPEG+HIF without RAW follows the generic rule: JPEG primary, HIF companion.
/// This type validates one set; it never scans, discovers sidecars, or resolves ambiguity.
public struct PhotoSet: Identifiable, Hashable, Sendable {
    /// Stable folder/subfolder/stem identity, independent of extension and membership (PRD P0-01).
    public let id: PhotoIdentity
    /// The source of truth, selected by G1 decision 1's precedence.
    public let primary: PhotoFile
    /// The optional JPEG reference when RAW is primary (G1 decisions 1–2).
    public let jpegCompanion: PhotoFile?
    /// The optional HIF reference when RAW or JPEG is primary (G1 decision 1).
    public let heifCompanion: PhotoFile?
    /// An already resolved sidecar's actual spelling; nil does not imply no XMP destination.
    /// Discovery and ambiguity handling belong to the caller (G1 sidecar naming).
    public let sidecarURL: URL?

    /// Builds a set from already paired files, preserving all supplied URLs (PRD scan scope).
    /// Supply the opened folder's opaque identity and the containing relative folder path.
    /// An optional sidecar is accepted only for RAW; it must have a matching stem and `.xmp`
    /// extension, ignoring case. Appended-extension packets are invalid (G1 sidecar naming).
    public init(
        folderID: FolderIdentity,
        relativeFolderPath: String,
        rawURL: URL? = nil,
        jpegURL: URL? = nil,
        heifURL: URL? = nil,
        sidecarURL: URL? = nil
    ) throws {
        func file(_ url: URL?, format: PhotoFormat) throws -> PhotoFile? {
            guard let url else { return nil }
            guard let file = PhotoFile(url: url), file.format == format else {
                throw PhotoSetError.invalidFile(url)
            }
            return file
        }
        let raw = try file(rawURL, format: .raw)
        let jpeg = try file(jpegURL, format: .jpeg)
        let heif = try file(heifURL, format: .heif)
        guard let primary = raw ?? jpeg ?? heif else { throw PhotoSetError.missingImage }
        let directory = primary.url.deletingLastPathComponent()
        let stem = primary.url.deletingPathExtension().lastPathComponent
        for member in [raw, jpeg, heif].compactMap({ $0 }) {
            guard member.url.deletingLastPathComponent() == directory,
                member.url.deletingPathExtension().lastPathComponent.lowercased()
                    == stem.lowercased()
            else {
                throw PhotoSetError.mismatchedMember(member.url)
            }
        }
        if let sidecarURL {
            guard raw != nil, sidecarURL.isFileURL,
                sidecarURL.deletingLastPathComponent() == directory,
                sidecarURL.pathExtension.lowercased() == "xmp",
                sidecarURL.deletingPathExtension().lastPathComponent.lowercased()
                    == stem.lowercased()
            else {
                throw PhotoSetError.invalidSidecar(sidecarURL)
            }
        }
        self.id = PhotoIdentity(
            folderID: folderID, relativeFolderPath: relativeFolderPath, stem: stem)
        self.primary = primary
        self.jpegCompanion = raw == nil ? nil : jpeg
        self.heifCompanion = primary.format == .heif ? nil : heif
        self.sidecarURL = sidecarURL
    }

    /// Image members in primary, JPEG companion, HIF companion order (G1 decision 1).
    public var imageFiles: [PhotoFile] {
        [primary, jpegCompanion, heifCompanion].compactMap { $0 }
    }

    /// Every known member, including a discovered sidecar, for whole-set moves (G1 decision 5).
    /// A prospective, undiscovered XMP destination is not an existing member.
    public var fileURLs: [URL] {
        imageFiles.map(\.url) + (sidecarURL.map { [$0] } ?? [])
    }

    /// Identifies a member's role, or nil for files outside this set (G1 decision 1).
    public func role(of file: PhotoFile) -> PhotoFileRole? {
        if file == primary { return .primary }
        if file == jpegCompanion { return .jpegCompanion }
        if file == heifCompanion { return .heifCompanion }
        return nil
    }

    /// Pure routing of each mark to its storage, per G1 decisions 2, 5 and 6.
    public var markPersistence: MarkPersistence { MarkPersistence(for: self) }
}
