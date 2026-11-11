import Foundation
import Testing

@testable import CloveCore

/// S1's failure table drives U7's situations; each case checks one row.
@Test func posixErrorsMapToTheSituationsU7Shows() {
    let cases: [(POSIXErrorCode, MarkWriteFailureReason)] = [
        (.EACCES, .permissionLost),
        (.EPERM, .permissionLost),
        (.EROFS, .readOnlyStorage),
        (.ENOSPC, .insufficientSpace),
        (.ENOENT, .locationUnavailable),
        (.EIO, .unknown),
    ]
    for (code, reason) in cases {
        let failure = MarkWriteFailure(classifying: POSIXError(code))
        #expect(failure.reason == reason, "\(code)")
        #expect(failure.errorChain.first?.domain == NSPOSIXErrorDomain)
        #expect(failure.errorChain.first?.code == Int(code.rawValue))
    }
}

@Test func cocoaErrorsMapToTheSituationsU7Shows() {
    let permission = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    let writePermission = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    let readOnly = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError)
    let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
    let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
    let readMissing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)

    #expect(MarkWriteFailure(classifying: permission).reason == .permissionLost)
    #expect(MarkWriteFailure(classifying: writePermission).reason == .permissionLost)
    #expect(MarkWriteFailure(classifying: readOnly).reason == .readOnlyStorage)
    #expect(MarkWriteFailure(classifying: full).reason == .insufficientSpace)
    #expect(MarkWriteFailure(classifying: missing).reason == .locationUnavailable)
    #expect(MarkWriteFailure(classifying: readMissing).reason == .locationUnavailable)
}

@Test func aGenericWriteErrorIsNeverCalledReadOnlyOrFull() {
    let generic = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)

    let failure = MarkWriteFailure(classifying: generic)

    // S1: a generic failed write must not be inferred as full or read-only storage.
    #expect(failure.reason == .unknown)
    #expect(failure.errorChain.first?.code == NSFileWriteUnknownError)
}

@Test func theDeepestRecognisedEvidenceWins() {
    let outer = NSError(
        domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
        userInfo: [NSUnderlyingErrorKey: POSIXError(.EROFS)])
    let inner = NSError(
        domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
        userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC)])

    #expect(MarkWriteFailure(classifying: outer).reason == .readOnlyStorage)
    #expect(MarkWriteFailure(classifying: inner).reason == .insufficientSpace)
}

@Test func anErrorChainKeepsEveryLevelAndEveryParallelError() {
    let parallel = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
    let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
    let root = NSError(
        domain: "ACMEProvider", code: 17,
        userInfo: [
            NSUnderlyingErrorKey: underlying,
            NSMultipleUnderlyingErrorsKey: [parallel],
        ])

    let entries = MarkWriteErrorEntry.chain(of: root)

    #expect(entries.map(\.domain) == ["ACMEProvider", NSPOSIXErrorDomain, NSCocoaErrorDomain])
    #expect(entries.map(\.code) == [17, Int(ENOENT), NSFileReadNoSuchFileError])
    #expect(MarkWriteFailure(classifying: root).reason == .locationUnavailable)
}

@Test func aCodecRefusalKeepsItsTypedError() {
    let failure = MarkWriteFailure(classifying: XMPCodecError.emptyPacket)

    #expect(failure.reason == .packetRefused)
    #expect(failure.codecError == .emptyPacket)
    #expect(failure.storeError == nil)
}

@Test func aStorageRefusalKeepsItsTypedError() {
    let url = URL(fileURLWithPath: "/tmp/Clove-test-marks.json")
    let corrupt = MarkWriteFailure(
        classifying: CloveMarkStoreError.corruptStorage(url, reason: "not JSON"))

    #expect(corrupt.reason == .unknown)
    #expect(corrupt.storeError == .corruptStorage(url, reason: "not JSON"))
    #expect(corrupt.codecError == nil)
}

@Test func anAmbiguousSidecarHasItsOwnReason() {
    let failure = MarkWriteFailure(
        reason: .ambiguousSidecar, message: "MMQ05184.xmp and MMQ05184.ARW.xmp")

    #expect(failure.reason == .ambiguousSidecar)
    #expect(failure.message.contains("MMQ05184.ARW.xmp"))
}

@Test func statesNeverReportAnUnconfirmedChangeAsSaved() {
    #expect(
        MarkChangeState.failed(
            MarkWriteFailure(reason: .conflict, message: "changed twice")
        ).isSaved == false)
    #expect(MarkChangeState.savedInSidecar.isSaved)
    #expect(MarkChangeState.savedInCloveOnly.isSaved)
}
