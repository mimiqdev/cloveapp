import Foundation

/// How a folder lives on disk, derived only from volume resource values.
///
/// This is a display and explanation hint for PRD P0-02. It never identifies a folder or grants
/// anything; G1 folder access requires a real read and the identity keys before either.
public enum FolderMediaType: String, Codable, Hashable, Sendable {
    /// Storage inside the device, including the app's own container.
    case internalVolume
    /// A removable or external drive, such as a card reader or an SSD (G1 decision 7).
    case externalDrive
    /// A Files provider or a network location, which may keep a stub reachable.
    case cloudProvider
    /// The system could not tell, or said nothing; never guess.
    case unknown
}

/// Whether the last successful scan covered the whole folder (PRD P0-02; C2 reports it).
public enum FolderScanStatus: String, Codable, Hashable, Sendable {
    /// The scan walked every supported entry.
    case complete
    /// The scan stopped early, so the photo count is a lower bound and P0-02 must say so.
    case partial
}

/// The identity keys a remembered folder is checked against: volume UUID plus file identifier.
///
/// G1 folder access accepts exactly this pair. A path, a volume name or a bookmark that merely
/// resolves is never identity; S1 showed that a stale bookmark can resolve a replacement folder.
public struct FolderIdentityKeys: Codable, Hashable, Sendable {
    /// The volume's UUID when the system reports one (S1 resource hints).
    public var volumeUUID: String?
    /// The folder's file identifier when the system reports one (S1: file identity when available).
    public var fileIdentifier: String?

    /// Stores the keys as read; missing values stay nil rather than being invented.
    public init(volumeUUID: String? = nil, fileIdentifier: String? = nil) {
        self.volumeUUID = volumeUUID
        self.fileIdentifier = fileIdentifier
    }

    /// Compares these saved keys with the keys read from the folder now.
    ///
    /// A comparable key that differs is a mismatch, never a silent switch (PRD P0-02). Complete
    /// keys on both sides that agree are verified. Anything else is weak: S1's deferred device
    /// checks in #29 may find volumes or providers that report no usable key.
    public func checkIdentity(against found: FolderIdentityKeys) -> FolderIdentityCheck {
        guard let savedVolume = volumeUUID, let foundVolume = found.volumeUUID else {
            return .weak
        }
        guard savedVolume == foundVolume else { return .mismatch }
        guard let savedFile = fileIdentifier, let foundFile = found.fileIdentifier else {
            return .weak
        }
        return savedFile == foundFile ? .verified : .mismatch
    }
}

/// How well an open folder's identity was established (G1 folder access).
public enum FolderIdentityCheck: Hashable, Sendable {
    /// Both the volume UUID and the file identifier matched the remembered folder.
    case verified
    /// Not enough keys existed on both sides to compare; accept provisionally until #29 reports
    /// which volumes and providers supply identity keys. Never treat this as verified.
    case weak
    /// A comparable key differed, for example a different card with the same name or a folder
    /// replaced at the same path. The user must choose the folder again (PRD P0-02).
    case mismatch
}

/// One remembered folder, persisted so P0-02 can reopen it with one tap.
///
/// Paths and volume names are display hints only: they never establish identity or permission
/// (G1 folder access). The `id` is the stable source of the folder's `FolderIdentity`, so marks
/// and caches stay keyed when the same folder is picked again or moved.
public struct RecentFolder: Identifiable, Codable, Hashable, Sendable {
    /// The stable key; `identity` wraps it for C1 photo identities and Clove-stored marks.
    public let id: UUID
    /// Default bookmark data, re-created only after a successful read and identity check.
    public var bookmark: Data
    /// A display-only path summary (PRD P0-02); never proof of identity or permission.
    public var pathSummary: String
    /// A display-only volume name (PRD P0-02); two cards may share it (S1).
    public var volumeName: String?
    /// The volume UUID and folder file identifier this record is checked against (G1 folder access).
    public var identityKeys: FolderIdentityKeys
    /// The volume kind derived from resource values, for P0-02's media hint only.
    public var mediaType: FolderMediaType
    /// The logical photo count from the last successful scan; nil until C2 reports one (PRD P0-02).
    public var photoCount: Int?
    /// Whether that scan was complete or partial (PRD P0-02).
    public var scanStatus: FolderScanStatus
    /// When the folder last opened successfully; failed opens never change it (PRD P0-02).
    public var lastOpened: Date

    /// Creates a remembered folder; only `pick` and `reopen` in `FolderAccess` write these records.
    public init(
        id: UUID = UUID(),
        bookmark: Data,
        pathSummary: String,
        volumeName: String? = nil,
        identityKeys: FolderIdentityKeys = FolderIdentityKeys(),
        mediaType: FolderMediaType = .unknown,
        photoCount: Int? = nil,
        scanStatus: FolderScanStatus = .complete,
        lastOpened: Date = Date()
    ) {
        self.id = id
        self.bookmark = bookmark
        self.pathSummary = pathSummary
        self.volumeName = volumeName
        self.identityKeys = identityKeys
        self.mediaType = mediaType
        self.photoCount = photoCount
        self.scanStatus = scanStatus
        self.lastOpened = lastOpened
    }

    /// The folder key used by photo identities and Clove-stored marks (G1 decision 5; PRD P0-02).
    /// It is derived from the stable record ID, never from a path or volume name.
    public var identity: FolderIdentity {
        FolderIdentity(rawValue: id.uuidString)
    }
}
