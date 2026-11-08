import SpikeSupport

/// S1 — Can folder access be remembered and restored reliably?
///
/// Bookmark records, exact system-error capture, coordinated probes, and watch
/// comparisons live in this module. The Lab screen is in `CloveLab/Spikes/S1/`;
/// findings and the pending device checklist are in `docs/spikes/S1-access.md`.
public enum SpikeS1Access {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S1",
        question: "Can folder access be remembered and restored reliably?"
    )
}
