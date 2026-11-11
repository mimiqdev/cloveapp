import Foundation

/// One photo's share of a batch write (PRD P0-09).
///
/// PRD P0-09 applies one bar action to photos that may not share marks, so the action resolves
/// to a change per photo before anything is written: a rating replaces Reject on a rejected photo
/// (PRD Marking rules), and a photo that already carries the requested mark has nothing to write
/// (PRD P0-06's no-change rule). C4's batch write takes one change for many photo sets, so
/// the library groups these items by change and still applies the action as one batch.
public struct BatchMarkItem: Hashable, Sendable, Identifiable {
    /// The photo the change belongs to (C1's stable identity).
    public let photo: PhotoIdentity

    /// The change this photo receives, which differs from another photo's only where C13's
    /// per-photo rules do (PRD P0-09, P0-06).
    public let change: MarkChange

    /// The photo's identity, which is also the item's identity.
    public var id: PhotoIdentity { photo }

    /// Pairs one photo with the change it receives from the batch (PRD P0-09).
    public init(photo: PhotoIdentity, change: MarkChange) {
        self.photo = photo
        self.change = change
    }
}

/// The per-photo changes one batch action resolves to (PRD P0-09, PRD Marking rules).
///
/// The plan is pure: it reads the photos' marks and C12's settings through C13's
/// ``MarkingInputRules``, and produces one ``BatchMarkItem`` per photo that has something to
/// write. Nothing is written here, so the rules can be tested without a folder, a sidecar or a
/// queue.
///
/// A batch sets a mark; it does not toggle the mark off. The single-photo bar clears a rating or
/// a label when the user taps the one already applied (PRD Marking rules, Detail and marking),
/// but inside a mixed selection that would clear some photos and set others from one tap, so the
/// batch bar applies the mark and photo already carrying it receives nothing. Clear is its own
/// control: rating `0` and label Clear (PRD Marking rules).
///
/// A photo that already carries the requested mark therefore has no item. The mark the user asked
/// for is on it, so nothing is missing from the grid, but the batch's report counts only the
/// photos it wrote: the bar's count can be higher than the copy's (PRD P0-09).
public struct BatchMarkPlan: Hashable, Sendable {
    /// The mark the bar applied (PRD P0-09).
    public let action: BatchMarkAction

    /// One item per photo that has a change to write, in the photos' order (PRD P0-09).
    public let items: [BatchMarkItem]

    /// Resolves one bar action against the photos a batch marks (PRD P0-09, P0-06).
    ///
    /// - Parameters:
    ///   - action: The mark the bar applied.
    ///   - photos: The photos the batch marks, normally
    ///     ``BatchSelection/targets(selection:shown:)``'s answer.
    ///   - settings: C12's settings, for the enabled ratings and the extended labels; the
    ///     launch defaults when a caller has none.
    public init(
        action: BatchMarkAction,
        photos: [GridPhoto],
        settings: AppSettings = AppSettings()
    ) {
        self.action = action
        let rules = MarkingInputRules(settings: settings)
        self.items = photos.compactMap { photo in
            guard let change = Self.change(for: action, marks: photo.marks, rules: rules) else {
                return nil
            }
            return BatchMarkItem(photo: photo.id, change: change)
        }
    }

    /// Whether the batch has nothing to write: every photo already carries the requested mark.
    public var isEmpty: Bool { items.isEmpty }

    /// The photos the batch writes, in the plan's order (PRD P0-09).
    public var photos: [PhotoIdentity] { items.map(\.photo) }

    /// The change one photo receives for one action, or nil when nothing would change
    /// (PRD P0-06).
    ///
    /// Every case goes through C13's rules, so a photo marked from the bar receives exactly the
    /// change a single-photo control would give it: a rating replaces Reject on a rejected photo
    /// (PRD Marking rules), an enabled level or an available label is required (PRD Enabled
    /// rating levels and Marking rules), and a change that leaves the marks equal writes nothing
    /// (PRD P0-06).
    private static func change(
        for action: BatchMarkAction, marks: PhotoMarks, rules: MarkingInputRules
    ) -> MarkChange? {
        switch action {
        case .rating(let rating):
            return marked(rules.result(for: .rating(rating), marks: marks))
        case .label(let label):
            guard label.isClear || label.colour.map(rules.settings.availableLabels.contains) == true
            else { return nil }
            guard marks.label != label else { return nil }
            return marked(rules.result(forLabel: label, marks: marks))
        case .reject:
            return marked(rules.result(for: .reject, marks: marks))
        }
    }

    /// The change a marking result applies, or nil when it reports no change (PRD P0-06).
    private static func marked(_ result: MarkingResult) -> MarkChange? {
        guard case .mark(let change, _) = result else { return nil }
        return change
    }
}
