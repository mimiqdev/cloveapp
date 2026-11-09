import Foundation

/// One photo as grouping receives it (PRD P0-11, G1's Grouping row).
///
/// The app maps the scanner's photo sets and the metadata reader onto these values; grouping
/// never reads a file, a mark or an XMP packet of its own. A RAW set with companions is one
/// photo already, because C1's `PhotoSet` is one identity (G1 decision 1), so grouping never
/// sees a companion file separately.
public struct GroupingPhoto: Hashable, Sendable {
    /// The stable photo key, also the key of a group's members (PRD P0-01, P0-11).
    public let id: PhotoIdentity

    /// The primary file's name including its extension, used for the numeric-aware tiebreak
    /// when two photos share a capture instant (PRD Similar groups step 1).
    public let fileName: String

    /// The photo's ordering time and its provenance (PRD P0-03). Only a capture-metadata time
    /// is groupable (G1 decision 3, G1 Grouping row).
    public let time: PhotoTimeState

    /// The camera body, or nil when the metadata read found no model (G1 Grouping row).
    public let body: CameraBody?

    /// Collects one photo with an already resolved body key.
    public init(id: PhotoIdentity, fileName: String, time: PhotoTimeState, body: CameraBody?) {
        self.id = id
        self.fileName = fileName
        self.time = time
        self.body = body
    }

    /// Collects one photo straight from the metadata reader's model and serial values, which
    /// are both optional (G1 Grouping row). A missing model leaves the photo ungrouped.
    public init(
        id: PhotoIdentity,
        fileName: String,
        time: PhotoTimeState,
        cameraModel: String?,
        cameraSerial: String? = nil
    ) {
        self.init(
            id: id,
            fileName: fileName,
            time: time,
            body: CameraBody(model: cameraModel, serial: cameraSerial))
    }

    /// Whether PRD P0-11 may put this photo in a group.
    ///
    /// The time must come from capture metadata, because a file time can drift from the real
    /// shot time, and pending or unavailable times are never grouped (G1 decision 3). A photo
    /// without a camera model is never grouped either, because grouping cannot attribute it to
    /// a body (G1's Grouping row; C9's model-less default).
    public var isEligibleForGrouping: Bool {
        time.isGroupable && body != nil
    }

    /// The capture instant used for sorting and for adjacent gaps, when the photo has one.
    var instant: Date? { time.time?.instant }
}
