import Foundation

/// One photo as the grid holds it: identity, primary file name, time and marks.
/// PRD P0-03 ordering and filtering read these values only; this type does no I/O.
public struct GridPhoto: Identifiable, Hashable, Sendable {
    /// The stable photo key, which also identifies the cell across updates (PRD P0-01).
    public let id: PhotoIdentity
    /// The primary file's name including its extension, shown as the file name and used by
    /// the filename order and its ties (PRD P0-03).
    public let fileName: String
    /// The ordering state; `.pending` keeps the photo out of the ordered list (PRD P0-03).
    public var time: PhotoTimeState
    /// Rating, label and Reject, which filters read without changing the order (PRD P0-03).
    public var marks: PhotoMarks

    /// Collects one photo with its current ordering time and marks.
    /// Ties fall through to `id`, so a stale `fileName` can never make the order ambiguous.
    public init(
        id: PhotoIdentity,
        fileName: String,
        time: PhotoTimeState,
        marks: PhotoMarks = PhotoMarks()
    ) {
        self.id = id
        self.fileName = fileName
        self.time = time
        self.marks = marks
    }

    /// Collects a scanned set, using its primary file's name (G1 decision 1).
    public init(set: PhotoSet, time: PhotoTimeState, marks: PhotoMarks = PhotoMarks()) {
        self.init(
            id: set.id, fileName: set.primary.url.lastPathComponent, time: time, marks: marks)
    }
}
