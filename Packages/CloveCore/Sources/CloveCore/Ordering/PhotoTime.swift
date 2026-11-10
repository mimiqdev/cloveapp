import Foundation

/// Where a photo's ordering instant came from (PRD P0-03, G1 decision 3).
public enum PhotoTimeSource: Hashable, Sendable {
    /// Capture metadata, the only source that keeps a photo eligible for grouping.
    case captureMetadata
    /// The primary file's creation time, used when capture metadata has no usable time.
    case fileCreation
    /// The primary file's modification time, used when creation time is missing too.
    case fileModification
}

/// One photo's ordering instant and its provenance (PRD P0-03, G1 decision 3).
///
/// CloveCore owns this value so the grid can order photos without importing the
/// metadata reader. Integration maps I4's `ImageMetadata.time` onto it mechanically:
///
/// - Capture metadata with a UTC offset: `instant` is that exact absolute instant,
///   the camera wall time plus subseconds shifted by the offset.
/// - Capture metadata without an offset: the camera wall time is not an instant, so
///   its wall components are read in the device's current time zone to produce
///   `instant`, and `hasUTCOffset` is false. It is never treated as UTC.
/// - `.fileCreation` and `.fileModification`: the date is used exactly as read.
/// - `.unavailable`: there is no value; the photo's state is `PhotoTimeState.unavailable`.
///
/// The instant keeps whatever subsecond precision it was read with. Ordering compares
/// these values directly and never rounds them.
public struct PhotoTime: Hashable, Sendable {
    /// The instant used for ordering, including the capture subsecond where one exists.
    public let instant: Date
    /// Which source produced `instant` (PRD P0-03, G1 decision 3).
    public let source: PhotoTimeSource
    /// Whether capture metadata carried an explicit UTC offset; always false for file times.
    public let hasUTCOffset: Bool

    /// Uses a capture instant, already resolved to an absolute time or to wall time in
    /// the device's zone (G1 decision 3).
    public init(captureTime instant: Date, hasUTCOffset: Bool) {
        self.instant = instant
        self.source = .captureMetadata
        self.hasUTCOffset = hasUTCOffset
    }

    /// Uses capture metadata's wall clock, resolving it to an instant (G1 decision 3, I4).
    ///
    /// EXIF stores the camera's own wall time, which is not an instant on its own. With an
    /// explicit UTC offset, subtracting it gives the exact instant and the subsecond is kept.
    /// Without one, the wall components are read in `timeZone` and the result records
    /// `hasUTCOffset == false`; it is never treated as UTC. Pass the device's current zone for
    /// I4's no-offset case, which is the mapping rule above.
    public init(captureWallTime wallTime: Date, utcOffsetSeconds: Int?, in timeZone: TimeZone) {
        if let utcOffsetSeconds {
            self.init(
                captureTime: wallTime.addingTimeInterval(-Double(utcOffsetSeconds)),
                hasUTCOffset: true)
        } else {
            self.init(
                captureTime: Self.instant(forWallTime: wallTime, in: timeZone),
                hasUTCOffset: false)
        }
    }

    /// Reads a zone-free wall clock's components as UTC, then rebuilds them in `timeZone`.
    ///
    /// The subsecond is carried through the calendar so a burst's frames keep their order.
    private static func instant(forWallTime wallTime: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: wallTime)
        calendar.timeZone = timeZone
        return calendar.date(from: components) ?? wallTime
    }

    /// Uses the primary file's creation time as it was read (G1 decision 3).
    public init(fileCreation instant: Date) {
        self.instant = instant
        self.source = .fileCreation
        self.hasUTCOffset = false
    }

    /// Uses the primary file's modification time as it was read (G1 decision 3).
    public init(fileModification instant: Date) {
        self.instant = instant
        self.source = .fileModification
        self.hasUTCOffset = false
    }

    /// Whether the photo may join a burst group: capture metadata only (G1 decision 3).
    /// A file time can drift from the real shot time, so fallback photos stay ungrouped.
    public var isGroupable: Bool { source == .captureMetadata }
}

/// What the grid currently knows about a photo's ordering time (PRD P0-03, G1 decision 3).
public enum PhotoTimeState: Hashable, Sendable {
    /// Metadata is still being read; the photo is withheld from the order.
    case pending
    /// The photo has a place on the timeline.
    case known(PhotoTime)
    /// The metadata read finished without a usable time. These photos follow every timed
    /// photo, ordered by relative folder path and file name, rather than being withheld
    /// like a pending photo or hidden from the grid.
    case unavailable

    /// The ordering time, when one exists.
    public var time: PhotoTime? {
        if case .known(let time) = self { return time }
        return nil
    }

    /// Whether the photo may join a burst group; only capture metadata qualifies
    /// (G1 decision 3, exposed so grouping does not re-derive it).
    public var isGroupable: Bool { time?.isGroupable ?? false }

    /// Whether the photo waits for its metadata read and stays out of the ordered list.
    public var isPending: Bool { self == .pending }

    /// Places timed photos first, then unavailable ones; pending photos are never placed.
    var placeRank: Int {
        switch self {
        case .known: return 0
        case .unavailable: return 1
        case .pending: return 2
        }
    }
}
