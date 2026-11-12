/// The grid's top filters, drawn from PRD P0-03's All, Unmarked, Rejected and N stars or higher.
/// A filter reads marks and the relative folder path without changing the grid's order.
public enum PhotoFilter: Hashable, Sendable {
    /// Every placed photo, rejected ones included, because Reject is shown on the cell.
    case all
    /// Rating 0, a clear label and not rejected (PRD P0-03).
    /// Unknown external label text is still a label, so it counts as marked.
    case unmarked
    /// Rejected photos, whatever their rating and label (PRD P0-03).
    case rejected
    /// `minimum` stars or higher. The grid offers 1 through 5 (PRD P0-03).
    case ratedAtLeast(Rating)
    /// Photos directly inside this path relative to the opened folder, not its descendants.
    case subfolder(String)

    /// Whether "N stars or higher" hides rejected photos (PRD P0-03 default).
    /// This constant is the only place the policy is decided; changing it changes every use.
    public static let ratedAtLeastHidesRejected = true

    /// Whether these marks pass the filter (PRD P0-03). The ordering time is never consulted.
    public func matches(_ marks: PhotoMarks, relativeFolderPath: String? = nil) -> Bool {
        switch self {
        case .subfolder(let path):
            return relativeFolderPath == path
        case .all:
            return true
        case .unmarked:
            return marks.rating == .unrated && marks.label.isClear && !marks.isRejected
        case .rejected:
            return marks.isRejected
        case .ratedAtLeast(let minimum):
            if Self.ratedAtLeastHidesRejected && marks.isRejected { return false }
            return marks.rating >= minimum
        }
    }
}
