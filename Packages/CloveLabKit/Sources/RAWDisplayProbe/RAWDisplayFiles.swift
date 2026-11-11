import Foundation
import LabSupport
import PreviewProbe

/// One logical photo for the probe: the RAW and, when present, its camera HEIF companion.
public struct RAWDisplayPair: Sendable, Hashable {
    public var raw: URL
    /// The same-folder HEIF/HIF companion, matched case-insensitively by stem.
    public var cameraPreview: URL?

    public init(raw: URL, cameraPreview: URL?) {
        self.raw = raw
        self.cameraPreview = cameraPreview
    }
}

/// Why a run cannot start.
public enum RAWDisplayRunError: Error, LocalizedError {
    case noRAWFiles

    public var errorDescription: String? {
        "No RAW files were found in the selected folder."
    }
}

/// Finds the RAW files and their camera HEIF companions.
public enum RAWDisplayFiles {
    /// Extensions the probe treats as RAW. Raster and HEIF extensions are excluded.
    public static let rawExtensions: Set<String> = [
        "cr3", "nef", "arw", "raf", "orf", "rw2", "dng",
    ]

    /// Sorted RAW files and their same-folder HEIF companions.
    ///
    /// Enumeration is the preview probe's, so hidden files and `_Rejected` are
    /// skipped the same way a real scan skips them.
    public static func pairs(in folder: URL) throws -> [RAWDisplayPair] {
        let files = try PreviewMeasurement.files(in: folder)
        var previews: [String: URL] = [:]
        for file in files where PhotoExtensions.heif.contains(file.pathExtension.lowercased()) {
            let key = stemKey(file)
            // A camera writes .HIF; prefer it when a folder holds more than one preview.
            if let existing = previews[key], existing.pathExtension.lowercased() == "hif" {
                continue
            }
            previews[key] = file
        }
        return
            files
            .filter { rawExtensions.contains($0.pathExtension.lowercased()) }
            .map { raw in RAWDisplayPair(raw: raw, cameraPreview: previews[stemKey(raw)]) }
    }

    /// Path relative to the tested folder, for reports. Falls back to the file name.
    public static func relativePath(_ file: URL, in folder: URL) -> String {
        let root = folder.standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : file.lastPathComponent
    }

    private static func stemKey(_ file: URL) -> String {
        file.deletingPathExtension().standardizedFileURL.path.lowercased()
    }
}
