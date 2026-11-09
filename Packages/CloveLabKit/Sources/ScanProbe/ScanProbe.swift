import SpikeSupport

/// S6 — How long does scanning take?
///
/// Placeholder: the spike's device code and measurements land in this module and
/// in `CloveLab/Spikes/S6/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every spike produces.
public enum SpikeS6Scan {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S6",
        question: "How long does scanning take?"
    )
}
