import Foundation
import Testing

@testable import CloveCore

private let green = ColourLabel(colour: .green)
private let three = Rating(rawValue: 3) ?? .unrated

/// Reads the packet back through an independent codec, so the assertion is not the writer's
/// own return value.
private func marks(at url: URL) throws -> XMPMarks {
    try XMPCodec().read(try Data(contentsOf: url))
}

@Test func aRatingAndLabelAreWrittenAndConfirmed() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let double = WriteFileSystemDouble()
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(
        XMPEdit(rating: .set(three), label: .set(green)), to: sidecar)

    #expect(result.isSaved, "\(String(describing: result.failure))")
    #expect(result.attemptCount == 1)
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(three), label: green))
    #expect(try folder.stagingNames().isEmpty)
}

@Test func aNewSidecarIsCreatedWhenNoneExists() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let writer = SidecarMarkWriter(fileSystem: WriteFileSystemDouble())

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.isSaved)
    let data = try Data(contentsOf: sidecar)
    #expect(String(decoding: data, as: UTF8.self).contains("<?xpacket begin="))
    #expect(try marks(at: sidecar).rating == .rated(three))
}

@Test func unknownBytesSurviveTheWriteThroughTheCodec() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    try writeTestUnknownPacket.write(to: sidecar)
    let writer = SidecarMarkWriter(fileSystem: WriteFileSystemDouble())

    let result = await writer.write(XMPEdit.label(green), to: sidecar)

    #expect(result.isSaved)
    let text = try String(contentsOf: sidecar, encoding: .utf8)
    #expect(text.contains("keep this byte"))
    #expect(text.contains("https://acme.example/ns/1.0/"))
    #expect(
        try marks(at: sidecar)
            == XMPMarks(rating: .rated(Rating(rawValue: 1) ?? .unrated), label: green))
}

@Test func aZeroByteSidecarIsRefusedAndKept() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    try Data().write(to: sidecar)
    let writer = SidecarMarkWriter(fileSystem: WriteFileSystemDouble())

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.failure?.reason == .packetRefused)
    #expect(result.failure?.codecError == .emptyPacket)
    #expect(try Data(contentsOf: sidecar).isEmpty, "Clove must not replace a packet it cannot read")
    #expect(try folder.stagingNames().isEmpty)
}

@Test func anExistingPermissionSetIsKeptAcrossTheReplacement() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    try writeTestUnknownPacket.write(to: sidecar)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o640)], ofItemAtPath: sidecar.path)
    let writer = SidecarMarkWriter(fileSystem: WriteFileSystemDouble())

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.isSaved)
    let attributes = try FileManager.default.attributesOfItem(atPath: sidecar.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o640)
}

@Test func aReadBackMismatchIsNeverSaved() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    try writeTestUnknownPacket.write(to: sidecar)
    let original = try Data(contentsOf: sidecar)
    let double = WriteFileSystemDouble()
    // The first read is the packet Clove edits; the second is the read-back after the rename.
    double.readResult = { record in
        record.url == sidecar && record.count == 2 ? original : nil
    }
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.failure?.reason == .notConfirmed)
    #expect(result.isSaved == false)
    #expect(try folder.stagingNames().isEmpty)
    // The packet really was replaced; the change is merely unconfirmed.
    #expect(try marks(at: sidecar).rating == .rated(three))
}

@Test func anExternalChangeIsRetriedOnceAndKeepsTheOtherAppsBytes() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let double = WriteFileSystemDouble()
    // The 2nd attributes read is the conflict check before the rename.
    double.beforeOperation = { record in
        guard record.step == .attributes, record.url == sidecar, record.count == 2 else { return }
        try? writeTestUnknownPacket.write(to: sidecar)
    }
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.isSaved, "\(String(describing: result.failure))")
    #expect(result.attemptCount == 2)
    let text = try String(contentsOf: sidecar, encoding: .utf8)
    #expect(text.contains("keep this byte"))
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(three), label: .clear))
}

@Test func aSecondExternalChangeIsAConflictAndNothingIsOverwritten() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let double = WriteFileSystemDouble()
    // Every conflict check sees another app's newer packet.
    double.beforeOperation = { record in
        guard record.step == .attributes, record.url == sidecar, record.count % 2 == 0 else {
            return
        }
        try? writeTestUnknownPacket.write(to: sidecar)
    }
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.failure?.reason == .conflict)
    #expect(result.attemptCount == 2)
    #expect(try folder.stagingNames().isEmpty)
    #expect(try marks(at: sidecar).rating == .rated(Rating(rawValue: 1) ?? .unrated))
}

@Test func everyInjectedStepFailureLeavesNoStagingAndTheRightReason() async throws {
    let cases:
        [(step: WriteFileSystemDouble.Step, error: any Error, reason: MarkWriteFailureReason)] =
            [
                (.read, POSIXError(.EACCES), .permissionLost),
                (.attributes, POSIXError(.EROFS), .readOnlyStorage),
                (.writeStaging, POSIXError(.ENOSPC), .insufficientSpace),
                (.synchronize, POSIXError(.ENOENT), .locationUnavailable),
                (.replace, POSIXError(.EACCES), .permissionLost),
                (.setPermissions, POSIXError(.EROFS), .readOnlyStorage),
            ]
    for testCase in cases {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let sidecar = folder.file("MMQ05184.xmp")
        try writeTestUnknownPacket.write(to: sidecar)
        let original = try Data(contentsOf: sidecar)
        let double = WriteFileSystemDouble()
        double.fail(testCase.step, with: testCase.error)
        let writer = SidecarMarkWriter(fileSystem: double)

        let result = await writer.write(XMPEdit.rating(three), to: sidecar)

        #expect(result.failure?.reason == testCase.reason, "step \(testCase.step)")
        #expect(result.isSaved == false)
        #expect(try folder.stagingNames().isEmpty, "step \(testCase.step) left a staging file")
        // Permissions are applied to the staging file, so every failure leaves the
        // destination exactly as it was.
        #expect(try Data(contentsOf: sidecar) == original, "step \(testCase.step)")
    }
}

@Test func concurrentWritesToOneSidecarDoNotLoseAField() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let writer = SidecarMarkWriter(fileSystem: WriteFileSystemDouble())

    async let ratingResult = writer.write(XMPEdit.rating(three), to: sidecar)
    async let labelResult = writer.write(XMPEdit.label(green), to: sidecar)
    let results = await [ratingResult, labelResult]

    #expect(results.filter { !$0.isSaved }.isEmpty)
    // Each read-modify-write saw the other's rename, so neither field was lost.
    #expect(try marks(at: sidecar) == XMPMarks(rating: .rated(three), label: green))
}

@Test func aReadBackThatIsNotAPacketIsNotConfirmed() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let double = WriteFileSystemDouble()
    // The read-back after the rename returns bytes the codec must refuse.
    double.readResult = { record in
        record.url == sidecar && record.count == 2 ? Data("<broken".utf8) : nil
    }
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.failure?.reason == .notConfirmed)
    #expect(result.failure?.codecError != nil)
    #expect(try folder.stagingNames().isEmpty)
}

@Test func aSidecarMissingAfterTheReplaceIsNotConfirmed() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    try writeTestUnknownPacket.write(to: sidecar)
    let double = WriteFileSystemDouble()
    // Another presenter removes the packet between the rename and the read-back.
    double.beforeOperation = { record in
        guard record.step == .read, record.url == sidecar, record.count == 2 else { return }
        try? FileManager.default.removeItem(at: sidecar)
    }
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    #expect(result.failure?.reason == .notConfirmed)
    #expect(!FileManager.default.fileExists(atPath: sidecar.path))
    #expect(try folder.stagingNames().isEmpty)
}

@Test func aCodecRefusalKeepsTheErrorAndWritesNothing() async throws {
    let folder = try WriteTestFolder()
    defer { folder.remove() }
    let sidecar = folder.file("MMQ05184.xmp")
    let malformed = Data("<x:xmpmeta".utf8)
    try malformed.write(to: sidecar)
    let double = WriteFileSystemDouble()
    let writer = SidecarMarkWriter(fileSystem: double)

    let result = await writer.write(XMPEdit.rating(three), to: sidecar)

    guard case .malformedXML? = result.failure?.codecError else {
        Issue.record(
            "Expected the codec's malformedXML error, got \(String(describing: result.failure))")
        return
    }
    #expect(result.failure?.reason == .packetRefused)
    #expect(try Data(contentsOf: sidecar) == malformed)
    #expect(double.count(of: .writeStaging) == 0)
}
