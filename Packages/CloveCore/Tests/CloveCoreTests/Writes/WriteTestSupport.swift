import Foundation

@testable import CloveCore

/// A throwaway folder tree for write tests; call ``remove()`` when the test ends.
struct WriteTestFolder {
    /// The folder a write targets, inside the system's temporary directory.
    let url: URL

    /// Creates an empty folder with a unique name.
    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clove-writes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The URL of `name` directly inside the folder, whether or not it exists.
    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// The file names directly inside the folder, including hidden ones.
    func entries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    /// The names of Clove's staging files that are still present, in sorted order.
    ///
    /// Pass a subdirectory to check Clove storage's own folder as well as a sidecar folder.
    func stagingNames(in subdirectory: String? = nil) throws -> [String] {
        let directory = subdirectory.map { file($0) } ?? url
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".clove-staging-") || $0.hasPrefix(".clove-marks-") }
            .sorted()
    }

    /// Deletes the whole tree.
    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// One call the write lane made into the file seam.
struct WriteFileSystemRecord: Sendable, Hashable {
    /// The seam operation that ran.
    let step: WriteFileSystemDouble.Step
    /// The URL the operation addressed.
    let url: URL
    /// The 1-based count of this operation on this URL, for ordered hooks.
    let count: Int
}

/// A file-system double for the write seam, backed by the real one.
///
/// Tests need to fail any step, mutate the destination between Clove's read and its
/// `rename`, and hand back different bytes on the read-back. The double records every call so
/// a test can also assert which URLs a write touched, or that a staging file was cleaned up.
/// Mutable state is guarded by `lock`, which is why the class may be `@unchecked Sendable`:
/// the writer actor, the store and the test task all reach it.
final class WriteFileSystemDouble: MarkWriteFileSystem, @unchecked Sendable {
    /// The seam operations a test can fail or observe (G1 Safe writes).
    enum Step: String, CaseIterable, Sendable {
        case read
        case attributes
        case createDirectory
        case writeStaging
        case synchronize
        case replace
        case setPermissions
        case remove
    }

    /// One injected failure: a step, an optional URL filter, and the error to throw.
    private struct Injection: Sendable {
        let step: Step
        let url: URL?
        let error: any Error
    }

    /// The real operations, so passing tests exercise the production path.
    private let backing: any MarkWriteFileSystem
    /// Guards the records, injections and hooks below.
    private let lock = NSLock()
    private var records: [WriteFileSystemRecord] = []
    private var injections: [Injection] = []
    private var hook: (@Sendable (WriteFileSystemRecord) -> Void)?
    private var readOverride: (@Sendable (WriteFileSystemRecord) -> Data?)?
    private var staging: [URL: Data] = [:]

    /// Creates the double over the production file system unless a test supplies another.
    init(backing: any MarkWriteFileSystem = FoundationMarkWriteFileSystem()) {
        self.backing = backing
    }

    /// Every operation so far, in call order.
    var allRecords: [WriteFileSystemRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    /// Operations on one URL, in call order.
    func records(for url: URL) -> [WriteFileSystemRecord] {
        allRecords.filter { $0.url == url }
    }

    /// How many times `step` ran, optionally only for one URL.
    func count(of step: Step, at url: URL? = nil) -> Int {
        allRecords.filter { $0.step == step && (url == nil || $0.url == url) }.count
    }

    /// The bytes handed to `writeStaging` for one URL, for content assertions.
    func stagedBytes(at url: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return staging[url]
    }

    /// Fails `step` with `error`, optionally only when it addresses `url`.
    func fail(_ step: Step, at url: URL? = nil, with error: any Error) {
        lock.lock()
        injections.append(Injection(step: step, url: url, error: error))
        lock.unlock()
    }

    /// Stops failing `step`, so a retry can succeed.
    func stopFailing(_ step: Step) {
        lock.lock()
        injections.removeAll { $0.step == step }
        lock.unlock()
    }

    /// Runs `body` before each operation, for an external change or a delay.
    ///
    /// The record carries the 1-based count for that step and URL, so a test can change the
    /// destination exactly on the conflict check and nowhere else.
    var beforeOperation: (@Sendable (WriteFileSystemRecord) -> Void)? {
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

    /// Replaces the bytes a read returns, for a read-back mismatch.
    var readResult: (@Sendable (WriteFileSystemRecord) -> Data?)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return readOverride
        }
        set {
            lock.lock()
            readOverride = newValue
            lock.unlock()
        }
    }

    /// Notes one operation, runs the hook, then throws an injected failure if one matches.
    private func prepare(_ step: Step, _ url: URL) throws -> WriteFileSystemRecord {
        lock.lock()
        let count = records.filter { $0.step == step && $0.url == url }.count + 1
        let record = WriteFileSystemRecord(step: step, url: url, count: count)
        records.append(record)
        let hook = self.hook
        let injection = injections.first { $0.step == step && ($0.url == nil || $0.url == url) }
        lock.unlock()
        hook?(record)
        if let injection { throw injection.error }
        return record
    }

    /// Reads through the seam, honouring a read override (G1 Safe writes read-back).
    func read(_ url: URL) throws -> Data? {
        let record = try prepare(.read, url)
        lock.lock()
        let override = readOverride
        lock.unlock()
        if let data = override?(record) { return data }
        return try backing.read(url)
    }

    /// Reads attributes through the seam (G1 conflict check and permissions).
    func attributes(of url: URL) throws -> MarkFileAttributes? {
        _ = try prepare(.attributes, url)
        return try backing.attributes(of: url)
    }

    /// Creates a directory through the seam (Clove storage).
    func createDirectory(_ url: URL) throws {
        _ = try prepare(.createDirectory, url)
        try backing.createDirectory(url)
    }

    /// Stages bytes through the seam, keeping a copy for content assertions.
    func writeStaging(_ data: Data, to url: URL) throws {
        _ = try prepare(.writeStaging, url)
        lock.lock()
        staging[url] = data
        lock.unlock()
        try backing.writeStaging(data, to: url)
    }

    /// Synchronizes through the seam (G1 Safe writes).
    func synchronize(_ url: URL) throws {
        _ = try prepare(.synchronize, url)
        try backing.synchronize(url)
    }

    /// Replaces through the seam with the real POSIX `rename` (G1 Safe writes).
    func replace(_ destination: URL, withItemAt staging: URL) throws {
        _ = try prepare(.replace, destination)
        try backing.replace(destination, withItemAt: staging)
    }

    /// Applies permissions through the seam (G1 Safe writes).
    func setPermissions(_ permissions: UInt16, of url: URL) throws {
        _ = try prepare(.setPermissions, url)
        try backing.setPermissions(permissions, of: url)
    }

    /// Removes through the seam (G1 Safe writes cleanup).
    func remove(_ url: URL) throws {
        _ = try prepare(.remove, url)
        try backing.remove(url)
    }
}

/// Builds a scanned photo set whose image files are names only.
///
/// G1's Safe writes row only ever opens the sidecar, so a write test needs no image bytes.
/// The members still carry real URLs so an assertion can prove a companion was never opened.
/// The stem keeps the `.ARW`/`.JPG`/`.HIF` spelling the owner's camera writes.
func makeScannedSet(
    folder: FolderIdentity,
    root: URL,
    stem: String,
    relativeFolderPath: String = "",
    formats: Set<PhotoFormat> = [.raw],
    sidecar: SidecarState = .absent
) throws -> ScannedPhotoSet {
    let directory =
        relativeFolderPath.isEmpty
        ? root : root.appendingPathComponent(relativeFolderPath, isDirectory: true)
    func memberURL(_ pathExtension: String) -> URL {
        directory.appendingPathComponent(stem).appendingPathExtension(pathExtension)
    }
    let photoSet = try PhotoSet(
        folderID: folder,
        relativeFolderPath: relativeFolderPath,
        rawURL: formats.contains(.raw) ? memberURL("ARW") : nil,
        jpegURL: formats.contains(.jpeg) ? memberURL("JPG") : nil,
        heifURL: formats.contains(.heif) ? memberURL("HIF") : nil,
        sidecarURL: sidecar.resolvedURL)
    let imageFiles = photoSet.imageFiles.map {
        ScannedImageFile(file: $0, size: 1024, modificationDate: Date(timeIntervalSince1970: 0))
    }
    return ScannedPhotoSet(photoSet: photoSet, sidecar: sidecar, imageFiles: imageFiles)
}

/// A folder identity for a test folder, independent of its path so tests stay isolated.
func makeFolderIdentity(_ name: String = "folder") -> FolderIdentity {
    FolderIdentity(rawValue: "test-\(name)-\(UUID().uuidString)")
}

/// Waits for a test gate from a synchronous helper.
///
/// `DispatchSemaphore.wait` is unavailable from an async context, and the coalescing and
/// drain tests need the calling thread held until one write reaches its gate. The wait is
/// bounded, so a broken test fails instead of hanging the suite.
func waitForTestSignal(_ semaphore: DispatchSemaphore, seconds: Double = 10) -> Bool {
    semaphore.wait(timeout: .now() + seconds) == .success
}

/// A valid packet with unknown content another app could have written.
let writeTestUnknownPacket = Data(
    """
    <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:acme="https://acme.example/ns/1.0/" xmp:Rating="1">
       <acme:Section><rdf:Bag><rdf:li>keep this byte</rdf:li></rdf:Bag></acme:Section>
      </rdf:Description>
     </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end="w"?>
    """.utf8)
