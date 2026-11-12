import Foundation

struct RenameReplacementPlanner {
    let fileSystem: any PhotoFileSystem

    func plan(files: [URL], row: BatchRenameRow, request: BatchRenameRequest) throws
        -> RenameReplacement
    {
        let sources = files.sorted {
            (Self.rank($0), $0.lastPathComponent) < (Self.rank($1), $1.lastPathComponent)
        }
        for source in sources where try fileSystem.isDirectory(at: source) {
            throw PhotoSetMoveError.notConfirmed(
                "\(source.lastPathComponent) is a folder, not a photo file.")
        }
        let folder = row.files[0].destination.deletingLastPathComponent()
        let rejectsName = request.rejectsFolderName.rawValue
        let existing = try fileSystem.child(named: rejectsName, in: folder)
        let actualName = existing?.lastPathComponent ?? rejectsName
        let rejects = folder.appendingPathComponent(actualName, isDirectory: true)
        if let existing, try !fileSystem.isDirectory(at: existing) {
            throw PhotoSetMoveError.notConfirmed("\(actualName) is a file, not a rejects folder.")
        }
        if let existing,
            !PhotoFilePath.canonical(existing).hasPrefix(PhotoFilePath.canonical(folder) + "/")
        {
            throw PhotoSetMoveError.notConfirmed(
                "The rejects folder is outside the photo's folder.")
        }
        guard
            let moves = try PhotoSetFileMovePlanner(fileSystem: fileSystem).plan(
                sources: sources, folder: rejects,
                maximumSuffixAttempts: RejectMovePlanner.maximumSuffixAttempts)
        else {
            throw PhotoSetMoveError.notConfirmed("Every rejects destination name is taken.")
        }
        let relative = row.destinationRelativeFolder
        let rejectsRelative = relative.isEmpty ? actualName : relative + "/" + actualName
        let stem = sources[0].deletingPathExtension().lastPathComponent
        return RenameReplacement(
            identity: PhotoIdentity(
                folderID: row.id.folderID, relativeFolderPath: relative, stem: stem),
            stem: stem,
            files: moves.map { RenameFile(source: $0.source, destination: $0.destination) },
            rejectsRelativeFolder: rejectsRelative)
    }

    private static func rank(_ url: URL) -> Int {
        switch PhotoFile(url: url)?.format {
        case .raw: 0
        case .jpeg: 1
        case .heif: 2
        case nil: 3
        }
    }
}

extension PhotoFileSystem {
    /// An existing child in its actual spelling; refuses an ambiguous case-sensitive folder.
    func child(named name: String, in folder: URL) throws -> URL? {
        let matches = try contentsOfDirectory(at: folder).filter {
            $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw PhotoSetMoveError.notConfirmed("Several entries match \(name).")
        }
        return matches.first
    }
}
