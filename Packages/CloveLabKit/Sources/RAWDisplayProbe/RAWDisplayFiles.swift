import Foundation
import LabSupport

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
    case cannotOpenFolder

    public var errorDescription: String? {
        switch self {
        case .noRAWFiles: return "No RAW files were found in the selected folder."
        case .cannotOpenFolder: return "The selected folder could not be read."
        }
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
        let files = try imageFiles(in: folder)
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

    /// Cancellable path enumeration using the preview probe's discovery rules:
    /// hidden files and `_Rejected` are skipped, and only RAW and camera HEIF
    /// extensions are kept. It reads paths, never image pixels.
    static func imageFiles(in folder: URL) throws -> [URL] {
        try Task.checkCancellation()
        var enumerationError: (any Error)?
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                })
        else { throw RAWDisplayRunError.cannotOpenFolder }
        var files: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if url.lastPathComponent == "_Rejected" {
                enumerator.skipDescendants()
                continue
            }
            let fileExtension = url.pathExtension.lowercased()
            guard
                rawExtensions.contains(fileExtension)
                    || PhotoExtensions.heif.contains(fileExtension)
            else { continue }
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files.append(url)
            }
        }
        if let enumerationError { throw enumerationError }
        try Task.checkCancellation()
        return files.sorted { $0.path < $1.path }
    }

    private static func stemKey(_ file: URL) -> String {
        file.deletingPathExtension().standardizedFileURL.path.lowercased()
    }
}
