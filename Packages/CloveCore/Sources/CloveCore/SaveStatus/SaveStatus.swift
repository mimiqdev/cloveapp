import Foundation

/// Turns the save state a photo or a folder has into the situation the UI explains
/// (PRD P0-08).
///
/// C4 reports one state per change and C11 reports a lost location or a folder that did not
/// open; this is the one place that decides which row of PRD "Failure and recovery" that is, so
/// the grid, the detail view and entry never invent wordings of their own.
///
/// The mapping follows S1's "Failure table and proposed PRD mapping" and C4's reason comments:
/// a lost permission is a lost permission, read-only storage and insufficient space keep their
/// own rows, and a missing location is the disconnected drive only when the location monitor
/// reported an external volume that is gone. Every other write reason is the single-photo write
/// failure, because the PRD has no separate copy for a refused packet, an ambiguous sidecar or an
/// unconfirmed read-back.
public enum SaveStatus {
    /// The one save-state line for a photo, as the marking HUD shows it (PRD P0-08).
    ///
    /// **Saved** appears only for ``MarkChangeState/savedInSidecar`` and **Saved in Clove only**
    /// only for ``MarkChangeState/savedInCloveOnly`` (PRD How marks reach disk, rules 6–7). A
    /// Reject is a rating, so a RAW set's Reject reads **Saved** once its sidecar confirms it. A
    /// failed change reads **Not saved**; the copy for why is ``situation(for:folderLoss:)``,
    /// shown beside the Retry the PRD asks for.
    ///
    /// `folderLost` marks a folder whose location was reported gone: a change that is still
    /// waiting or writing can no longer reach its storage, so it reads **Not saved** instead of
    /// **Writing…**, which PRD Failure and recovery forbids keeping on screen after a loss.
    public static func text(for state: MarkChangeState?, folderLost: Bool = false) -> String {
        if folderLost, let state, state.isUnfinished { return "Not saved" }
        return switch state {
        case nil:
            "No change yet"
        case .pending, .writing:
            "Writing…"
        case .savedInSidecar:
            "Saved"
        case .savedInCloveOnly:
            "Saved in Clove only"
        case .failed:
            "Not saved"
        case .superseded:
            "Replaced by a newer change"
        }
    }

    /// The situation one photo's latest change explains, or nil when it has nothing to explain.
    ///
    /// A saved change is not a failure, and a superseded change was replaced by a newer one the
    /// user asked for, so neither has copy (PRD How marks reach disk, rule 8). A failed change is
    /// explained by its reason, and a change still waiting when the folder's location is gone is
    /// explained by that loss, because the PRD does not allow it to keep reading **Writing…**.
    public static func situation(
        for state: MarkChangeState?, folderLoss: FolderLocationLoss?
    ) -> SaveSituation? {
        switch state {
        case nil, .savedInSidecar, .savedInCloveOnly, .superseded:
            nil
        case .pending, .writing:
            folderLoss.map { situation(for: $0) }
        case .failed(let failure):
            situation(for: failure.reason, folderLoss: folderLoss)
        }
    }

    /// The situation one write failure reason shows (S1's failure table, PRD Failure and recovery).
    ///
    /// PRD Failure and recovery keeps read-only storage and insufficient space apart, and S1's
    /// table warns against inferring either from a generic failed write, so every other reason is
    /// the single-photo write failure rather than a guess.
    public static func situation(
        for reason: MarkWriteFailureReason, folderLoss: FolderLocationLoss?
    ) -> SaveSituation {
        switch reason {
        case .permissionLost:
            .lostPermission
        case .readOnlyStorage:
            .readOnly
        case .insufficientSpace:
            .insufficientSpace
        case .locationUnavailable:
            // G1 folder access: only a gone volume root makes a missing folder a disconnect.
            folderLoss?.reason == .externalVolumeDisconnected
                ? .driveDisconnected : .locationUnavailable
        case .packetRefused, .ambiguousSidecar, .notConfirmed, .conflict, .unknown:
            .singleWriteFailure
        }
    }

    /// The situation a watched folder's loss shows (PRD Failure and recovery, rows 3 and 6).
    public static func situation(for loss: FolderLocationLoss) -> SaveSituation {
        switch loss.reason {
        case .externalVolumeDisconnected:
            .driveDisconnected
        case .locationUnavailable:
            .locationUnavailable
        }
    }

    /// The situation a folder that did not open shows, when the PRD has copy for it.
    ///
    /// PRD P0-02 asks for the folder to be selected again, and S1's table separates a lost
    /// permission from a location that is gone. A replaced folder, an unreadable folder and a
    /// Recents file that could not be read have no row in the PRD's table, so they answer nil and
    /// entry keeps their own exact explanation instead of inventing a PRD wording.
    public static func situation(for failure: FolderAccessFailure) -> SaveSituation? {
        switch failure {
        case .locationUnavailable:
            .locationUnavailable
        case .permissionDenied:
            .lostPermission
        case .identityMismatch, .readFailed, .storageUnavailable, .unknownRecent:
            nil
        }
    }
}
