import LabSupport

/// RAW display — What does it cost to show a RAW's own colours on the iPhone?
///
/// Measurement code for Clove Lab, not the production preview pipeline. The report
/// identifier and export file name come from the plan's verification table.
public enum RAWDisplayProbe {
    /// How Clove Lab lists this probe.
    public static let descriptor = ProbeDescriptor(
        id: "S8",
        question: "What does showing a RAW's own colours cost on the iPhone?"
    )
}
