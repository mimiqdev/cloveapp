import Foundation

/// The result returned by a completed write, never a retained per-photo state.
public enum MarkChangeState: Hashable, Sendable {
    case savedInSidecar
    case savedInCloveOnly
    case failed(MarkWriteFailure)

    public var isConfirmed: Bool { failure == nil }

    public var failure: MarkWriteFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}

/// One completed write and the fields it attempted. The caller owns the result.
public struct MarkChangeStatus: Hashable, Sendable, Identifiable {
    public let id: MarkChangeID
    public let identity: PhotoIdentity
    public let requested: MarkChange
    public let state: MarkChangeState

    public init(
        id: MarkChangeID, identity: PhotoIdentity, requested: MarkChange, state: MarkChangeState
    ) {
        self.id = id
        self.identity = identity
        self.requested = requested
        self.state = state
    }
}

public struct MarkBatchID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init() { self.rawValue = UUID() }
    public var description: String { rawValue.uuidString }
}

/// The per-photo results of a completed batch, in caller order.
public struct MarkBatchResult: Hashable, Sendable {
    public let id: MarkBatchID
    public let change: MarkChange
    public let outcomes: [MarkChangeStatus]

    public init(id: MarkBatchID, change: MarkChange, outcomes: [MarkChangeStatus]) {
        self.id = id
        self.change = change
        self.outcomes = outcomes
    }

    public var confirmed: [MarkChangeStatus] { outcomes.filter { $0.state.isConfirmed } }
    public var failed: [MarkChangeStatus] { outcomes.filter { $0.state.failure != nil } }
    public var failedCount: Int { failed.count }

}
