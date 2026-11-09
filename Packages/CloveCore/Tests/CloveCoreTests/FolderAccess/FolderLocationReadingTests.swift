import Foundation
import Testing

import CloveCore

@Test func theFileSystemReaderReportsIdentityHintsForARealFolder() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let facts = FileSystemLocationReader().facts(for: folder)
    #expect(facts.identityKeys.volumeUUID != nil)
    #expect(facts.identityKeys.fileIdentifier != nil)
    #expect(facts.volumeName != nil)
    #expect(facts.mediaType != .unknown)
    #expect(facts.volumeRootURL != nil)
    try Data("x".utf8).write(to: folder.appendingPathComponent("one.ARW"))
    #expect(
        try FileSystemLocationReader().listContents(of: folder).map(\.lastPathComponent)
            == ["one.ARW"])
}

@Test func factsForAMissingFolderStayUnknownRatherThanInventingIdentity() throws {
    let folder = try makeTemporaryFolder()
    let missing = folder.appendingPathComponent("gone")
    try FileManager.default.removeItem(at: folder)
    let facts = FileSystemLocationReader().facts(for: missing)
    #expect(facts.identityKeys.volumeUUID == nil || facts.identityKeys.fileIdentifier == nil)
    #expect(facts.volumeRootURL == nil)
    #expect(facts.mediaType == .unknown)
}
