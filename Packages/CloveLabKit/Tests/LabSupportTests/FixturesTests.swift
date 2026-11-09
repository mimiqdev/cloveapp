import Foundation
import Testing

@testable import LabSupport

/// Directory URLs keep a trailing slash in their path; drop it for comparisons.
private func filePath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}

@Test func fixtureDirectoryDefaultsToTheSharedCache() {
    let directory = Fixtures.directory(environment: [:])
    #expect(filePath(directory) == "/Volumes/T7/Projects/.clove-fixtures")
    #expect(filePath(Fixtures.defaultDirectory) == filePath(directory))
}

@Test func fixtureDirectoryUsesTheEnvironmentOverride() {
    let directory = Fixtures.directory(
        environment: [Fixtures.directoryEnvironmentVariable: "/tmp/clove-fixtures"]
    )
    #expect(filePath(directory) == "/tmp/clove-fixtures")

    let blank = Fixtures.directory(environment: [Fixtures.directoryEnvironmentVariable: ""])
    #expect(filePath(blank) == filePath(Fixtures.defaultDirectory))
}

@Test func setResolvesUnderSetsAndOnlyWhenItExists() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("clove-fixtures-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("sets/card-basic", isDirectory: true),
        withIntermediateDirectories: true
    )

    let set = try #require(Fixtures.set("card-basic", directory: root))
    #expect(set.lastPathComponent == "card-basic")
    #expect(set.deletingLastPathComponent().lastPathComponent == "sets")

    #expect(Fixtures.set("name-collision", directory: root) == nil)
}

@Test func missingSetIsNilWhenTheCacheIsEmpty() throws {
    let empty = FileManager.default.temporaryDirectory
        .appendingPathComponent("clove-empty-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

    #expect(Fixtures.set("card-basic", directory: empty) == nil)
    #expect(
        Fixtures.set(
            "card-basic",
            environment: [Fixtures.directoryEnvironmentVariable: empty.path(percentEncoded: false)]
        ) == nil
    )
}

/// Skipped on a machine that has not run `mise run fixtures-sets`.
@Test(.enabled(if: Fixtures.set("card-basic") != nil))
func cardBasicSetIsAvailable() throws {
    let set = try #require(Fixtures.set("card-basic"))
    let dcim = set.appendingPathComponent("DCIM", isDirectory: true)
    #expect(FileManager.default.fileExists(atPath: dcim.path(percentEncoded: false)))
}
