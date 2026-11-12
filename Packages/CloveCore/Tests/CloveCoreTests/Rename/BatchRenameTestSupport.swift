import Foundation

@testable import CloveCore

struct RenameFixture {
    let folder: MoveTestFolder
    let fileSystem: PhotoFileSystemDouble
    let store: CloveMarkStore
    let renamer: BatchRenamer

    init(markFileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem()) throws {
        folder = try MoveTestFolder()
        fileSystem = PhotoFileSystemDouble()
        store = CloveMarkStore(directory: folder.storage, fileSystem: markFileSystem)
        renamer = BatchRenamer(store: store, fileSystem: fileSystem)
    }

    func item(
        _ stem: String, path: String = "", formats: [PhotoFormat] = [.raw],
        sidecar: String? = nil, captureWallTime: Date? = nil
    ) throws -> RenameItem {
        let set = try makeMoveSet(
            root: folder.url, relativePath: path, stem: stem, formats: formats,
            sidecarName: sidecar)
        try writeMoveSet(set, in: folder)
        return RenameItem(set: set, captureWallTime: captureWallTime)
    }

    func plan(
        _ items: [RenameItem], template: RenameTemplate = RenameTemplate(),
        destination: RenameDestination = .inPlace, timeZone: TimeZone = .gmt,
        rejectsFolderName: RejectsFolderName = .defaultFolderName
    ) -> BatchRenamePlan {
        BatchRenamePlanner(fileSystem: fileSystem).plan(
            for: BatchRenameRequest(
                rootURL: folder.url, items: items, template: template,
                destination: destination, timeZone: timeZone, rejectsFolderName: rejectsFolderName))
    }

    func identity(_ stem: String, path: String = "") -> PhotoIdentity {
        PhotoIdentity(
            folderID: FolderIdentity(rawValue: "folder-1"), relativeFolderPath: path, stem: stem)
    }

    func cleanup() { folder.remove() }
}
