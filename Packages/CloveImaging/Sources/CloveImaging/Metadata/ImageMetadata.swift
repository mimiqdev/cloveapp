import Foundation

/// The location selected for a metadata field. A missing field has no location.
public enum MetadataLocation: Sendable, Equatable {
    case imageProperty(String)
    case fileCreation
    case fileModification
}

public enum MetadataField<Value: Sendable & Equatable>: Sendable, Equatable {
    case value(Value, source: MetadataLocation)
    case missing
    case invalid(rawValue: String, source: MetadataLocation)

    public var value: Value? {
        if case .value(let value, _) = self { return value }
        return nil
    }

    public var source: MetadataLocation? {
        switch self {
        case .value(_, let source), .invalid(_, let source): source
        case .missing: nil
        }
    }
}

/// A wall clock without an offset must never be interpreted in the device's zone.
public enum MetadataTimestamp: Sendable, Equatable {
    case cameraWallTime(Date)
    case utc(Date)
}

public struct CaptureTime: Sendable, Equatable {
    /// Gregorian camera wall time, encoded relative to UTC solely as a zone-free surrogate.
    /// Includes the fractional second. This alone is not an absolute instant.
    public let wallTime: Date
    public let utcOffsetSeconds: Int?

    public var timestamp: MetadataTimestamp {
        if let utcOffsetSeconds {
            return .utc(wallTime.addingTimeInterval(-Double(utcOffsetSeconds)))
        }
        return .cameraWallTime(wallTime)
    }
}

/// Only `captureMetadata` is eligible for grouping. File dates are sorting fallbacks.
public enum MetadataTime: Sendable, Equatable {
    case captureMetadata(CaptureTime)
    case fileCreation(Date)
    case fileModification(Date)
    case unavailable
}

public struct ImageMetadata: Sendable, Equatable {
    public let captureTime: MetadataField<CaptureTime>
    /// Original digits, including leading/trailing zeroes, so precision is retained.
    public let subseconds: MetadataField<String>
    /// Signed seconds east of UTC; `.missing` explicitly means no known offset.
    public let utcOffset: MetadataField<Int>
    public let model: MetadataField<String>
    public let bodySerial: MetadataField<String>
    public let fileCreationTime: MetadataField<Date>
    public let fileModificationTime: MetadataField<Date>

    public var time: MetadataTime {
        if let capture = captureTime.value { return .captureMetadata(capture) }
        if let creation = fileCreationTime.value { return .fileCreation(creation) }
        if let modification = fileModificationTime.value { return .fileModification(modification) }
        return .unavailable
    }
}

public enum MetadataReadFailure: Sendable, Equatable {
    case unreadableFile
    case propertiesUnavailable
    case cancelled
}

public enum MetadataReadOutcome: Sendable, Equatable {
    case success(ImageMetadata)
    case failure(MetadataReadFailure)
}

public struct MetadataFileResult: Sendable, Equatable {
    public let url: URL
    public let outcome: MetadataReadOutcome
}
