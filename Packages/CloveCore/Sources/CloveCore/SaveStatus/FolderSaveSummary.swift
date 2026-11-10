import Foundation

/// The one save-state line for the open folder, as the grid and the detail view show it
/// (PRD P0-08).
///
/// PRD P0-08 keeps save status always visible and confirms each change in its own storage, so
/// the indicator summarises the folder instead of repeating every photo: **Writing…** while a
/// change is admitted and unfinished, **All saved** only once every requested change read back
/// from the storage it uses, and a count of the photos whose change is not saved. A folder with
/// nothing requested has nothing to confirm and says so, rather than claiming everything saved.
public enum FolderSaveSummary: Hashable, Sendable {
    /// No change was requested in this folder, so there is nothing to confirm.
    case noChanges
    /// At least one change is waiting for or running its write (PRD P0-08: **Writing…**).
    case writing
    /// Every requested change is confirmed in its storage (PRD P0-08: read-back matched), with
    /// how many of them are Rejects that only Clove storage holds (G1 decision 5).
    case saved(storedInClove: Int)
    /// This many photos have a change that did not confirm.
    case unsaved(Int)
    /// Every change is confirmed, but only in Clove storage, so nothing was saved to a file.
    ///
    /// G1 decision 5 keeps the word Saved for XMP writes and a confirmed move, so a folder whose
    /// changes are all stored Rejects says they are stored rather than calling them saved.
    case storedInClove(Int)

    /// Summarises every photo's latest state in the open folder.
    ///
    /// A change still in progress wins, because PRD P0-08 shows **Writing…** until it settles; a
    /// finished failure counts as unsaved, and a superseded change counts as neither, because a
    /// newer change the user asked for replaced it (PRD How marks reach disk, rule 8). A Clove
    /// Reject counts as confirmed but not as saved, so it never turns the count down and a folder
    /// of only Rejects never reads **All saved**.
    public init(states: [MarkChangeState]) {
        var isWriting = false
        var failed = 0
        var saved = 0
        var stored = 0
        for state in states {
            switch state {
            case .pending, .writing:
                isWriting = true
            case .failed:
                failed += 1
            case .savedInSidecar, .savedInCloveOnly:
                saved += 1
            case .storedInClove:
                stored += 1
            case .superseded:
                break
            }
        }
        if isWriting {
            self = .writing
        } else if failed > 0 {
            self = .unsaved(failed)
        } else if saved > 0 {
            self = .saved(storedInClove: stored)
        } else if stored > 0 {
            self = .storedInClove(stored)
        } else {
            self = .noChanges
        }
    }

    /// What the indicator reads.
    ///
    /// A stored Reject is never folded into **All saved**: when one exists, the line says how
    /// many are only stored in Clove, so the folder never claims a save the Reject has not had
    /// (G1 decision 5, PRD How marks reach disk, rule 7).
    public var text: String {
        switch self {
        case .noChanges:
            "No changes yet"
        case .writing:
            "Writing…"
        case .saved(let stored) where stored == 0:
            "All saved"
        case .saved(let stored):
            stored == 1 ? "All saved, 1 stored in Clove" : "All saved, \(stored) stored in Clove"
        case .storedInClove(let count):
            count == 1 ? "1 stored in Clove" : "\(count) stored in Clove"
        case .unsaved(let count):
            count == 1 ? "1 photo not saved" : "\(count) photos not saved"
        }
    }

    /// How many photos have a change that is not saved, which is what the list opens.
    public var unsavedCount: Int {
        if case .unsaved(let count) = self { return count }
        return 0
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
