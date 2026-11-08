import Darwin
import Foundation
import UniformTypeIdentifiers

/// Lists a folder tree three ways with the same filters, so the spike can price
/// each method and key set.
///
/// Every method returns photo candidates in traversal order. The rejects folder,
/// hidden entries (which include the AppleDouble `._` files), and unsupported
/// extensions are left out unless ``ScanOptions`` asks for them. Sidecar `.xmp`
/// files are not photos and are skipped.
public enum ScanLister {
    /// Lists `folder` with `method`, prefetching `keySet`.
    ///
    /// - Parameters:
    ///   - folder: The root to walk.
    ///   - method: How the walk lists directories.
    ///   - keySet: The resource keys to fetch while walking.
    ///   - options: Filters, rejects folder name, and batch size.
    ///   - onBatch: Called synchronously for each full batch of accepted files, and
    ///     once more for the remainder. Batches are in traversal order.
    public static func list(
        folder: URL,
        method: ScanMethod,
        keySet: ScanKeySet = .all,
        options: ScanOptions = ScanOptions(),
        onBatch: (@Sendable (ScanBatch) -> Void)? = nil
    ) throws -> ScanListing {
        try Task.checkCancellation()
        switch method {
        case .fileManager:
            return try fileManagerList(
                folder: folder, keySet: keySet, options: options, onBatch: onBatch)
        case .contentsOfDirectory:
            return try contentsOfDirectoryList(
                folder: folder, keySet: keySet, options: options, onBatch: onBatch)
        case .posixReaddir:
            return try readdirList(
                folder: folder, keySet: keySet, options: options, onBatch: onBatch)
        }
    }
}

// MARK: - FileManager.enumerator

extension ScanLister {
    private static func fileManagerList(
        folder: URL,
        keySet: ScanKeySet,
        options: ScanOptions,
        onBatch: (@Sendable (ScanBatch) -> Void)?
    ) throws -> ScanListing {
        let start = ContinuousClock.now
        var accumulator = ScanAccumulator(
            folder: folder, keySet: keySet, options: options, start: start, onBatch: onBatch)
        var enumerationError: (any Error)?
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keySet.keys.isEmpty ? nil : keySet.keys,
                options: options.includeHidden ? [] : [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return true
                }
            )
        else { throw ScanFailure.cannotOpen(folder) }

        // The enumerator reports its own spelling of the root (on macOS a `/var`
        // root comes back as `/private/var/…`), so relative paths come from a
        // directory table instead of string prefixes. The enumerator yields a
        // folder before its contents, and its first entry's parent is the root.
        var relatives: [String: String] = [:]
        for case let url as URL in enumerator {
            let parent = url.deletingLastPathComponent().path(percentEncoded: false)
            let relativeParent = relatives[parent] ?? ""
            relatives[parent] = relativeParent
            let relative =
                relativeParent.isEmpty
                ? url.lastPathComponent : relativeParent + "/" + url.lastPathComponent
            if url.hasDirectoryPath {
                if Task.isCancelled { throw CancellationError() }
                relatives[url.path(percentEncoded: false)] = relative
                accumulator.countDirectory()
                if !options.includeRejected, url.lastPathComponent == options.rejectsFolderName {
                    enumerator.skipDescendants()
                    accumulator.countRejectedFolder()
                }
                continue
            }
            try accumulator.addFile(url: url, relativePath: relative)
        }
        if let enumerationError, accumulator.entriesSeen == 0 {
            throw enumerationError
        }
        if enumerationError != nil {
            accumulator.countError()
        }
        return accumulator.finish()
    }
}

// MARK: - contentsOfDirectory recursion

extension ScanLister {
    private static func contentsOfDirectoryList(
        folder: URL,
        keySet: ScanKeySet,
        options: ScanOptions,
        onBatch: (@Sendable (ScanBatch) -> Void)?
    ) throws -> ScanListing {
        let start = ContinuousClock.now
        var accumulator = ScanAccumulator(
            folder: folder, keySet: keySet, options: options, start: start, onBatch: onBatch)
        var stack: [(url: URL, relativePath: String)] = [(folder, "")]
        var openedRoot = false
        while let (directory, relativePath) = stack.popLast() {
            if Task.isCancelled { throw CancellationError() }
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: keySet.keys.isEmpty ? nil : keySet.keys,
                    options: options.includeHidden ? [] : [.skipsHiddenFiles]
                )
                openedRoot = true
            } catch {
                if !openedRoot && relativePath.isEmpty { throw ScanFailure.cannotOpen(directory) }
                accumulator.countError()
                continue
            }
            for child in children {
                let childPath =
                    relativePath.isEmpty
                    ? child.lastPathComponent : relativePath + "/" + child.lastPathComponent
                if child.hasDirectoryPath {
                    accumulator.countDirectory()
                    if !options.includeRejected,
                        child.lastPathComponent == options.rejectsFolderName
                    {
                        accumulator.countRejectedFolder()
                        continue
                    }
                    stack.append((child, childPath))
                } else {
                    try accumulator.addFile(url: child, relativePath: childPath)
                }
            }
        }
        return accumulator.finish()
    }
}

// MARK: - POSIX readdir

extension ScanLister {
    private static func readdirList(
        folder: URL,
        keySet: ScanKeySet,
        options: ScanOptions,
        onBatch: (@Sendable (ScanBatch) -> Void)?
    ) throws -> ScanListing {
        let start = ContinuousClock.now
        var accumulator = ScanAccumulator(
            folder: folder, keySet: keySet, options: options, start: start, onBatch: onBatch)
        let root = folder.path(percentEncoded: false).trimmingTrailingSlashes
        var stack: [(path: String, relativePath: String)] = [(root, "")]
        while let (directory, relativePath) = stack.popLast() {
            if Task.isCancelled { throw CancellationError() }
            guard let handle = directory.withCString({ opendir($0) }) else {
                if relativePath.isEmpty { throw ScanFailure.cannotOpen(folder) }
                accumulator.countError()
                continue
            }
            var children: [(name: String, isDirectory: Bool)] = []
            while let pointer = readdir(handle) {
                let entry = pointer.pointee
                guard let name = entry.entryName, name != ".", name != ".." else { continue }
                if !options.includeHidden && ScanRule.isHidden(name) {
                    accumulator.countHidden()
                    continue
                }
                let childPath = directory + "/" + name
                let isDirectory: Bool
                switch Int32(entry.d_type) {
                case DT_DIR:
                    isDirectory = true
                case DT_REG, DT_LNK:
                    isDirectory = false
                default:
                    // DT_UNKNOWN, or a type this walk does not trust: one lstat.
                    accumulator.countStatFallback()
                    var information = stat()
                    guard childPath.withCString({ lstat($0, &information) }) == 0 else {
                        accumulator.countError()
                        continue
                    }
                    isDirectory = (information.st_mode & S_IFMT) == S_IFDIR
                }
                children.append((name, isDirectory))
            }
            closedir(handle)
            for child in children {
                let childPath =
                    relativePath.isEmpty ? child.name : relativePath + "/" + child.name
                if child.isDirectory {
                    accumulator.countDirectory()
                    if !options.includeRejected, child.name == options.rejectsFolderName {
                        accumulator.countRejectedFolder()
                        continue
                    }
                    stack.append((directory + "/" + child.name, childPath))
                } else {
                    let url = URL(fileURLWithPath: directory).appendingPathComponent(child.name)
                    try accumulator.addFile(url: url, relativePath: childPath)
                }
            }
        }
        return accumulator.finish()
    }
}

// MARK: - Shared bookkeeping

/// One walk's filters, entries, batches, and counters.
///
/// Every method feeds the same accumulator, so the only difference between two
/// measurements is how directory entries and resource values were obtained.
struct ScanAccumulator {
    let folder: URL
    let keySet: ScanKeySet
    let options: ScanOptions
    let start: ContinuousClock.Instant
    let onBatch: (@Sendable (ScanBatch) -> Void)?
    private let reader: ScanKeyReader

    private(set) var entries: [ScanEntry] = []
    private(set) var directories = 0
    private(set) var entriesSeen = 0
    private(set) var hiddenSkipped = 0
    private(set) var unsupportedSkipped = 0
    private(set) var rejectedSkipped = 0
    private(set) var statFallbacks = 0
    private(set) var errors = 0
    private(set) var firstHundredMilliseconds: Double?
    private(set) var batches = 0
    private(set) var firstBatchMilliseconds: Double?

    private var pending: [ScanEntry] = []

    init(
        folder: URL,
        keySet: ScanKeySet,
        options: ScanOptions,
        start: ContinuousClock.Instant,
        onBatch: (@Sendable (ScanBatch) -> Void)?
    ) {
        self.folder = folder
        self.keySet = keySet
        self.options = options
        self.start = start
        self.onBatch = onBatch
        self.reader = ScanKeyReader(keySet)
    }

    mutating func countDirectory() {
        directories += 1
    }

    mutating func countHidden() {
        hiddenSkipped += 1
        entriesSeen += 1
    }

    mutating func countRejectedFolder() {
        rejectedSkipped += 1
        entriesSeen += 1
    }

    mutating func countStatFallback() {
        statFallbacks += 1
    }

    mutating func countError() {
        errors += 1
    }

    /// Applies the filters and, for a photo file, appends an entry with the
    /// requested resource values.
    mutating func addFile(url: URL, relativePath: String) throws {
        entriesSeen += 1
        let name = relativePath.lastPathComponent
        if !options.includeHidden && ScanRule.isHidden(name) {
            hiddenSkipped += 1
            return
        }
        guard ScanRule.isPhotoFile(name) else {
            unsupportedSkipped += 1
            return
        }
        if !options.includeRejected,
            relativePath.relativeDirectory.split(separator: "/").contains(
                Substring(options.rejectsFolderName))
        {
            rejectedSkipped += 1
            return
        }
        var entry = ScanEntry(url: url, relativePath: relativePath)
        do {
            try reader.apply(to: url, entry: &entry)
        } catch {
            errors += 1
            return
        }
        entries.append(entry)
        pending.append(entry)
        if entries.count == 100 {
            firstHundredMilliseconds = ScanClock.milliseconds(from: start)
        }
        if pending.count >= options.batchSize {
            flushBatch()
        }
    }

    mutating func finish() -> ScanListing {
        if !pending.isEmpty {
            flushBatch()
        }
        return ScanListing(
            entries: entries,
            directories: directories,
            entriesSeen: entriesSeen,
            hiddenSkipped: hiddenSkipped,
            unsupportedSkipped: unsupportedSkipped,
            rejectedSkipped: rejectedSkipped,
            statFallbacks: statFallbacks,
            errors: errors,
            firstHundredMilliseconds: firstHundredMilliseconds,
            batches: batches,
            firstBatchMilliseconds: firstBatchMilliseconds
        )
    }

    private mutating func flushBatch() {
        guard let onBatch else {
            pending.removeAll(keepingCapacity: true)
            return
        }
        batches += 1
        if firstBatchMilliseconds == nil {
            firstBatchMilliseconds = ScanClock.milliseconds(from: start)
        }
        onBatch(ScanBatch(entries: pending, number: batches))
        pending.removeAll(keepingCapacity: true)
    }
}

/// Reads exactly the keys of one ``ScanKeySet``, so a measurement only pays for
/// the values it asked for.
struct ScanKeyReader {
    private let keys: Set<URLResourceKey>
    private let wantsName: Bool
    private let wantsType: Bool
    private let wantsDirectory: Bool
    private let wantsSize: Bool
    private let wantsModified: Bool
    private let wantsContentType: Bool

    init(_ keySet: ScanKeySet) {
        let keys = Set(keySet.keys)
        self.keys = keys
        self.wantsName = keys.contains(.nameKey)
        self.wantsType = keys.contains(.isRegularFileKey)
        self.wantsDirectory = keys.contains(.isDirectoryKey)
        self.wantsSize = keys.contains(.fileSizeKey)
        self.wantsModified = keys.contains(.contentModificationDateKey)
        self.wantsContentType = keys.contains(.contentTypeKey)
    }

    func apply(to url: URL, entry: inout ScanEntry) throws {
        guard !keys.isEmpty else { return }
        let values = try url.resourceValues(forKeys: keys)
        if wantsName { entry.resourceName = values.name }
        if wantsType { entry.isRegularFile = values.isRegularFile }
        if wantsDirectory { entry.isDirectory = values.isDirectory ?? false }
        if wantsSize { entry.byteCount = values.fileSize }
        if wantsModified { entry.modificationDate = values.contentModificationDate }
        if wantsContentType { entry.contentTypeIdentifier = values.contentType?.identifier }
    }
}

// MARK: - C helpers

extension dirent {
    /// The entry's name as a Swift string, or `nil` when it is empty.
    var entryName: String? {
        var copy = self
        return withUnsafePointer(to: &copy.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                let name = String(cString: $0)
                return name.isEmpty ? nil : name
            }
        }
    }
}

extension String {
    /// The path without trailing slashes, so `root + "/" + name` never doubles one.
    var trimmingTrailingSlashes: String {
        var path = self
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// Last path component, for a relative path or an absolute path.
    var lastPathComponent: String {
        guard let slash = lastIndex(of: "/") else { return self }
        return String(self[index(after: slash)...])
    }
}
