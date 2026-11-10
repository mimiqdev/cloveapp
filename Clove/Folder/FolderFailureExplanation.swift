import CloveCore

/// Plain text for why a folder did not open, shown next to the Recents item or picker that asked
/// for it (PRD P0-02, PRD Failure and recovery).
///
/// PRD P0-02 requires the user to be asked to select the folder again instead of seeing a silent
/// failure, and S1's failure table keeps a lost permission, a missing location and a folder that
/// was replaced at the same path apart. The two situations the PRD's "Failure and recovery" table
/// has copy for come from CloveCore's one mapping, so entry and the rest of the app never word
/// them differently. A replaced folder, an unreadable folder and a Recents file that could not be
/// read have no row in that table, so they keep their own exact explanation rather than borrowing
/// one that would place the blame on the wrong thing.
enum FolderFailureExplanation {
    /// The explanation for one access failure (PRD P0-02).
    static func text(for failure: FolderAccessFailure) -> String {
        if let situation = SaveStatus.situation(for: failure) { return situation.message }
        return switch failure {
        case .identityMismatch:
            "A different folder is at this location now. Choose the folder again."
        case .readFailed:
            "The folder could not be read. Choose it again."
        case .storageUnavailable:
            "Clove could not read its list of recent folders. Choose the folder again."
        case .unknownRecent:
            "This folder is no longer in Recents. Choose it again."
        case .locationUnavailable, .permissionDenied:
            // Both have a PRD row and were answered above; this keeps the switch exhaustive.
            SaveSituation.locationUnavailable.message
        }
    }
}
