/// The value one mark field carries, so undo can compare and replace fields one at a time.
///
/// PRD P0-05 keeps the rating and the label separate, and Reject is the rating value −1 (decision
/// record `reject-as-rating.md`). A single value type lets the field check compare "what the
/// change set", "what was there before" and "what is there now" without mixing the two marks.
enum MarkFieldValue: Hashable, Sendable {
    /// A −1…5 rating, Reject included (PRD P0-05).
    case rating(Rating)
    /// A colour label, including external text Clove preserves (PRD P0-05).
    case label(ColourLabel)
}

/// Field-level helpers shared by recording and restoring (PRD P0-05; DEV-PLAN C5).
enum MarkUndoFields {
    /// The fields a change names, in ``MarkUndoField`` order.
    static func namedFields(of change: MarkChange) -> [MarkUndoField] {
        MarkUndoField.allCases.filter { requestedValue(of: change, for: $0) != nil }
    }

    /// The value a change asks for in one field, or `nil` when the change leaves it alone.
    static func requestedValue(
        of change: MarkChange, for field: MarkUndoField
    ) -> MarkFieldValue? {
        switch field {
        case .rating: change.rating.map(MarkFieldValue.rating)
        case .label: change.label.map(MarkFieldValue.label)
        }
    }

    /// The value one field holds in a photo's marks (PRD P0-05).
    static func value(of marks: PhotoMarks, for field: MarkUndoField) -> MarkFieldValue {
        switch field {
        case .rating: .rating(marks.rating)
        case .label: .label(marks.label)
        }
    }

    /// The change that writes the supplied field values, or `nil` when none are left.
    ///
    /// A field absent from `values` is left out of the change, so C4 keeps its stored value
    /// instead of rewriting it (PRD How marks reach disk, rule 9).
    static func change(_ values: [MarkUndoField: MarkFieldValue]) -> MarkChange? {
        var change = MarkChange()
        for field in MarkUndoField.allCases {
            switch values[field] {
            case .rating(let rating)?: change.rating = rating
            case .label(let label)?: change.label = label
            case nil: continue
            }
        }
        return change.isEmpty ? nil : change
    }
}

/// The field-level restore one undo or redo plans for one photo (PRD P0-05; DEV-PLAN C5).
///
/// Undo restores only the fields the recorded change set, back to that photo's own marks from
/// before the action, and only where the field still holds the value the change wrote. Redo is
/// the mirror image: it re-applies the change where the field still holds the value undo
/// restored. A field at either end needs no write when it already holds the target value, and a
/// field holding any other value is a newer mark that is left alone (PRD P0-05: restore the
/// previous mark, never overwrite a newer one).
struct MarkUndoRestorePlan: Hashable, Sendable {
    /// The photo this plan restores (C1's stable identity).
    let photo: PhotoIdentity
    /// The fields already at the target value, which need no write (PRD P0-05).
    var alreadyAtTarget: [MarkUndoField]
    /// The fields a newer value replaced, with the reason each stays (PRD P0-05).
    var leftAlone: [MarkUndoLeftAloneField]
    /// The change that writes the remaining fields, or `nil` when every field is settled.
    var change: MarkChange?

    /// Plans the undo of one recorded change: restore the marks from before the action.
    static func undo(_ recorded: MarkUndoPhoto, current: PhotoMarks) -> MarkUndoRestorePlan {
        plan(recorded, current: current) { field in
            (
                expected: MarkUndoFields.requestedValue(of: recorded.change, for: field),
                target: MarkUndoFields.value(of: recorded.marksBefore, for: field)
            )
        }
    }

    /// Plans the redo of one recorded change: re-apply the change over the restored marks.
    static func redo(_ recorded: MarkUndoPhoto, current: PhotoMarks) -> MarkUndoRestorePlan {
        plan(recorded, current: current) { field in
            (
                expected: MarkUndoFields.value(of: recorded.marksBefore, for: field),
                target: MarkUndoFields.requestedValue(of: recorded.change, for: field)
            )
        }
    }

    /// Keeps every restorable field as it is, with the reason it cannot be written now.
    mutating func leaveRestorableFieldsAlone(_ reason: MarkUndoLeftAloneReason) {
        guard let change else { return }
        for field in MarkUndoFields.namedFields(of: change) {
            leftAlone.append(MarkUndoLeftAloneField(field: field, reason: reason))
        }
        self.change = nil
    }

    /// Applies the per-field rule once, for both directions.
    ///
    /// `values` supplies, for one field, the value this step expects to find before replacing it
    /// and the value it writes. Only fields the recorded change altered are considered, so a
    /// rating undo never touches a label it did not set (PRD P0-05).
    private static func plan(
        _ recorded: MarkUndoPhoto,
        current: PhotoMarks,
        values: (MarkUndoField) -> (expected: MarkFieldValue?, target: MarkFieldValue?)
    ) -> MarkUndoRestorePlan {
        var alreadyAtTarget: [MarkUndoField] = []
        var leftAlone: [MarkUndoLeftAloneField] = []
        var restored: [MarkUndoField: MarkFieldValue] = [:]
        for field in recorded.changedFields {
            let (expected, target) = values(field)
            guard let expected, let target else { continue }
            let now = MarkUndoFields.value(of: current, for: field)
            if now == target {
                alreadyAtTarget.append(field)
            } else if now == expected {
                restored[field] = target
            } else {
                leftAlone.append(
                    MarkUndoLeftAloneField(field: field, reason: .newerMark))
            }
        }
        return MarkUndoRestorePlan(
            photo: recorded.photo,
            alreadyAtTarget: alreadyAtTarget,
            leftAlone: leftAlone,
            change: MarkUndoFields.change(restored))
    }
}
