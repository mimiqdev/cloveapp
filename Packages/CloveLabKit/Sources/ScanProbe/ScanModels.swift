import Foundation
import LabSupport

/// How a scanner walks a folder tree.
public enum ScanMethod: String, CaseIterable, Sendable {
    /// `FileManager.enumerator(at:includingPropertiesForKeys:options:)`, which walks
    /// the tree itself and can prefetch resource values in bulk.
    case fileManager
    /// Recursive `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`.
    case contentsOfDirectory
    /// Foundation-free `opendir`/`readdir`/`closedir`, using the entry type or one
    /// `lstat` per entry to tell directories from files.
    case posixReaddir

    /// Label used in report tags, for example `posix-readdir`.
    public var tag: String {
        switch self {
        case .fileManager: "filemanager"
        case .contentsOfDirectory: "contents-of-directory"
        case .posixReaddir: "posix-readdir"
        }
    }

    /// Short name for a Clove Lab status line.
    public var displayName: String {
        switch self {
        case .fileManager: "FileManager.enumerator"
        case .contentsOfDirectory: "contentsOfDirectory"
        case .posixReaddir: "POSIX readdir"
        }
    }
}

/// The resource keys a scanner prefetches while listing.
///
/// The first seven cases isolate one key, so the report can price each key on its
/// own. The `name…` ladder adds one key at a time, ending in ``all``.
public enum ScanKeySet: String, CaseIterable, Sendable {
    /// No keys: names come from the directory entries only.
    case names = "names"
    case name = "name"
    case type = "type"
    case isDirectory = "isDirectory"
    case size = "size"
    case modified = "modified"
    case contentType = "contentType"
    case nameType = "name+type"
    case nameTypeSize = "name+type+size"
    case nameTypeSizeModified = "name+type+size+modified"
    case nameTypeSizeModifiedDirectory = "name+type+size+modified+isDirectory"
    /// Every key the scan lane needs: name, type, size, modification date,
    /// `isDirectory`, and content type.
    case all = "all"

    /// Keys passed to `FileManager` and requested through `URL.resourceValues`.
    public var keys: [URLResourceKey] {
        switch self {
        case .names: []
        case .name: [.nameKey]
        case .type: [.isRegularFileKey]
        case .isDirectory: [.isDirectoryKey]
        case .size: [.fileSizeKey]
        case .modified: [.contentModificationDateKey]
        case .contentType: [.contentTypeKey]
        case .nameType: [.nameKey, .isRegularFileKey]
        case .nameTypeSize: [.nameKey, .isRegularFileKey, .fileSizeKey]
        case .nameTypeSizeModified:
            [.nameKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        case .nameTypeSizeModifiedDirectory:
            [
                .nameKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                .isDirectoryKey,
            ]
        case .all:
            [
                .nameKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                .isDirectoryKey, .contentTypeKey,
            ]
        }
    }
}

/// One directory entry a scanner accepted, with only the values it was asked to
/// fetch. `nil` means the scan did not request that key.
public struct ScanEntry: Sendable, Hashable {
    /// Absolute URL of the file.
    public var url: URL
    /// Path below the scanned root, for example `DCIM/100CANON/IMG_0001.CR3`.
    public var relativePath: String
    /// `true` for a directory. Accepted entries are files, so this is `false`
    /// unless the entry was kept for diagnostics.
    public var isDirectory: Bool
    /// Value of `.nameKey` when requested; otherwise the URL's last component.
    public var resourceName: String?
    /// Value of `.isRegularFileKey` when requested.
    public var isRegularFile: Bool?
    /// Value of `.fileSizeKey` when requested.
    public var byteCount: Int?
    /// Value of `.contentModificationDateKey` when requested.
    public var modificationDate: Date?
    /// Identifier of `.contentTypeKey` when requested.
    public var contentTypeIdentifier: String?

    public init(
        url: URL,
        relativePath: String,
        isDirectory: Bool = false,
        resourceName: String? = nil,
        isRegularFile: Bool? = nil,
        byteCount: Int? = nil,
        modificationDate: Date? = nil,
        contentTypeIdentifier: String? = nil
    ) {
        self.url = url
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.resourceName = resourceName
        self.isRegularFile = isRegularFile
        self.byteCount = byteCount
        self.modificationDate = modificationDate
        self.contentTypeIdentifier = contentTypeIdentifier
    }

    /// File name without its extension, for example `IMG_0001`.
    public var baseName: String {
        (resourceName ?? url.lastPathComponent).baseNameWithoutExtension
    }

    /// Lowercased extension, without the dot.
    public var fileExtension: String {
        (resourceName ?? url.lastPathComponent).fileExtensionLowercased
    }

    /// Directory part of ``relativePath``, without a trailing slash.
    public var relativeDirectory: String {
        relativePath.relativeDirectory
    }
}

/// What one listing found, plus the counts that explain what it skipped.
public struct ScanListing: Sendable {
    /// Photo candidates in traversal order. Sort before pairing for a stable grid.
    public var entries: [ScanEntry]
    /// Directories the walk entered.
    public var directories: Int
    /// File entries the walk looked at, including skipped ones.
    public var entriesSeen: Int
    /// Hidden files and folders skipped (the AppleDouble `._` files are hidden).
    public var hiddenSkipped: Int
    /// Entries with an extension the app does not open, such as `.MOV` or `.txt`.
    public var unsupportedSkipped: Int
    /// Rejects folders, or their files, that the walk left out.
    public var rejectedSkipped: Int
    /// Entries whose type came from `lstat` because the directory entry did not
    /// carry one; only `posixReaddir` reports this.
    public var statFallbacks: Int
    /// Entries or folders that could not be read; the walk continued.
    public var errors: Int
    /// Time from the start of the walk until the 100th accepted file, in
    /// milliseconds; `nil` when fewer than 100 files were accepted.
    public var firstHundredMilliseconds: Double?
    /// Number of batches handed to `onBatch`.
    public var batches: Int
    /// Time until the first batch was produced, in milliseconds.
    public var firstBatchMilliseconds: Double?

    public init(
        entries: [ScanEntry] = [],
        directories: Int = 0,
        entriesSeen: Int = 0,
        hiddenSkipped: Int = 0,
        unsupportedSkipped: Int = 0,
        rejectedSkipped: Int = 0,
        statFallbacks: Int = 0,
        errors: Int = 0,
        firstHundredMilliseconds: Double? = nil,
        batches: Int = 0,
        firstBatchMilliseconds: Double? = nil
    ) {
        self.entries = entries
        self.directories = directories
        self.entriesSeen = entriesSeen
        self.hiddenSkipped = hiddenSkipped
        self.unsupportedSkipped = unsupportedSkipped
        self.rejectedSkipped = rejectedSkipped
        self.statFallbacks = statFallbacks
        self.errors = errors
        self.firstHundredMilliseconds = firstHundredMilliseconds
        self.batches = batches
        self.firstBatchMilliseconds = firstBatchMilliseconds
    }

    /// Entries ordered by relative path, the order the grid and pairing assume.
    public func sortedByPath() -> [ScanEntry] {
        entries.sorted { $0.relativePath < $1.relativePath }
    }
}

/// Rules applied when scanning photo folders; see the scan scope in `docs/PRD.en.md`.
public enum ScanRule {
    /// Rejects folder name used when the settings have no override (`_Rejected`).
    public static let defaultRejectsFolderName = "_Rejected"

    /// Extensions the app treats as RAW, including DNG.
    public static let rawExtensions: Set<String> = [
        "cr3", "nef", "arw", "raf", "orf", "rw2", "dng",
    ]
    /// JPEG extensions that pair with a same-name RAW.
    public static let jpegExtensions: Set<String> = ["jpg", "jpeg"]
    /// HEIC/HEIF, including camera .HIF files that can pair with a same-name RAW.
    public static let heicExtensions = PhotoExtensions.heif

    /// Every extension the scan returns as a photo.
    public static let photoExtensions: Set<String> =
        rawExtensions.union(jpegExtensions).union(heicExtensions)

    /// Whether `name` is a file the app opens.
    public static func isPhotoFile(_ name: String) -> Bool {
        photoExtensions.contains(name.fileExtensionLowercased)
    }

    /// Whether `name` is a hidden file or directory, which includes `._` files.
    public static func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".")
    }

    /// Whether `extensions` contains the lowercased extension of `name`.
    public static func hasExtension(_ name: String, in extensions: Set<String>) -> Bool {
        extensions.contains(name.fileExtensionLowercased)
    }
}

/// Options for one listing.
public struct ScanOptions: Sendable, Hashable {
    /// Folder name to skip, configurable in the app's settings (`_Rejected`).
    public var rejectsFolderName: String
    /// Whether hidden files and folders are scanned. Off by default.
    public var includeHidden: Bool
    /// Whether the rejects folder is walked and its files returned. Off by
    /// default, so the scan never touches it; the benchmark turns it on to price
    /// the alternative.
    public var includeRejected: Bool
    /// Entries per batch handed to a streaming consumer.
    public var batchSize: Int

    public init(
        rejectsFolderName: String = ScanRule.defaultRejectsFolderName,
        includeHidden: Bool = false,
        includeRejected: Bool = false,
        batchSize: Int = 64
    ) {
        self.rejectsFolderName = rejectsFolderName
        self.includeHidden = includeHidden
        self.includeRejected = includeRejected
        self.batchSize = max(1, batchSize)
    }
}

/// A photo the grid shows: one primary file, plus a paired JPEG or HEIF when present.
public struct ScannedPhoto: Sendable, Hashable {
    /// RAW when the item has a pair, otherwise the single file (JPEG, HEIC, or DNG).
    public var primary: URL
    /// Same-name JPEG or HEIF in the same folder, when the primary is a RAW.
    /// The historical probe property name is retained for report consumers.
    public var pairedJPEG: URL?
    /// Primary file name without its extension.
    public var baseName: String
    /// Folder below the scanned root, without a trailing slash.
    public var relativeDirectory: String

    public init(primary: URL, pairedJPEG: URL? = nil, baseName: String, relativeDirectory: String) {
        self.primary = primary
        self.pairedJPEG = pairedJPEG
        self.baseName = baseName
        self.relativeDirectory = relativeDirectory
    }

    /// `true` when a RAW and a JPEG or HEIF share the item's cell.
    public var isPaired: Bool {
        pairedJPEG != nil
    }
}

/// One batch of accepted files as the walk produces it.
public struct ScanBatch: Sendable {
    /// Accepted files in this batch, in traversal order.
    public var entries: [ScanEntry]
    /// Batch number, starting at 1.
    public var number: Int

    public init(entries: [ScanEntry], number: Int) {
        self.entries = entries
        self.number = number
    }
}

/// A streamed batch of photos, as the grid would receive it.
public struct ScanStreamBatch: Sendable {
    /// Photos in this batch, in traversal order.
    public var photos: [ScannedPhoto]
    /// Batch number, starting at 1.
    public var number: Int
    /// Time from the start of the scan until the batch was produced, in milliseconds.
    public var producedMilliseconds: Double
    /// Time until the consumer received the batch, in milliseconds.
    public var receivedMilliseconds: Double

    public init(photos: [ScannedPhoto], number: Int, producedMilliseconds: Double) {
        self.photos = photos
        self.number = number
        self.producedMilliseconds = producedMilliseconds
        self.receivedMilliseconds = 0
    }
}

/// What a streaming run observed.
public struct ScanStreamReport: Sendable {
    /// Batches the consumer received.
    public var batches: Int
    /// Photo files the walk accepted.
    public var files: Int
    /// Time until the producer finished the first batch, in milliseconds.
    public var firstBatchProducedMilliseconds: Double?
    /// Time until the consumer received the first batch, in milliseconds.
    public var firstBatchReceivedMilliseconds: Double?
    /// Time until the consumer received the last batch, in milliseconds.
    public var lastBatchReceivedMilliseconds: Double?
    /// Time until the walk accepted its 100th file, in milliseconds.
    public var firstHundredMilliseconds: Double?

    public init(
        batches: Int = 0,
        files: Int = 0,
        firstBatchProducedMilliseconds: Double? = nil,
        firstBatchReceivedMilliseconds: Double? = nil,
        lastBatchReceivedMilliseconds: Double? = nil,
        firstHundredMilliseconds: Double? = nil
    ) {
        self.batches = batches
        self.files = files
        self.firstBatchProducedMilliseconds = firstBatchProducedMilliseconds
        self.firstBatchReceivedMilliseconds = firstBatchReceivedMilliseconds
        self.lastBatchReceivedMilliseconds = lastBatchReceivedMilliseconds
        self.firstHundredMilliseconds = firstHundredMilliseconds
    }
}

/// Failures the scan lane reports without stopping the walk.
public enum ScanFailure: Error, CustomStringConvertible {
    /// The root folder could not be opened or listed.
    case cannotOpen(URL)
    /// A serialized report could not be turned back into a scan listing.
    case missingRoot(String)

    public var description: String {
        switch self {
        case .cannotOpen(let url): "cannot open \(url.lastPathComponent)"
        case .missingRoot(let path): "missing root \(path)"
        }
    }
}

/// Monotonic milliseconds between two `ContinuousClock` instants.
public enum ScanClock {
    /// Milliseconds from `start` to `end` (default: now).
    public static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant = .now
    ) -> Double {
        let parts = start.duration(to: end).components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}

extension String {
    /// Name without its extension, using the last dot only.
    var baseNameWithoutExtension: String {
        guard let dot = lastIndex(of: "."), dot != startIndex else { return self }
        return String(self[..<dot])
    }

    /// Lowercased extension without the dot, or an empty string.
    var fileExtensionLowercased: String {
        guard let dot = lastIndex(of: "."), dot != startIndex else { return "" }
        return String(self[index(after: dot)...]).lowercased()
    }

    /// Directory part of a relative path, or an empty string at the root.
    var relativeDirectory: String {
        guard let slash = lastIndex(of: "/") else { return "" }
        return String(self[..<slash])
    }
}
