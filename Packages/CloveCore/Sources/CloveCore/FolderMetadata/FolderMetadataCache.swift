import CryptoKit
import Foundation

/// Per-folder photo metadata cache in Clove's own storage.
///
/// Reopening an unchanged folder (including after unplugging and replugging an external drive)
/// reuses primary capture metadata and marks from this cache instead of re-opening every RAW and
/// sidecar on disk. Clove's own stored marks (`CloveMarkStore`) are always read live and combined
/// freshly at open time.
///
/// Cache reads and writes are best-effort and atomic: a missing, corrupt, foreign, or
/// version-mismatched file is ignored and rebuilt cleanly on the next complete scan.
public struct FolderMetadataCache: Sendable {
    /// Identifies one logical photo inside a cached folder, matching `PhotoIdentity`'s key.
    public struct Key: Hashable, Codable, Sendable {
        /// Containing directory relative to the opened folder root, empty at the root.
        public let relativeFolderPath: String
        /// Case-folded stem matching `PhotoIdentity.stem`.
        public let stem: String

        /// Creates a key from a relative folder path and stem (folded to lowercase).
        public init(relativeFolderPath: String, stem: String) {
            self.relativeFolderPath = relativeFolderPath
            self.stem = stem.lowercased()
        }

        /// Creates a key from a `PhotoIdentity`.
        public init(photoID: PhotoIdentity) {
            self.init(relativeFolderPath: photoID.relativeFolderPath, stem: photoID.stem)
        }
    }

    /// Strict primary-file fingerprint: filename, byte size, and exact modification timestamp.
    /// Requires non-nil size and finite modification date; any mismatch invalidates.
    public struct PrimaryFingerprint: Hashable, Codable, Sendable {
        /// Primary filename including extension (`IMG_0001.ARW`), catching primary-format changes.
        public let fileName: String
        /// Byte size from enumeration prefetch.
        public let size: Int
        /// Exact IEEE-754 bit pattern of `modificationDate.timeIntervalSinceReferenceDate`.
        public let modificationDateBits: UInt64

        /// Creates a primary fingerprint from non-nil file metadata.
        public init?(fileName: String, size: Int, modificationDate: Date) {
            guard modificationDate.timeIntervalSinceReferenceDate.isFinite else { return nil }
            self.fileName = fileName
            self.size = size
            self.modificationDateBits = modificationDate.timeIntervalSinceReferenceDate.bitPattern
        }

        /// Builds a strict primary fingerprint from a scanned set, or `nil` when size or
        /// modification date is unavailable.
        public init?(for set: ScannedPhotoSet) {
            let primary = set.photoSet.primary
            guard
                let scannedPrimary = set.imageFiles.first(where: { $0.file == primary })
                    ?? set.imageFiles.first,
                let size = scannedPrimary.size,
                let modificationDate = scannedPrimary.modificationDate
            else { return nil }
            self.init(
                fileName: primary.url.lastPathComponent,
                size: size,
                modificationDate: modificationDate)
        }

        /// Reconstructed modification date with full precision.
        public var modificationDate: Date {
            Date(timeIntervalSinceReferenceDate: Double(bitPattern: modificationDateBits))
        }

        fileprivate var isValid: Bool {
            !fileName.isEmpty && Double(bitPattern: modificationDateBits).isFinite
        }
    }

    /// Strict sidecar fingerprint for RAW photo sets.
    public enum SidecarFingerprint: Hashable, Codable, Sendable {
        case absent
        case resolved(fileName: String, size: Int, modificationDateBits: UInt64)
        case ambiguous

        /// Builds a sidecar fingerprint for a RAW photo set, or `nil` for standalone JPEG/HEIF or
        /// when a resolved sidecar lacks valid prefetched revision values.
        public init?(for set: ScannedPhotoSet) {
            guard set.photoSet.primary.format == .raw else { return nil }
            switch set.sidecar {
            case .absent:
                self = .absent
            case .resolved(let url):
                guard let revision = set.sidecarRevision,
                    let size = revision.size,
                    let modificationDate = revision.modificationDate,
                    modificationDate.timeIntervalSinceReferenceDate.isFinite
                else { return nil }
                self = .resolved(
                    fileName: url.lastPathComponent,
                    size: size,
                    modificationDateBits: modificationDate.timeIntervalSinceReferenceDate.bitPattern
                )
            case .ambiguous:
                self = .ambiguous
            }
        }

        /// Convenience builder for a resolved sidecar fingerprint.
        public static func resolved(fileName: String, size: Int, modificationDate: Date)
            -> SidecarFingerprint?
        {
            guard modificationDate.timeIntervalSinceReferenceDate.isFinite else { return nil }
            return .resolved(
                fileName: fileName,
                size: size,
                modificationDateBits: modificationDate.timeIntervalSinceReferenceDate.bitPattern)
        }

        fileprivate var isValid: Bool {
            switch self {
            case .absent, .ambiguous:
                return true
            case .resolved(let fileName, _, let bits):
                return !fileName.isEmpty && Double(bitPattern: bits).isFinite
            }
        }
    }

    /// Pure-Core representation of a photo's cached time provenance.
    ///
    /// Capture wall clock without an explicit UTC offset is stored as `(wallTime, nil)` so
    /// reopening in another time zone resolves `PhotoTime` against `TimeZone.current`.
    public enum TimeSource: Hashable, Sendable {
        case captureMetadata(wallTime: Date, utcOffsetSeconds: Int?)
        case fileCreation(Date)
        case fileModification(Date)
        case unavailable

        /// Reconstructs `PhotoTimeState` in the supplied `timeZone`.
        public func photoTimeState(in timeZone: TimeZone = .current) -> PhotoTimeState {
            switch self {
            case .captureMetadata(let wallTime, let utcOffsetSeconds):
                return .known(
                    PhotoTime(
                        captureWallTime: wallTime,
                        utcOffsetSeconds: utcOffsetSeconds,
                        in: timeZone))
            case .fileCreation(let date):
                return .known(PhotoTime(fileCreation: date))
            case .fileModification(let date):
                return .known(PhotoTime(fileModification: date))
            case .unavailable:
                return .unavailable
            }
        }
    }

    /// Cached primary-file metadata values (time provenance, body, and filter dimensions).
    public struct PrimaryPayload: Hashable, Sendable {
        public var timeSource: TimeSource
        public var cameraBody: CameraBody?
        public var filterMetadata: PhotoFilterMetadata

        public init(
            timeSource: TimeSource,
            cameraBody: CameraBody?,
            filterMetadata: PhotoFilterMetadata
        ) {
            self.timeSource = timeSource
            self.cameraBody = cameraBody
            self.filterMetadata = filterMetadata
        }
    }

    /// Cached marks payload, keyed by whether the set is standalone (embedded) or RAW (sidecar).
    public enum MarksPayload: Hashable, Sendable {
        /// Standalone JPEG/HEIF embedded metadata; valid only when the primary fingerprint matches.
        case standalone(embedded: XMPMarks?)
        /// RAW set XMP sidecar marks; valid only when the sidecar fingerprint matches.
        case raw(sidecar: SidecarFingerprint, xmp: XMPMarks?)
    }

    /// Resolution of a cached marks lookup for one scanned photo set.
    public enum CachedMarksResolution: Hashable, Sendable {
        case hit(embedded: XMPMarks?, xmp: XMPMarks?)
        case miss
    }

    /// One photo's cached primary metadata and/or marks.
    public struct Entry: Hashable, Sendable {
        public var primaryFingerprint: PrimaryFingerprint?
        public var primary: PrimaryPayload?
        public var marks: MarksPayload?

        public init(
            primaryFingerprint: PrimaryFingerprint? = nil,
            primary: PrimaryPayload? = nil,
            marks: MarksPayload? = nil
        ) {
            self.primaryFingerprint = primaryFingerprint
            self.primary = primary
            self.marks = marks
        }

        /// Returns the cached primary payload if `set`'s primary fingerprint matches strictly.
        public func cachedPrimary(for set: ScannedPhotoSet) -> PrimaryPayload? {
            guard let primary,
                let cachedFingerprint = primaryFingerprint,
                let currentFingerprint = PrimaryFingerprint(for: set),
                cachedFingerprint == currentFingerprint
            else { return nil }
            return primary
        }

        /// Returns cached embedded/XMP marks if `set`'s format and file fingerprint match strictly.
        public func cachedMarks(for set: ScannedPhotoSet) -> CachedMarksResolution {
            guard let marks else { return .miss }
            switch (set.photoSet.primary.format == .raw, marks) {
            case (false, .standalone(let embedded)):
                guard let cachedFingerprint = primaryFingerprint,
                    let currentFingerprint = PrimaryFingerprint(for: set),
                    cachedFingerprint == currentFingerprint
                else { return .miss }
                return .hit(embedded: embedded, xmp: nil)
            case (true, .raw(let cachedSidecar, let xmp)):
                guard let currentSidecar = SidecarFingerprint(for: set),
                    cachedSidecar == currentSidecar
                else { return .miss }
                return .hit(embedded: nil, xmp: xmp)
            default:
                return .miss
            }
        }
    }

    /// Detailed outcome of reading a folder's cache file.
    public enum LoadOutcome: Equatable, Sendable {
        case loaded([Key: Entry])
        case missing
        case unusable
    }

    /// The app-private directory holding one file per folder identity.
    public let directory: URL

    /// Roots the cache at `directory`; tests pass a temporary directory.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The production location below Application Support (`Application Support/Clove/FolderMetadata/`).
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        return base.appendingPathComponent("Clove", isDirectory: true)
            .appendingPathComponent("FolderMetadata", isDirectory: true)
    }

    /// The versioned file for one folder identity, named by its SHA-256 digest.
    public func fileURL(for folderID: FolderIdentity) -> URL {
        let digest = SHA256.hash(data: Data(folderID.rawValue.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("metadata-v1-\(name).json")
    }

    /// Loads cached entries for `folderID`, returning empty on missing, corrupt, or foreign files.
    public func load(folderID: FolderIdentity) -> [Key: Entry] {
        switch loadWithOutcome(folderID: folderID) {
        case .loaded(let entries): return entries
        case .missing, .unusable: return [:]
        }
    }

    /// Loads cached entries for `folderID` and reports whether the cache file was missing, unusable,
    /// or valid.
    public func loadWithOutcome(folderID: FolderIdentity) -> LoadOutcome {
        let url = fileURL(for: folderID)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            return .unusable
        }
        guard let stored = try? JSONDecoder().decode(StoredFolderMetadata.self, from: data),
            stored.version == StoredFolderMetadata.currentVersion,
            stored.folder == folderID.rawValue
        else { return .unusable }

        var entries: [Key: Entry] = [:]
        entries.reserveCapacity(stored.entries.count)
        for storedEntry in stored.entries {
            let key = Key(
                relativeFolderPath: storedEntry.relativeFolderPath, stem: storedEntry.stem)
            guard entries[key] == nil,
                let entry = storedEntry.entry()
            else { return .unusable }
            entries[key] = entry
        }
        return .loaded(entries)
    }

    /// Atomically persists `entries` for `folderID`, replacing any earlier file. Failures are ignored.
    public func save(_ entries: [Key: Entry], folderID: FolderIdentity) {
        let storedEntries =
            entries
            .compactMap { key, entry -> StoredFolderMetadata.EntryRecord? in
                StoredFolderMetadata.EntryRecord(key: key, entry: entry)
            }
            .sorted { lhs, rhs in
                (lhs.relativeFolderPath, lhs.stem) < (rhs.relativeFolderPath, rhs.stem)
            }
        let stored = StoredFolderMetadata(
            version: StoredFolderMetadata.currentVersion,
            folder: folderID.rawValue,
            entries: storedEntries)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var cacheDirectory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? cacheDirectory.setResourceValues(resourceValues)
        try? data.write(to: fileURL(for: folderID), options: .atomic)
    }
}

// MARK: - On-disk JSON representation

private struct StoredFolderMetadata: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var folder: String
    var entries: [EntryRecord]

    struct EntryRecord: Codable, Sendable {
        var relativeFolderPath: String
        var stem: String
        var primaryFingerprint: FolderMetadataCache.PrimaryFingerprint?
        var primary: StoredPrimaryPayload?
        var marks: StoredMarksPayload?

        init?(key: FolderMetadataCache.Key, entry: FolderMetadataCache.Entry) {
            if entry.primary != nil, entry.primaryFingerprint == nil {
                return nil
            }
            if let fingerprint = entry.primaryFingerprint, !fingerprint.isValid {
                return nil
            }
            if case .standalone = entry.marks, entry.primaryFingerprint == nil {
                return nil
            }
            let encodedPrimary = entry.primary.flatMap(StoredPrimaryPayload.init)
            let encodedMarks = entry.marks.flatMap(StoredMarksPayload.init)
            guard encodedPrimary != nil || encodedMarks != nil else { return nil }
            self.relativeFolderPath = key.relativeFolderPath
            self.stem = key.stem
            self.primaryFingerprint = entry.primaryFingerprint
            self.primary = encodedPrimary
            self.marks = encodedMarks
        }

        func entry() -> FolderMetadataCache.Entry? {
            if let primaryFingerprint, !primaryFingerprint.isValid {
                return nil
            }
            let decodedPrimary: FolderMetadataCache.PrimaryPayload?
            if let primary {
                guard primaryFingerprint != nil, let resolved = primary.payload() else {
                    return nil
                }
                decodedPrimary = resolved
            } else {
                decodedPrimary = nil
            }
            let decodedMarks: FolderMetadataCache.MarksPayload?
            if let marks {
                guard let resolved = marks.payload() else { return nil }
                if case .standalone = resolved, primaryFingerprint == nil {
                    return nil
                }
                decodedMarks = resolved
            } else {
                decodedMarks = nil
            }
            return FolderMetadataCache.Entry(
                primaryFingerprint: primaryFingerprint,
                primary: decodedPrimary,
                marks: decodedMarks)
        }
    }

    enum StoredTimeSource: Codable, Sendable {
        case captureMetadata(wallTimeBits: UInt64, utcOffsetSeconds: Int?)
        case fileCreation(dateBits: UInt64)
        case fileModification(dateBits: UInt64)
        case unavailable

        init?(timeSource: FolderMetadataCache.TimeSource) {
            switch timeSource {
            case .captureMetadata(let wallTime, let utcOffsetSeconds):
                guard wallTime.timeIntervalSinceReferenceDate.isFinite else { return nil }
                self = .captureMetadata(
                    wallTimeBits: wallTime.timeIntervalSinceReferenceDate.bitPattern,
                    utcOffsetSeconds: utcOffsetSeconds)
            case .fileCreation(let date):
                guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
                self = .fileCreation(dateBits: date.timeIntervalSinceReferenceDate.bitPattern)
            case .fileModification(let date):
                guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
                self = .fileModification(dateBits: date.timeIntervalSinceReferenceDate.bitPattern)
            case .unavailable:
                self = .unavailable
            }
        }

        func timeSource() -> FolderMetadataCache.TimeSource? {
            switch self {
            case .captureMetadata(let wallTimeBits, let utcOffsetSeconds):
                let interval = Double(bitPattern: wallTimeBits)
                guard interval.isFinite else { return nil }
                return .captureMetadata(
                    wallTime: Date(timeIntervalSinceReferenceDate: interval),
                    utcOffsetSeconds: utcOffsetSeconds)
            case .fileCreation(let dateBits):
                let interval = Double(bitPattern: dateBits)
                guard interval.isFinite else { return nil }
                return .fileCreation(Date(timeIntervalSinceReferenceDate: interval))
            case .fileModification(let dateBits):
                let interval = Double(bitPattern: dateBits)
                guard interval.isFinite else { return nil }
                return .fileModification(Date(timeIntervalSinceReferenceDate: interval))
            case .unavailable:
                return .unavailable
            }
        }
    }

    struct StoredPrimaryPayload: Codable, Sendable {
        var timeSource: StoredTimeSource
        var bodyModel: String?
        var bodySerial: String?
        var filterCamera: String?
        var filterLens: String?
        var filterFocalLengthMillimetres: Double?

        init?(payload: FolderMetadataCache.PrimaryPayload) {
            guard let time = StoredTimeSource(timeSource: payload.timeSource) else { return nil }
            self.timeSource = time
            self.bodyModel = payload.cameraBody?.model
            self.bodySerial = payload.cameraBody?.serial
            self.filterCamera = payload.filterMetadata.camera
            self.filterLens = payload.filterMetadata.lens
            self.filterFocalLengthMillimetres = payload.filterMetadata.focalLengthMillimetres
        }

        func payload() -> FolderMetadataCache.PrimaryPayload? {
            guard let time = timeSource.timeSource() else { return nil }
            if let focalLength = filterFocalLengthMillimetres,
                !focalLength.isFinite || focalLength <= 0
            {
                return nil
            }
            let body = bodyModel.flatMap { CameraBody(model: $0, serial: bodySerial) }
            let filter = PhotoFilterMetadata(
                camera: filterCamera,
                lens: filterLens,
                focalLengthMillimetres: filterFocalLengthMillimetres)
            return FolderMetadataCache.PrimaryPayload(
                timeSource: time, cameraBody: body, filterMetadata: filter)
        }
    }

    struct StoredXMPMarks: Codable, Sendable {
        var rating: Int
        var label: String
        var keywords: [String]

        init(marks: XMPMarks) {
            switch marks.rating {
            case .rated(let rating):
                self.rating = rating.rawValue
            case .external(let value):
                self.rating = value
            }
            self.label = marks.label.rawValue
            self.keywords = marks.keywords
        }

        var xmpMarks: XMPMarks {
            XMPMarks(
                rating: XMPRating(rating),
                label: ColourLabel(rawValue: label),
                keywords: keywords)
        }
    }

    enum StoredMarksPayload: Codable, Sendable {
        case standalone(embedded: StoredXMPMarks?)
        case raw(sidecar: FolderMetadataCache.SidecarFingerprint, xmp: StoredXMPMarks?)

        init?(payload: FolderMetadataCache.MarksPayload) {
            switch payload {
            case .standalone(let embedded):
                self = .standalone(embedded: embedded.map(StoredXMPMarks.init))
            case .raw(let sidecar, let xmp):
                guard sidecar.isValid else { return nil }
                self = .raw(sidecar: sidecar, xmp: xmp.map(StoredXMPMarks.init))
            }
        }

        func payload() -> FolderMetadataCache.MarksPayload? {
            switch self {
            case .standalone(let embedded):
                return .standalone(embedded: embedded?.xmpMarks)
            case .raw(let sidecar, let xmp):
                guard sidecar.isValid else { return nil }
                return .raw(sidecar: sidecar, xmp: xmp?.xmpMarks)
            }
        }
    }
}
