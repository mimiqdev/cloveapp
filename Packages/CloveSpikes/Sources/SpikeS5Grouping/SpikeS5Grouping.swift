import SpikeSupport

/// S5 — Is the data needed for grouping available?
///
/// Placeholder: the spike's device code and measurements land in this module and
/// in `CloveLab/Spikes/S5/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every spike produces.
public enum SpikeS5Grouping {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S5",
        question: "Is the data needed for grouping available?"
    )
}
