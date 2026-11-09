import CryptoKit
import Foundation

/// The caller's token for the inputs a grouping ran on (PRD Similar groups rules).
///
/// The cache is keyed by this value and the threshold set, so the caller changes the token
/// whenever a photo's time, camera body, file name or membership changes. Nothing about the
/// folder's marks enters the key, because grouping never reads or writes them (PRD P0-11).
public struct GroupingInputRevision: RawRepresentable, Hashable, Sendable {
    /// The opaque revision token, for example a scan generation plus a photo count.
    public let rawValue: String

    /// Wraps the caller's token.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Groups cached per opened folder in Clove's own storage (PRD Similar groups rules).
///
/// PRD Similar groups, "Groups are cached only in Clove and never written to XMP", puts the
/// cache in app-private storage beside the other Clove data, one file per folder identity. The
/// file is keyed by the caller's ``GroupingInputRevision`` and the `GroupingThresholds`, so a
/// changed input or a changed threshold invalidates it. Only finished results are stored, so a
/// restored folder is already Analyzed.
///
/// The location is injectable for tests; production passes ``applicationSupportDirectory()``.
/// Cache writes and reads are best effort: a corrupt, foreign or stale file is ignored and the
/// folder is grouped again, and a failed write never fails grouping.
public struct SimilarGroupsCache: Sendable {
    /// The app-private directory holding one file per folder identity.
    public let directory: URL

    /// Roots the cache at an existing directory; tests pass a temporary folder.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The production location: an app-private folder below Application Support.
    ///
    /// PRD Similar groups rules allow only Clove's own storage, and a folder beside the stored
    /// marks keeps the cache separate from every other Clove file.
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        return base.appendingPathComponent("Clove", isDirectory: true)
            .appendingPathComponent("SimilarGroups", isDirectory: true)
    }

    /// The one file for a folder identity, named by a digest so no path enters a file name.
    func fileURL(for folderID: FolderIdentity) -> URL {
        let digest = SHA256.hash(data: Data(folderID.rawValue.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("groups-v1-\(name).json")
    }

    /// The cached finished groups, or nil when the cache is missing, stale or unusable.
    ///
    /// A file counts as usable only when its version, folder identity, input revision and
    /// threshold key all match and every stored member is one of the current photos, so a
    /// cache written for another input can never leak into this result. A damaged file returns
    /// nil and is rebuilt (PRD Similar groups rules).
    func load(
        folderID: FolderIdentity,
        revision: GroupingInputRevision,
        thresholds: GroupingThresholds,
        photos: [GroupingPhoto]
    ) -> [SimilarGroup]? {
        guard let data = try? Data(contentsOf: fileURL(for: folderID)),
            let stored = try? JSONDecoder().decode(StoredGroups.self, from: data),
            stored.version == StoredGroups.currentVersion,
            stored.folder == folderID.rawValue,
            stored.revision == revision.rawValue,
            stored.thresholds == thresholds.cacheKey
        else { return nil }

        let known = Set(photos.map(\.id))
        var seen: Set<GroupID> = []
        var groups: [SimilarGroup] = []
        for cachedGroup in stored.groups {
            let id = GroupID(rawValue: cachedGroup.id)
            guard seen.insert(id).inserted else { return nil }
            var members: [PhotoIdentity] = []
            for cachedPhoto in cachedGroup.photos {
                let photo = PhotoIdentity(
                    folderID: folderID,
                    relativeFolderPath: cachedPhoto.relativeFolderPath,
                    stem: cachedPhoto.stem)
                guard known.contains(photo), !members.contains(photo) else { return nil }
                members.append(photo)
            }
            guard members.count >= 2 else { return nil }
            groups.append(
                SimilarGroup(
                    id: id,
                    members: members,
                    refinement: .refined,
                    usedFallbackSimilarity: cachedGroup.usedFallback))
        }
        return groups
    }

    /// Stores a finished result for a folder, replacing any earlier file; failures are ignored.
    func save(
        _ groups: [SimilarGroup],
        folderID: FolderIdentity,
        revision: GroupingInputRevision,
        thresholds: GroupingThresholds
    ) {
        let stored = StoredGroups(
            version: StoredGroups.currentVersion,
            folder: folderID.rawValue,
            revision: revision.rawValue,
            thresholds: thresholds.cacheKey,
            groups: groups.map { group in
                StoredGroups.Group(
                    id: group.id.rawValue,
                    photos: group.members.map {
                        StoredGroups.Photo(
                            relativeFolderPath: $0.relativeFolderPath, stem: $0.stem)
                    },
                    usedFallback: group.usedFallbackSimilarity)
            })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: folderID), options: .atomic)
    }
}

/// The on-disk shape of one folder's finished groups; a persisted format.
///
/// A version change makes every older file unusable, which is what a changed group shape or a
/// changed grouping rule needs; the folder is then grouped again rather than migrated.
struct StoredGroups: Codable, Sendable {
    /// The only format this version reads and writes; bump it when a stored result would no
    /// longer match what the current rule produces.
    static let currentVersion = 1

    /// The format version, checked before anything else is trusted.
    var version: Int
    /// The folder identity the groups belong to, so a copied file is refused.
    var folder: String
    /// The input revision the groups were computed from.
    var revision: String
    /// The threshold key the groups were computed under.
    var thresholds: String
    /// The finished groups in grid order.
    var groups: [Group]

    /// One stored group: its stable key, its members and its fallback flag.
    struct Group: Codable, Sendable {
        /// The stable group key (PRD P0-11).
        var id: String
        /// The members in capture-time order.
        var photos: [Photo]
        /// Whether a joined boundary inside the group used the dHash fallback (G1 Grouping row).
        var usedFallback: Bool
    }

    /// One stored member, without the folder identity, which the file already carries.
    struct Photo: Codable, Sendable {
        /// The member's containing directory relative to the opened folder.
        var relativeFolderPath: String
        /// The member's case-folded stem (PRD P0-01).
        var stem: String
    }
}
