import LabSupport

/// Scan — How long does scanning take?
///
/// Placeholder: the probe's device code and measurements land in this module and
/// in `CloveLab/Probes/Scan/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every probe produces.
public enum ScanProbe {
    /// How Clove Lab lists this probe; the identifier and question come from the
    /// verification table in `docs/DEV-PLAN.md`.
    public static let descriptor = ProbeDescriptor(
        id: "S6",
        question: "How long does scanning take?"
    )
}
