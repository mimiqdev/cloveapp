import LabSupport

/// XMP — How should XMP be read and written?
///
/// Verification codecs, independent inspection, and the folder suite live in
/// this module. The Lab screen exports the suite's measurements for device verification.
public enum XMPProbe {
    /// How Clove Lab lists this probe; the identifier and question come from the
    /// verification table in `docs/DEV-PLAN.md`.
    public static let descriptor = ProbeDescriptor(
        id: "S3",
        question: "How should XMP be read and written?"
    )
}
