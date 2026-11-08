import SpikeSupport

/// S4 — Can metadata be changed without re-encoding?
///
/// Reusable verification code lives in this module; the device confirmation
/// screen is in `CloveLab/Spikes/S4/`. See `docs/spikes/S4-metadata.md` for the
/// macOS/simulator findings and the pending hardware confirmation.
public enum SpikeS4Metadata {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S4",
        question: "Can metadata be changed without re-encoding?"
    )
}
