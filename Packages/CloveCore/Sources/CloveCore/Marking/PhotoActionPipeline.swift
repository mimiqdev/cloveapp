/// Every user action enters this same queue at input time.
public enum PhotoAction: Sendable {
    case mark(DesiredMarkEdit)
    case batch([DesiredMarkEdit])
    case finishing(GroupFinishingPlan, [DesiredMarkEdit])
    case keep([DesiredMarkEdit])
    case move(RejectMovePlan, kept: [DesiredMarkEdit])
    case moveUndo(RejectMoveUndoEntry, [DesiredMarkEdit])
}

/// FIFO admission and a single active entry. The consumer completes an entry only after
/// all of its writes or moves finish, so a later action cannot run ahead of a file operation.
public struct PhotoActionPipeline: Sendable {
    public struct Entry: Sendable {
        public let id: UInt64
        public let action: PhotoAction
    }

    private var nextID: UInt64 = 0
    private var pending: [Entry] = []
    public private(set) var active: Entry?

    public init() {}

    public var isEmpty: Bool { active == nil && pending.isEmpty }

    public func hasPendingMark(for photo: PhotoIdentity) -> Bool {
        pending.contains { entry in
            switch entry.action {
            case .mark(let edit): edit.photo == photo
            case .batch(let edits), .keep(let edits), .finishing(_, let edits),
                .moveUndo(_, let edits):
                edits.contains { $0.photo == photo }
            case .move: false
            }
        }
    }

    @discardableResult
    public mutating func submit(_ action: PhotoAction) -> UInt64 {
        nextID += 1
        pending.append(Entry(id: nextID, action: action))
        return nextID
    }

    public mutating func beginNext() -> Entry? {
        guard active == nil, !pending.isEmpty else { return nil }
        active = pending.removeFirst()
        return active
    }

    /// Disconnection drops queued actions. The consumer finishes its active entry.
    public mutating func removePending() {
        pending.removeAll()
    }

    public mutating func finish(_ id: UInt64) {
        precondition(active?.id == id, "Only the active action can finish")
        active = nil
    }
}
