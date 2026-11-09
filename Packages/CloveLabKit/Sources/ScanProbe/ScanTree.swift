import Darwin
import Foundation

/// Builds the DCIM-like folder tree the spike scans, and deletes it again.
///
/// The tree mimics a card after a shoot: several `DCIM/1xx…` folders, RAW+JPG
/// pairs and standalone JPEG, HEIC, and DNG files, a `_Rejected` folder, hidden
/// AppleDouble `._` files, and a few files the app does not open. It is written
/// below a container the caller picks (a temporary directory on the Mac, the SD
/// card root in Clove Lab), always inside one ``folderName`` folder, so deleting
/// it cannot touch anything else.
///
/// File content is a small placeholder by default: a listing reads names and
/// metadata, not pixels, and 2,000 real RAW files would need tens of gigabytes.
/// ``ScanTreePlan/realisticSizes`` extends each file to a plausible photo size
/// with a sparse write, which only works on a file system that supports sparse
/// files (APFS); leave it off for a camera card.
public enum ScanTree {
    /// Folder the generator creates below the chosen container.
    public static let folderName = "Clove-S6-Scan"

    /// Bytes written into every placeholder file.
    public static let placeholderBytes = 1_024

    /// The tree folder below `container`, whether or not it exists.
    public static func treeURL(in container: URL) -> URL {
        container.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Whether a generated tree exists below `container`.
    public static func exists(in container: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = treeURL(in: container).path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Deletes a generated tree below `container`, if there is one.
    @discardableResult
    public static func removeTree(in container: URL) throws -> Bool {
        let tree = treeURL(in: container)
        guard FileManager.default.fileExists(atPath: tree.path(percentEncoded: false)) else {
            return false
        }
        try removeTree(at: tree)
        return true
    }

    /// Deletes exactly one generated tree.
    ///
    /// Refuses a folder whose name is not ``folderName``, so a mistyped path
    /// cannot remove a camera folder.
    public static func removeTree(at tree: URL) throws {
        guard tree.lastPathComponent == folderName else {
            throw ScanTreeFailure.notAGeneratedTree(tree.lastPathComponent)
        }
        try FileManager.default.removeItem(at: tree)
    }

    /// Writes the tree below `container` and returns what it contains.
    ///
    /// An existing generated tree is replaced, so a second run starts clean.
    ///
    /// - Parameters:
    ///   - container: The folder that receives ``folderName``; a temporary
    ///     directory on the Mac, the SD card root in Clove Lab.
    ///   - plan: Shape and size of the tree.
    ///   - progress: Called with the number of written files and the total.
    public static func makeTree(
        in container: URL,
        plan: ScanTreePlan = ScanTreePlan(),
        progress: @Sendable (ScanTreeProgress) async -> Void = { _ in }
    ) async throws -> ScanTreeSummary {
        let root = treeURL(in: container)
        try removeTree(in: container)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var summary = ScanTreeSummary(root: root, folders: plan.folders.count)
        let total = plan.fileTarget + plan.rejectsFileCount
        var written = 0
        var counter = 0
        for (folderIndex, folder) in plan.folders.enumerated() {
            let directoryURL =
                root
                .appendingPathComponent("DCIM", isDirectory: true)
                .appendingPathComponent(folder, isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let quota = plan.quota(forFolderAt: folderIndex)
            var nameIndex = (folderIndex + 1) * 1_000
            var writtenInFolder = 0
            while writtenInFolder < quota {
                if Task.isCancelled {
                    try? fileManager.removeItem(at: root)
                    throw CancellationError()
                }
                let shape = ScanTreeShape.shape(for: counter)
                let isPair = shape == .pair && quota - writtenInFolder >= 2
                nameIndex += 1
                let baseName = String(format: "IMG_%04d", nameIndex)
                let bytes = try write(
                    shape: isPair ? .pair : (shape == .pair ? .raw : shape),
                    baseName: baseName, index: counter, plan: plan, to: directoryURL)
                writtenInFolder += isPair ? 2 : 1
                written += isPair ? 2 : 1
                summary.photoFiles += isPair ? 2 : 1
                summary.pairs += isPair ? 1 : 0
                summary.bytes += bytes
                counter += 1
                if writtenInFolder > quota {
                    writtenInFolder = quota
                }
                if written % 64 == 0 || written >= total {
                    await progress(ScanTreeProgress(completed: written, total: total))
                }
            }
            try addJunk(to: directoryURL, plan: plan, folderIndex: folderIndex)
        }

        if plan.rejectsFileCount > 0 {
            let rejectsURL =
                root
                .appendingPathComponent("DCIM", isDirectory: true)
                .appendingPathComponent(plan.folders.first ?? "100CANON", isDirectory: true)
                .appendingPathComponent(plan.rejectsFolderName, isDirectory: true)
            try fileManager.createDirectory(at: rejectsURL, withIntermediateDirectories: true)
            for index in 0..<plan.rejectsFileCount {
                let name = String(format: "IMG_9%03d.JPG", index)
                summary.bytes += try writeFile(
                    named: name, to: rejectsURL,
                    bytes: ScanTreeShape.size(for: .jpeg, index: index),
                    plan: plan, index: index)
                summary.rejectedFiles += 1
                written += 1
                if written % 64 == 0 {
                    await progress(ScanTreeProgress(completed: written, total: total))
                }
            }
        }
        await progress(ScanTreeProgress(completed: max(total, written), total: max(total, written)))
        summary.photos = summary.photoFiles - summary.pairs
        return summary
    }

    // MARK: - Writing

    private static func write(
        shape: ScanTreeShape,
        baseName: String,
        index: Int,
        plan: ScanTreePlan,
        to directory: URL
    ) throws -> Int {
        switch shape {
        case .pair:
            let rawExtension = ScanTreeShape.rawExtensions[
                index % ScanTreeShape.rawExtensions.count]
            var bytes = 0
            bytes += try writeFile(
                named: baseName + "." + rawExtension.uppercased(), to: directory,
                bytes: ScanTreeShape.size(for: .pair, index: index), plan: plan, index: index)
            bytes += try writeFile(
                named: baseName + ".JPG", to: directory,
                bytes: ScanTreeShape.size(for: .jpeg, index: index), plan: plan, index: index)
            return bytes
        case .raw:
            let rawExtension = ScanTreeShape.rawExtensions[
                index % ScanTreeShape.rawExtensions.count]
            return try writeFile(
                named: baseName + "." + rawExtension.uppercased(), to: directory,
                bytes: ScanTreeShape.size(for: .raw, index: index), plan: plan, index: index)
        case .jpeg:
            return try writeFile(
                named: baseName + ".JPG", to: directory,
                bytes: ScanTreeShape.size(for: .jpeg, index: index), plan: plan, index: index)
        case .heic:
            return try writeFile(
                named: baseName + ".HEIC", to: directory,
                bytes: ScanTreeShape.size(for: .heic, index: index), plan: plan, index: index)
        case .dng:
            return try writeFile(
                named: baseName + ".DNG", to: directory,
                bytes: ScanTreeShape.size(for: .dng, index: index), plan: plan, index: index)
        }
    }

    private static func writeFile(
        named name: String,
        to directory: URL,
        bytes: Int,
        plan: ScanTreePlan,
        index: Int
    ) throws -> Int {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: UInt8(truncatingIfNeeded: index), count: placeholderBytes)
            .write(to: url)
        guard plan.realisticSizes, bytes > placeholderBytes else { return placeholderBytes }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.truncate(atOffset: UInt64(bytes))
        } catch {
            try? handle.close()
            throw error
        }
        try handle.close()
        return bytes
    }

    /// Hidden AppleDouble files, a `.DS_Store`, a sidecar, and files the app
    /// does not open, so the filters are exercised on every run.
    private static func addJunk(
        to directory: URL,
        plan: ScanTreePlan,
        folderIndex: Int
    ) throws {
        let fileManager = FileManager.default
        for index in 0..<plan.appleDoubleCount {
            let name = String(format: "._IMG_%04d.CR3", (folderIndex + 1) * 1_000 + index + 1)
            try Data([0]).write(to: directory.appendingPathComponent(name))
        }
        if folderIndex == 0 {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(".Trashes", isDirectory: true),
                withIntermediateDirectories: true)
            try Data([0]).write(
                to: directory.appendingPathComponent(".Trashes").appendingPathComponent(
                    "IMG_0105.JPG"))
        }
        if folderIndex == 1 {
            try Data([0]).write(to: directory.appendingPathComponent("MVI_0001.MOV"))
            try Data([0]).write(to: directory.appendingPathComponent("NOTES.txt"))
            try Data([0]).write(to: directory.appendingPathComponent("IMG_0200.XMP"))
        }
        if folderIndex == 0 {
            try Data([0]).write(to: directory.appendingPathComponent(".DS_Store"))
        }
    }
}

/// Shapes mixed into the generated tree.
enum ScanTreeShape: Sendable, Hashable {
    case pair
    case raw
    case jpeg
    case heic
    case dng

    /// RAW extensions cycled through the tree, so every format the app opens appears.
    static let rawExtensions = ["CR3", "NEF", "ARW", "RAF", "ORF", "RW2", "DNG"]

    /// Seven in twenty slots are a RAW+JPG pair, four are a standalone JPEG, two
    /// a HEIC, two a DNG, and the rest a standalone RAW.
    static func shape(for index: Int) -> ScanTreeShape {
        switch index % 20 {
        case 0..<7: .pair
        case 7..<11: .jpeg
        case 11..<13: .heic
        case 13..<15: .dng
        default: .raw
        }
    }

    /// A plausible file size, so `.fileSizeKey` and `.contentModificationDateKey`
    /// see numbers like a card's. Used only with `realisticSizes`.
    static func size(for shape: ScanTreeShape, index: Int) -> Int {
        let ranges: [ScanTreeShape: (min: Int, max: Int)] = [
            .pair: (18_000_000, 32_000_000),
            .raw: (8_000_000, 32_000_000),
            .jpeg: (3_000_000, 8_000_000),
            .heic: (2_000_000, 4_000_000),
            .dng: (15_000_000, 30_000_000),
        ]
        guard let range = ranges[shape] else { return placeholderBytesSize }
        return range.min + (index &* 7_919) % (range.max - range.min)
    }

    private static let placeholderBytesSize = ScanTree.placeholderBytes
}

/// Shape and size of the generated tree.
public struct ScanTreePlan: Sendable, Hashable {
    /// Photo files written below `DCIM`, with a pair counting as two files.
    public var fileTarget: Int
    /// `DCIM` subfolder names, one per camera-folder style folder.
    public var folders: [String]
    /// Rejects folder name; the tree also uses it so the skip path runs.
    public var rejectsFolderName: String
    /// JPEG files inside the rejects folder.
    public var rejectsFileCount: Int
    /// AppleDouble `._` files per folder.
    public var appleDoubleCount: Int
    /// Extend each file to a plausible photo size with a sparse write. Only for
    /// a file system with sparse files (APFS); leave off for a camera card.
    public var realisticSizes: Bool

    public init(
        fileTarget: Int = 2_000,
        folders: [String] = [
            "100CANON", "101CANON", "102NIKON", "103SONY", "104FUJI", "105PANASONIC",
        ],
        rejectsFolderName: String = ScanRule.defaultRejectsFolderName,
        rejectsFileCount: Int = 150,
        appleDoubleCount: Int = 3,
        realisticSizes: Bool = false
    ) {
        self.fileTarget = max(0, fileTarget)
        self.folders = folders
        self.rejectsFolderName = rejectsFolderName
        self.rejectsFileCount = max(0, rejectsFileCount)
        self.appleDoubleCount = max(0, appleDoubleCount)
        self.realisticSizes = realisticSizes
    }

    /// Files for one folder; the last folder takes the remainder.
    public func quota(forFolderAt index: Int) -> Int {
        guard !folders.isEmpty else { return 0 }
        let base = fileTarget / folders.count
        let remainder = fileTarget % folders.count
        return base + (index < remainder ? 1 : 0)
    }
}

/// What ``ScanTree/makeTree(in:plan:progress:)`` wrote.
public struct ScanTreeSummary: Sendable, Hashable {
    /// Folder that holds `DCIM`.
    public var root: URL
    /// `DCIM` subfolders.
    public var folders: Int
    /// Photo files below `DCIM`, pairs counted separately.
    public var photoFiles: Int
    /// Grid photos: pairs plus standalone files.
    public var photos: Int
    /// RAW+JPG pairs.
    public var pairs: Int
    /// JPEG files in the rejects folder.
    public var rejectedFiles: Int
    /// Logical bytes written; sparse files report their full size.
    public var bytes: Int

    public init(
        root: URL, folders: Int = 0, photoFiles: Int = 0, photos: Int = 0, pairs: Int = 0,
        rejectedFiles: Int = 0, bytes: Int = 0
    ) {
        self.root = root
        self.folders = folders
        self.photoFiles = photoFiles
        self.photos = photos
        self.pairs = pairs
        self.rejectedFiles = rejectedFiles
        self.bytes = bytes
    }
}

/// Generator progress for the Clove Lab status line.
public struct ScanTreeProgress: Sendable, Hashable {
    /// Files written so far.
    public var completed: Int
    /// Files the plan writes.
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

/// Why the tree could not be built or removed.
public enum ScanTreeFailure: Error, CustomStringConvertible {
    /// The folder name is not ``ScanTree/folderName``.
    case notAGeneratedTree(String)

    public var description: String {
        switch self {
        case .notAGeneratedTree(let name):
            "\(name) is not a \(ScanTree.folderName) folder"
        }
    }
}

/// The volume a folder lives on, for the report's context.
public enum ScanVolume {
    /// Mount point and file system name of `folder`, for example `T7` and `apfs`.
    public static func describe(_ folder: URL) -> [String: String] {
        var description: [String: String] = [:]
        if let name = try? folder.resourceValues(forKeys: [.volumeNameKey]).volumeName {
            description["volume"] = name
        }
        var information = statfs()
        let path = folder.path(percentEncoded: false)
        guard path.withCString({ statfs($0, &information) }) == 0 else { return description }
        var fileSystemName = information.f_fstypename
        let capacity = MemoryLayout.size(ofValue: fileSystemName)
        description["fileSystem"] = withUnsafePointer(to: &fileSystemName) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return description
    }
}
