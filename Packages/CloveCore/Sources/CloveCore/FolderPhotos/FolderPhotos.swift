import Foundation

/// The photos one open folder holds, built from C2's scan and kept current as reads and writes
/// land (PRD P0-01, P0-03, P0-05).
///
/// The scan is the only source of photos: each `.photo` item becomes one grid value with a
/// `.pending` time, so no photo can appear in a temporary filename order before its metadata
/// read finishes (G1 decision 3). Times and marks then arrive as separate updates, and the value
/// also keeps each photo's C2 scanned set so a write, a thumbnail or the grouping follow-up can
/// resolve an identity back to the files it names (PRD P0-08).
///
/// Every update is pure, and ``photos`` keeps the order photos arrived in; the grid applies C8's
/// order on top (``PhotoOrdering``), so nothing here decides how a photo is placed.
public struct FolderPhotos: Sendable {
    /// The grid value of each photo, by its C1 identity.
    private var gridPhotos: [PhotoIdentity: GridPhoto] = [:]
    /// The scanned set behind each photo, for writes and later thumbnail and grouping lookups.
    private var scannedSets: [PhotoIdentity: ScannedPhotoSet] = [:]
    /// The order photos first arrived in, so reads never depend on dictionary order.
    private var arrival: [PhotoIdentity] = []
    /// The camera body I4 read for each photo, kept for grouping (PRD P0-11, G1's Grouping row).
    private var cameraBodies: [PhotoIdentity: CameraBody] = [:]

    /// The photos this folder holds as grouping receives them (PRD P0-11, G1's Grouping row).
    ///
    /// Every photo enters in scan order; grouping itself decides which ones may join a group from
    /// the time's provenance and the camera body (``GroupingPhoto/isEligibleForGrouping``). The
    /// body is I4's camera model plus the serial when the file carried one, so a photo without a
    /// model never joins a group (G1's Grouping row, PRD Similar groups step 1).
    public var groupingPhotos: [GroupingPhoto] {
        photos.map { photo in
            GroupingPhoto(
                id: photo.id,
                fileName: photo.fileName,
                time: photo.time,
                body: cameraBodies[photo.id])
        }
    }

    /// Starts with no photos; the scan's batches fill it (PRD P0-01).
    public init() {}

    /// The photos this folder holds, in the order the scan delivered them (PRD P0-01).
    public var photos: [GridPhoto] { arrival.compactMap { gridPhotos[$0] } }

    /// Whether the folder holds no photo yet.
    public var isEmpty: Bool { arrival.isEmpty }

    /// How many photos the folder holds.
    public var count: Int { arrival.count }

    /// One photo's grid value, or nil when the folder no longer holds it.
    public func photo(for id: PhotoIdentity) -> GridPhoto? { gridPhotos[id] }

    /// The C2 scanned set behind one photo, for writes and the U3 thumbnail lookup (PRD P0-08).
    ///
    /// A photo the folder no longer holds has no set, so a write or a thumbnail request cannot
    /// target a file that left the folder.
    public func scannedSet(for id: PhotoIdentity) -> ScannedPhotoSet? { scannedSets[id] }

    /// Adds the photos of one scan batch and reports the ones that were new.
    ///
    /// Each `.photo` item enters with a `.pending` time and the marks Clove stores for it, so the
    /// grid withholds it until its metadata read finishes and never shows a filename order first
    /// (G1 decision 3). `.ambiguousStem` items produce no photo, because the scan refused to pick
    /// a winner among their files (PRD scan scope). A photo the folder already holds keeps its
    /// time and marks and takes the newer scanned set, so a rescan cannot drop what is on screen.
    @discardableResult
    public mutating func insert(
        _ items: [ScanItem],
        storedMarks: [PhotoIdentity: CloveStoredMarks] = [:]
    ) -> [GridPhoto] {
        var added: [GridPhoto] = []
        for item in items {
            guard case .photo(let set) = item else { continue }
            let id = set.id
            scannedSets[id] = set
            guard gridPhotos[id] == nil else { continue }
            let photo = GridPhoto(
                set: set.photoSet, time: .pending,
                marks: PhotoMarks(stored: storedMarks[id]))
            gridPhotos[id] = photo
            arrival.append(id)
            added.append(photo)
        }
        return added
    }

    /// Records a photo's ordering state once its metadata read finishes (PRD P0-03).
    ///
    /// The value comes from I4's read: capture metadata, a file-time fallback, or
    /// ``PhotoTimeState/unavailable`` when no usable time exists. An unknown identity is ignored.
    public mutating func setTime(_ time: PhotoTimeState, for id: PhotoIdentity) {
        gridPhotos[id]?.time = time
    }

    /// Replaces one photo's marks after a read or a confirmed write (PRD P0-05, P0-07).
    public mutating func setMarks(_ marks: PhotoMarks, for id: PhotoIdentity) {
        gridPhotos[id]?.marks = marks
    }

    /// Records the camera body I4 read for one photo, which grouping separates photos by
    /// (PRD P0-11, G1's Grouping row).
    ///
    /// The body is nil when the read found no usable model, so the photo stays ungrouped instead
    /// of being guessed into a bucket. An unknown identity is ignored.
    public mutating func setCameraBody(_ body: CameraBody?, for id: PhotoIdentity) {
        cameraBodies[id] = body
    }

    /// Applies the fields a confirmed change named to the photo's marks (PRD P0-08).
    ///
    /// A field the change left nil keeps its value, the same rule C4 applies per field, so a
    /// rating change never clears a label and a label never changes the rating.
    public mutating func apply(_ change: MarkChange, to id: PhotoIdentity) {
        guard var photo = gridPhotos[id] else { return }
        if let rating = change.rating { photo.marks.rating = rating }
        if let label = change.label { photo.marks.label = label }
        gridPhotos[id] = photo
    }

    /// Drops photos that left the open folder, such as the sets a rejects move took away
    /// (PRD P0-10). Unknown identities are ignored.
    public mutating func remove(_ ids: [PhotoIdentity]) {
        let removing = Set(ids)
        for id in removing {
            gridPhotos[id] = nil
            scannedSets[id] = nil
            cameraBodies[id] = nil
        }
        arrival.removeAll { removing.contains($0) }
    }
}
