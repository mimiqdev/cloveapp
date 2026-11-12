import Foundation

/// Builds the confirmation plan and the pre-flight checks for one Move rejects request.
///
/// PRD P0-10's confirmation names how many photos, companions and XMP files move and where
/// they go, and G1 decision 5 moves each photo set as one unit. The planner does exactly that:
/// it validates the request's whole-request preconditions, then gives every requested set either
/// a ready destination or a refusal. It reads existence only — nothing is created, renamed or
/// deleted — so the sheet can show its counts before the user commits.
public struct RejectMovePlanner: Sendable {
    /// The most suffixes tried for one set before its destination is called unavailable.
    ///
    /// The bound keeps a misconfigured destination from looping; a real folder needs one or
    /// two suffixed names at most. PRD P0-10's suffix rule is unchanged by the limit.
    public static let maximumSuffixAttempts = 1_000

    /// The file operations the plan's existence checks go through (PRD P0-10).
    private let fileSystem: any PhotoFileSystem

    /// Creates a planner over the production file system unless a test supplies another.
    public init(fileSystem: any PhotoFileSystem = FoundationPhotoFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Refuses a request that must not touch any file (PRD P0-10, Failure and recovery).
    ///
    /// PRD Move rejects turns the feature off in Settings, and a read-only location cannot be
    /// organized. Both refusals come before a plan or a run, so the UI shows one message
    /// instead of a failure per photo. Read-only is only ever taken from the volume's own
    /// read-only value; a generic failure is classified later and never inferred as read-only
    /// (S1's failure table).
    public func preflight(_ request: RejectMoveRequest) throws(RejectMoveRefusal) {
        try preflight(rootURL: request.rootURL, configuration: request.configuration)
    }

    /// Refuses a plan or a run whose settings or location forbid every move (PRD P0-10).
    public func preflight(
        rootURL: URL, configuration: RejectMoveConfiguration
    ) throws(RejectMoveRefusal) {
        guard configuration.isEnabled else { throw .disabled }
        // A failed read is not evidence of a read-only volume, so only `true` refuses.
        if (try? fileSystem.isReadOnlyVolume(at: rootURL)) == true {
            let name =
                rootURL.lastPathComponent.isEmpty
                ? rootURL.path(percentEncoded: false) : rootURL.lastPathComponent
            throw .readOnlyLocation(
                RejectMoveFailure(
                    reason: .readOnlyStorage,
                    message: "The volume holding \(name) reports itself read-only."))
        }
    }

    /// Builds one request's plan, with a destination for every set that can move (PRD P0-10).
    ///
    /// Throws only the whole-request refusal; a set that cannot move is an entry, so the sheet
    /// can show "N photos will move" next to the sets that will not. The destination of each
    /// file keeps its name and extension case, gains one suffix for the whole set when any
    /// destination name is taken, and stays inside `<root>/<rejects folder>/<relative folder>`.
    public func plan(for request: RejectMoveRequest) throws(RejectMoveRefusal) -> RejectMovePlan {
        try preflight(request)
        let destinationURL = request.rootURL.appendingPathComponent(
            request.configuration.rejectsFolderName.rawValue, isDirectory: true)
        var entries: [RejectMovePlanEntry] = []
        entries.reserveCapacity(request.sets.count)
        for set in request.sets {
            entries.append(entry(for: set, request: request, destinationURL: destinationURL))
        }
        return RejectMovePlan(
            rootURL: request.rootURL, configuration: request.configuration, sets: request.sets,
            entries: entries, destinationURL: destinationURL)
    }

    /// Plans one set, or refuses it with the reason the result reports (PRD P0-10).
    private func entry(
        for set: ScannedPhotoSet, request: RejectMoveRequest, destinationURL: URL
    ) -> RejectMovePlanEntry {
        let identity = set.photoSet.id
        if let refusal = refusal(for: set, request: request) {
            return .refused(identity: identity, refusal: refusal)
        }
        let relativeFolderPath = set.photoSet.id.relativeFolderPath
        let folder =
            relativeFolderPath.isEmpty
            ? destinationURL
            : destinationURL.appendingPathComponent(relativeFolderPath, isDirectory: true)
        let sources: [(role: RejectMoveFileRole, url: URL)]
        do {
            sources = try PhotoSetFileCollector(fileSystem: fileSystem).members(of: set).map {
                url in
                let role: RejectMoveFileRole
                if url == set.photoSet.primary.url {
                    role = .primary
                } else if url == set.photoSet.jpegCompanion?.url {
                    role = .jpegCompanion
                } else if url == set.photoSet.heifCompanion?.url {
                    role = .heifCompanion
                } else {
                    role = .sidecar
                }
                return (role, url)
            }
        } catch {
            return .refused(
                identity: identity,
                refusal: .destinationCheckFailed(RejectMoveFailure(classifying: error)))
        }
        guard !sources.isEmpty else {
            return .refused(identity: identity, refusal: .outsideOpenedFolder)
        }
        // PRD P0-10: one suffix for the whole set, so a RAW, its companions and its XMP still
        // pair by stem after the move. The first attempt is the untouched name.
        var attempt = 0
        while attempt <= Self.maximumSuffixAttempts {
            let files = sources.map { member in
                RejectMoveFilePlan(
                    role: member.role,
                    source: member.url,
                    destination: folder.appendingPathComponent(
                        RejectMoveNaming.suffixed(member.url.lastPathComponent, attempt: attempt)))
            }
            do {
                if try files.allSatisfy({ try fileSystem.exists(at: $0.destination) == false }) {
                    return .ready(
                        RejectMoveSetPlan(
                            identity: identity, relativeFolderPath: relativeFolderPath,
                            destinationFolder: folder, files: files))
                }
            } catch {
                return .refused(
                    identity: identity,
                    refusal: .destinationCheckFailed(RejectMoveFailure(classifying: error)))
            }
            attempt += 1
        }
        return .refused(
            identity: identity,
            refusal: .destinationUnavailable(attempts: Self.maximumSuffixAttempts))
    }

    /// Whether the set must not move at all, and why (PRD P0-10, G1 Sidecar naming).
    ///
    /// An ambiguous packet is a failure, not a skip: the user has to resolve the packet, and
    /// PRD How marks reach disk, rule 3, forbids choosing a candidate or leaving one behind.
    /// A set already inside the rejects folder is a skip, because moving it would nest the
    /// rejects folder inside itself. A set whose files are not exactly under the opened root
    /// plus its scanned relative folder is refused, so a move can never leave the opened
    /// folder's scope.
    private func refusal(
        for set: ScannedPhotoSet, request: RejectMoveRequest
    ) -> RejectMoveSetRefusal? {
        if case .ambiguous(let candidates) = set.sidecar {
            return .ambiguousSidecar(candidates)
        }
        let relativeFolderPath = set.photoSet.id.relativeFolderPath
        let rejectsName = request.configuration.rejectsFolderName.rawValue
        let firstComponent = relativeFolderPath.split(separator: "/").first.map(String.init)
        if let firstComponent, firstComponent.caseInsensitiveCompare(rejectsName) == .orderedSame {
            return .insideRejectsFolder
        }
        let sourceFolder = set.photoSet.primary.url.deletingLastPathComponent()
        let expectedFolder =
            relativeFolderPath.isEmpty
            ? request.rootURL
            : request.rootURL.appendingPathComponent(relativeFolderPath, isDirectory: true)
        guard PhotoFilePath.matches(sourceFolder, expectedFolder) else {
            return .outsideOpenedFolder
        }
        for file in set.photoSet.fileURLs {
            guard PhotoFilePath.matches(file.deletingLastPathComponent(), sourceFolder) else {
                return .outsideOpenedFolder
            }
        }
        return nil
    }
}
