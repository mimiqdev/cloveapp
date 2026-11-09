import LabSupport

/// Folder access — Can folder access be remembered and restored reliably?
///
/// Bookmark records, exact system-error capture, coordinated probes, and watch
/// comparisons live in this module. The Lab screen is in `CloveLab/Probes/FolderAccess/`;
/// findings and the pending device checklist are in `docs/spikes/S1-access.md`.
public enum FolderAccessProbe {
    /// How Clove Lab lists this probe; the identifier and question come from the
    /// verification table in `docs/DEV-PLAN.md`.
    public static let descriptor = ProbeDescriptor(
        id: "S1",
        question: "Can folder access be remembered and restored reliably?"
    )
}
