/// Counts photos still needing a decision. A rating, label or Reject decides a photo.
public struct GroupUndecidedCount: Hashable, Sendable {
    /// Members with no rating, label or Reject.
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

    /// Whether every member has a rating, label or Reject.
    public var isCompleteByMarks: Bool { undecided == 0 }

}
