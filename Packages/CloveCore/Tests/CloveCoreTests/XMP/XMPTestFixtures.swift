import Foundation
import Testing

import CloveCore

/// Locates the committed sidecar fixtures and the shared fixture sets.
///
/// Core tests must not import the lab support that owns `Fixtures`, so this repeats the
/// small cache lookup. A machine without the cache skips the set tests through the
/// `enabled(if:)` trait instead of failing.
enum XMPTestFixtures {
    /// Repository root, found by walking up from this file to the committed sidecars.
    static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            let candidate = url.appendingPathComponent("fixtures/xmp/README.md")
            if FileManager.default.fileExists(atPath: candidate.path) { return url }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    /// Cache directory, overridden by `CLOVE_FIXTURES_DIR` as `docs/fixtures.md` describes.
    static var cacheDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CLOVE_FIXTURES_DIR"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: "/Volumes/T7/Projects/.clove-fixtures", isDirectory: true)
    }

    /// `sets/<name>` in the cache, or `nil` when `mise run fixtures-sets` has not run.
    static func set(_ name: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent("sets/\(name)", isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue ? url : nil
    }

    /// Every committed `fixtures/xmp/*.xmp` packet, sorted by file name.
    static func committedPackets() throws -> [(name: String, data: Data)] {
        let directory = repositoryRoot.appendingPathComponent("fixtures/xmp", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".xmp") }
            .sorted()
        return try names.map { name in
            (name, try Data(contentsOf: directory.appendingPathComponent(name)))
        }
    }

    /// Every `.xmp`/`.XMP` sidecar under a set folder, sorted by path.
    static func sidecars(in directory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == "xmp" {
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    /// The packet name relative to its set folder, for test names and messages.
    static func relativeName(of url: URL, in directory: URL) -> String {
        let root = directory.path(percentEncoded: false)
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.count)).trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
    }
}

/// Wraps a description, or several, in the standard XMP packet envelope.
func xmpPacket(_ body: String) -> Data {
    Data(
        """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        \(body)
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """.utf8)
}
