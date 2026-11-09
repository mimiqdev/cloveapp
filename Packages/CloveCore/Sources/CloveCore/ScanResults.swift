import Foundation

/// One image file as a scan listed it, with the values later lanes reuse.
/// G1's scan approach prefetches size and modification date so I1 can key a thumbnail
/// revision; the file itself is still C1's `PhotoFile` (PRD Supported files).
public struct ScannedImageFile: Hashable, Sendable {
    /// The file with its actual URL and spelling, classified once by `PhotoFormat`.
    public let file: PhotoFile
    /// Size from G1's prefetched keys, or nil when the file system reported none.
    public let size: Int?
    /// Modification date from G1's prefetched keys; cache data, never a capture time
    /// (PRD Grid).
    public let modificationDate: Date?

    /// Describes one listed image file without reading its contents (PRD scan scope).
    public init(file: PhotoFile, size: Int?, modificationDate: Date?) {
        self.file = file
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// What one walk found next to a photo set's stem (G1 sidecar naming, PRD How marks reach disk).
public enum SidecarState: Hashable, Sendable {
    /// No packet exists yet; C1's persistence rule proposes `<stem>.xmp` for a RAW set and
    /// nothing for a standalone JPEG or HIF (G1 decisions 2 and 6).
    case absent
    /// Exactly one same-folder `<stem>.xmp` in any case; its actual spelling is reused.
    case resolved(URL)
    /// Competing packets, such as an appended-extension `NAME.ARW.xmp` or two same-stem
    /// names on a case-sensitive volume. Later tasks must refuse to write (G1 sidecar naming).
    case ambiguous([URL])

    /// The packet C1 may reuse, or nil when none exists or the choice is ambiguous.
    /// G1 sidecar naming refuses to invent one of several possible destinations.
    public var resolvedURL: URL? {
        guard case .resolved(let url) = self else { return nil }
        return url
    }

    /// Every packet the walk found for the stem, in walk order (G1 sidecar naming).
    public var candidates: [URL] {
        switch self {
        case .absent: []
        case .resolved(let url): [url]
        case .ambiguous(let urls): urls
        }
    }
}

/// One logical photo produced by a scan: C1's set, its sidecar state, and member metadata.
public struct ScannedPhotoSet: Hashable, Sendable {
    /// The validated set with G1 decision 1's primary and companions (PRD P0-01).
    public let photoSet: PhotoSet
    /// What the walk found for the set's sidecar; `.resolved` is also passed into `photoSet`
    /// so C1 reuses the actual spelling (G1 sidecar naming).
    public let sidecar: SidecarState
    /// The image members in `photoSet.imageFiles` order, with size and modification date.
    public let imageFiles: [ScannedImageFile]

    /// Combines a set with what the same walk discovered for it (G1 scan approach).
    public init(photoSet: PhotoSet, sidecar: SidecarState, imageFiles: [ScannedImageFile]) {
        self.photoSet = photoSet
        self.sidecar = sidecar
        self.imageFiles = imageFiles
    }

    /// The stable identity C1 defines from folder, relative path and folded stem (PRD P0-01).
    public var id: PhotoIdentity { photoSet.id }
}

/// Two or more files of one family share a folder and stem, so no single set is chosen.
/// PRD scan scope and G1 decision 1: the scan never picks a winner silently, and later
/// tasks must refuse to write to such a stem.
public struct AmbiguousStem: Hashable, Sendable {
    /// The containing folder relative to the opened root, empty at the root (PRD scan scope).
    public let relativeFolderPath: String
    /// The stem's actual spelling, from its first member in walk order (PRD scan scope).
    public let stem: String
    /// Every member of the stem group in walk order, with size and modification date.
    public let imageFiles: [ScannedImageFile]
    /// The packets found for the group, so a later task can see why it must refuse to write
    /// (G1 sidecar naming).
    public let sidecar: SidecarState

    /// Combines one ambiguous group's members and packets (PRD scan scope).
    public init(
        relativeFolderPath: String,
        stem: String,
        imageFiles: [ScannedImageFile],
        sidecar: SidecarState
    ) {
        self.relativeFolderPath = relativeFolderPath
        self.stem = stem
        self.imageFiles = imageFiles
        self.sidecar = sidecar
    }

    /// Every member URL, so a later task can show or refuse the whole group (PRD scan scope).
    public var urls: [URL] { imageFiles.map(\.file.url) }
}

/// One result of a scan, in walk order.
public enum ScanItem: Hashable, Sendable {
    /// A logical photo the walk could pair (G1 decision 1).
    case photo(ScannedPhotoSet)
    /// A stem with duplicate files of one family; it carries every member and no set
    /// (PRD scan scope).
    case ambiguousStem(AmbiguousStem)

    /// The image members of the item in walk order, with size and modification date.
    public var imageFiles: [ScannedImageFile] {
        switch self {
        case .photo(let photo): photo.imageFiles
        case .ambiguousStem(let ambiguous): ambiguous.imageFiles
        }
    }

    /// The sidecar state that later tasks read before proposing a destination.
    public var sidecar: SidecarState {
        switch self {
        case .photo(let photo): photo.sidecar
        case .ambiguousStem(let ambiguous): ambiguous.sidecar
        }
    }
}

/// Results delivered together, in walk order, with at most `ScanConfiguration.batchSize` items.
/// G1's scan approach streams batches so the first photos arrive long before the walk ends.
public struct ScanBatch: Hashable, Sendable {
    /// The items, in walk order; a photo set's members are always in one item (PRD scan scope).
    public let items: [ScanItem]
    /// The batch's 1-based position in delivery order (G1 scan approach).
    public let number: Int

    /// Wraps one delivery of items (G1 scan approach).
    public init(items: [ScanItem], number: Int) {
        self.items = items
        self.number = number
    }
}

/// Whether a scan finished with every folder and file it could read (PRD scan scope).
public enum ScanStatus: String, CaseIterable, Hashable, Sendable {
    /// Every entry was read; the counts describe the whole opened folder.
    case complete
    /// At least one folder or file could not be read; see ``ScanSummary/issues``.
    /// A partial scan is never reported as a complete scan with fewer photos (PRD P0-01).
    case partial
}

/// One NSError level in a read failure, kept so a partial scan explains itself (PRD P0-01).
public struct ScanErrorEntry: Hashable, Sendable {
    /// The error domain, for example `NSCocoaErrorDomain`.
    public let domain: String
    /// The error code within its domain.
    public let code: Int
    /// The localized description the system supplied.
    public let message: String

    /// Describes one level of an NSError chain (PRD P0-01).
    public init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }
}

/// A folder or file a scan could not read, with the URL and the NSError chain it hit.
/// PRD scan scope and P0-01 require a visible partial result instead of a shorter silent one.
public struct ScanIssue: Hashable, Sendable {
    /// The entry that failed, as the walk addressed it.
    public let url: URL
    /// The error and each `NSUnderlyingErrorKey` below it, outermost first.
    public let errorChain: [ScanErrorEntry]

    /// Flattens an error into its domain, code and description chain (PRD P0-01).
    public init(url: URL, error: any Error) {
        self.url = url
        var chain: [ScanErrorEntry] = []
        var current: NSError? = error as NSError
        // A malformed chain must not loop; real ones are two or three levels deep.
        while let level = current, chain.count < 16 {
            chain.append(
                ScanErrorEntry(
                    domain: level.domain, code: level.code, message: level.localizedDescription))
            current = level.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.errorChain = chain
    }

    /// The outermost error's description, for logs and status lines.
    public var message: String { errorChain.first?.message ?? "" }
}

/// What one scan found, reported after its batch sequence ends (PRD P0-01).
public struct ScanSummary: Hashable, Sendable {
    /// Logical photos the walk paired, one per grid cell (G1 decision 1).
    public let logicalPhotoCount: Int
    /// Files outside the supported formats, excluding `.xmp` (PRD Supported files).
    public let unsupportedFileCount: Int
    /// The unsupported files' URLs, in walk order, so the grid can explain each one.
    public let unsupportedFiles: [URL]
    /// Stem groups with two or more files of one family, which produced no photo set.
    public let ambiguousMemberCount: Int
    /// Photo sets whose sidecar choice is ambiguous, so no write may target them
    /// (G1 sidecar naming).
    public let ambiguousSidecarCount: Int
    /// `.xmp` files with no RAW in their stem group; they are ignored without an error
    /// (G1 sidecar naming and decision 6).
    public let orphanSidecarCount: Int
    /// Folders the walk left alone: the rejects folder, packages, and any hidden folder a
    /// provider still listed (PRD scan scope, G1 decision 5).
    public let skippedFolderCount: Int
    /// Complete or partial, from whether ``issues`` is empty (PRD scan scope).
    public let status: ScanStatus
    /// Every folder or file the walk could not read, in the order it hit them.
    public let issues: [ScanIssue]

    /// Reports one finished walk's counts and status (PRD P0-01, G1 scan approach).
    public init(
        logicalPhotoCount: Int,
        unsupportedFileCount: Int,
        unsupportedFiles: [URL],
        ambiguousMemberCount: Int,
        ambiguousSidecarCount: Int,
        orphanSidecarCount: Int,
        skippedFolderCount: Int,
        status: ScanStatus,
        issues: [ScanIssue]
    ) {
        self.logicalPhotoCount = logicalPhotoCount
        self.unsupportedFileCount = unsupportedFileCount
        self.unsupportedFiles = unsupportedFiles
        self.ambiguousMemberCount = ambiguousMemberCount
        self.ambiguousSidecarCount = ambiguousSidecarCount
        self.orphanSidecarCount = orphanSidecarCount
        self.skippedFolderCount = skippedFolderCount
        self.status = status
        self.issues = issues
    }

    /// Every ambiguity the scan surfaced, counted together for a status line.
    public var ambiguousCount: Int { ambiguousMemberCount + ambiguousSidecarCount }

    /// Whether the walk read every entry it could (PRD scan scope).
    public var isComplete: Bool { status == .complete }
}

/// A scan that could not start; read errors during the walk are issues, not failures.
/// PRD P0-02 and G1 folder access let the caller validate access before scanning.
public enum PhotoScanError: Error, Hashable, Sendable {
    /// The opened folder could not be enumerated at all.
    case unreadableRoot(URL)
}

extension PhotoScanError: CustomStringConvertible {
    /// Names the folder that could not be opened, for a log or a status line.
    public var description: String {
        switch self {
        case .unreadableRoot(let url): "cannot read \(url.lastPathComponent)"
        }
    }
}
