import CloveCore
import Foundation

/// One photo whose change has not finished saving, for the indicator's short list
/// (PRD P0-08).
///
/// The list names the photos instead of repeating the whole folder, and each row's Retry resends
/// exactly that photo's latest change. The status is C4's, so a row can show **Writing…** and a
/// failure without the indicator asking the library again.
struct UnsavedChange: Identifiable, Hashable {
    /// C4's handle for the change, which is also the row's identity.
    let id: MarkChangeID
    /// The photo the change belongs to (PRD P0-08).
    let photo: PhotoIdentity
    /// The photo's file name, so the row is recognisable.
    let fileName: String
    /// The change's current save state (PRD P0-08).
    let state: MarkChangeState
}

/// Where a destination that leaves the open folder goes once the user answers
/// (PRD Failure and recovery, last row).
enum LeaveFolderDestination: Hashable {
    /// The entry screen, with the folder closed behind it.
    case entry
    /// A folder chosen in the system picker (PRD P0-01).
    case picked(URL)
    /// A remembered folder (PRD P0-02).
    case recent(RecentFolder)
}

/// The question standing before a destination that leaves the open folder.
///
/// PRD Failure and recovery asks "Some marks haven't finished saving." with **Wait for writes**
/// and **Leave anyway** before leaving a folder with unconfirmed writes; the copy and the actions
/// live in CloveCore's ``LeaveFolderConfirmation``. The prompt only remembers where the user was
/// going, so the question is asked once and the answer performs that one destination.
struct LeaveFolderPrompt: Identifiable, Hashable {
    /// A fresh value per question, so a re-asked question is a new sheet.
    let id = UUID()
    /// Where the user was going when the question appeared.
    let destination: LeaveFolderDestination
}
