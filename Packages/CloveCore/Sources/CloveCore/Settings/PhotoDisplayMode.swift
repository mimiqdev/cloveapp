/// The two consistent colour sources offered by Show photos as.
public enum PhotoDisplayMode: String, CaseIterable, Hashable, Sendable {
    case rawFirst
    case cameraPreviewFirst
}

/// The first five successful screen-size RAW render durations, in milliseconds.
/// This value has no clock or storage dependency. The app persists it across launches.
public struct RAWRenderMeasurement: Hashable, Sendable {
    public private(set) var samples: [Double]

    public init(samples: [Double] = []) {
        self.samples = Array(samples.filter { $0.isFinite && $0 >= 0 }.prefix(5))
    }

    /// A completed measurement is immutable, so it is never re-measured.
    public mutating func record(milliseconds: Double) {
        guard samples.count < 5, milliseconds.isFinite, milliseconds >= 0 else { return }
        samples.append(milliseconds)
    }

    public var medianMilliseconds: Double? {
        guard samples.count == 5 else { return nil }
        return samples.sorted()[2]
    }
}

/// Device capability policy from the display decision. Exactly 6 GiB and 700 ms
/// still default to RAW. A person's explicit choice always wins.
public enum PhotoDisplayDefault {
    public static func mode(
        physicalMemory: UInt64, measurement: RAWRenderMeasurement = RAWRenderMeasurement(),
        choice: PhotoDisplayMode? = nil
    ) -> PhotoDisplayMode {
        if let choice { return choice }
        if physicalMemory < 6 * 1024 * 1024 * 1024
            || (measurement.medianMilliseconds.map { $0 > 700 } ?? false)
        {
            return .cameraPreviewFirst
        }
        return .rawFirst
    }
}
