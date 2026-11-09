import Foundation
import Testing

import CloveCore

/// One saved key pair, one found key pair, and the check they must produce (G1 folder access).
private struct IdentityCase: Sendable, CustomStringConvertible {
    let saved: FolderIdentityKeys
    let found: FolderIdentityKeys
    let expected: FolderIdentityCheck

    var description: String {
        "saved \(saved) / found \(found)"
    }

    private static let volume = "VOLUME"
    private static let otherVolume = "OTHER-VOLUME"
    private static let file = "data:AAEC"
    private static let otherFile = "data:AAED"

    static let all: [IdentityCase] = [
        // Both sides have each key: compare them.
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            expected: .verified),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: otherFile),
            expected: .mismatch),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(volumeUUID: otherVolume, fileIdentifier: file),
            expected: .mismatch),
        // The record has the key and the folder does not: never accept it as the same folder.
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(volumeUUID: volume),
            expected: .mismatch),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(fileIdentifier: file),
            expected: .mismatch),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(),
            expected: .mismatch),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume),
            found: FolderIdentityKeys(fileIdentifier: file),
            expected: .mismatch),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume),
            found: FolderIdentityKeys(),
            expected: .mismatch),
        // The record has no key for a value: weak, because the folder may report it later.
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume),
            found: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            expected: .weak),
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume),
            found: FolderIdentityKeys(volumeUUID: volume),
            expected: .weak),
        IdentityCase(
            saved: FolderIdentityKeys(fileIdentifier: file),
            found: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            expected: .weak),
        IdentityCase(
            saved: FolderIdentityKeys(fileIdentifier: file),
            found: FolderIdentityKeys(fileIdentifier: otherFile),
            expected: .mismatch),
        IdentityCase(
            saved: FolderIdentityKeys(),
            found: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            expected: .weak),
        IdentityCase(
            saved: FolderIdentityKeys(),
            found: FolderIdentityKeys(),
            expected: .weak),
        // A mismatch on either key wins over a weak key.
        IdentityCase(
            saved: FolderIdentityKeys(volumeUUID: volume, fileIdentifier: file),
            found: FolderIdentityKeys(volumeUUID: otherVolume),
            expected: .mismatch),
    ]
}

@Test(arguments: IdentityCase.all)
private func identityKeysAreComparedPerKey(testCase: IdentityCase) {
    #expect(testCase.saved.checkIdentity(against: testCase.found) == testCase.expected)
}

@Test func theRecordIdentityComesFromItsStableID() {
    let id = UUID()
    let record = RecentFolder(
        id: id, bookmark: Data([0x01]), pathSummary: "/Volumes/CARD/DCIM",
        volumeName: "CARD", identityKeys: FolderIdentityKeys(volumeUUID: "A", fileIdentifier: "B"),
        mediaType: .externalDrive, photoCount: 42, scanStatus: .partial)
    #expect(record.identity == FolderIdentity(rawValue: id.uuidString))
    #expect(record.identity.rawValue != record.pathSummary)
    #expect(record.identity.rawValue != (record.volumeName ?? ""))
}

@Test func aNewRecordHasNoScanStatusUntilAScanRuns() throws {
    let record = RecentFolder(bookmark: Data([0x01]), pathSummary: "/Photos")
    #expect(record.photoCount == nil)
    #expect(record.scanStatus == nil)
    let data = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(RecentFolder.self, from: data).scanStatus == nil)
}

@Test func aRecordRoundTripsAsCodable() throws {
    let record = RecentFolder(
        id: UUID(), bookmark: Data([0x00, 0xFF]), pathSummary: "/Photos",
        volumeName: nil, identityKeys: FolderIdentityKeys(volumeUUID: "V", fileIdentifier: "F"),
        mediaType: .cloudProvider, photoCount: nil, scanStatus: .complete,
        lastOpened: Date(timeIntervalSinceReferenceDate: 800_000_000.5))
    let data = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(RecentFolder.self, from: data) == record)
}

@Test func aRecordWrittenWithoutAScanStatusDecodesWithNone() throws {
    let record = RecentFolder(
        id: UUID(), bookmark: Data([0x01]), pathSummary: "/Photos", photoCount: 3,
        scanStatus: .complete)
    let encoded = try JSONEncoder().encode(record)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "scanStatus")
    let withoutStatus = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(RecentFolder.self, from: withoutStatus)
    #expect(decoded.id == record.id)
    #expect(decoded.photoCount == 3)
    #expect(decoded.scanStatus == nil)
}

@Test func identityKeysAreCompleteOnlyWhenBothArePresent() {
    #expect(FolderIdentityKeys(volumeUUID: "V", fileIdentifier: "F").isComplete)
    #expect(!FolderIdentityKeys(volumeUUID: "V").isComplete)
    #expect(!FolderIdentityKeys(fileIdentifier: "F").isComplete)
    #expect(!FolderIdentityKeys().isComplete)
}
