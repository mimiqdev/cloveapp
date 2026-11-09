import Foundation

@testable import CloveCore

/// A throwaway opened folder and Clove storage for move tests; call ``remove()`` when done.
///
/// The opened folder is `root`, and Clove's storage is its sibling `store`, so a file count
/// over the photo folder never counts the store's JSON and a failed move can be checked against
/// the exact number of image and packet files.
struct MoveTestFolder {
    /// The one temporary directory holding both parts.
    private let base: URL
    /// The opened folder Move rejects acts on.
    let url: URL
    /// Clove's stored-marks directory, outside the opened folder.
    let storage: URL

    /// Creates the two empty folders with a unique name.
    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clove-moves-\(UUID().uuidString)", isDirectory: true)
        url = base.appendingPathComponent("root", isDirectory: true)
        storage = base.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    }

    /// The URL of `relativePath` inside the opened folder, whether or not it exists.
    func file(_ relativePath: String) -> URL {
        relativePath.isEmpty ? url : url.appendingPathComponent(relativePath)
    }

    /// Writes `bytes` to `relativePath`, creating its folders, and returns the URL.
    @discardableResult
    func write(_ bytes: String, to relativePath: String) throws -> URL {
        let target = file(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: target)
        return target
    }

    /// Writes `data` to `relativePath`, creating its folders, and returns the URL.
    @discardableResult
    func write(_ data: Data, to relativePath: String) throws -> URL {
        let target = file(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
        return target
    }

    /// Writes `count` bytes of one byte value to `relativePath` and returns the URL.
    @discardableResult
    func write(bytes count: Int, to relativePath: String) throws -> URL {
        let target = file(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: count).write(to: target)
        return target
    }

    /// Whether something exists at `relativePath`.
    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: file(relativePath).path(percentEncoded: false))
    }

    /// Whether `relativePath` is a directory.
    func isDirectory(_ relativePath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: file(relativePath).path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// The exact bytes at `relativePath`, or `nil` when it does not exist.
    func contents(of relativePath: String) -> Data? {
        try? Data(contentsOf: file(relativePath))
    }

    /// Every regular file under the opened folder, as sorted relative paths.
    func files() -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var paths: [String] = []
        // The enumerator spells a temporary folder `/private/var/...`, so both sides are
        // resolved before one is subtracted from the other.
        let rootPath = RejectMovePath.canonical(url)
        for case let entry as URL in enumerator {
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = RejectMovePath.canonical(entry)
            paths.append(String(path.dropFirst(rootPath.count + 1)))
        }
        return paths.sorted()
    }

    /// How many regular files the opened folder holds, for the "nothing is deleted" check.
    func fileCount() -> Int { files().count }

    /// Deletes the whole tree.
    func remove() { try? FileManager.default.removeItem(at: base) }
}

/// `url`'s path relative to the opened folder, for assertions on a destination.
func relativePath(of url: URL, in folder: MoveTestFolder) -> String {
    let rootPath = RejectMovePath.canonical(folder.url)
    let path = RejectMovePath.canonical(url)
    guard path.hasPrefix(rootPath) else { return path }
    return String(path.dropFirst(rootPath.count + 1))
}

/// Waits until `condition` holds, failing instead of spinning forever.
///
/// A test that waits for a seam call or a mark write uses this so a broken precondition ends
/// the test after a short bound instead of hanging the suite. Polling is bounded by wall time,
/// not by an iteration count, and sleeps one millisecond per turn.
func eventually(
    timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}

/// One call the move lane made into the file seam.
struct MoveFileSystemRecord: Sendable, Hashable {
    /// The seam operation that ran.
    let step: RejectMoveFileSystemDouble.Step
    /// The URL the operation addressed.
    let url: URL
    /// The 1-based count of this operation on this URL, for ordered hooks.
    let count: Int
}

/// A file-system double for the move seam, backed by the real one.
///
/// Tests need to fail any step, refuse a different volume, make the destination appear between
/// the plan and the move, and fail the move back after some files of a set already moved. Every
/// call is recorded so a test can also prove which URLs were touched, and no operation in the
/// seam can delete or copy a file (the protocol has none).
final class RejectMoveFileSystemDouble: RejectMoveFileSystem, @unchecked Sendable {
    /// The seam operations a test can fail or observe (PRD P0-10).
    enum Step: String, CaseIterable, Sendable {
        case fileSize
        case exists
        case volumeIdentifier
        case isReadOnlyVolume
        case createDirectory
        case move
    }

    /// One injected failure: a step, a URL filter and the error to throw.
    private struct Injection: Sendable {
        let step: Step
        let matches: @Sendable (URL) -> Bool
        let error: any Error
    }

    /// The real operations, so passing tests exercise the production path.
    private let backing: any RejectMoveFileSystem
    /// Guards the records, injections, hook and overrides below.
    private let lock = NSLock()
    private var records: [MoveFileSystemRecord] = []
    private var injections: [Injection] = []
    private var hook: (@Sendable (MoveFileSystemRecord) -> Void)?
    private var volume: (@Sendable (URL) -> String?)?
    private var readOnly = false

    /// Creates the double over the production file system unless a test supplies another.
    init(backing: any RejectMoveFileSystem = FoundationRejectMoveFileSystem()) {
        self.backing = backing
    }

    /// Every operation so far, in call order.
    var allRecords: [MoveFileSystemRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    /// How many times `step` ran, optionally only for one URL.
    func count(of step: Step, at url: URL? = nil) -> Int {
        allRecords.filter { $0.step == step && (url == nil || $0.url == url) }.count
    }

    /// Fails `step` with `error`, optionally only when it addresses `url`.
    func fail(_ step: Step, at url: URL? = nil, with error: any Error) {
        let target = url
        fail(step, where: { target == nil || $0 == target }, with: error)
    }

    /// Fails `step` with `error` whenever the URL matches, for the move-back failures.
    func fail(_ step: Step, where matches: @escaping @Sendable (URL) -> Bool, with error: any Error)
    {
        lock.lock()
        injections.append(Injection(step: step, matches: matches, error: error))
        lock.unlock()
    }

    /// Stops failing `step`, so a retry can succeed.
    func stopFailing(_ step: Step) {
        lock.lock()
        injections.removeAll { $0.step == step }
        lock.unlock()
    }

    /// Runs `body` before each operation, for an external change or a delay.
    var beforeOperation: (@Sendable (MoveFileSystemRecord) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return hook
        }
        set {
            lock.lock()
            hook = newValue
            lock.unlock()
        }
    }

    /// The identifier `volumeIdentifier` reports; by default every URL is on one volume.
    var volumeIdentifier: (@Sendable (URL) -> String?)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return volume
        }
        set {
            lock.lock()
            volume = newValue
            lock.unlock()
        }
    }

    /// Whether ``isReadOnlyVolume(at:)`` reports a read-only location (PRD P0-10).
    var reportsReadOnlyVolume: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return readOnly
        }
        set {
            lock.lock()
            readOnly = newValue
            lock.unlock()
        }
    }

    /// Notes one operation, runs the hook, then throws an injected failure if one matches.
    private func prepare(_ step: Step, _ url: URL) throws -> MoveFileSystemRecord {
        lock.lock()
        let count = records.filter { $0.step == step && $0.url == url }.count + 1
        let record = MoveFileSystemRecord(step: step, url: url, count: count)
        records.append(record)
        let hook = self.hook
        let injection = injections.first { $0.step == step && $0.matches(url) }
        lock.unlock()
        hook?(record)
        if let injection { throw injection.error }
        return record
    }

    /// Reads a size through the seam (PRD P0-10's confirmation).
    func fileSize(at url: URL) throws -> Int? {
        _ = try prepare(.fileSize, url)
        return try backing.fileSize(at: url)
    }

    /// Reports existence through the seam (PRD P0-10's collision and confirmation checks).
    func exists(at url: URL) throws -> Bool {
        _ = try prepare(.exists, url)
        return try backing.exists(at: url)
    }

    /// Reports the volume through the seam, or the test's override (PRD P0-10).
    func volumeIdentifier(of url: URL) throws -> String? {
        _ = try prepare(.volumeIdentifier, url)
        lock.lock()
        let volume = self.volume
        lock.unlock()
        if let volume { return volume(url) }
        return try backing.volumeIdentifier(of: url)
    }

    /// Reports the read-only value through the seam, or the test's override (PRD P0-10).
    func isReadOnlyVolume(at url: URL) throws -> Bool {
        _ = try prepare(.isReadOnlyVolume, url)
        lock.lock()
        let readOnly = self.readOnly
        lock.unlock()
        if readOnly { return true }
        return try backing.isReadOnlyVolume(at: url)
    }

    /// Creates a folder through the seam, honouring an injected failure (PRD P0-10).
    func createDirectory(_ url: URL) throws {
        _ = try prepare(.createDirectory, url)
        try backing.createDirectory(url)
    }

    /// Renames through the seam with the real exclusive rename (PRD P0-10).
    func moveExclusively(from source: URL, to destination: URL) throws {
        _ = try prepare(.move, destination)
        try backing.moveExclusively(from: source, to: destination)
    }
}

/// A mark-write seam that can fail, block and log, so C4's queue and the move lane agree.
///
/// C4 owns the sidecar and store writes; C6 only drains them and removes a stored Reject
/// through the queue. This double lets a test hold a change in `.writing`, fail the store's
/// later write after a first Reject was stored, and record the order of a mark write and a
/// move so the drain rule can be checked without a sleep.
final class MoveMarkFileSystem: MarkWriteFileSystem, @unchecked Sendable {
    /// The real mark-write operations.
    private let backing: any MarkWriteFileSystem
    /// Guards the failure predicate, the gate and the log.
    private let lock = NSLock()
    private var failure: (@Sendable (URL) -> (any Error)?)?
    private var gate: (@Sendable (URL) -> DispatchSemaphore?)?
    private let log: MoveEventLog

    /// Creates the double over the production file system.
    init(
        backing: any MarkWriteFileSystem = FoundationMarkWriteFileSystem(),
        log: MoveEventLog = MoveEventLog()
    ) {
        self.backing = backing
        self.log = log
    }

    /// Fails a write when `failure` returns an error for the destination.
    func failWrites(when failure: @escaping @Sendable (URL) -> (any Error)?) {
        lock.lock()
        self.failure = failure
        lock.unlock()
    }

    /// Blocks `writeStaging` on the semaphore `gate` returns for the destination.
    func blockWrites(when gate: @escaping @Sendable (URL) -> DispatchSemaphore?) {
        lock.lock()
        self.gate = gate
        lock.unlock()
    }

    /// Reads through the seam without a failure injection.
    func read(_ url: URL) throws -> Data? { try backing.read(url) }

    /// Reads attributes through the seam.
    func attributes(of url: URL) throws -> MarkFileAttributes? { try backing.attributes(of: url) }

    /// Creates a folder through the seam.
    func createDirectory(_ url: URL) throws { try backing.createDirectory(url) }

    /// Writes the staging file, after honouring a gate and a failure (PRD P0-08).
    func writeStaging(_ data: Data, to url: URL) throws {
        lock.lock()
        let gate = self.gate
        let failure = self.failure
        lock.unlock()
        if let semaphore = gate?(url) { semaphore.wait() }
        log.append("markWrite")
        if let error = failure?(url) { throw error }
        try backing.writeStaging(data, to: url)
    }

    /// Synchronizes through the seam.
    func synchronize(_ url: URL) throws { try backing.synchronize(url) }

    /// Replaces through the seam.
    func replace(_ destination: URL, withItemAt staging: URL) throws {
        try backing.replace(destination, withItemAt: staging)
    }

    /// Applies permissions through the seam.
    func setPermissions(_ permissions: UInt16, of url: URL) throws {
        try backing.setPermissions(permissions, of: url)
    }

    /// Removes through the seam.
    func remove(_ url: URL) throws { try backing.remove(url) }
}

/// A lock-guarded event log shared by a mark-write double and a move double.
final class MoveEventLog: @unchecked Sendable {
    /// Guards ``events``.
    private let lock = NSLock()
    private var events: [String] = []

    /// Appends one event in call order.
    func append(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    /// Every event so far, in call order.
    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    /// The first index of `event`, or `nil` when it never happened.
    func firstIndex(of event: String) -> Int? { all.firstIndex(of: event) }
}

/// Builds one scanned photo set whose member files a test already wrote on disk.
///
/// G1 decision 5 moves every member, so the set is built from C1's own initializer: the URLs,
/// the sidecar spelling and the folder path all come from the same validation the scan uses.
func makeMoveSet(
    root: URL,
    folder: FolderIdentity = FolderIdentity(rawValue: "folder-1"),
    relativePath: String,
    stem: String,
    formats: [PhotoFormat],
    sidecarName: String? = nil
) throws -> ScannedPhotoSet {
    let directory =
        relativePath.isEmpty
        ? root : root.appendingPathComponent(relativePath, isDirectory: true)
    func member(_ pathExtension: String) -> URL {
        directory.appendingPathComponent(stem).appendingPathExtension(pathExtension)
    }
    let sidecarURL = sidecarName.map { directory.appendingPathComponent($0) }
    let sidecar = sidecarURL.map { SidecarState.resolved($0) } ?? .absent
    let set = try PhotoSet(
        folderID: folder,
        relativeFolderPath: relativePath,
        rawURL: formats.contains(.raw) ? member("ARW") : nil,
        jpegURL: formats.contains(.jpeg) ? member("JPG") : nil,
        heifURL: formats.contains(.heif) ? member("HIF") : nil,
        sidecarURL: sidecarURL)
    let imageFiles = set.imageFiles.map { file in
        ScannedImageFile(file: file, size: nil, modificationDate: nil)
    }
    return ScannedPhotoSet(photoSet: set, sidecar: sidecar, imageFiles: imageFiles)
}

/// The bytes one set member gets in a test: a valid packet for a sidecar, marker bytes otherwise.
///
/// G1's Safe writes row reads the sidecar before writing, so a test sidecar must be a valid XMP
/// packet; C3's codec builds one for an empty edit. Image contents are never read by the move,
/// so their bytes just carry the source name, which lets a test prove a destination holds the
/// same content and that a collision never overwrote an existing file.
func moveTestBytes(for url: URL, in folder: MoveTestFolder) throws -> Data {
    if url.pathExtension.lowercased() == "xmp" {
        return try XMPCodec().write(XMPEdit(), into: nil)
    }
    return Data("contents of \(relativePath(of: url, in: folder))".utf8)
}

/// Writes every file of one set with distinct, valid bytes, so a move can be checked byte for
/// byte and a later mark write can read its sidecar.
func writeMoveSet(_ set: ScannedPhotoSet, in folder: MoveTestFolder) throws {
    for url in set.photoSet.fileURLs {
        let relative = relativePath(of: url, in: folder)
        let bytes = try moveTestBytes(for: url, in: folder)
        try folder.write(bytes, to: relative)
    }
}

/// The C12 settings for a normal move test, with an optional rejects folder name.
func moveSettings(
    rejectsFolderName: String = "_Rejected", enabled: Bool = true
) -> AppSettings {
    AppSettings(
        rejectsFolderName: RejectsFolderName(rawValue: rejectsFolderName) ?? .defaultFolderName,
        moveRejectsEnabled: enabled)
}

/// One test's mover, file seams, mark queue and throwaway folders.
///
/// The real Foundation file system sits under the move double, so a passing test exercises the
/// production rename; the mark double lets a test fail or hold C4's writes. Call ``cleanup()``
/// when the test ends.
struct MoveFixture {
    /// The opened folder and Clove storage.
    let folder: MoveTestFolder
    /// The move seam, with recording and failure injection.
    let fileSystem: RejectMoveFileSystemDouble
    /// C4's mark seam, with failure and blocking hooks.
    let markFileSystem: MoveMarkFileSystem
    /// C4's write queue over the injectable store.
    let queue: MarkWriteQueue
    /// The mover under test.
    let mover: RejectMover
    /// The settings the plan and the move read (PRD P0-10).
    let configuration: RejectMoveConfiguration

    /// Creates the folders and wires the mover to the doubles.
    init(rejectsFolderName: String = "_Rejected", enabled: Bool = true) throws {
        folder = try MoveTestFolder()
        fileSystem = RejectMoveFileSystemDouble()
        markFileSystem = MoveMarkFileSystem()
        queue = MarkWriteQueue(storeDirectory: folder.storage, fileSystem: markFileSystem)
        mover = RejectMover(markQueue: queue, fileSystem: fileSystem)
        configuration = RejectMoveConfiguration(
            settings: moveSettings(rejectsFolderName: rejectsFolderName, enabled: enabled))
    }

    /// Plans `sets` against the fixture's opened folder and settings (PRD P0-10).
    func plan(_ sets: [ScannedPhotoSet]) async throws -> RejectMovePlan {
        try await mover.plan(
            for: RejectMoveRequest(
                rootURL: folder.url, sets: sets, configuration: configuration))
    }

    /// Moves a plan through the fixture's mover (PRD P0-10).
    func move(_ plan: RejectMovePlan) async throws -> RejectMoveResult {
        try await mover.move(plan)
    }

    /// Deletes the throwaway folders.
    func cleanup() { folder.remove() }
}
