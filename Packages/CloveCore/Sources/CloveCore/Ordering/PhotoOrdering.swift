import Foundation

/// The grid's ordered photos, their withheld set and their filters (PRD P0-03, G1 decision 3).
///
/// Photos enter in the scanner's batches, get their time or marks updated, and leave when
/// they move to the rejects folder. Only a photo with a known time, or with a finished read
/// that found no time, is placed. A pending photo is withheld and counted instead, so the
/// grid never shows a temporary filename order first (G1 decision 3).
///
/// Reads order the placed photos deterministically:
///
/// - one ascending timeline by instant, including subseconds;
/// - capture times and file-time fallbacks interleaved, never split into sections;
/// - equal instants broken by relative folder path, then file name, then identity;
/// - photos with no usable time after every timed photo, in that same path, name and
///   identity order.
///
/// The order is a total function of each photo's own values, so adding photos, or a pending
/// photo getting its time, can only insert the newcomers in their positions: a photo that is
/// already placed never moves relative to another. Ordering a few thousand photos is cheap, so
/// reads sort rather than the model maintaining an order across updates.
public struct PhotoOrdering: Sendable {
    private var placed: [GridPhoto] = []
    private var placedIDs: Set<PhotoIdentity> = []
    private var pending: [PhotoIdentity: GridPhoto] = [:]

    /// Starts from photos in any input order; `.pending` ones stay withheld (PRD P0-03).
    public init(photos: [GridPhoto] = []) {
        insert(photos)
    }

    /// How many photos wait for a metadata read and are withheld from the ordered photos.
    public var pendingCount: Int { pending.count }

    /// Adds or replaces photos, keeping every other photo. Supply the scanner's batches as
    /// they stream; a photo already known is replaced under its new time. When one batch
    /// repeats an identity, the last copy wins.
    public mutating func insert(_ photos: [GridPhoto]) {
        for photo in photos { store(photo) }
    }

    /// Gives a withheld or placed photo its capture or fallback time, or records that its read
    /// finished with no usable time (PRD P0-03). A pending photo leaves the withheld count
    /// and takes its position; no other photo changes place. An unknown identity is ignored.
    public mutating func setTime(_ time: PhotoTimeState, for id: PhotoIdentity) {
        guard var photo = photo(for: id) else { return }
        photo.time = time
        store(photo)
    }

    /// Replaces a photo's marks. The order and the withheld set are untouched, because
    /// filters never change the order (PRD P0-03). An unknown identity is ignored.
    public mutating func setMarks(_ marks: PhotoMarks, for id: PhotoIdentity) {
        if pending[id] != nil {
            pending[id]?.marks = marks
            return
        }
        guard let index = placed.firstIndex(where: { $0.id == id }) else { return }
        placed[index].marks = marks
    }

    /// Drops photos that left the opened folder, such as the sets a move to `_Rejected`
    /// took away (G1 decision 5). Unknown identities are ignored.
    public mutating func remove(_ ids: [PhotoIdentity]) {
        let removing = Set(ids)
        placed.removeAll { removing.contains($0.id) }
        placedIDs.subtract(removing)
        pending = pending.filter { !removing.contains($0.key) }
    }

    /// The placed photos in `order`, holding only the ones `filter` accepts (PRD P0-03).
    /// Filtering never reorders, and neither option changes the stored photos.
    public func photos(order: PhotoOrder = .captureTime, matching filter: PhotoFilter = .all)
        -> [GridPhoto]
    {
        let accepted = placed.filter {
            filter.matches($0.marks, relativeFolderPath: $0.id.relativeFolderPath)
        }
        switch order {
        case .captureTime:
            return accepted.sorted(by: precedes)
        case .fileName:
            return accepted.sorted(by: filePrecedes)
        }
    }

    /// The one photo under an identity, withheld or placed.
    private func photo(for id: PhotoIdentity) -> GridPhoto? {
        pending[id] ?? placed.first { $0.id == id }
    }

    /// Places or replaces one photo, using its identity as the key (PRD P0-01).
    private mutating func store(_ photo: GridPhoto) {
        if placedIDs.contains(photo.id) {
            placed.removeAll { $0.id == photo.id }
            placedIDs.remove(photo.id)
        }
        pending.removeValue(forKey: photo.id)
        switch photo.time {
        case .known, .unavailable:
            placed.append(photo)
            placedIDs.insert(photo.id)
        case .pending:
            pending[photo.id] = photo
        }
    }
}

/// The default order: timed photos ascending, then untimed photos, with the path, name and
/// identity tiebreaks (PRD P0-03, G1 decision 3).
private func precedes(_ lhs: GridPhoto, _ rhs: GridPhoto) -> Bool {
    let left = lhs.time.placeRank
    let right = rhs.time.placeRank
    if left != right { return left < right }
    if let leftTime = lhs.time.time, let rightTime = rhs.time.time,
        leftTime.instant != rightTime.instant
    {
        return leftTime.instant < rightTime.instant
    }
    return pathNameIdentityPrecede(lhs, rhs)
}

/// The filename order: Finder-like path then file name, identity last (PRD P0-03).
private func filePrecedes(_ lhs: GridPhoto, _ rhs: GridPhoto) -> Bool {
    let paths = lhs.id.relativeFolderPath.localizedStandardCompare(rhs.id.relativeFolderPath)
    if paths != .orderedSame { return paths == .orderedAscending }
    let names = lhs.fileName.localizedStandardCompare(rhs.fileName)
    if names != .orderedSame { return names == .orderedAscending }
    return identityPrecedes(lhs.id, rhs.id)
}

/// The tiebreak inside one relative folder path, ending at identity (PRD P0-03).
private func pathNameIdentityPrecede(_ lhs: GridPhoto, _ rhs: GridPhoto) -> Bool {
    if lhs.id.relativeFolderPath != rhs.id.relativeFolderPath {
        return lhs.id.relativeFolderPath < rhs.id.relativeFolderPath
    }
    if lhs.fileName != rhs.fileName { return lhs.fileName < rhs.fileName }
    return identityPrecedes(lhs.id, rhs.id)
}

/// Identity's own order, so two distinct photos never compare equal (PRD P0-01 keys).
private func identityPrecedes(_ lhs: PhotoIdentity, _ rhs: PhotoIdentity) -> Bool {
    if lhs.folderID != rhs.folderID { return lhs.folderID.rawValue < rhs.folderID.rawValue }
    if lhs.relativeFolderPath != rhs.relativeFolderPath {
        return lhs.relativeFolderPath < rhs.relativeFolderPath
    }
    return lhs.stem < rhs.stem
}
