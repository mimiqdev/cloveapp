import LabSupport

/// Previews — Are previews fast enough? Measurement code, not the production pipeline.
public enum PreviewProbe {
    public static let descriptor = ProbeDescriptor(id: "S2", question: "Are previews fast enough?")
}
