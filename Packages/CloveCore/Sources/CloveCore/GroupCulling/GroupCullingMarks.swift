/// The shared culling definition: a rating, colour label or Reject decides a photo.
extension PhotoMarks {
    /// Only photos with no rating, label or Reject may be rejected by the finishing action.
    public var isUnmarked: Bool { rating == .unrated && label.isClear && !isRejected }

    /// Any rating, label or Reject is a decision.
    public var isMarked: Bool { !isUnmarked }
}
