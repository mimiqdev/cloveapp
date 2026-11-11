import Foundation

/// Run-local labels for report rows.
///
/// A report is shared from a private folder, so it never records the folder or file
/// names. Each RAW becomes `raw-01.<EXT>`, and its camera preview shares the photo's
/// number with its own extension (`raw-01.HIF`). The numbers follow the sorted RAW
/// order used by the run; they are not stable across folders or runs.
public struct RAWDisplayFileLabels: Sendable {
    private let labelsByPath: [String: String]

    public init(pairs: [RAWDisplayPair]) {
        var labels: [String: String] = [:]
        for (index, pair) in pairs.enumerated() {
            let number = String(format: "%02d", index + 1)
            labels[Self.key(pair.raw)] = "raw-\(number).\(pair.raw.pathExtension.uppercased())"
            if let camera = pair.cameraPreview {
                labels[Self.key(camera)] =
                    "raw-\(number).\(camera.pathExtension.uppercased())"
            }
        }
        labelsByPath = labels
    }

    /// The report label for a file in this run.
    public func label(for url: URL) -> String {
        labelsByPath[Self.key(url)] ?? "file-unknown.\(url.pathExtension.uppercased())"
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
