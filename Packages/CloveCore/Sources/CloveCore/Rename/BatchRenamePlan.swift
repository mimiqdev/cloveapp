import Foundation

/// The sequence follows the supplied order across every subfolder.
public struct RenameTemplate: Hashable, Sendable {
    public let prefix: String
    public let sequenceStart: Int
    public let digits: Int
    public let includesCaptureDate: Bool
    public let dateSeparator: String

    public init(
        prefix: String = "", sequenceStart: Int = 1, digits: Int = 3,
        includesCaptureDate: Bool = false, dateSeparator: String = "_"
    ) {
        self.prefix = prefix
        self.sequenceStart = sequenceStart
        self.digits = digits
        self.includesCaptureDate = includesCaptureDate
        self.dateSeparator = dateSeparator
    }
}

public enum RenameDestination: Hashable, Sendable {
    case inPlace
    /// A single folder name directly inside the opened folder, created if missing.
    case folder(String)
}

public struct RenameItem: Hashable, Sendable {
    public let set: ScannedPhotoSet
    /// Camera wall components encoded in UTC, as in the metadata reader. Do not pass an
    /// offset-adjusted ordering instant: the date must stay as the camera recorded it.
    public let captureWallTime: Date?

    public init(set: ScannedPhotoSet, captureWallTime: Date? = nil) {
        self.set = set
        self.captureWallTime = captureWallTime
    }
}

public struct BatchRenameRequest: Hashable, Sendable {
    public let rootURL: URL
    public let items: [RenameItem]
    public let template: RenameTemplate
    public let destination: RenameDestination
    public let rejectsFolderName: RejectsFolderName
    /// File creation dates use the device's zone; capture wall dates never change zones.
    public let timeZone: TimeZone

    public init(
        rootURL: URL, items: [RenameItem], template: RenameTemplate = RenameTemplate(),
        destination: RenameDestination = .inPlace, timeZone: TimeZone = .current,
        rejectsFolderName: RejectsFolderName = .defaultFolderName
    ) {
        self.rootURL = rootURL
        self.items = items
        self.template = template
        self.destination = destination
        self.rejectsFolderName = rejectsFolderName
        self.timeZone = timeZone
    }
}

public enum RenameProblem: Hashable, Sendable {
    case invalidName(String)
    case nameTooLong(String)
    case invalidSequence
    case sequenceOverflow
    case dateUnavailable
    case destinationIsFile(URL)
    case rejectsDestination(String)
    case duplicateTarget(URL)
    case duplicateSource(PhotoIdentity)
    case ambiguousSidecar([URL])
    case outsideOpenedFolder
    case fileSystem(String)
}

public struct RenameFile: Hashable, Sendable {
    public let source: URL
    public let destination: URL
}

/// An existing set that will be preserved in its own folder's rejects folder.
public struct RenameReplacement: Hashable, Sendable {
    public let identity: PhotoIdentity
    public let stem: String
    public let files: [RenameFile]
    public let rejectsRelativeFolder: String
}

public struct BatchRenameRow: Hashable, Sendable, Identifiable {
    public let item: RenameItem
    public let oldStem: String
    public let newStem: String
    public let destinationRelativeFolder: String
    public let files: [RenameFile]
    public internal(set) var problems: [RenameProblem]
    public internal(set) var replacement: RenameReplacement? = nil
    public let isNoOp: Bool
    public var id: PhotoIdentity { item.set.id }
}

/// Constructed only by the planner; a caller cannot remove problems before execution.
public struct BatchRenamePlan: Hashable, Sendable {
    public let request: BatchRenameRequest
    public let rows: [BatchRenameRow]
    public let requiresTemporaryNames: Bool
    /// Uses an existing destination folder's actual on-disk spelling.
    public let destination: RenameDestination
    public var replacementCount: Int { rows.compactMap(\.replacement).count }
    public var canRename: Bool { rows.allSatisfy { $0.problems.isEmpty } }
}

public enum BatchRenameRefusal: Error, Hashable, Sendable {
    /// Every row, including all problems, is kept for the confirmation sheet.
    case problems(BatchRenamePlan)
    case alreadyRunning
}
