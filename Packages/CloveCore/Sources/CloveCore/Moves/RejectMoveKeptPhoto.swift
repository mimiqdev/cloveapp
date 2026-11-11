/// A kept photo and the complete desired marks the keep left on screen.
/// Move undo compares these with current desired marks before restoring Reject.
public struct RejectMoveKeptPhoto: Hashable, Sendable {
    public let set: ScannedPhotoSet
    public let marksAfter: PhotoMarks

    public init(set: ScannedPhotoSet, marksAfter: PhotoMarks) {
        self.set = set
        self.marksAfter = marksAfter
    }
}
