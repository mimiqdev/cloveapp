import Foundation
import Testing

import CloveCore

@Test func identityKeysNeedBothSidesToVerify() {
    let saved = FolderIdentityKeys(volumeUUID: "VOLUME", fileIdentifier: "data:AAEC")
    #expect(saved.checkIdentity(against: saved) == .verified)
    #expect(
        saved.checkIdentity(
            against: FolderIdentityKeys(volumeUUID: "VOLUME", fileIdentifier: "data:AAED"))
            == .mismatch)
    #expect(
        saved.checkIdentity(
            against: FolderIdentityKeys(volumeUUID: "OTHER", fileIdentifier: "data:AAEC"))
            == .mismatch)
    // A missing key on either side is provisional, never a silent verification.
    #expect(saved.checkIdentity(against: FolderIdentityKeys(volumeUUID: "VOLUME")) == .weak)
    #expect(
        saved.checkIdentity(
            against: FolderIdentityKeys(volumeUUID: "OTHER", fileIdentifier: nil)) == .mismatch)
    #expect(saved.checkIdentity(against: FolderIdentityKeys()) == .weak)
    #expect(FolderIdentityKeys().checkIdentity(against: saved) == .weak)
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

@Test func aRecordRoundTripsAsCodable() throws {
    let record = RecentFolder(
        id: UUID(), bookmark: Data([0x00, 0xFF]), pathSummary: "/Photos",
        volumeName: nil, identityKeys: FolderIdentityKeys(volumeUUID: "V", fileIdentifier: "F"),
        mediaType: .cloudProvider, photoCount: nil, scanStatus: .complete,
        lastOpened: Date(timeIntervalSinceReferenceDate: 800_000_000.5))
    let data = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(RecentFolder.self, from: data) == record)
}

@Test func identityKeysAreCompleteOnlyWhenBothArePresent() {
    #expect(FolderIdentityKeys(volumeUUID: "V", fileIdentifier: "F").isComplete)
    #expect(!FolderIdentityKeys(volumeUUID: "V").isComplete)
    #expect(!FolderIdentityKeys(fileIdentifier: "F").isComplete)
    #expect(!FolderIdentityKeys().isComplete)
}
