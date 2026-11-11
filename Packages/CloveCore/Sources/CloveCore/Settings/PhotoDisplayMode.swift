/// The two consistent colour sources offered by Show photos as.
public enum PhotoDisplayMode: String, CaseIterable, Hashable, Sendable {
    case rawFirst
    case cameraPreviewFirst
}

/// Memory-only device default. Exactly 5 GiB defaults to RAW.
/// A person's explicit choice always wins; no render measurements are stored.
public enum PhotoDisplayDefault {
    public static func mode(
        physicalMemory: UInt64, choice: PhotoDisplayMode? = nil
    ) -> PhotoDisplayMode {
        if let choice { return choice }
        return physicalMemory < 5 * 1024 * 1024 * 1024 ? .cameraPreviewFirst : .rawFirst
    }
}
