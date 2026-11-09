import LabSupport

/// Fold state — How does the system expose Duo fold state?
///
/// The platform-independent event model and report formatting live alongside
/// this descriptor. UIKit sampling lives in `CloveLab/Probes/FoldState/`.
public enum FoldStateProbe {
    /// How Clove Lab lists this probe; the identifier and question come from the
    /// verification table in `docs/DEV-PLAN.md`.
    public static let descriptor = ProbeDescriptor(
        id: "S7",
        question: "How does the system expose Duo fold state?"
    )
}
