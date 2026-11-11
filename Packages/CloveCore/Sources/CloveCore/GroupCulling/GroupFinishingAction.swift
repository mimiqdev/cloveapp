/// The group's explicit finishing action. It is submitted as one ordered action and undo step.
public enum GroupFinishingAction: String, CaseIterable, Hashable, Sendable {
    case rejectUnmarked
}

public enum GroupFinishingAvailability: Hashable, Sendable {
    case available
    case noRatedOrLabelledPhoto

    public var isAvailable: Bool { self == .available }
}

/// One reject's before and after values, retained for per-photo results and undo.
public struct GroupFinishingChange: Hashable, Sendable {
    public let photo: PhotoIdentity
    public let marksBefore: PhotoMarks
    public let change: MarkChange

    init(photo: PhotoIdentity, marksBefore: PhotoMarks, change: MarkChange) {
        self.photo = photo
        self.marksBefore = marksBefore
        self.change = change
    }
}
