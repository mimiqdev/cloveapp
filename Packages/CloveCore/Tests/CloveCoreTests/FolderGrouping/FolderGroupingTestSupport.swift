import Foundation
import Testing

import CloveCore

/// One scanned RAW set, built the way C2's walk builds one, for the grouping-input tests.
func folderGroupingItem(
    _ stem: String, path: String = "DCIM/100CAM", folder: FolderIdentity = groupingFolder
) throws -> ScanItem {
    let url = URL(fileURLWithPath: "/photos/\(path)/\(stem).ARW")
    let set = try PhotoSet(folderID: folder, relativeFolderPath: path, rawURL: url)
    let file = try #require(PhotoFile(url: url))
    return .photo(
        ScannedPhotoSet(
            photoSet: set, sidecar: .absent,
            imageFiles: [
                ScannedImageFile(
                    file: file, size: 40 * 1024, modificationDate: groupingBase)
            ]))
}

/// The identity the scan gives one stem below the grouping test folder.
func folderGroupingID(
    _ stem: String, path: String = "DCIM/100CAM", folder: FolderIdentity = groupingFolder
) -> PhotoIdentity {
    PhotoIdentity(folderID: folder, relativeFolderPath: path, stem: stem)
}
