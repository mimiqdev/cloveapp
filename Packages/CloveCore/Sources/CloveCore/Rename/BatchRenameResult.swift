import Foundation

public struct RenameFileLocation: Hashable, Sendable {
    public enum Location: Hashable, Sendable { case source, destination, missing, unknown }
    public let source: URL
    public let destination: URL
    public let location: Location
    public var url: URL? {
        switch location {
        case .source: source
        case .destination: destination
        case .missing, .unknown: nil
        }
    }
}

public struct BatchRenameFailure: Hashable, Sendable {
    public let identity: PhotoIdentity
    public let message: String
    public let errorChain: [MarkWriteErrorEntry]
    public let rollbackFailures: [String]
    /// Includes split sets when a per-set rollback itself failed.
    public let files: [RenameFileLocation]

    init(
        identity: PhotoIdentity, error: any Error, rollbackFailures: [any Error] = [],
        files: [RenameFileLocation], context: String = ""
    ) {
        self.identity = identity
        let detail: String
        switch error as? PhotoSetMoveError {
        case .missingSource(let url): detail = "\(url.lastPathComponent) is no longer there."
        case .differentVolume: detail = "The destination is on a different volume."
        case .notConfirmed(let text): detail = text
        case nil: detail = String(describing: error)
        }
        self.message = context + detail
        self.errorChain = MarkWriteErrorEntry.chain(of: error)
        self.rollbackFailures = rollbackFailures.map { String(describing: $0) }
        self.files = files
    }
}

public struct TemporaryRenameSet: Hashable, Sendable {
    /// The original identity, for matching the confirmation row.
    public let identity: PhotoIdentity
    public let stem: String
    public let files: [URL]
}

public struct BatchRenameResult: Hashable, Sendable {
    /// Sets that actually changed and reached their final names. No-op rows do not count.
    /// A mark-store failure after a final move leaves that set included in this count.
    public let renamedCount: Int
    /// Existing sets whose files reached the rejects folder, even if a later rekey failed.
    public let replacedSets: [RenameReplacement]
    public var replacementCount: Int { replacedSets.count }
    /// The destination's actual on-disk spelling, matching the plan and stored marks.
    public let destination: RenameDestination
    public let failure: BatchRenameFailure?
    public let temporarySets: [TemporaryRenameSet]
}

public enum RenamePass: Hashable, Sendable { case temporary, finalName }

public enum BatchRenameProgress: Hashable, Sendable {
    case replacementStarted(PhotoIdentity)
    case replacementFinished(RenameReplacement)
    case setStarted(PhotoIdentity, pass: RenamePass)
    case setFinished(PhotoIdentity, pass: RenamePass)
    case finished(BatchRenameResult)
}
