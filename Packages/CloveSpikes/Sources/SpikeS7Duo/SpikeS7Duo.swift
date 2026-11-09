import SpikeSupport

/// S7 — How does the system expose Duo fold state?
///
/// The platform-independent event model and report formatting live alongside
/// this descriptor. UIKit sampling lives in `CloveLab/Spikes/S7/`.
public enum SpikeS7Duo {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S7",
        question: "How does the system expose Duo fold state?"
    )
}
