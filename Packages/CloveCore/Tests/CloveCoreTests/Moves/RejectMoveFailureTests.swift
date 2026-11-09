import Foundation
import Testing

@testable import CloveCore

/// The move's failure reasons reuse C4's classifier and add only the move's own codes.
///
/// PRD P0-10 requires `EXDEV` and a taken destination to be failures with their reasons, and
/// S1's table decides which `NSError` chain means which situation. The cases below pin the
/// mapping so a later edit cannot silently report a different story.
@Suite("Reject move failure", .timeLimit(.minutes(1)))
struct RejectMoveFailureTests {
    /// `EXDEV` is the same-volume rule, never a copy fallback (PRD P0-10).
    @Test func classifiesEXDEVAsADifferentVolume() {
        let failure = RejectMoveFailure(classifying: POSIXError(.EXDEV))
        #expect(failure.reason == .differentVolume)
        #expect(failure.errorChain.first?.domain == NSPOSIXErrorDomain)
        #expect(failure.errorChain.first?.code == Int(EXDEV))
    }

    /// An exclusive rename's `EEXIST` is the collision PRD P0-10 never overwrites.
    @Test func classifiesAnExistingDestinationAsAConflict() {
        #expect(RejectMoveFailure(classifying: POSIXError(.EEXIST)).reason == .conflict)
        let cocoa = NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError,
            userInfo: [NSUnderlyingErrorKey: POSIXError(.EEXIST)])
        #expect(RejectMoveFailure(classifying: cocoa).reason == .conflict)
    }

    /// The write lane's own reasons carry over unchanged (G1 decision 5's shared vocabulary).
    @Test func classifiesTheWriteLaneReasons() {
        #expect(RejectMoveFailure(classifying: POSIXError(.EROFS)).reason == .readOnlyStorage)
        #expect(RejectMoveFailure(classifying: POSIXError(.EACCES)).reason == .permissionLost)
        #expect(RejectMoveFailure(classifying: POSIXError(.EPERM)).reason == .permissionLost)
        #expect(RejectMoveFailure(classifying: POSIXError(.ENOSPC)).reason == .insufficientSpace)
        #expect(RejectMoveFailure(classifying: POSIXError(.ENOENT)).reason == .locationUnavailable)
        let cocoa = NSError(
            domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError,
            userInfo: [NSUnderlyingErrorKey: POSIXError(.EROFS)])
        #expect(RejectMoveFailure(classifying: cocoa).reason == .readOnlyStorage)
    }

    /// A generic error stays unknown instead of guessing a full or read-only location (S1).
    @Test func keepsAnUnrecognisedErrorUnknown() {
        let failure = RejectMoveFailure(classifying: POSIXError(.EIO))
        #expect(failure.reason == .unknown)
        #expect(failure.message.isEmpty == false)
        #expect(failure.description.hasPrefix("unknown: "))
    }

    /// A reason set by the move itself keeps its message and chain (PRD P0-10).
    @Test func describesAReasonTheMoveSetItself() {
        let failure = RejectMoveFailure(
            reason: .notConfirmed, message: "The destination's size changed.")
        #expect(failure.reason == .notConfirmed)
        #expect(failure.message == "The destination's size changed.")
        #expect(failure.errorChain.isEmpty)
    }
}
