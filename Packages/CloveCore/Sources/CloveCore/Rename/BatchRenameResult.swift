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
        files: [RenameFileLocation]
    ) {
        self.identity = identity
        switch error as? PhotoSetMoveError {
        case .missingSource(let url): message = "\(url.lastPathComponent) is no longer there."
        case .differentVolume: message = "The destination is on a different volume."
        case .notConfirmed(let text): message = text
        case nil: message = String(describing: error)
        }
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
    public let failure: BatchRenameFailure?
    public let temporarySets: [TemporaryRenameSet]
}

public enum RenamePass: Hashable, Sendable { case temporary, finalName }

public enum BatchRenameProgress: Hashable, Sendable {
    case setStarted(PhotoIdentity, pass: RenamePass)
    case setFinished(PhotoIdentity, pass: RenamePass)
    case finished(BatchRenameResult)
}
