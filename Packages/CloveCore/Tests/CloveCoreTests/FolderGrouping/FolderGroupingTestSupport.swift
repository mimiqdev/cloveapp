import Foundation
import Testing

import CloveCore

/// One scanned RAW set, built the way C2's walk builds one, for the grouping-input tests.
func folderGroupingSet(
    _ stem: String, path: String = "DCIM/100CAM", folder: FolderIdentity = groupingFolder,
    size: Int? = 40 * 1024, modified: Date? = groupingBase
) throws -> ScannedPhotoSet {
    let url = URL(fileURLWithPath: "/photos/\(path)/\(stem).ARW")
    let set = try PhotoSet(folderID: folder, relativeFolderPath: path, rawURL: url)
    let file = try #require(PhotoFile(url: url))
    return ScannedPhotoSet(
        photoSet: set, sidecar: .absent,
        imageFiles: [ScannedImageFile(file: file, size: size, modificationDate: modified)])
}

/// The scan item of one set, as a batch delivers it.
func folderGroupingItem(
    _ stem: String, path: String = "DCIM/100CAM", folder: FolderIdentity = groupingFolder,
    size: Int? = 40 * 1024, modified: Date? = groupingBase
) throws -> ScanItem {
    .photo(
        try folderGroupingSet(
            stem, path: path, folder: folder, size: size, modified: modified))
}

/// The identity the scan gives one stem below the grouping test folder.
func folderGroupingID(
    _ stem: String, path: String = "DCIM/100CAM", folder: FolderIdentity = groupingFolder
) -> PhotoIdentity {
    PhotoIdentity(folderID: folder, relativeFolderPath: path, stem: stem)
}
