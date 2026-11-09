/// The group view's header count, "Undecided N / M total" (PRD In-group culling, layout).
///
/// `undecided` counts members with no rating and no Reject, so a colour label alone is still
/// undecided (PRD In-group culling, layout). `total` is the group's member count, so the
/// header always has both numbers even while the marks are changing.
public struct GroupUndecidedCount: Hashable, Sendable {
    /// Members with no rating and no Reject (PRD In-group culling, layout).
    public let undecided: Int

    /// Every member of the group, marked or not (PRD In-group culling, layout).
    public let total: Int

    /// Describes a count the caller already computed.
    public init(undecided: Int, total: Int) {
        self.undecided = undecided
        self.total = total
    }

    /// Counts one marks value per photo, for a caller that holds the marks in a list.
    public init<Marks: Sequence>(_ marks: Marks) where Marks.Element == PhotoMarks {
        var undecided = 0
        var total = 0
        for marks in marks {
            total += 1
            if marks.isUndecided { undecided += 1 }
        }
        self.init(undecided: undecided, total: total)
    }

    /// Counts a group against the marks read for it; a member without an entry is unmarked.
    ///
    /// The group's member order is not needed for counting, and a member missing from `marks`
    /// reads as a photo with no marks, which is undecided (PRD In-group culling, layout).
    public init(group: SimilarGroup, marks: [PhotoIdentity: PhotoMarks]) {
        self.init(group.members.map { marks[$0] ?? PhotoMarks() })
    }

    /// Whether every member is rated or rejected, the marks half of group completion
    /// (PRD In-group culling, group completion).
    public var isCompleteByMarks: Bool { undecided == 0 }

    /// The PRD's header wording; the exact string stays a UI decision (PRD In-group culling,
    /// layout).
    public var headerText: String { "Undecided \(undecided) / \(total) total" }
}
