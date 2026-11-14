import Foundation

/// Walks one opened folder once and pairs its files into photo sets.
///
/// PRD scan scope and G1's scan approach fix the shape: one `FileManager.enumerator` pass
/// that prefetches name, regular file, directory, size and modification date and never asks
/// for a file type; hidden entries, `._` files, package contents and the rejects folder are
/// left alone; same-folder stems pair without regard to case.
struct PhotoFolderWalk: Sendable {
    /// The opened folder to walk; the caller already has access to it (PRD P0-02).
    let rootURL: URL
    /// The caller's durable folder key, used for every `PhotoIdentity` (C1, G1 decision 5).
    let folderID: FolderIdentity
    /// Rejects folder name and batch size (PRD scan scope, G1 scan approach).
    let configuration: ScanConfiguration

    /// The five keys G1's scan approach prefetches, and the only ones the walk reads.
    static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey,
        .contentModificationDateKey,
    ]

    /// The same five keys as a set, for the one resource read per image file.
    static let resourceKeySet = Set(resourceKeys)

    /// Walks the tree, hands batches to `emit`, and returns the walk's summary.
    /// Throws `CancellationError` when the calling task is cancelled, and
    /// ``PhotoScanError/unreadableRoot(_:)`` when the root cannot be enumerated at all.
    func run(emit: (ScanBatch) -> Void) throws -> ScanSummary {
        try Task.checkCancellation()
        var walk = FolderWalk(folderID: folderID, configuration: configuration)
        var enumerationIssues: [ScanIssue] = []
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Self.resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    // PRD scan scope: one unreadable folder or file makes the scan partial,
                    // and the walk carries on.
                    enumerationIssues.append(ScanIssue(url: url, error: error))
                    return true
                })
        else { throw PhotoScanError.unreadableRoot(rootURL) }

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let entry = WalkEntry(url: url, isDirectory: url.hasDirectoryPath)
            if try walk.receive(entry, emit: emit) {
                enumerator.skipDescendants()
            }
        }
        for issue in enumerationIssues {
            walk.record(issue)
        }
        return try walk.finish(emit: emit)
    }

    /// The path without a trailing slash, so folder keys compare equal across entries.
    /// Foundation gives a directory URL a trailing slash and keeps one on its parent.
    static func directoryPath(of url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

// MARK: - Entry-by-entry walk

/// One entry the walk visits, in the depth-first order an enumerator produces.
/// A directory appears before its contents, so files always belong to the deepest open
/// folder; the type comes from the enumeration and is never resolved again.
struct WalkEntry: Sendable {
    /// The entry's actual URL and spelling (PRD scan scope).
    let url: URL
    /// Whether the entry is a folder to descend into. The enumeration already knows, so
    /// the walk never resolves a file type of its own (G1 scan approach).
    let isDirectory: Bool
}

/// The walk's bookkeeping, one entry at a time.
///
/// A folder is reconciled only after the walk has left it, so every file of a stem group is
/// known before its set is built. A set's members therefore never split across batches, even
/// when a subfolder is walked between two of them. Items keep the order in which the first
/// file of each stem appeared, and nothing is sorted by name: ordering is C8's job (PRD Grid).
///
/// The type is separate from `FileManager` so a test can feed an exact walk order, which no
/// generated folder can guarantee on a hashed directory index.
struct FolderWalk {
    private let folderID: FolderIdentity
    private let configuration: ScanConfiguration
    /// Folder contents not yet reconciled, by relative path without a trailing slash.
    private var directories: [String: DirectoryContents] = [:]
    private var batches: BatchEmitter
    private var unsupportedFiles: [URL] = []
    private var issues: [ScanIssue] = []
    private var skippedFolderCount = 0
    private var logicalPhotoCount = 0
    private var ambiguousMemberCount = 0
    private var ambiguousSidecarCount = 0
    private var orphanSidecarCount = 0
    /// Folders still being walked, outermost first, in absolute and opened-root relative form.
    /// The enumerator may spell the root differently from the caller's URL (for example
    /// `/private/var` for `/var`), so this table starts from the first entry's parent.
    private var open: [(absolutePath: String, relativePath: String)] = []

    /// Prepares one walk's counters and open-folder table (PRD scan scope, G1 scan approach).
    init(folderID: FolderIdentity, configuration: ScanConfiguration) {
        self.folderID = folderID
        self.configuration = configuration
        self.batches = BatchEmitter(size: configuration.batchSize)
        // The opened root is never yielded as an entry of its own, so its contents start here.
        self.directories[""] = DirectoryContents()
    }

    /// Visits one entry in depth-first order.
    /// Returns true when the caller must skip the folder's descendants: the rejects folder,
    /// a package or a hidden folder (PRD scan scope, G1 decision 5).
    mutating func receive(_ entry: WalkEntry, emit: (ScanBatch) -> Void) throws -> Bool {
        let parentPath = PhotoFolderWalk.directoryPath(
            of: entry.url.deletingLastPathComponent())
        if open.isEmpty { open.append((parentPath, "")) }
        while let deepest = open.last, deepest.absolutePath != parentPath {
            try complete(deepest.relativePath, emit: emit)
            open.removeLast()
            if open.isEmpty { open.append((parentPath, "")) }
        }
        guard let parent = open.last else { return false }
        let name = entry.url.lastPathComponent
        let relativePath = parent.relativePath.isEmpty ? name : parent.relativePath + "/" + name
        guard entry.isDirectory else {
            addFile(url: entry.url, relativeFolderPath: parent.relativePath)
            return false
        }
        if entry.url.pathExtension.lowercased() == "xmp" {
            directories[parent.relativePath]?.add(packetURL: entry.url)
            return true
        }
        if shouldSkip(folder: entry.url, name: name) {
            skippedFolderCount += 1
            return true
        }
        open.append((PhotoFolderWalk.directoryPath(of: entry.url), relativePath))
        directories[relativePath] = DirectoryContents()
        return false
    }

    /// Records one read issue; the walk carries on and the summary becomes partial
    /// (PRD scan scope, P0-01).
    mutating func record(_ issue: ScanIssue) {
        issues.append(issue)
    }

    /// Reconciles everything still open and reports what the walk found (PRD P0-01).
    mutating func finish(emit: (ScanBatch) -> Void) throws -> ScanSummary {
        while let deepest = open.popLast() {
            try complete(deepest.relativePath, emit: emit)
        }
        batches.flush(emit: emit)
        return ScanSummary(
            logicalPhotoCount: logicalPhotoCount,
            unsupportedFileCount: unsupportedFiles.count,
            unsupportedFiles: unsupportedFiles,
            ambiguousMemberCount: ambiguousMemberCount,
            ambiguousSidecarCount: ambiguousSidecarCount,
            orphanSidecarCount: orphanSidecarCount,
            skippedFolderCount: skippedFolderCount,
            status: issues.isEmpty ? .complete : .partial,
            issues: issues)
    }

    /// Whether a directory is left alone: the rejects folder, a package or a hidden folder.
    /// PRD scan scope, G1 decision 5 (`_Rejected` is skipped) and G1's scan approach.
    private func shouldSkip(folder url: URL, name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if name.caseInsensitiveCompare(configuration.rejectsFolderName) == .orderedSame {
            return true
        }
        // `.skipsPackageDescendants` already stops the walk; this read only lets the walk
        // count the package it skipped. It is one check per directory, never per file.
        let values = try? url.resourceValues(forKeys: [.isPackageKey])
        return values?.isPackage ?? false
    }

    /// Classifies one file once and files it under its open folder.
    /// Extensions come from `PhotoFormat`, never from a content type (PRD Supported files,
    /// G1 scan approach).
    private mutating func addFile(url: URL, relativeFolderPath: String) {
        let name = url.lastPathComponent
        // Foundation normally omits hidden and AppleDouble files itself; names are still
        // filtered here rather than depending on that behavior (S6, PRD scan scope).
        guard !name.hasPrefix(".") else { return }
        if url.pathExtension.lowercased() == "xmp" {
            directories[relativeFolderPath]?.add(packetURL: url)
            return
        }
        guard let file = PhotoFile(url: url) else {
            unsupportedFiles.append(url)
            return
        }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: PhotoFolderWalk.resourceKeySet)
        } catch {
            record(ScanIssue(url: url, error: error))
            return
        }
        guard values.isRegularFile != false else { return }
        directories[relativeFolderPath]?.add(
            image: ScannedImageFile(
                file: file, size: values.fileSize,
                modificationDate: values.contentModificationDate))
    }

    /// Reconciles one completed folder and publishes its sets.
    private mutating func complete(_ relativePath: String, emit: (ScanBatch) -> Void) throws {
        guard let contents = directories.removeValue(forKey: relativePath) else { return }
        let result = try PhotoFolderWalk.reconcile(
            contents, folderID: folderID, relativeFolderPath: relativePath)
        orphanSidecarCount += result.orphanSidecarCount
        for item in result.items {
            switch item {
            case .photo(let photo):
                logicalPhotoCount += 1
                if case .ambiguous = photo.sidecar { ambiguousSidecarCount += 1 }
            case .ambiguousStem:
                ambiguousMemberCount += 1
            }
        }
        batches.add(result.items, emit: emit)
        // The folder's sets are whole now, so publish them instead of waiting for a full
        // batch: the first batch arrives as early as pairing allows (G1 scan approach).
        batches.flush(emit: emit)
    }
}

// MARK: - Reconciliation

extension PhotoFolderWalk {
    /// Turns one folder's stem groups into items and counts the packets no RAW claimed.
    /// G1 decision 1 fixes the primary rule through `PhotoSet`; G1 sidecar naming decides
    /// when a packet can be reused and when the choice is ambiguous.
    static func reconcile(
        _ contents: DirectoryContents,
        folderID: FolderIdentity,
        relativeFolderPath: String
    ) throws -> (items: [ScanItem], orphanSidecarCount: Int) {
        var items: [ScanItem] = []
        var claimedPackets: Set<URL> = []
        for key in contents.stemOrder {
            guard let group = contents.groups[key] else { continue }
            let members = group.members
            let raws = members.filter { $0.file.format == .raw }
            let jpegs = members.filter { $0.file.format == .jpeg }
            let heifs = members.filter { $0.file.format == .heif }
            let memberExtensions = Set(members.map { $0.file.url.pathExtension.lowercased() })
            var sidecar = SidecarState.absent
            if !raws.isEmpty {
                let packets = contents.packets(forStem: key, memberExtensions: memberExtensions)
                sidecar = Self.sidecarState(from: packets)
                claimedPackets.formUnion(packets.map(\.url))
            }
            if raws.count > 1 || jpegs.count > 1 || heifs.count > 1 {
                items.append(
                    .ambiguousStem(
                        AmbiguousStem(
                            relativeFolderPath: relativeFolderPath, stem: group.stem,
                            imageFiles: members, sidecar: sidecar)))
                continue
            }
            let photoSet = try PhotoSet(
                folderID: folderID,
                relativeFolderPath: relativeFolderPath,
                rawURL: raws.first?.file.url,
                jpegURL: jpegs.first?.file.url,
                heifURL: heifs.first?.file.url,
                sidecarURL: sidecar.resolvedURL)
            items.append(
                .photo(
                    ScannedPhotoSet(
                        photoSet: photoSet, sidecar: sidecar,
                        imageFiles: [raws.first, jpegs.first, heifs.first].compactMap { $0 })))
        }
        let orphanSidecarCount = contents.packets.filter {
            !claimedPackets.contains($0.url)
        }.count
        return (items, orphanSidecarCount)
    }

    /// Reads one RAW group's packets: one same-stem packet is reused, anything else that
    /// could be the destination is ambiguous and never silently chosen (G1 sidecar naming).
    static func sidecarState(from packets: [DirectoryContents.PacketMatch]) -> SidecarState {
        switch packets.count {
        case 0:
            return .absent
        case 1 where !packets[0].isAppendedExtension:
            return .resolved(packets[0].url)
        default:
            // An appended name such as `NAME.ARW.xmp`, or two same-stem packets on a
            // case-sensitive volume, would make C1 propose a second packet.
            return .ambiguous(packets.map(\.url))
        }
    }
}

// MARK: - Per-directory contents

/// The files one folder contributed, grouped by case-folded stem in walk order.
/// PRD scan scope pairs same-stem files within one folder and never across folders.
struct DirectoryContents {
    /// One stem group: every image with that stem, in walk order.
    struct StemGroup {
        /// The stem's actual spelling, from its first member (PRD scan scope).
        let stem: String
        /// The images of the group in walk order.
        var members: [ScannedImageFile] = []
    }

    /// One packet found in the folder, with the stem its name carries.
    struct Packet {
        /// The packet's actual URL and spelling (G1 sidecar naming).
        let url: URL
        /// The last path component without `.xmp`; `NAME.ARW.xmp` has the stem `NAME.ARW`.
        let stem: String
    }

    /// One packet that could belong to a stem, and whether its name appends an extension.
    struct PacketMatch {
        /// The packet's actual URL.
        let url: URL
        /// True for a name like `NAME.ARW.xmp`, false for a plain `NAME.xmp`.
        let isAppendedExtension: Bool
    }

    /// Stem groups by folded stem, with their actual spelling kept in the group.
    private(set) var groups: [String: StemGroup] = [:]
    /// Folded stems in first-appearance order, which is the folder's walk order.
    private(set) var stemOrder: [String] = []
    /// Every `.xmp` file in the folder, in walk order.
    private(set) var packets: [Packet] = []

    /// Adds one image to its stem group, creating the group in walk order.
    mutating func add(image: ScannedImageFile) {
        let stem = image.file.url.deletingPathExtension().lastPathComponent
        let key = stem.lowercased()
        if var group = groups[key] {
            group.members.append(image)
            groups[key] = group
        } else {
            groups[key] = StemGroup(stem: stem, members: [image])
            stemOrder.append(key)
        }
    }

    /// Adds one `.xmp` file; it is never a photo and never unsupported (G1 sidecar naming).
    mutating func add(packetURL url: URL) {
        let stem = url.deletingPathExtension().lastPathComponent
        packets.append(Packet(url: url, stem: stem))
    }

    /// The folder's packets that could belong to one stem, in walk order.
    /// A plain `<stem>.xmp` matches in any case; a name that appends one of the group's own
    /// extensions, such as `<stem>.ARW.xmp`, also matches, because G1 sidecar naming calls it
    /// ambiguity rather than a destination.
    func packets(forStem key: String, memberExtensions: Set<String>) -> [PacketMatch] {
        packets.compactMap { packet in
            let stem = packet.stem.lowercased()
            if stem == key { return PacketMatch(url: packet.url, isAppendedExtension: false) }
            guard let dot = stem.lastIndex(of: "."), dot != stem.startIndex else { return nil }
            let base = String(stem[stem.startIndex..<dot])
            let extended = String(stem[stem.index(after: dot)...])
            guard base == key, memberExtensions.contains(extended) else { return nil }
            return PacketMatch(url: packet.url, isAppendedExtension: true)
        }
    }
}

// MARK: - Batches

/// Collects items and hands them out as batches of at most `size` items.
/// G1's scan approach streams results during the walk, and a set's members are always in
/// one item, so a batch boundary can never split them (PRD scan scope).
struct BatchEmitter {
    /// Maximum items per batch (G1 scan approach: 64).
    let size: Int
    private var pending: [ScanItem] = []
    private var nextNumber = 1

    /// Uses a positive batch size; ``ScanConfiguration`` already clamps its own.
    init(size: Int) {
        self.size = max(1, size)
    }

    /// Adds items and emits every full batch they complete.
    mutating func add(_ items: [ScanItem], emit: (ScanBatch) -> Void) {
        pending.append(contentsOf: items)
        while pending.count >= size {
            emit(ScanBatch(items: Array(pending.prefix(size)), number: nextNumber))
            nextNumber += 1
            pending.removeFirst(size)
        }
    }

    /// Emits the rest of the pending items; a folder's sets arrive as soon as it completes.
    mutating func flush(emit: (ScanBatch) -> Void) {
        guard !pending.isEmpty else { return }
        emit(ScanBatch(items: pending, number: nextNumber))
        nextNumber += 1
        pending.removeAll(keepingCapacity: true)
    }
}
