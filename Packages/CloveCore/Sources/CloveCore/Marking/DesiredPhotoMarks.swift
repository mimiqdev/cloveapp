/// One synchronous marking action, including the values a later undo needs.
public struct DesiredMarkEdit: Hashable, Sendable {
    public let photo: PhotoIdentity
    public let revision: UInt64
    public let before: PhotoMarks
    public let after: PhotoMarks
    /// Includes fields from earlier unconfirmed requests, so a successful write confirms them too.
    public let change: MarkChange
}

/// Requested marks stay visible until their own revision (or a newer one) confirms.
/// This value has no tasks, storage or actor dependency; its owner serializes access.
public struct DesiredPhotoMarks: Sendable {
    public struct Entry: Hashable, Sendable {
        public let edit: DesiredMarkEdit
        public var state: MarkChangeState
    }

    private var revisions: [PhotoIdentity: UInt64] = [:]
    private var entries: [PhotoIdentity: Entry] = [:]

    public init() {}

    public func entry(for photo: PhotoIdentity) -> Entry? { entries[photo] }

    public func shown(for photo: PhotoIdentity, confirmed: PhotoMarks) -> PhotoMarks {
        entries[photo]?.edit.after ?? confirmed
    }

    @discardableResult
    public mutating func apply(
        _ change: MarkChange, to photo: PhotoIdentity, confirmed: PhotoMarks
    ) -> DesiredMarkEdit {
        let before = shown(for: photo, confirmed: confirmed)
        let revision = (revisions[photo] ?? 0) + 1
        revisions[photo] = revision
        let edit = DesiredMarkEdit(
            photo: photo, revision: revision, before: before,
            after: before.including(change),
            change: entries[photo]?.edit.change.merged(with: change) ?? change)
        entries[photo] = Entry(edit: edit, state: .pending)
        return edit
    }

    /// An old result can update confirmed storage without replacing a newer requested mark.
    public mutating func finish(_ edit: DesiredMarkEdit, state: MarkChangeState) {
        guard let entry = entries[edit.photo], edit.revision >= entry.edit.revision else { return }
        if state.isConfirmed {
            entries[edit.photo] = nil
        } else {
            entries[edit.photo]?.state = state
        }
    }

    public mutating func retry(_ edit: DesiredMarkEdit) {
        guard entries[edit.photo]?.edit.revision == edit.revision else { return }
        entries[edit.photo]?.state = .pending
    }
}

/// Restores only when the complete shown marks still equal what the earlier action left.
/// The field replacement itself uses the same rule as mark undo.
public enum DesiredMarkRestore {
    public static func change(
        photo: PhotoIdentity, current: PhotoMarks, expected: PhotoMarks,
        target: PhotoMarks, fields: MarkChange
    ) -> MarkChange? {
        guard current == expected else { return nil }
        return MarkUndoRestorePlan.undo(
            MarkUndoPhoto(photo: photo, marksBefore: target, change: fields),
            current: current
        ).change
    }

}
