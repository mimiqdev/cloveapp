import SpikeSupport

/// S1 — Can folder access be remembered and restored reliably?
///
/// Placeholder: the spike's device code and measurements land in this module and
/// in `CloveLab/Spikes/S1/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every spike produces.
public enum SpikeS1Access {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S1",
        question: "Can folder access be remembered and restored reliably?"
    )
}
