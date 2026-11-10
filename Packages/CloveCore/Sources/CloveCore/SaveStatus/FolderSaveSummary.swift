import Foundation

/// The one save-state line for the open folder, as the grid and the detail view show it
/// (PRD P0-08).
///
/// PRD P0-08 keeps save status always visible and confirms each change in its own storage, so
/// the indicator summarises the folder instead of repeating every photo: **Writing…** while a
/// change is admitted and unfinished, **All saved** only once every requested change read back
/// as a sidecar write, and a count for the photos whose change did not confirm or is only
/// confirmed in Clove. PRD Failure and recovery requires the failed count to stay visible while
/// other writes run, so a failure never hides behind **Writing…**.
///
/// G1 decisions 5 and 6 keep three confirmed kinds apart: a sidecar write is **Saved**, a
/// standalone JPEG/HIF mark is **Saved in Clove only**, and a Reject that is merely stored is
/// **Stored in Clove**. The folder line never folds either Clove kind into **All saved**, and a
/// folder with nothing requested says so rather than claiming everything was saved.
public struct FolderSaveSummary: Hashable, Sendable {
    /// How many changes read back from their sidecar (PRD P0-08's **Saved**).
    public let savedInSidecar: Int
    /// How many standalone marks are confirmed in Clove storage only (G1 decision 6).
    public let savedInCloveOnly: Int
    /// How many Rejects are confirmed in Clove storage and not moved yet (G1 decision 5).
    public let storedInClove: Int
    /// How many changes are waiting for or running their write.
    public let writing: Int
    /// How many changes did not confirm (PRD P0-08).
    public let failed: Int

    /// Summarises every photo's latest state in the open folder.
    ///
    /// A superseded change counts as neither saved nor unsaved, because a newer change the user
    /// asked for replaced it (PRD How marks reach disk, rule 8).
    public init(states: [MarkChangeState]) {
        var savedInSidecar = 0
        var savedInCloveOnly = 0
        var storedInClove = 0
        var writing = 0
        var failed = 0
        for state in states {
            switch state {
            case .pending, .writing:
                writing += 1
            case .failed:
                failed += 1
            case .savedInSidecar:
                savedInSidecar += 1
            case .savedInCloveOnly:
                savedInCloveOnly += 1
            case .storedInClove:
                storedInClove += 1
            case .superseded:
                break
            }
        }
        self.savedInSidecar = savedInSidecar
        self.savedInCloveOnly = savedInCloveOnly
        self.storedInClove = storedInClove
        self.writing = writing
        self.failed = failed
    }

    /// Whether a change is unfinished, so the unsaved list has something to show.
    public var hasUnfinished: Bool { writing > 0 || failed > 0 }

    /// Whether every recorded change is a confirmed sidecar write.
    public var isAllSaved: Bool {
        failed == 0 && writing == 0 && savedInCloveOnly == 0 && storedInClove == 0
            && savedInSidecar > 0
    }

    /// What the indicator reads.
    ///
    /// A failure is never hidden by a running write (PRD Failure and recovery), and a Clove-only
    /// mark or a stored Reject keeps its own words instead of being called saved
    /// (G1 decisions 5–6).
    public var text: String {
        if failed > 0 {
            let unsaved = failed == 1 ? "1 photo not saved" : "\(failed) photos not saved"
            return writing > 0 ? "Writing…, \(failed) not saved" : unsaved
        }
        if writing > 0 { return "Writing…" }
        if isAllSaved { return "All saved" }
        var parts: [String] = []
        if savedInSidecar > 0 {
            parts.append(savedInSidecar == 1 ? "1 saved" : "\(savedInSidecar) saved")
        }
        if savedInCloveOnly > 0 {
            parts.append(
                savedInCloveOnly == 1
                    ? "1 saved in Clove only" : "\(savedInCloveOnly) saved in Clove only")
        }
        if storedInClove > 0 {
            parts.append(
                storedInClove == 1 ? "1 stored in Clove" : "\(storedInClove) stored in Clove")
        }
        return parts.isEmpty ? "No changes yet" : parts.joined(separator: ", ")
    }
}

/// Whether leaving the open folder asks first (PRD Failure and recovery, last row).
///
/// PRD P0-08 and "Failure and recovery" require a question before leaving a folder with
/// unconfirmed writes, and also require the answer to never treat those changes as saved. A
/// folder with nothing unfinished leaves without a question, so the confirmation never becomes
/// noise the user learns to dismiss.
public enum LeaveFolderConfirmation: Hashable, Sendable {
    /// Nothing is unfinished, so leaving needs no question.
    case leave
    /// This many changes are unfinished; ask before leaving.
    case ask(unfinished: Int)

    /// The PRD's proposed copy, used as written.
    public static let message = "Some marks haven't finished saving."

    /// Decides from every photo's latest state in the folder.
    ///
    /// A failed change stays unfinished until it is retried or superseded (PRD How marks reach
    /// disk, rule 8), and PRD Failure and recovery forbids reporting it as saved after leaving,
    /// so a failure asks exactly like a write that has not run yet.
    public init(states: [MarkChangeState]) {
        let unfinished = states.filter(\.isUnfinished).count
        self = unfinished > 0 ? .ask(unfinished: unfinished) : .leave
    }

    /// Whether the folder must be left behind a question.
    public var shouldAsk: Bool {
        if case .ask = self { return true }
        return false
    }

    /// How many changes the question is about.
    public var unfinishedCount: Int {
        if case .ask(let count) = self { return count }
        return 0
    }

    /// The PRD's question, or nil when leaving needs none.
    public var question: String? {
        switch self {
        case .leave:
            nil
        case .ask:
            LeaveFolderConfirmation.message
        }
    }

    /// The action that waits for C4 to finish before the folder closes.
    public var waitTitle: String { "Wait for writes" }

    /// The action that closes the folder now, without reporting the unconfirmed changes as saved.
    public var leaveTitle: String { "Leave anyway" }
}
