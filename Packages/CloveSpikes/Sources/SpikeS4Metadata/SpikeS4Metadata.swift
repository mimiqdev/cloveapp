import SpikeSupport

/// S4 — Can metadata be changed without re-encoding?
///
/// Placeholder: the spike's device code and measurements land in this module and
/// in `CloveLab/Spikes/S4/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every spike produces.
public enum SpikeS4Metadata {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S4",
        question: "Can metadata be changed without re-encoding?"
    )
}
