import Foundation

/// The on-disk facts about a folder, read once after a successful listing.
///
/// Only `identityKeys` may identify the folder. The media type, volume name and root are display
/// hints for PRD P0-02 and for deciding whether a lost location is a disconnected drive.
public struct FolderLocationFacts: Hashable, Sendable {
    /// The volume UUID and folder file identifier the system reported, if any (G1 folder access).
    public let identityKeys: FolderIdentityKeys
    /// The volume kind derived from resource values, or unknown.
    public let mediaType: FolderMediaType
    /// The volume's display name, or nil when the system said nothing.
    public let volumeName: String?
    /// The volume's root, used to tell a folder loss from a drive disconnect (G1 folder access).
    public let volumeRootURL: URL?

    /// Stores the facts as read; missing hints stay nil rather than being guessed.
    public init(
        identityKeys: FolderIdentityKeys = FolderIdentityKeys(),
        mediaType: FolderMediaType = .unknown,
        volumeName: String? = nil,
        volumeRootURL: URL? = nil
    ) {
        self.identityKeys = identityKeys
        self.mediaType = mediaType
        self.volumeName = volumeName
        self.volumeRootURL = volumeRootURL
    }
}

/// Reads a folder's resource facts and performs the read that validates access.
///
/// G1 folder access validates by listing the folder, not by trusting a bookmark, a scope result or
/// resource hints. Both operations are injectable so the disconnect watch can be tested without
/// pretending a local folder is an external drive.
public protocol FolderLocationReading: Sendable {
    /// Returns best-effort hints for `url`; a failed resource query yields unknown facts.
    func facts(for url: URL) -> FolderLocationFacts
    /// Lists the folder, the real read that proves access before scanning (G1 folder access).
    func listContents(of url: URL) throws -> [URL]
}

/// Reads folder facts and directory listings from the file system (G1 folder access).
public struct FileSystemLocationReader: FolderLocationReading {
    /// Resource keys read as separate hints; an unsupported key never hides the others (S1).
    static let keys: Set<URLResourceKey> = [
        .volumeUUIDStringKey, .fileResourceIdentifierKey, .volumeNameKey, .volumeIsInternalKey,
        .volumeIsLocalKey, .isUbiquitousItemKey, .volumeURLKey,
    ]

    /// Creates a reader; it holds no state and queries the file system on each call.
    public init() {}

    /// Reads the folder's resource values; failure yields unknown facts, never invented identity.
    public func facts(for url: URL) -> FolderLocationFacts {
        guard let values = try? url.resourceValues(forKeys: Self.keys) else {
            return FolderLocationFacts()
        }
        return FolderLocationFacts(
            identityKeys: FolderIdentityKeys(
                volumeUUID: values.volumeUUIDString,
                fileIdentifier: Self.fileIdentifier(from: values.fileResourceIdentifier)),
            mediaType: Self.mediaType(from: values),
            volumeName: values.volumeName,
            volumeRootURL: values.volume)
    }

    /// Lists the folder; this is the read G1 folder access validates before scanning.
    public func listContents(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    /// Encodes the system's opaque file identifier without the inode fallback.
    ///
    /// S1 leaves external-volume behavior open, so a missing identifier makes identity weak rather
    /// than substituting a value that could compare equal on a different volume.
    private static func fileIdentifier(
        from identifier: (any NSCopying & NSSecureCoding & NSObjectProtocol)?
    ) -> String? {
        if let data = identifier as? Data { return "data:\(data.base64EncodedString())" }
        if let number = identifier as? NSNumber { return "number:\(number.stringValue)" }
        return nil
    }

    /// Derives the P0-02 media hint; a provider or network volume is cloud, not external storage.
    private static func mediaType(from values: URLResourceValues) -> FolderMediaType {
        if values.isUbiquitousItem == true { return .cloudProvider }
        if values.volumeIsLocal == false { return .cloudProvider }
        if let isInternal = values.volumeIsInternal {
            return isInternal ? .internalVolume : .externalDrive
        }
        return .unknown
    }
}
