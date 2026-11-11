/// The confirmation's counts are a preview. The result retains both counts when re-planning
/// finds different photos or files after earlier writes have finished.
public struct RejectMovePlanDifference: Hashable, Sendable {
    public struct Counts: Hashable, Sendable {
        public let photos: Int
        public let companions: Int
        public let sidecars: Int

        init(_ plan: RejectMovePlan) {
            photos = plan.photoCount
            companions = plan.companionCount
            sidecars = plan.sidecarCount
        }
    }

    public let preview: Counts
    public let actual: Counts

    public init(preview: RejectMovePlan, actual: RejectMovePlan) {
        self.preview = Counts(preview)
        self.actual = Counts(actual)
    }

    public var hasChanges: Bool { preview != actual }

    public var announcement: String {
        "Move updated: \(actual.photos) photos, \(actual.companions) companions, "
            + "\(actual.sidecars) XMP files."
    }
}
