import Foundation

/// A folder that opened successfully, with the scope held by its session (G1 folder access).
public struct OpenedFolder: Sendable {
    /// The remembered folder, already updated for this open (PRD P0-02).
    public let recent: RecentFolder
    /// The security-scope session that C2 keeps until its work drains (G1 folder access).
    public let session: FolderAccessSession

    /// Pairs a record with the session that holds its scope.
    public init(recent: RecentFolder, session: FolderAccessSession) {
        self.recent = recent
        self.session = session
    }
}

/// The count and completeness C2 reports for a folder it scanned (PRD P0-02).
public struct FolderScanSummary: Hashable, Sendable {
    /// The logical photo count, not the file count (PRD P0-01, P0-02).
    public let photoCount: Int
    /// Whether the scan covered the whole folder; a partial scan stays partial (PRD P0-02).
    public let status: FolderScanStatus

    /// Records one scan outcome; `FolderAccess.recordScan` stores it after a successful open.
    public init(photoCount: Int, status: FolderScanStatus) {
        self.photoCount = photoCount
        self.status = status
    }
}

/// Remembers opened folders and reopens them with a validated grant.
///
/// This is the P0-02 Recents data layer and G1 folder access in one place. A record's path and
/// volume name are display hints only; reopening validates with a real listing and the volume UUID
/// plus file identifier before anything is refreshed or scanned. A stale bookmark means the
/// bookmark needs rewriting, not that permission was lost. The actor serializes store writes, so
/// two opens cannot interleave a load and a save.
public actor FolderAccess {
    private let store: RecentFolderStore
    private let scope: any FolderAccessScope
    private let locations: any FolderLocationReading
    private let now: @Sendable () -> Date

    /// Creates the Recents data layer; every dependency is injectable for tests.
    public init(
        store: RecentFolderStore,
        scope: any FolderAccessScope = SecurityScopedFolderAccess(),
        locations: any FolderLocationReading = FileSystemLocationReader(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.scope = scope
        self.locations = locations
        self.now = now
    }

    /// Every remembered folder, most recently opened first (PRD P0-02).
    ///
    /// Throws the store error when the file is corrupt or from a newer schema, so the caller can
    /// explain the problem instead of showing an empty list.
    public func recents() throws -> [RecentFolder] {
        try store.load().sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Opens a folder chosen in the system picker and remembers it (PRD P0-01, P0-02).
    ///
    /// Access starts before the validating read, and the folder is only remembered after that read
    /// and the bookmark succeed. An existing record with the same identity keys keeps its ID, so
    /// marks and caches stay keyed; a path or volume name alone never matches. A folder that cannot
    /// supply both identity keys opens provisionally (`.weak`) until #29 reports which volumes do.
    public func pick(_ url: URL) -> FolderOpenResult {
        let scopeIsHeld = scope.startAccessing(url)
        func failure(_ failure: FolderAccessFailure) -> FolderOpenResult {
            if scopeIsHeld { scope.stopAccessing(url) }
            return .failed(failure)
        }
        do {
            _ = try locations.listContents(of: url)
        } catch {
            return failure(Self.failure(for: error, stage: .read))
        }
        let facts = locations.facts(for: url)
        let bookmark: Data
        do {
            bookmark = try FolderBookmarks.data(for: url)
        } catch {
            return failure(.locationUnavailable(FolderErrorChain(error)))
        }
        let folders: [RecentFolder]
        do {
            folders = try store.load()
        } catch {
            return failure(.storageUnavailable(Self.storeError(error)))
        }
        let openedAt = now()
        var updated = folders
        let recent: RecentFolder
        if let index = updated.firstIndex(where: {
            $0.identityKeys.checkIdentity(against: facts.identityKeys) == .verified
        }) {
            var existing = updated[index]
            existing.bookmark = bookmark
            existing.pathSummary = url.path
            existing.volumeName = facts.volumeName
            existing.identityKeys = facts.identityKeys
            existing.mediaType = facts.mediaType
            existing.lastOpened = openedAt
            existing.needsReconnect = false
            updated[index] = existing
            recent = existing
        } else {
            recent = RecentFolder(
                bookmark: bookmark, pathSummary: url.path, volumeName: facts.volumeName,
                identityKeys: facts.identityKeys, mediaType: facts.mediaType,
                lastOpened: openedAt)
            updated.insert(recent, at: 0)
        }
        do {
            try store.save(updated)
        } catch {
            return failure(.storageUnavailable(Self.storeError(error)))
        }
        let session = makeSession(
            for: recent, rootURL: url,
            identityCheck: facts.identityKeys.isComplete ? .verified : .weak,
            scopeIsHeld: scopeIsHeld)
        return .opened(OpenedFolder(recent: recent, session: session))
    }

    /// Reopens a remembered folder after a real read and an identity check (G1 folder access).
    ///
    /// Resolution suppresses UI and mounting, access starts explicitly, and the folder is listed
    /// before anything is refreshed. A stale bookmark is re-created only after that read and the
    /// identity check, while the scope is held; if re-creating it fails, the previous bookmark is
    /// kept so the next open can retry. A failed reopen keeps the record and its last-opened time
    /// unchanged, so P0-02 can ask the user to choose the folder again.
    public func reopen(_ recentID: UUID) -> FolderOpenResult {
        let folders: [RecentFolder]
        do {
            folders = try store.load()
        } catch {
            return .failed(.storageUnavailable(Self.storeError(error)))
        }
        guard let index = folders.firstIndex(where: { $0.id == recentID }) else {
            return .failed(.unknownRecent(recentID))
        }
        var recent = folders[index]
        let resolved: URL
        let isStale: Bool
        do {
            let resolution = try FolderBookmarks.resolve(recent.bookmark)
            resolved = resolution.url
            isStale = resolution.isStale
        } catch {
            return .failed(Self.failure(for: error, stage: .resolve))
        }
        let scopeIsHeld = scope.startAccessing(resolved)
        func failure(_ failure: FolderAccessFailure) -> FolderOpenResult {
            if scopeIsHeld { scope.stopAccessing(resolved) }
            return .failed(failure)
        }
        do {
            _ = try locations.listContents(of: resolved)
        } catch {
            return failure(Self.failure(for: error, stage: .read))
        }
        let facts = locations.facts(for: resolved)
        let identityCheck = recent.identityKeys.checkIdentity(against: facts.identityKeys)
        guard identityCheck != .mismatch else {
            return failure(
                .identityMismatch(recorded: recent.identityKeys, found: facts.identityKeys))
        }
        if isStale, let refreshed = try? FolderBookmarks.data(for: resolved) {
            recent.bookmark = refreshed
        }
        recent.pathSummary = resolved.path
        recent.volumeName = facts.volumeName ?? recent.volumeName
        recent.identityKeys = recent.identityKeys.merging(facts.identityKeys)
        recent.mediaType = facts.mediaType
        recent.lastOpened = now()
        recent.needsReconnect = false
        var updated = folders
        updated[index] = recent
        do {
            try store.save(updated)
        } catch {
            return failure(.storageUnavailable(Self.storeError(error)))
        }
        let session = makeSession(
            for: recent, rootURL: resolved, identityCheck: identityCheck,
            scopeIsHeld: scopeIsHeld)
        return .opened(OpenedFolder(recent: recent, session: session))
    }

    /// Records a completed scan's count and completeness after a successful open (PRD P0-02).
    ///
    /// Only call this after a successful open; a failed open never updates a record. A partial scan
    /// is stored as partial. The last-opened time moves with the successful open and scan, as P0-02
    /// shows it. A session whose record no longer exists is ignored, and a store error is thrown so
    /// the caller can report it.
    public func recordScan(_ summary: FolderScanSummary, for session: FolderAccessSession) throws {
        var folders = try store.load()
        guard let index = folders.firstIndex(where: { $0.id == session.recentID }) else { return }
        folders[index].photoCount = summary.photoCount
        folders[index].scanStatus = summary.status
        folders[index].lastOpened = now()
        try store.save(folders)
    }

    /// Stores only confirmed progress without changing the last-opened date (handoff Entry).
    public func recordProgress(_ progress: FolderProgress, for identity: FolderIdentity) throws {
        var folders = try store.load()
        guard let index = folders.firstIndex(where: { $0.identity == identity }) else { return }
        folders[index].progress = progress
        try store.save(folders)
    }

    /// Remembers an observed loss without probing folders on Entry (handoff Entry; G1 access).
    public func recordLocationLoss(for identity: FolderIdentity) throws {
        var folders = try store.load()
        guard let index = folders.firstIndex(where: { $0.identity == identity }) else { return }
        folders[index].needsReconnect = true
        try store.save(folders)
    }

    private func makeSession(
        for recent: RecentFolder,
        rootURL: URL,
        identityCheck: FolderIdentityCheck,
        scopeIsHeld: Bool
    ) -> FolderAccessSession {
        FolderAccessSession(
            folder: FolderSession(
                id: recent.identity, displayURL: rootURL,
                displayName: rootURL.lastPathComponent),
            rootURL: rootURL, recentID: recent.id, identityCheck: identityCheck, scope: scope,
            scopeIsHeld: scopeIsHeld)
    }

    private enum Stage {
        case resolve
        case read
    }

    private static func failure(for error: any Error, stage: Stage) -> FolderAccessFailure {
        let chain = FolderErrorChain(error)
        if chain.isPermissionDenied { return .permissionDenied(chain) }
        switch stage {
        case .resolve:
            return .locationUnavailable(chain)
        case .read:
            return chain.isLocationUnavailable ? .locationUnavailable(chain) : .readFailed(chain)
        }
    }

    private static func storeError(_ error: any Error) -> RecentFolderStoreError {
        if let storeError = error as? RecentFolderStoreError { return storeError }
        return .unreadable(FolderErrorChain(error))
    }
}

extension FolderIdentityKeys {
    /// Keeps a key the current read could not supply, so a partial provider read does not erase
    /// identity that a later comparison can still use. A differing key is not merged.
    fileprivate func merging(_ found: FolderIdentityKeys) -> FolderIdentityKeys {
        FolderIdentityKeys(
            volumeUUID: found.volumeUUID ?? volumeUUID,
            fileIdentifier: found.fileIdentifier ?? fileIdentifier)
    }
}
