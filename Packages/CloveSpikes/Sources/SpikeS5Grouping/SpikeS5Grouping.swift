import SpikeSupport

/// S5 — Is the data needed for grouping available?
///
/// Verification only: metadata, image-feature measurements, a pure grouping
/// trial, and explicitly reviewed boundary labels. G1 chooses production defaults.
public enum SpikeS5Grouping {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S5",
        question: "Is the data needed for grouping available?"
    )
}
