import Foundation

/// One of a photo's marks that an undo step can restore (PRD P0-05).
///
/// PRD P0-05 applies ratings and colour labels separately, and a Reject is the rating value −1
/// (decision record `reject-as-rating.md`). Undo therefore restores the rating and the label on
/// their own: undoing a Reject restores the stars it replaced, and undoing a rating never
/// rewrites a label that a later action changed.
public enum MarkUndoField: String, CaseIterable, Hashable, Sendable {
    /// The −1…5 rating, Reject included; XMP for a RAW set (G1 decision 2).
    case rating
    /// The colour label (PRD P0-05); XMP for a RAW set (G1 decisions 2 and 6).
    case label
}

/// Why an undo or redo left one field alone instead of restoring it (PRD P0-05).
///
/// PRD P0-05's Undo row restores the previous mark. It never overwrites a newer one, so a field
/// another app, a later marking action or another queued write changed keeps its newer value and
/// is reported as left alone rather than silently replaced.
public enum MarkUndoLeftAloneReason: Hashable, Sendable {
    /// The field no longer held the value the step was about to replace, so the newer mark won.
    case newerMark
    /// The photo's set is no longer available to write, for example after a rescan dropped it.
    case photoUnavailable
}

/// One field a step kept as it was, with the reason (PRD P0-05: undo restores the previous mark).
public struct MarkUndoLeftAloneField: Hashable, Sendable {
    /// The field that kept its newer value (PRD P0-05).
    public let field: MarkUndoField
    /// Why the field was left alone (PRD P0-05).
    public let reason: MarkUndoLeftAloneReason

    /// Describes one field a step kept as it was.
    public init(field: MarkUndoField, reason: MarkUndoLeftAloneReason) {
        self.field = field
        self.reason = reason
    }
}

/// One photo's part of an undo entry: its marks before the action and the change that ran.
///
/// PRD P0-05's Undo row and PRD P0-12 keep the previous mark per photo. A multi-select batch
/// (PRD P0-09) keeps each photo's own marks before, because two photos in one batch need not
/// have started from the same marks. The value is `Sendable` and holds no reference to C4's
/// queue or to the file system, so a record can outlive the write that produced it.
public struct MarkUndoPhoto: Hashable, Sendable {
    /// The photo the change touched (C1's stable identity).
    public let photo: PhotoIdentity
    /// The marks read before the change, which undo restores (PRD P0-05).
    public let marksBefore: PhotoMarks
    /// The change C4 admitted (PRD P0-07, P0-09).
    public let change: MarkChange

    /// Collects one photo's part of a record; only the history builds these.
    init(photo: PhotoIdentity, marksBefore: PhotoMarks, change: MarkChange) {
        self.photo = photo
        self.marksBefore = marksBefore
        self.change = change
    }

    /// The fields the change actually altered, in ``MarkUndoField`` order (PRD P0-05).
    ///
    /// A field the change names but leaves at its ``marksBefore`` value is not part of the
    /// record: there is nothing to restore for it, and a change that alters no field at all is
    /// not recorded (PRD P0-06's no-change rule).
    var changedFields: [MarkUndoField] {
        MarkUndoFields.namedFields(of: change).filter { field in
            MarkUndoFields.requestedValue(of: change, for: field)
                != MarkUndoFields.value(of: marksBefore, for: field)
        }
    }
}

/// Which action produced an undo entry (PRD P0-05, P0-09, P0-12).
public enum MarkUndoEntryKind: Hashable, Sendable {
    /// A mark change on one photo (PRD P0-05).
    case single
    /// One change applied to the photos of a multi-select batch (PRD P0-09).
    case batch
    /// Reject unmarked in one group.
    case groupFinishing
}

/// The group and action one finishing-action entry undoes (PRD P0-12).
///
/// Undoing the entry also clears the group's finishing-action record in C10's
/// ``GroupCompletionTracker``; redoing restores it (PRD P0-12: finishing actions can be undone).
public struct MarkUndoGroupFinishing: Hashable, Sendable {
    /// The group the action finished, for the completion record (PRD P0-12).
    public let groupID: GroupID
    /// The action that ran (PRD In-group culling, finishing actions).
    public let action: GroupFinishingAction

    /// Builds the group part of an entry; only the history builds these.
    init(groupID: GroupID, action: GroupFinishingAction) {
        self.groupID = groupID
        self.action = action
    }

    /// A short action name for the undo menu title; the final copy belongs to U8.
    public var actionName: String {
        switch action {
        case .rejectUnmarked: "Reject unmarked"
        }
    }
}

/// A stable handle for one recorded action, so a UI can match a menu item to its entry.
public struct MarkUndoEntryID: Hashable, Sendable, CustomStringConvertible {
    /// The underlying value; a new one per recorded action.
    public let rawValue: UUID

    /// Creates a fresh identifier for a recorded action.
    public init() { self.rawValue = UUID() }

    /// A stable, log-friendly spelling.
    public var description: String { rawValue.uuidString }
}

/// One recorded action the undo history can undo (PRD P0-05, P0-12; DEV-PLAN C5).
///
/// A record is a `Sendable` value with no reference to C4's queue or to the file system, so the
/// history keeps it in memory and a test can compare it. The three kinds follow the plan's C5
/// row and the PRD: a mark change on one photo (P0-05), a batch from multi-select (P0-09), and
/// one of the two in-group finishing actions (P0-12).
public struct MarkUndoEntry: Hashable, Sendable, Identifiable {
    /// The entry's handle, for a UI that refers to one recorded action.
    public let id: MarkUndoEntryID
    /// Which kind of action produced the entry (PRD P0-05, P0-09, P0-12).
    public let kind: MarkUndoEntryKind
    /// One record per photo the action changed, in the order the action supplied them.
    public let photos: [MarkUndoPhoto]
    /// Where undo sends the view back to (PRD Undo row: the photo whose mark was undone).
    ///
    /// PRD Auto-advance moves the detail view on after a mark; the recorded photo is the one
    /// that was marked, not the one now on screen, so undo after auto-advance returns to the
    /// photo whose mark it restored.
    public let photoToReturnTo: PhotoIdentity
    /// The group and action when this entry came from a finishing action (PRD P0-12).
    public let groupFinishing: MarkUndoGroupFinishing?

    /// Collects one record; the history builds these so every entry is consistent.
    init(
        id: MarkUndoEntryID,
        kind: MarkUndoEntryKind,
        photos: [MarkUndoPhoto],
        photoToReturnTo: PhotoIdentity,
        groupFinishing: MarkUndoGroupFinishing?
    ) {
        self.id = id
        self.kind = kind
        self.photos = photos
        self.photoToReturnTo = photoToReturnTo
        self.groupFinishing = groupFinishing
    }

    /// A short action name for the undo menu title; the final copy belongs to U8.
    ///
    /// A single or batch change is named after the field it set: a rating of −1 (PRD Marking
    /// rules) reads as "Reject", and any other rating reads as "Rating".
    public var actionName: String {
        if let groupFinishing { return groupFinishing.actionName }
        return MarkUndoEntry.actionName(for: photos.first?.change ?? MarkChange())
    }

    /// The name one mark change uses in the undo menu: Reject for −1, then rating, then label.
    static func actionName(for change: MarkChange) -> String {
        if change.rating == .rejected { return "Reject" }
        if change.rating != nil { return "Rating" }
        if change.label != nil { return "Label" }
        return "Mark"
    }

    /// The entry without the photos that moved out of the folder (PRD Move rejects).
    ///
    /// G1 decision 5 makes Move rejects the durable result: a moved photo's files are under
    /// `_Rejected` and restoring them is the user's job, so undo must never write to the old
    /// path. An entry left with no photos is removed. When the recorded photo to return to was
    /// itself moved, the entry returns to its first remaining photo instead.
    func removingPhotos(_ moved: Set<PhotoIdentity>) -> MarkUndoEntry? {
        let remaining = photos.filter { !moved.contains($0.photo) }
        guard let first = remaining.first else { return nil }
        let returnTo =
            remaining.contains { $0.photo == photoToReturnTo } ? photoToReturnTo : first.photo
        return MarkUndoEntry(
            id: id,
            kind: kind,
            photos: remaining,
            photoToReturnTo: returnTo,
            groupFinishing: groupFinishing)
    }
}
