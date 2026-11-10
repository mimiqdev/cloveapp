import CloveCore

/// Plain text for why a folder did not open, shown next to the Recents item or picker that asked
/// for it (PRD P0-02, PRD Failure and recovery).
///
/// PRD P0-02 requires the user to be asked to select the folder again instead of seeing a silent
/// failure, and S1's failure table keeps a lost permission, a missing location and a folder that
/// was replaced at the same path apart. Each case therefore says what happened and what to do,
/// and none of them claims the photos are gone.
///
/// Design placeholder: U7 owns the copy for all eight failure situations; these lines only keep
/// the flow explicit until then.
enum FolderFailureExplanation {
    /// The explanation for one access failure (PRD P0-02).
    static func text(for failure: FolderAccessFailure) -> String {
        switch failure {
        case .locationUnavailable:
            "This location is no longer available. Choose the folder again."
        case .permissionDenied:
            "Clove no longer has permission to open this folder. Choose it again."
        case .identityMismatch:
            "A different folder is at this location now. Choose the folder again."
        case .readFailed:
            "The folder could not be read. Choose it again."
        case .storageUnavailable:
            "Clove could not read its list of recent folders. Choose the folder again."
        case .unknownRecent:
            "This folder is no longer in Recents. Choose it again."
        }
    }
}
