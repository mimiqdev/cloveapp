import CloveCore

/// The save state of a photo's latest change, as plain text (PRD P0-08).
///
/// Design placeholder: U7 shows the save state with its own copy, the failure reason the same
/// `MarkChangeStatus` carries, a retry and the global indicator; these words only follow
/// PRD P0-08's split between a confirmed sidecar write (**Saved**), a confirmed Clove-only mark
/// (**Saved in Clove only**) and a Clove-stored Reject, which is confirmed but never shown as
/// saved (G1 decision 5).
enum SaveStateSummary {
    /// The words for one photo's save state, or for a photo nothing has been requested for.
    static func text(for state: MarkChangeState?) -> String {
        switch state {
        case nil:
            "No change yet"
        case .pending, .writing:
            "Writing…"
        case .savedInSidecar:
            "Saved"
        case .savedInCloveOnly:
            "Saved in Clove only"
        case .storedInClove:
            "Stored in Clove"
        case .failed:
            "Not saved"
        case .superseded:
            "Replaced by a newer change"
        }
    }
}
