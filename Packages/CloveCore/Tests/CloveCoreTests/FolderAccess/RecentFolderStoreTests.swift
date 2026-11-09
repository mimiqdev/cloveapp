import Foundation
import Testing

import CloveCore

private func storeRecord(bookmark: Data = Data([0x01, 0x02])) throws -> RecentFolder {
    let id = try #require(UUID(uuidString: "4B3D1C4E-8A2F-4E0B-9A41-1F2C3D4E5F60"))
    return RecentFolder(
        id: id, bookmark: bookmark,
        pathSummary: "/Volumes/CARD/DCIM/100MSDCF",
        volumeName: "CARD",
        identityKeys: FolderIdentityKeys(volumeUUID: "VOLUME-A", fileIdentifier: "data:AAEC"),
        mediaType: .externalDrive,
        photoCount: 1_204,
        scanStatus: .partial,
        lastOpened: Date(timeIntervalSinceReferenceDate: 800_000_000.125))
}

@Test func recordsRoundTripThroughOneVersionedFile() throws {
    let root = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = RecentFolderStore(fileURL: root.appendingPathComponent("nested/recents.json"))
    #expect(try store.load().isEmpty)

    let records = [
        try storeRecord(),
        RecentFolder(
            id: UUID(), bookmark: Data(), pathSummary: "/Photos", mediaType: .internalVolume,
            scanStatus: .complete),
    ]
    try store.save(records)
    #expect(try store.load() == records)
    #expect(
        FileManager.default.fileExists(
            atPath: root.appendingPathComponent("nested/recents.json").path))
}

@Test func aNewerSchemaIsRefusedRatherThanGuessed() throws {
    let root = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("recents.json")
    try Data(#"{"version":99,"folders":[]}"#.utf8).write(to: file)
    let store = RecentFolderStore(fileURL: file)

    do {
        _ = try store.load()
        Issue.record("expected the newer schema to be refused")
    } catch let error as RecentFolderStoreError {
        #expect(error == .unsupportedVersion(99))
    }
    #expect(try Data(contentsOf: file) == Data(#"{"version":99,"folders":[]}"#.utf8))
}

@Test func corruptDataIsReportedWithItsErrorAndKept() throws {
    let root = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("recents.json")
    let corrupt = Data("{\"version\":1,\"folders\":[".utf8)
    try corrupt.write(to: file)
    let store = RecentFolderStore(fileURL: file)

    do {
        _ = try store.load()
        Issue.record("expected corrupt storage to be reported")
    } catch let error as RecentFolderStoreError {
        guard case .unreadable(let chain) = error else {
            Issue.record("expected an unreadable error, got \(error)")
            return
        }
        #expect(!chain.errors.isEmpty)
        #expect(!chain.message.isEmpty)
    }
    #expect(try Data(contentsOf: file) == corrupt)
}

@Test func unreadableFilePathIsReportedAsUnreadable() throws {
    let root = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    // Point the store at a directory: the file exists but has no readable payload.
    let store = RecentFolderStore(fileURL: root)

    do {
        _ = try store.load()
        Issue.record("expected a directory path to be unreadable")
    } catch let error as RecentFolderStoreError {
        guard case .unreadable(let chain) = error else {
            Issue.record("expected an unreadable error, got \(error)")
            return
        }
        #expect(!chain.errors.isEmpty)
    }
}

@Test func appliedSchemaVersionIsTheCurrentOne() throws {
    let root = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("recents.json")
    let store = RecentFolderStore(fileURL: file)
    try store.save([try storeRecord()])

    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
    let envelope = try #require(object as? [String: Any])
    #expect(envelope["version"] as? Int == RecentFolderStore.schemaVersion)
    let folders = try #require(envelope["folders"] as? [[String: Any]])
    #expect(folders.count == 1)
    #expect(folders.first?["scanStatus"] as? String == "partial")
}
