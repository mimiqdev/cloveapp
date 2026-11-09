import Darwin
import Foundation

@testable import CloveCore

/// A throwaway folder tree for scan tests; call ``remove()`` when the test ends.
struct ScanTestFolder {
    /// The folder the scan opens, inside the system's temporary directory.
    let url: URL

    /// Creates an empty folder with a unique name (PRD scan scope tests only).
    init() throws {
        let created = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clove-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        // The enumerator reports `/private/var` where the system temporary directory says
        // `/var`, so the test's own URLs are canonicalized to what the walk yields.
        url = Self.canonicalURL(for: created)
    }

    /// Resolves the volume's firmlinks, so the test's URL spelling matches the enumerator's.
    private static func canonicalURL(for url: URL) -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let resolved = url.path(percentEncoded: false).withCString { realpath($0, &buffer) }
        guard let resolved else { return url }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// Writes `relativePath` as a small placeholder file and returns its URL.
    @discardableResult
    func file(_ relativePath: String, bytes: Int = 16) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: fileURL)
        return fileURL
    }

    /// Creates `relativePath` as a directory and returns its URL.
    @discardableResult
    func directory(_ relativePath: String) throws -> URL {
        let directoryURL = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// The URL of `relativePath` below the folder, whether or not the file exists.
    func fileURL(_ relativePath: String) -> URL {
        url.appendingPathComponent(relativePath)
    }

    /// Deletes the whole tree; permissions are restored first by the tests that change them.
    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Everything one scan delivered, collected from its batches and summary.
struct ScanOutcome {
    /// The batches in delivery order.
    var batches: [ScanBatch] = []
    /// The walk's final summary, once the sequence ended.
    var summary: ScanSummary?

    /// The items in delivery order.
    var items: [ScanItem] { batches.flatMap(\.items) }

    /// The logical photos the walk produced.
    var photos: [ScannedPhotoSet] {
        items.compactMap { item in
            guard case .photo(let photo) = item else { return nil }
            return photo
        }
    }

    /// The stems the walk could not turn into one set.
    var ambiguousStems: [AmbiguousStem] {
        items.compactMap { item in
            guard case .ambiguousStem(let ambiguous) = item else { return nil }
            return ambiguous
        }
    }

    /// Photos by their folded stem, for folders whose stems are unique.
    var photosByStem: [String: ScannedPhotoSet] {
        Dictionary(
            photos.map { ($0.photoSet.id.stem, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Whether every batch's items together match the summary's logical photo count.
    var itemsMatchLogicalPhotoCount: Bool {
        (summary?.logicalPhotoCount ?? -1) == photos.count
    }
}

/// Runs one scan and collects every batch plus the summary.
func scanFolder(
    _ folder: ScanTestFolder,
    configuration: ScanConfiguration = ScanConfiguration(),
    folderID: FolderIdentity = FolderIdentity(rawValue: "scan-test-folder")
) async throws -> ScanOutcome {
    let scan = FolderScan(
        folderURL: folder.url, folderID: folderID, configuration: configuration)
    var outcome = ScanOutcome()
    for try await batch in scan {
        outcome.batches.append(batch)
    }
    outcome.summary = try await scan.summary()
    return outcome
}

/// Holds a task at a known point until the test opens it, so a cancellation lands first.
actor TestGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    /// Suspends until ``open()`` ran; returns at once when it already did.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    /// Releases whoever is waiting, and everyone who waits later.
    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

/// Whether `directory` accepts two names that differ only by case (a case-sensitive volume).
func acceptsCaseDistinctNames(_ directory: URL) throws -> Bool {
    let fileManager = FileManager.default
    let lower = directory.appendingPathComponent("CaseProbe.txt")
    let upper = directory.appendingPathComponent("CASEPROBE.TXT")
    try Data([0x41]).write(to: lower)
    defer {
        try? fileManager.removeItem(at: lower)
        try? fileManager.removeItem(at: upper)
    }
    try Data([0x42]).write(to: upper)
    let names = try fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
    return names.filter { $0.lowercased() == "caseprobe.txt" }.count == 2
}
