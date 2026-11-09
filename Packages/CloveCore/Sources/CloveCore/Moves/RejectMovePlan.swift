import Foundation

/// The Move rejects settings a plan and a move read (PRD P0-10).
///
/// C12 owns the destination name and the on/off switch; this value is the move lane's view of
/// them, so the mover never reads a settings screen or a defaults domain of its own.
public struct RejectMoveConfiguration: Hashable, Sendable {
    /// The validated folder name created under the opened folder (PRD Move rejects, C12).
    public let rejectsFolderName: RejectsFolderName
    /// Whether Move rejects is offered at all (PRD Move rejects, C12). Reject itself still
    /// works for filtering when this is off.
    public let isEnabled: Bool

    /// Configures the move lane; `_Rejected` and enabled are the launch values (PRD P0-10).
    public init(
        rejectsFolderName: RejectsFolderName = .defaultFolderName, isEnabled: Bool = true
    ) {
        self.rejectsFolderName = rejectsFolderName
        self.isEnabled = isEnabled
    }

    /// Reads the two C12 settings Move rejects uses (PRD Move rejects).
    public init(settings: AppSettings) {
        self.init(
            rejectsFolderName: settings.rejectsFolderName,
            isEnabled: settings.moveRejectsEnabled)
    }
}

/// One Move rejects request: the opened folder, its rejected photo sets and the settings.
///
/// PRD P0-10 moves rejected photo sets under the opened folder, so the root and the sets come
/// from C2's scan path and C11's opened session. The request is also what the plan keeps for
/// ``RejectMovePlan`` and what the result keeps for a retry of failed items.
public struct RejectMoveRequest: Hashable, Sendable {
    /// The opened folder the rejects folder is created under (PRD Move rejects).
    public let rootURL: URL
    /// The rejected photo sets, in the caller's display order (PRD P0-10).
    ///
    /// The caller supplies the sets it read as rejected from Clove storage; the mover moves
    /// exactly these and never re-reads Clove storage to decide which photos are rejected.
    public let sets: [ScannedPhotoSet]
    /// The rejects folder name and the on/off switch (PRD Move rejects, C12).
    public let configuration: RejectMoveConfiguration

    /// Describes one request without touching the disk (PRD P0-10).
    public init(
        rootURL: URL, sets: [ScannedPhotoSet], configuration: RejectMoveConfiguration
    ) {
        self.rootURL = rootURL
        self.sets = sets
        self.configuration = configuration
    }
}

/// A file's part in its photo set, so the confirmation can count companions and sidecars.
///
/// G1 decision 5 moves a set as one unit and PRD P0-10's confirmation names how many JPEG and
/// HIF companions and how many XMP files travel with the primaries.
public enum RejectMoveFileRole: String, CaseIterable, Hashable, Sendable {
    /// The RAW, or the standalone JPEG/HIF when no RAW exists (G1 decision 1).
    case primary
    /// A same-stem JPEG reference that is never modified (G1 decisions 1–2).
    case jpegCompanion
    /// A same-stem HIF/HEIF reference that is never modified (G1 decisions 1–2).
    case heifCompanion
    /// The set's one resolved `.xmp` packet, in the spelling it already uses (G1 Sidecar naming).
    case sidecar
}

/// One file of a set with the exact destination it will be renamed to (PRD P0-10).
///
/// Both URLs keep the on-disk spelling: the name and the extension's case are never rewritten
/// and never normalized, so `IMG_0001.HIF` stays `IMG_0001.HIF` under the rejects folder.
public struct RejectMoveFilePlan: Hashable, Sendable {
    /// The file's part in the set (G1 decision 5).
    public let role: RejectMoveFileRole
    /// Where the file is now (PRD P0-10).
    public let source: URL
    /// Where it is renamed to, under the rejects folder (PRD P0-10).
    public let destination: URL

    /// Describes one member and its destination (PRD P0-10).
    public init(role: RejectMoveFileRole, source: URL, destination: URL) {
        self.role = role
        self.source = source
        self.destination = destination
    }
}

/// One photo set's plan: every file, the destination folder and the set's identity.
///
/// G1 decision 5 makes the photo set the unit of a move, so the set's files are planned
/// together. A set is only ever ready with all of its files; a set with an unresolved sidecar
/// or a destination that cannot be named is refused instead (PRD P0-10, G1 Sidecar naming).
public struct RejectMoveSetPlan: Hashable, Sendable, Identifiable {
    /// C1's stable photo identity, which the Reject record is keyed by (G1 decision 5).
    public let identity: PhotoIdentity
    /// The set's folder relative to the opened root, empty at the root (PRD scan scope).
    public let relativeFolderPath: String
    /// `<root>/<rejects folder>/<relative folder>` (PRD P0-10).
    public let destinationFolder: URL
    /// Every file to rename, in primary, companion, sidecar order (G1 decision 5).
    public let files: [RejectMoveFilePlan]

    /// Describes one ready set (PRD P0-10).
    public init(
        identity: PhotoIdentity, relativeFolderPath: String, destinationFolder: URL,
        files: [RejectMoveFilePlan]
    ) {
        self.identity = identity
        self.relativeFolderPath = relativeFolderPath
        self.destinationFolder = destinationFolder
        self.files = files
    }

    /// The set's id for a SwiftUI list, which is C1's stable identity (G1 decision 5).
    public var id: PhotoIdentity { identity }

    /// Connections that are not the photo's own files and never change the image (G1 decision 1).
    public var companions: [RejectMoveFilePlan] { files.filter { $0.role.isCompanion } }
    /// The set's resolved `.xmp`, absent when the set has no packet to carry (G1 decision 6).
    public var sidecars: [RejectMoveFilePlan] { files.filter { $0.role == .sidecar } }
}

extension RejectMoveFileRole {
    /// Whether the role is a JPEG or HIF companion of the primary (G1 decision 1).
    public var isCompanion: Bool { self == .jpegCompanion || self == .heifCompanion }
}

/// Why a set cannot be planned as a single unit, kept so the result explains it (PRD P0-10).
public enum RejectMoveSetRefusal: Hashable, Sendable {
    /// C2 found more than one candidate packet; the set fails and no candidate is chosen
    /// (G1 Sidecar naming, PRD How marks reach disk, rule 3).
    case ambiguousSidecar([URL])
    /// The set's files are not in the opened root plus the scanned relative folder (PRD P0-10).
    case outsideOpenedFolder
    /// The set already sits in the rejects folder, so moving it would nest that folder (P0-10).
    case insideRejectsFolder
    /// A destination name could not be checked, so no suffix decision is safe (PRD P0-10).
    case destinationCheckFailed(RejectMoveFailure)
    /// Every suffix up to the plan's limit is already taken at the destination (PRD P0-10).
    case destinationUnavailable(attempts: Int)

    /// The failure this refusal becomes when the move reports its per-photo results.
    ///
    /// PRD P0-10 counts an unmoved set as failed; only a set that is already inside the
    /// rejects folder is a skip, because nothing is wrong with it.
    public var failure: RejectMoveFailure? {
        switch self {
        case .ambiguousSidecar(let candidates):
            RejectMoveFailure(
                reason: .ambiguousSidecar,
                message:
                    "The photo set has more than one candidate XMP packet: "
                    + candidates.map(\.lastPathComponent).joined(separator: ", "))
        case .outsideOpenedFolder:
            RejectMoveFailure(
                reason: .outsideOpenedFolder,
                message: "The photo set is not inside the folder the move was asked to open.")
        case .insideRejectsFolder:
            nil
        case .destinationCheckFailed(let failure):
            failure
        case .destinationUnavailable(let attempts):
            RejectMoveFailure(
                reason: .conflict,
                message: "Every destination name is taken after \(attempts) suffixes.")
        }
    }
}

/// One requested set's planning result, in the caller's order (PRD P0-10).
public enum RejectMovePlanEntry: Hashable, Sendable {
    /// The set can move as one unit (G1 decision 5).
    case ready(RejectMoveSetPlan)
    /// The set cannot move, with the reason shown by the result (PRD P0-10).
    case refused(identity: PhotoIdentity, refusal: RejectMoveSetRefusal)

    /// C1's stable identity of the requested set, whatever the outcome (G1 decision 5).
    public var identity: PhotoIdentity {
        switch self {
        case .ready(let plan): plan.identity
        case .refused(let identity, _): identity
        }
    }
}

/// Everything the confirmation sheet needs before the user commits (PRD P0-10, U10).
///
/// The plan lists each set's files and their destinations under
/// `<root>/<rejects folder>/<set's relative folder>`, and counts the photos, the companions
/// and the sidecars that travel with them. Computing it only reads existence, sizes are left
/// to the move, and nothing is created or renamed here.
public struct RejectMovePlan: Hashable, Sendable {
    /// The opened folder the plan belongs to (PRD Move rejects).
    public let rootURL: URL
    /// The rejects folder name and the on/off switch the plan was built with (C12).
    public let configuration: RejectMoveConfiguration
    /// The requested sets, kept so a retry of failed items reuses the same inputs.
    public let sets: [ScannedPhotoSet]
    /// One entry per requested set, in the caller's order (PRD P0-10).
    public let entries: [RejectMovePlanEntry]
    /// `<root>/<rejects folder>`, the destination the confirmation names (PRD P0-10).
    public let destinationURL: URL

    /// Describes one built plan (PRD P0-10).
    public init(
        rootURL: URL, configuration: RejectMoveConfiguration, sets: [ScannedPhotoSet],
        entries: [RejectMovePlanEntry], destinationURL: URL
    ) {
        self.rootURL = rootURL
        self.configuration = configuration
        self.sets = sets
        self.entries = entries
        self.destinationURL = destinationURL
    }

    /// The sets that will move as one unit each (G1 decision 5).
    public var readyEntries: [RejectMoveSetPlan] {
        entries.compactMap { entry in
            guard case .ready(let plan) = entry else { return nil }
            return plan
        }
    }

    /// The sets that cannot move, with the reason the result will report (PRD P0-10).
    public var refusedEntries: [RejectMovePlanEntry] {
        entries.filter { entry in
            guard case .refused = entry else { return false }
            return true
        }
    }

    /// PRD P0-10's photo count: one per set that will move, not one per file.
    public var photoCount: Int { readyEntries.count }

    /// PRD P0-10's companion count: every JPEG and HIF file that travels with a primary.
    public var companionCount: Int { readyEntries.reduce(0) { $0 + $1.companions.count } }

    /// PRD P0-10's XMP count: every resolved packet that travels with a set.
    public var sidecarCount: Int { readyEntries.reduce(0) { $0 + $1.sidecars.count } }

    /// How many requested sets the plan cannot move, reported separately from the counts.
    public var refusedCount: Int { refusedEntries.count }

    /// Every file the move will rename, across the ready sets (G1 decision 5).
    public var fileCount: Int { readyEntries.reduce(0) { $0 + $1.files.count } }
}

/// The whole request was refused before any file was touched (PRD P0-10, Failure and recovery).
///
/// PRD P0-10 refuses Move rejects entirely when the feature is off, and PRD "Read-only
/// location" refuses a read-only location instead of reporting every photo as failed. Neither
/// case attempts a set, so both are request errors rather than per-photo outcomes.
public enum RejectMoveRefusal: Error, Hashable, Sendable, CustomStringConvertible {
    /// C12's Move rejects setting is off (PRD Move rejects).
    case disabled
    /// The opened location reports itself read-only (PRD Failure and recovery).
    case readOnlyLocation(RejectMoveFailure)

    /// A developer-facing explanation; product copy belongs to the result UI.
    public var description: String {
        switch self {
        case .disabled: "Move rejects is turned off."
        case .readOnlyLocation(let failure): failure.description
        }
    }
}
