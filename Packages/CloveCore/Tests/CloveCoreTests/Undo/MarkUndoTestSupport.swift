import Foundation
import Testing

@testable import CloveCore

/// A valid rating for undo tests; an out-of-range value records an issue instead of passing.
func undoRating(_ value: Int) -> Rating {
    guard let rating = Rating(rawValue: value) else {
        Issue.record("\(value) is not a valid rating")
        return .unrated
    }
    return rating
}

/// The green label several undo tests use (PRD Marking rules).
let undoGreen = ColourLabel(colour: .green)

/// Reads a sidecar packet's marks through the codec, independent of C4's confirmation.
func undoSidecarMarks(at url: URL) throws -> XMPMarks {
    try XMPCodec().read(try Data(contentsOf: url))
}

/// Writes a sidecar packet holding the supplied marks, as an earlier session left it.
///
/// The packet goes through C4's own staged writer on the real file system, so the next read
/// sees exactly the marks a folder open would see (PRD How marks reach disk, rule 1).
func undoSeedSidecar(_ marks: PhotoMarks, at url: URL) async {
    _ = await SidecarMarkWriter().write(
        XMPEdit(rating: .set(marks.rating), label: .set(marks.label)), to: url)
}

/// The marks a folder session would read now: XMP for a RAW set, Clove storage otherwise.
///
/// PRD How marks reach disk, rule 1, reads a RAW set's rating (Reject included) and label from
/// the sidecar and a standalone photo's from app storage (G1 decisions 2 and 6). Tests use this
/// to check what the next read returns.
func undoCurrentMarks(
    for set: ScannedPhotoSet,
    stored: [PhotoIdentity: CloveStoredMarks]
) throws -> PhotoMarks {
    var marks = PhotoMarks()
    switch set.photoSet.markPersistence.rating {
    case .cloveStorage:
        marks.rating = stored[set.id]?.rating ?? .unrated
        marks.label = stored[set.id]?.label ?? .clear
    case .xmpSidecar(let url):
        if FileManager.default.fileExists(atPath: url.path) {
            let packet = try XMPCodec().read(try Data(contentsOf: url))
            marks.rating = packet.rating.rating ?? .unrated
            marks.label = packet.label
        }
    }
    return marks
}

/// The marks source undo reads at step time, backed by the files C4 writes.
///
/// Reading the storage rather than a mirror is what makes a newer mark visible to a step, so a
/// field another app or a later write changed is kept (PRD P0-05).
actor UndoFolderReader {
    /// C4's queue, for sidecar writes and standalone Clove-stored marks (G1 decisions 2 and 6).
    private let queue: MarkWriteQueue
    /// The sets the session can read, keyed by C1's identity.
    private let sets: [PhotoIdentity: ScannedPhotoSet]

    /// Starts from the sets a scan produced.
    init(queue: MarkWriteQueue, sets: [ScannedPhotoSet]) {
        self.queue = queue
        var lookup: [PhotoIdentity: ScannedPhotoSet] = [:]
        for set in sets { lookup[set.id] = set }
        self.sets = lookup
    }

    /// The marks for one photo now; a missing set reads as unmarked (PRD P0-05).
    func marks(for photo: PhotoIdentity) async -> PhotoMarks {
        guard let set = sets[photo] else { return PhotoMarks() }
        var stored: [PhotoIdentity: CloveStoredMarks] = [:]
        if let value = try? await queue.storedMarks(for: photo) {
            stored[photo] = value
        }
        return (try? undoCurrentMarks(for: set, stored: stored)) ?? PhotoMarks()
    }
}

/// The photo-set lookup a folder session passes to undo, with removable sets.
///
/// A removed set stands in for a rescan that dropped a photo, which must be reported rather
/// than guessed at (PRD P0-05).
actor UndoPhotoSetSource {
    /// The sets the session can still write, keyed by C1's identity.
    private var sets: [PhotoIdentity: ScannedPhotoSet] = [:]

    /// Starts from the sets a scan produced.
    init(_ sets: [ScannedPhotoSet] = []) {
        for set in sets { self.sets[set.id] = set }
    }

    /// Adds or replaces one photo's set.
    func set(_ set: ScannedPhotoSet) {
        sets[set.id] = set
    }

    /// Drops one photo's set, as a rescan that no longer finds it would.
    func remove(_ photo: PhotoIdentity) {
        sets[photo] = nil
    }

    /// The set for one photo, or `nil` when the session no longer has it.
    func set(for photo: PhotoIdentity) -> ScannedPhotoSet? {
        sets[photo]
    }
}

/// A queue, history, reader and set source over a fresh test folder.
///
/// The queue and the reader share one injected file seam, so a test can fail a specific write
/// and still read the marks the way the folder session does.
struct UndoTestFixture {
    /// The throwaway folder; call ``remove()`` when the test ends.
    let folder: WriteTestFolder
    /// The file seam C4 writes through, for injected failures and write counts.
    let double: WriteFileSystemDouble
    /// C4's queue, rooted at the folder's Clove storage.
    let queue: MarkWriteQueue
    /// The session's finishing-action records, shared with ``history`` (PRD P0-12).
    let completion: GroupCompletionTracker
    /// C5's history over that queue and those records.
    let history: MarkUndoHistory
    /// The marks source a step reads.
    let reader: UndoFolderReader
    /// The set lookup a step writes with.
    let sets: UndoPhotoSetSource
    /// The RAW sets the fixture created, in order.
    let photoSets: [ScannedPhotoSet]

    /// Creates RAW sets named after `stems` in a new folder.
    init(stems: [String] = ["A"], folderID: FolderIdentity = makeFolderIdentity()) throws {
        let testFolder = try WriteTestFolder()
        folder = testFolder
        double = WriteFileSystemDouble()
        queue = MarkWriteQueue(storeDirectory: testFolder.file("store"), fileSystem: double)
        completion = GroupCompletionTracker()
        history = MarkUndoHistory(queue: queue, completion: completion)
        photoSets = try stems.map {
            try makeScannedSet(folder: folderID, root: testFolder.url, stem: $0)
        }
        reader = UndoFolderReader(queue: queue, sets: photoSets)
        sets = UndoPhotoSetSource(photoSets)
    }

    /// The sidecar a RAW set writes, named by replacing the RAW extension (G1 Sidecar naming).
    func sidecar(_ index: Int = 0) -> URL {
        photoSets[index].photoSet.primary.url.deletingPathExtension()
            .appendingPathExtension("xmp")
    }

    /// Applies a change and records it, as a detail view's marking action does.
    ///
    /// The marks before come from ``reader``, so the record holds exactly what the folder
    /// showed before the write (PRD P0-05).
    @discardableResult
    func record(
        _ change: MarkChange,
        on photo: PhotoIdentity,
        photoToReturnTo: PhotoIdentity? = nil
    ) async -> MarkChangeStatus? {
        guard let set = photoSets.first(where: { $0.id == photo }) else { return nil }
        let before = await reader.marks(for: photo)
        let status = await queue.apply(change, to: set)
        await history.record(status, marksBefore: before, photoToReturnTo: photoToReturnTo)
        return status
    }

    /// Applies one change to many photos and records the batch, as multi-select marking does.
    @discardableResult
    func recordBatch(
        _ change: MarkChange,
        on photos: [PhotoIdentity],
        photoToReturnTo: PhotoIdentity? = nil
    ) async -> MarkBatchResult? {
        let members = photoSets.filter { photos.contains($0.id) }
        guard members.count == photos.count else { return nil }
        var before: [PhotoIdentity: PhotoMarks] = [:]
        for photo in photos { before[photo] = await reader.marks(for: photo) }
        let batch = await queue.apply(change, to: members)
        await history.recordBatch(
            batch, marksBefore: before, photoToReturnTo: photoToReturnTo)
        return batch
    }

    /// Deletes the whole folder tree.
    func remove() { folder.remove() }
}

/// Runs one undo step with the fixture's sources, matching the view's call.
func undoStep(_ fixture: UndoTestFixture) async -> MarkUndoResult? {
    let sets = fixture.sets
    let reader = fixture.reader
    return await fixture.history.undo(
        photoSet: { await sets.set(for: $0) },
        latestMarks: { await reader.marks(for: $0) })
}

/// Runs one redo step with the fixture's sources, matching the view's call.
func undoRedoStep(_ fixture: UndoTestFixture) async -> MarkUndoResult? {
    let sets = fixture.sets
    let reader = fixture.reader
    return await fixture.history.redo(
        photoSet: { await sets.set(for: $0) },
        latestMarks: { await reader.marks(for: $0) })
}

/// Every field one left-alone reason covers, for a compact assertion.
func undoLeftAloneFields(_ outcome: MarkUndoPhotoOutcome) -> [MarkUndoField] {
    outcome.leftAlone.map(\.field)
}
