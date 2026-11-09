import LabSupport

/// Grouping — Is the data needed for grouping available?
///
/// Verification only: metadata, image-feature measurements, a pure grouping
/// trial, and explicitly reviewed boundary labels. Production defaults are decided separately.
public enum GroupingProbe {
    /// How Clove Lab lists this probe; the identifier and question come from the
    /// verification table in `docs/DEV-PLAN.md`.
    public static let descriptor = ProbeDescriptor(
        id: "S5",
        question: "Is the data needed for grouping available?"
    )
}
