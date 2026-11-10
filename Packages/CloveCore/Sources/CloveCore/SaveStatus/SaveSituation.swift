import Foundation

/// One row of the PRD's "Failure and recovery" table that the save-state UI explains
/// (PRD P0-08).
///
/// The PRD marks these strings as proposals, so they live here once and the owner can change
/// them in one place. PRD Failure and recovery requires read-only storage and insufficient space
/// to stay apart, so they are separate cases with different copy, and a lost permission is never
/// reported as a missing location. PRD P0-08 forbids showing a failed or unconfirmed change as
/// saved, so every case here is an explanation and never a success.
///
/// The table's "Partial batch failure" and "Partial Move rejects failure" rows belong to the
/// batch bar (PRD P0-09) and to Move rejects (PRD P0-10); the leaving row is
/// ``LeaveFolderConfirmation``'s. Those three are not situations a photo or a folder reaches.
public enum SaveSituation: String, CaseIterable, Hashable, Sendable {
    /// One photo's change could not be confirmed (PRD Failure and recovery, row 1).
    case singleWriteFailure
    /// The system denied access to the open folder (PRD Failure and recovery, row 2).
    case lostPermission
    /// The remembered location is gone or unreadable (PRD Failure and recovery, row 3).
    case locationUnavailable
    /// The location does not permit writes (PRD Failure and recovery, row 4).
    case readOnly
    /// The location is full (PRD Failure and recovery, row 5).
    case insufficientSpace
    /// The external drive holding the open folder disconnected during use
    /// (PRD Failure and recovery, row 6).
    case driveDisconnected

    /// The PRD's proposed copy for this situation, used as written.
    ///
    /// PRD "Proposed copy (pending revision)" lists the same words as one line per situation;
    /// this is the one place the app reads them from.
    public var message: String {
        switch self {
        case .singleWriteFailure:
            "This photo's marks weren't saved. Try again?"
        case .lostPermission:
            "Access to this folder is no longer available. Open it again."
        case .locationUnavailable:
            "This location can't be found. Select it again through Open."
        case .readOnly:
            "You can view this location, but can't save marks here."
        case .insufficientSpace:
            "There isn't enough space here to save marks."
        case .driveDisconnected:
            "The drive disconnected. Reconnect it, then reopen this folder."
        }
    }

    /// The actions the PRD's row offers, in the order it lists them.
    ///
    /// A screen shows the ones it can perform; it never invents a different action, and it never
    /// offers Retry for a situation whose row does not. A retry that would surely fail again is
    /// worse than the recovery the row names.
    public var actions: [SaveAction] {
        switch self {
        case .singleWriteFailure:
            [.retry, .cancel]
        case .lostPermission:
            [.reopenFolder]
        case .locationUnavailable:
            [.openFolder]
        case .readOnly:
            [.cancel, .openFolder]
        case .insufficientSpace:
            [.freeSpaceAndRetry]
        case .driveDisconnected:
            [.reopenFolder]
        }
    }
}

/// One recovery action a failure situation offers (PRD Failure and recovery's action column).
///
/// The title is what the button says. The screen decides how to perform the action, because
/// reopening the same folder, choosing another folder and retrying one change are different
/// calls.
public enum SaveAction: String, CaseIterable, Hashable, Sendable {
    /// Send the failed change again (PRD Failure and recovery, row 1).
    case retry
    /// Dismiss the explanation without changing anything (rows 1 and 4).
    case cancel
    /// Ask for the open folder again, which validates it with a real read (C11, PRD P0-02).
    case reopenFolder
    /// Choose a folder through the system picker (PRD P0-01, P0-02).
    case openFolder
    /// Try the change again once the user has freed space (PRD Failure and recovery, row 5).
    case freeSpaceAndRetry

    /// What the button that performs this action says.
    public var title: String {
        switch self {
        case .retry:
            "Retry"
        case .cancel:
            "Cancel"
        case .reopenFolder:
            "Reopen folder"
        case .openFolder:
            "Open folder…"
        case .freeSpaceAndRetry:
            "Free space and retry"
        }
    }
}
