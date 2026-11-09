import Foundation

/// Why an open folder could not be used, as distinct states with their system error chain.
///
/// PRD P0-02 requires an explicit "select it again" answer instead of a silent failure, and G1
/// folder access distinguishes a stale bookmark from lost permission. The four access states are
/// kept apart, and storage and unknown-Recent states never pretend to be access failures.
public enum FolderAccessFailure: Error, Hashable, Sendable {
    /// The bookmark could not be resolved, or the folder it points at is gone (PRD P0-02).
    case locationUnavailable(FolderErrorChain)
    /// The system denied access to the folder (PRD P0-02: lost permission, not stale data).
    case permissionDenied(FolderErrorChain)
    /// A different folder answered the bookmark; the user must choose the folder again
    /// (PRD P0-02; S1: a same-name card or a folder replaced at the same path is never a match).
    case identityMismatch(recorded: FolderIdentityKeys, found: FolderIdentityKeys)
    /// The folder resolved but could not be listed for a reason other than access or absence.
    case readFailed(FolderErrorChain)
    /// The Recents file could not be read or written; existing data was left untouched (PRD P0-02).
    case storageUnavailable(RecentFolderStoreError)
    /// The Recents file has no record with the requested ID; nothing was removed (PRD P0-02).
    case unknownRecent(UUID)

    /// The preserved system error, when this state came from one (S1 failure table).
    public var errorChain: FolderErrorChain? {
        switch self {
        case .locationUnavailable(let chain), .permissionDenied(let chain), .readFailed(let chain):
            return chain
        case .storageUnavailable(let error):
            switch error {
            case .unreadable(let chain), .writeFailed(let chain): return chain
            case .unsupportedVersion: return nil
            }
        case .identityMismatch, .unknownRecent:
            return nil
        }
    }
}

/// The explicit outcome of opening a folder, so callers never have to guess (PRD P0-02).
public enum FolderOpenResult: Sendable {
    /// The folder opened and holds a security scope until its session ends (G1 folder access).
    case opened(OpenedFolder)
    /// The folder did not open; the caller asks for a new selection (PRD P0-02).
    case failed(FolderAccessFailure)

    /// The open folder, or nil when the folder did not open (PRD P0-02).
    public var openedFolder: OpenedFolder? {
        guard case .opened(let folder) = self else { return nil }
        return folder
    }

    /// The failure, or nil when the folder opened (PRD P0-02).
    public var failure: FolderAccessFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}
