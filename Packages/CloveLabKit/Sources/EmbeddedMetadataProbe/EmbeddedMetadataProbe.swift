import LabSupport

/// Embedded metadata — Can metadata be changed without re-encoding?
///
/// Reusable verification code lives in this module; the device confirmation
/// screen is in `CloveLab/Probes/EmbeddedMetadata/`. See `docs/spikes/S4-metadata.md` for the
/// macOS/simulator findings and the pending hardware confirmation.
public enum EmbeddedMetadataProbe {
    /// How Clove Lab lists this probe; the identifier and question come from the
    /// verification table in `docs/DEV-PLAN.md`.
    public static let descriptor = ProbeDescriptor(
        id: "S4",
        question: "Can metadata be changed without re-encoding?"
    )
}
