import Darwin
import Foundation

@testable import SpikeS6Scan

/// Temporary trees for the S6 tests. Every helper writes below its own
/// UUID-named temporary folder and never into the fixture cache.
enum ScanTestTree {
    /// A fresh container folder, plus a cleanup closure.
    static func container() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-s6-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A small generated tree, so the tests do not spend a second on 2,000 files.
    static func generated(
        in container: URL,
        fileTarget: Int = 200,
        folders: [String] = ["100CANON", "101CANON"],
        rejectsFileCount: Int = 10
    ) async throws -> ScanTreeSummary {
        try await ScanTree.makeTree(
            in: container,
            plan: ScanTreePlan(
                fileTarget: fileTarget,
                folders: folders,
                rejectsFileCount: rejectsFileCount,
                appleDoubleCount: 2))
    }

    /// A tree with exactly the names a pairing rule needs.
    static func handmade(in container: URL) throws -> URL {
        let first = container.appendingPathComponent("DCIM/100CANON", isDirectory: true)
        let second = container.appendingPathComponent("DCIM/101CANON", isDirectory: true)
        let rejects = first.appendingPathComponent("_Rejected", isDirectory: true)
        for directory in [first, second, rejects] {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
        let firstFiles = [
            "IMG_0001.CR3", "IMG_0001.JPG",  // pair
            "IMG_0002.JPG",  // standalone JPEG
            "IMG_0003.HEIC",  // standalone HEIC
            "IMG_0004.CR3", "IMG_0004.jpeg",  // pair, lowercase JPEG extension
            "IMG_0005.NEF",  // standalone RAW
            "IMG_0006.CR3", "IMG_0006.XMP",  // sidecar next to a RAW, not a photo
            "IMG_0007.ARW", "IMG_0007.HIF",  // Sony RAW+HEIF pair
            "IMG_0008.ARW", "IMG_0008.JPG", "IMG_0008.hif",  // JPEG wins; HEIF is standalone
            "MVI_0007.MOV", "NOTES.txt", "._IMG_0001.CR3", ".DS_Store",
        ]
        for name in firstFiles {
            try Data("x".utf8).write(to: first.appendingPathComponent(name))
        }
        // Same base name in another folder must not pair with the first folder.
        try Data("x".utf8).write(to: second.appendingPathComponent("IMG_0001.CR3"))
        try Data("x".utf8).write(to: second.appendingPathComponent("IMG_0002.JPG"))
        try Data("x".utf8).write(to: rejects.appendingPathComponent("IMG_9000.JPG"))
        try Data("x".utf8).write(to: rejects.appendingPathComponent("IMG_9001.CR3"))
        return container
    }

    /// `realpath`, because `FileManager.enumerator` resolves `/var` to `/private/var`
    /// while `URL.resolvingSymlinksInPath()` does not.
    static func realPath(of url: URL) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path(percentEncoded: false), &buffer) != nil else {
            return url.path(percentEncoded: false)
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Photo files below `root` that a scan should return, counted independently
    /// of ``ScanLister`` so a filter bug cannot hide itself.
    static func expectedPhotoFiles(in root: URL, rejects: String = "_Rejected") throws -> [String] {
        var found: [String] = []
        let resolved = ScanTestTree.realPath(of: root)
        let prefix = resolved + "/"
        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: resolved),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: { _, _ in true }
            )
        else { return [] }
        for case let url as URL in enumerator {
            let path = url.path(percentEncoded: false)
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            let name = url.lastPathComponent
            if ScanRule.isHidden(name) {
                if url.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.hasDirectoryPath {
                if name == rejects { enumerator.skipDescendants() }
                continue
            }
            if relative.split(separator: "/").dropLast().contains(Substring(rejects)) { continue }
            if ScanRule.isPhotoFile(name) {
                found.append(relative)
            }
        }
        return found.sorted()
    }
}
