import Foundation

/// The confirmation sheet's copy for one Move rejects plan (PRD Move rejects, P0-10).
///
/// PRD "Proposed copy" asks the confirmation to say how many photos move, that their JPEG and/or
/// HIF companions and XMP travel with them, and that originals are not deleted. The plan already
/// knows every file, so the sentence names only the companion kinds it actually contains and the
/// folder name the move was planned with (PRD Move rejects, C12).
public struct RejectMoveConfirmation: Hashable, Sendable {
    /// The sentence PRD "Move confirmation" proposes, narrowed to the plan's file kinds.
    public let message: String
    /// The separate line for sets that cannot move, or nil when every set is ready (P0-10).
    ///
    /// PRD P0-10 keeps the photo count honest: a refused set is never folded into or hidden by
    /// "N rejected photos".
    public let refusedMessage: String?
    /// How many photo sets the move will rename (PRD P0-10).
    public let photoCount: Int
    /// How many JPEG and HIF files travel with those sets (PRD P0-10).
    public let companionCount: Int
    /// How many `.xmp` packets travel with those sets (PRD P0-10).
    public let sidecarCount: Int
    /// How many requested sets the plan refuses to move (PRD P0-10).
    public let refusedCount: Int

    /// Builds the confirmation copy from a plan (PRD Move rejects, P0-10).
    public init(plan: RejectMovePlan) {
        photoCount = plan.photoCount
        companionCount = plan.companionCount
        sidecarCount = plan.sidecarCount
        refusedCount = plan.refusedCount
        let folder = plan.configuration.rejectsFolderName.rawValue
        let photos =
            plan.photoCount == 1 ? "1 rejected photo" : "\(plan.photoCount) rejected photos"
        let travelling = Self.travelling(
            jpegCount: plan.jpegCompanionCount, heifCount: plan.heifCompanionCount,
            sidecarCount: plan.sidecarCount)
        let destination = "to the \"\(folder)\" folder? Originals won't be deleted."
        message =
            travelling.isEmpty
            ? "Move \(photos) \(destination)"
            : "Move \(photos), with their \(travelling), \(destination)"
        refusedMessage =
            plan.refusedCount == 0
            ? nil
            : plan.refusedCount == 1
                ? "1 photo can't be moved right now."
                : "\(plan.refusedCount) photos can't be moved right now."
    }
}

extension RejectMovePlan {
    /// PRD P0-10's JPEG companion count, named in the confirmation's "with..." clause.
    public var jpegCompanionCount: Int {
        readyEntries.reduce(0) { count, set in
            count + set.companions.filter { $0.role == .jpegCompanion }.count
        }
    }

    /// PRD P0-10's HIF companion count, named in the confirmation's "with..." clause.
    public var heifCompanionCount: Int {
        readyEntries.reduce(0) { count, set in
            count + set.companions.filter { $0.role == .heifCompanion }.count
        }
    }
}

/// The result view's copy for one Move rejects run (PRD P0-10, Failure and recovery).
///
/// PRD "Partial move failure" proposes "Moved N photos. M photos couldn't be moved." and keeps a
/// retry for the failed sets only. C6's result leaves skipped sets out of "couldn't be moved", so
/// they get a line of their own instead of disappearing from the sheet (P0-10).
public struct RejectMoveResultSummary: Hashable, Sendable {
    /// The run's main sentence: a short confirmation, or PRD "Partial move failure" copy.
    public let message: String
    /// The separate line for sets that were skipped, or nil when none was (P0-10).
    public let skippedMessage: String?
    /// Whether "Retry unmoved items" can resend anything (PRD P0-10).
    ///
    /// C6 retries failed sets only; a split set stays reported because its files are in two
    /// places, so it never enables the retry.
    public let canRetry: Bool

    /// Builds the result copy from one run's result (PRD P0-10, Failure and recovery).
    public init(result: RejectMoveResult) {
        if let partial = result.partialFailureSummary {
            message = partial
        } else {
            message =
                result.movedCount == 1 ? "Moved 1 photo." : "Moved \(result.movedCount) photos."
        }
        skippedMessage =
            result.skippedCount == 0
            ? nil
            : result.skippedCount == 1
                ? "1 photo was skipped." : "\(result.skippedCount) photos were skipped."
        canRetry = result.failedCount > 0
    }
}

/// The one place the Move rejects screens keep wording C6 does not own (PRD Failure and recovery).
public enum RejectMoveCopy {
    /// PRD Failure and recovery's "Read-only location" sentence, reused by the move sheet.
    ///
    /// The real move lane refuses a read-only volume before it touches a file
    /// (``RejectMoveRefusal/readOnlyLocation(_:)``), and the sheet shows this sentence instead of
    /// reporting every photo as failed. U7's save-state mapping can reuse the same sentence.
    public static let viewOnlyLocation =
        "You can view this location, but can't save marks here."
}

extension RejectMoveConfirmation {
    /// The plan's travelling files, naming only the kinds it contains (PRD Move rejects).
    private static func travelling(jpegCount: Int, heifCount: Int, sidecarCount: Int) -> String {
        var parts: [String] = []
        if jpegCount > 0 {
            parts.append(jpegCount == 1 ? "JPEG companion" : "JPEG companions")
        }
        if heifCount > 0 {
            parts.append(heifCount == 1 ? "HIF companion" : "HIF companions")
        }
        if sidecarCount > 0 { parts.append("XMP") }
        guard let last = parts.popLast() else { return "" }
        return parts.isEmpty ? last : "\(parts.joined(separator: ", ")) and \(last)"
    }
}
