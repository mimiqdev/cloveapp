import Foundation

/// The rejected photos a person chooses to keep before a Move rejects run (PRD P0-10).
///
/// The design handoff's confirmation lets a tap keep one reject and a second tap un-keep it, and
/// the keep is only staged: nothing is written until Move, and dismissing the sheet discards the
/// selection. This value owns that staging, so the sheet's counts and the plan it moves come from
/// one place that has no file or UI dependency.
public struct RejectMoveKeepSelection: Hashable, Sendable {
    /// The plan the confirmation was built from (PRD P0-10).
    public let plan: RejectMovePlan
    /// The ready sets the person kept, in no order (PRD P0-10).
    public private(set) var keptIdentities: Set<PhotoIdentity>

    /// Starts with no keep, so every ready set will move (PRD P0-10).
    public init(plan: RejectMovePlan) {
        self.plan = plan
        self.keptIdentities = []
    }

    /// Keeps one ready set, or un-keeps it when it is already kept (PRD P0-10).
    ///
    /// A refused set is not ready to move, so it cannot be kept. The keep stays staged; clearing
    /// its Reject and moving the rest happen only when the sheet's Move action runs.
    public mutating func toggle(_ identity: PhotoIdentity) {
        guard plan.readyEntries.contains(where: { $0.identity == identity }) else { return }
        if keptIdentities.contains(identity) {
            keptIdentities.remove(identity)
        } else {
            keptIdentities.insert(identity)
        }
    }

    /// Whether one ready set is currently kept (PRD P0-10).
    public func isKept(_ identity: PhotoIdentity) -> Bool {
        keptIdentities.contains(identity)
    }

    /// How many ready sets the confirmation counts (PRD P0-10).
    public var totalCount: Int { plan.photoCount }

    /// How many ready sets will move after the staged keeps (PRD P0-10).
    public var movingCount: Int { plan.photoCount - keptCount }

    /// How many ready sets are staged to stay (PRD P0-10).
    public var keptCount: Int {
        plan.readyEntries.filter { keptIdentities.contains($0.identity) }.count
    }

    /// The kept identities in the plan's order, for the completed move C14 will undo (P0-10).
    public var orderedKeptIdentities: [PhotoIdentity] {
        plan.readyEntries.map(\.identity).filter { keptIdentities.contains($0) }
    }

    /// The plan with every kept set removed, so the move never touches a kept photo (P0-10).
    public var movingPlan: RejectMovePlan {
        plan.removing(kept: keptIdentities)
    }
}

extension RejectMovePlan {
    /// The same plan with the listed sets removed from its entries and inputs (PRD P0-10).
    ///
    /// Filtering is not re-planning: destinations, suffixes and refusals stay exactly as C6 built
    /// them. A kept set is simply no longer requested, so C6's move cannot rename it.
    public func removing(kept identities: Set<PhotoIdentity>) -> RejectMovePlan {
        guard !identities.isEmpty else { return self }
        let entries = entries.filter { !identities.contains($0.identity) }
        let remaining = Set(entries.map(\.identity))
        return RejectMovePlan(
            rootURL: rootURL, configuration: configuration,
            sets: sets.filter { remaining.contains($0.photoSet.id) }, entries: entries,
            destinationURL: destinationURL)
    }
}

/// The confirmation sheet's copy for one Move rejects plan (PRD P0-10, design handoff).
///
/// The design handoff's "Move Rejects" copy replaces the PRD's proposed sentence for this sheet:
/// a title with the rejected count, the destination and the promise that nothing is deleted, and
/// a partial line and button once the person keeps some rejects. The refused line is kept from
/// the earlier brief because the handoff has no string for sets that cannot move (P0-10).
public struct RejectMoveConfirmation: Hashable, Sendable {
    /// The sheet's title, "Move N rejected photos" (design handoff, P0-10).
    public let title: String
    /// "To <folder> in this folder. Nothing is deleted." (design handoff, P0-10).
    public let body: String
    /// "K of N will move" once a keep is staged, or nil while every ready set moves (P0-10).
    public let partialLine: String?
    /// "Move" or "Move K" for the confirm action (design handoff, P0-10).
    public let moveButtonTitle: String
    /// The separate line for refused sets, or nil when every set is ready (P0-10).
    public let refusedMessage: String?
    /// How many ready sets the sheet counts (PRD P0-10).
    public let photoCount: Int
    /// How many ready sets will move after the staged keeps (PRD P0-10).
    public let movingCount: Int
    /// How many requested sets the plan refuses to move (PRD P0-10).
    public let refusedCount: Int

    /// Builds the sheet copy from a plan and its staged keeps (design handoff, P0-10).
    public init(plan: RejectMovePlan, kept: Set<PhotoIdentity> = []) {
        let keptCount = plan.readyEntries.filter { kept.contains($0.identity) }.count
        self.init(
            plan: plan, keptCount: keptCount, movingCount: plan.photoCount - keptCount)
    }

    /// Builds the sheet copy from the staging value the sheet toggles (design handoff, P0-10).
    public init(selection: RejectMoveKeepSelection) {
        self.init(
            plan: selection.plan, keptCount: selection.keptCount,
            movingCount: selection.movingCount)
    }

    private init(plan: RejectMovePlan, keptCount: Int, movingCount: Int) {
        photoCount = plan.photoCount
        self.movingCount = movingCount
        refusedCount = plan.refusedCount
        title =
            plan.photoCount == 1
            ? "Move 1 rejected photo" : "Move \(plan.photoCount) rejected photos"
        body =
            "To \(plan.configuration.rejectsFolderName.rawValue) in this folder."
            + " Nothing is deleted."
        partialLine =
            keptCount == 0 ? nil : "\(movingCount) of \(plan.photoCount) will move"
        moveButtonTitle = movingCount == plan.photoCount ? "Move" : "Move \(movingCount)"
        refusedMessage =
            plan.refusedCount == 0
            ? nil
            : plan.refusedCount == 1
                ? "1 photo can't be moved right now."
                : "\(plan.refusedCount) photos can't be moved right now."
    }
}

/// The toast one completed Move rejects run shows over the grid (design handoff, PRD P0-10).
///
/// The handoff shows "Moved N to <folder>"; a partial run adds "<M> couldn't be moved" and a
/// Details action. The skipped line is kept from the earlier brief because C6 leaves skipped sets
/// out of "couldn't be moved" and the handoff has no string for them.
public struct RejectMoveToast: Hashable, Sendable {
    /// "Moved N to <folder>" (design handoff, P0-10).
    public let message: String
    /// "<M> couldn't be moved", or nil when every move was confirmed (design handoff).
    public let failureMessage: String?
    /// The skipped sets, or nil when none was (P0-10).
    public let skippedMessage: String?
    /// The failed sets whose Reject was cleared before the retry, or nil (P0-10).
    public let noLongerRejectedMessage: String?
    /// Whether the toast offers Details (design handoff, P0-10).
    public let showsDetails: Bool

    /// Builds the toast from one run's result and the folder it moved to (design handoff).
    public init(result: RejectMoveResult, rejectsFolderName: RejectsFolderName) {
        message = "Moved \(result.movedCount) to \(rejectsFolderName.rawValue)"
        failureMessage =
            result.unmovedCount == 0 ? nil : "\(result.unmovedCount) couldn't be moved"
        skippedMessage = Self.skipped(result.otherSkippedCount)
        noLongerRejectedMessage = Self.noLongerRejected(result.noLongerRejectedCount)
        showsDetails = result.unmovedCount > 0
    }

    /// The skipped sentence, shared with the details sheet (PRD P0-10).
    static func skipped(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 photo was skipped." : "\(count) photos were skipped."
    }

    /// The "no longer rejected" sentence, shared with the details sheet (PRD P0-10).
    static func noLongerRejected(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1
            ? "1 photo is no longer rejected." : "\(count) photos are no longer rejected."
    }
}

/// The details sheet behind a partial Move rejects toast (design handoff, PRD P0-10).
///
/// The handoff's title and subtitle say that the failed photos stay rejected and nothing was
/// deleted, and each row names the photo set and the reason. Try again is offered only when C6 has
/// failed sets it can resend; a split set is reported but never retried (PRD P0-10).
public struct RejectMoveDetails: Hashable, Sendable {
    /// One failed photo set, with the file name and the plain-text reason (design handoff).
    public struct Row: Hashable, Sendable, Identifiable {
        /// C1's stable identity of the set (PRD P0-10).
        public let id: PhotoIdentity
        /// The primary file name, with its companion kinds when it has any (design handoff).
        public let fileName: String
        /// The reason in the details sheet's plain wording (design handoff, P0-10).
        public let reason: String

        /// Describes one failed set's row (design handoff).
        public init(id: PhotoIdentity, fileName: String, reason: String) {
            self.id = id
            self.fileName = fileName
            self.reason = reason
        }
    }

    /// "N photos couldn't be moved" (design handoff, P0-10).
    public let title: String
    /// "They stay rejected in Clove. Nothing was deleted." (design handoff, P0-10).
    public let subtitle: String
    /// One row per failed or split set, in the result's order (PRD P0-10).
    public let rows: [Row]
    /// The skipped sets, or nil when none was (PRD P0-10).
    public let skippedMessage: String?
    /// The failed sets whose Reject was cleared before the retry, or nil (P0-10).
    public let noLongerRejectedMessage: String?
    /// Whether Try again can resend anything (PRD P0-10).
    public let canRetry: Bool

    /// Builds the details sheet from one run's result (design handoff, PRD P0-10).
    public init(result: RejectMoveResult) {
        let unmoved = result.unmovedCount
        title =
            unmoved == 1
            ? "1 photo couldn't be moved" : "\(unmoved) photos couldn't be moved"
        subtitle = "They stay rejected in Clove. Nothing was deleted."
        var rows: [Row] = result.failed.map { set in
            Row(
                id: set.identity, fileName: Self.fileName(set.files, identity: set.identity),
                reason: set.failure.reason.userMessage)
        }
        rows.append(
            contentsOf: result.split.map { set in
                Row(
                    id: set.identity, fileName: Self.fileName(set.files, identity: set.identity),
                    reason: set.failure.reason.userMessage)
            })
        self.rows = rows
        skippedMessage = RejectMoveToast.skipped(result.otherSkippedCount)
        noLongerRejectedMessage = RejectMoveToast.noLongerRejected(
            result.noLongerRejectedCount)
        canRetry = result.failedCount > 0
    }

    /// The primary name plus the companion kinds the set carries (design handoff).
    private static func fileName(
        _ files: [RejectMoveFilePlan], identity: PhotoIdentity
    ) -> String {
        guard let primary = files.first(where: { $0.role == .primary })?.source.lastPathComponent
        else { return identity.stem }
        var parts = [primary]
        if files.contains(where: { $0.role == .jpegCompanion }) { parts.append("JPG") }
        if files.contains(where: { $0.role == .heifCompanion }) { parts.append("HIF") }
        return parts.joined(separator: " + ")
    }

    /// The primary name plus the companion kinds a split set's locations name (design handoff).
    private static func fileName(
        _ files: [RejectMoveFileLocation], identity: PhotoIdentity
    ) -> String {
        guard let primary = files.first(where: { $0.role == .primary })?.source.lastPathComponent
        else { return identity.stem }
        var parts = [primary]
        if files.contains(where: { $0.role == .jpegCompanion }) { parts.append("JPG") }
        if files.contains(where: { $0.role == .heifCompanion }) { parts.append("HIF") }
        return parts.joined(separator: " + ")
    }
}

/// The one place the Move rejects screens keep wording C6 does not own (PRD Failure and recovery).
public enum RejectMoveCopy {
    /// PRD Failure and recovery's "Read-only location" sentence, reused by the move sheet.
    ///
    /// The real move lane refuses a read-only volume before it touches a file
    /// (``RejectMoveRefusal/readOnlyLocation(_:)``), and the sheet shows this sentence instead of
    /// reporting every photo as failed. U7's save-state mapping can reuse the same sentence.
    public static let viewOnlyLocation =
        "You can view this location, but can't save marks here."
}

extension RejectMoveFailureReason {
    /// The details sheet's plain reason for one failure (design handoff, PRD P0-10).
    ///
    /// The handoff's rows show a short sentence such as "The location is read-only."; these are
    /// placeholder strings until U7's approved failure copy lands.
    public var userMessage: String {
        switch self {
        case .permissionLost: "The location can't be written to."
        case .readOnlyStorage: "The location is read-only."
        case .insufficientSpace: "There isn't enough space here."
        case .locationUnavailable: "The file couldn't be found. Try again."
        case .differentVolume: "The rejects folder is on a different drive."
        case .conflict: "A file with that name is already there."
        case .notConfirmed: "The move wasn't confirmed. Try again."
        case .ambiguousSidecar: "The photo set has more than one XMP file."
        case .outsideOpenedFolder: "The photo set is outside this folder."
        case .unknown: "The file couldn't be moved. Try again."
        }
    }
}
