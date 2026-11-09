import Foundation

/// Creates an empty folder under the system temporary directory.
func makeTemporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "clove-folder-access-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Compares URLs after resolving the temporary directory's symlink to `/private/var`.
func isSameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL.path
        == rhs.resolvingSymlinksInPath().standardizedFileURL.path
}
