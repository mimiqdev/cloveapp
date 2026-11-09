import SpikeSupport

/// S3 — How should XMP be read and written?
///
/// Verification codecs, independent inspection, and the folder suite live in
/// this module. The Lab screen exports the suite's measurements for part 2.
public enum SpikeS3XMP {
    /// How Clove Lab lists this spike; the identifier and question come from the
    /// M1 table in `docs/DEV-PLAN.md`.
    public static let descriptor = SpikeDescriptor(
        id: "S3",
        question: "How should XMP be read and written?"
    )
}
