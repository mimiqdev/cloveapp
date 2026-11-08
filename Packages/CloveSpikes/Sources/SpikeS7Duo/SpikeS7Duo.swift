import SpikeSupport

/// S7 — How does the system expose Duo fold state?
///
/// Placeholder: the spike's device code and measurements land in this module and
/// in `CloveLab/Spikes/S7/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every spike produces.
public enum SpikeS7Duo {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S7",
        question: "How does the system expose Duo fold state?"
    )
}
