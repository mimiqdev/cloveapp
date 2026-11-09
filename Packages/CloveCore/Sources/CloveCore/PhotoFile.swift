import Foundation

/// The closed file families used by PRD P0-01, Supported files, and G1 decision 1.
public enum PhotoFormat: String, CaseIterable, Hashable, Sendable {
    /// Camera RAW, including standalone DNG (PRD How marks reach disk, rule 6).
    case raw
    /// JPEG, which is primary only when RAW is absent (G1 decision 1).
    case jpeg
    /// HIF/HEIF/HEIC, previewed when the system supports it (PRD Supported files).
    case heif

    /// The repository's RAW baseline for PRD Supported files, also used by its fixture set.
    /// This is extension classification, not a camera/decoder compatibility guarantee.
    public static let rawExtensions: Set<String> = [
        "cr3", "nef", "arw", "raf", "orf", "rw2", "dng",
    ]

    /// Classifies an extension without a leading dot, ignoring case, with no content-type lookup.
    /// PRD Supported files includes HIF, HEIF and HEIC; PRD scan scope is case-insensitive.
    public init?(pathExtension: String) {
        let value = pathExtension.lowercased()
        if Self.rawExtensions.contains(value) {
            self = .raw
        } else {
            switch value {
            case "jpg", "jpeg": self = .jpeg
            case "hif", "heif", "heic": self = .heif
            default: return nil
            }
        }
    }
}

/// One image file, retaining its actual URL and spelling (PRD P0-01, G1 decision 1).
public struct PhotoFile: Hashable, Sendable {
    /// The on-disk URL as supplied; classification never rewrites it (PRD scan scope).
    public let url: URL
    /// The extension-derived family, independent of preview support (PRD Supported files).
    public let format: PhotoFormat

    /// Accepts a supported file URL without reading the file (PRD Supported files).
    public init?(url: URL) {
        guard url.isFileURL, let format = PhotoFormat(pathExtension: url.pathExtension) else {
            return nil
        }
        self.url = url
        self.format = format
    }
}

/// A file's role in a logical photo, following G1 decision 1.
public enum PhotoFileRole: Hashable, Sendable {
    /// RAW first, otherwise JPEG, otherwise HIF/HEIF (G1 decision 1).
    case primary
    /// A same-folder, same-stem JPEG reference, never modified (G1 decisions 1–2).
    case jpegCompanion
    /// A same-folder, same-stem HIF/HEIF reference, never modified (G1 decisions 1–2).
    case heifCompanion
}
