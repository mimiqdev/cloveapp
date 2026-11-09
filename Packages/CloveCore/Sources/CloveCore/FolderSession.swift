import Foundation

/// An opaque, persistent folder key supplied by bookmark handling, never a display name or path.
/// G1 folder access and PRD P0-02 require distinguishing even identically named cards.
public struct FolderIdentity: RawRepresentable, Hashable, Sendable {
    /// The caller's durable key; this model does not create or resolve bookmarks (G1 folder access).
    public let rawValue: String

    /// Wraps the identity established by folder access, per G1 folder access.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// An opened folder's identity and display hints; contains no access or bookmark I/O.
/// PRD P0-01/P0-02 and G1 folder access make identity independent of these hints.
public struct FolderSession: Identifiable, Hashable, Sendable {
    /// The opaque folder key used by photo identities and Clove-stored marks (G1 decision 5).
    public let id: FolderIdentity
    /// A display hint only, not proof of identity or permission (G1 folder access).
    public var displayURL: URL?
    /// A display hint only; two folders may have the same name (PRD P0-02).
    public var displayName: String?

    /// Describes a session whose identity was established by the caller (PRD P0-01/P0-02).
    public init(id: FolderIdentity, displayURL: URL? = nil, displayName: String? = nil) {
        self.id = id
        self.displayURL = displayURL
        self.displayName = displayName
    }
}

/// A photo key stable across rescans and companion/sidecar discovery (PRD P0-01, G1 decision 5).
/// The relative directory keeps same-stem photos in separate subfolders distinct.
public struct PhotoIdentity: Hashable, Sendable {
    /// The opened folder's opaque identity, not its display URL (G1 decision 5).
    public let folderID: FolderIdentity
    /// The containing directory relative to the opened folder; empty at its root (PRD scan scope).
    public let relativeFolderPath: String
    /// The case-folded stem used for same-folder pairing (PRD scan scope).
    /// Actual on-disk spelling remains in each `PhotoFile.url`.
    public let stem: String

    /// Uses the stem as found, folding only its case to match PRD scan scope pairing.
    /// Callers supply the same relative folder spelling across rescans, without a trailing slash.
    /// No transient hash, primary extension, mark, or companion membership enters this key.
    public init(folderID: FolderIdentity, relativeFolderPath: String, stem: String) {
        self.folderID = folderID
        self.relativeFolderPath = relativeFolderPath
        self.stem = stem.lowercased()
    }
}
