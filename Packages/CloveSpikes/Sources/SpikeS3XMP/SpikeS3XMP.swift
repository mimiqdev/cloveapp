import SpikeSupport

/// S3 — How should XMP be read and written?
///
/// Placeholder: the spike's device code and measurements land in this module and
/// in `CloveLab/Spikes/S3/`, without touching shared files. See
/// `docs/spikes/README.md` for the report every spike produces.
public enum SpikeS3XMP {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S3",
        question: "How should XMP be read and written?"
    )
}
