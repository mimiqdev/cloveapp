/// One synchronous marking action, including the values a later undo needs.
public struct DesiredMarkEdit: Hashable, Sendable {
    public let photo: PhotoIdentity
    public let before: PhotoMarks
    public let after: PhotoMarks
    public let change: MarkChange
}

/// Only marks awaiting a write live here. The files supply everything else.
public struct DesiredPhotoMarks: Sendable {
    private var pending: [PhotoIdentity: PhotoMarks] = [:]

    public init() {}

    public func shown(for photo: PhotoIdentity, confirmed: PhotoMarks) -> PhotoMarks {
        pending[photo] ?? confirmed
    }

    @discardableResult
    public mutating func apply(
        _ change: MarkChange, to photo: PhotoIdentity, confirmed: PhotoMarks
    ) -> DesiredMarkEdit {
        let before = shown(for: photo, confirmed: confirmed)
        let edit = DesiredMarkEdit(
            photo: photo, before: before, after: before.applying(change), change: change)
        pending[photo] = edit.after
        return edit
    }

    /// The owner clears a photo after its last queued marking action finishes.
    public mutating func finish(for photo: PhotoIdentity) { pending[photo] = nil }

    public func hasPending(for photo: PhotoIdentity) -> Bool { pending[photo] != nil }

    public mutating func removeAll() { pending.removeAll() }
}

/// Restores only when the shown marks still equal what the earlier action left.
public enum DesiredMarkRestore {
    public static func change(
        photo: PhotoIdentity, current: PhotoMarks, expected: PhotoMarks,
        target: PhotoMarks, fields: MarkChange
    ) -> MarkChange? {
        guard current == expected else { return nil }
        return MarkUndoRestorePlan.undo(
            MarkUndoPhoto(photo: photo, marksBefore: target, change: fields), current: current
        ).change
    }
}
