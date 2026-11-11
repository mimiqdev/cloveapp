import Foundation
import Testing

import CloveCore

private let directory = URL(fileURLWithPath: "/Photos/DCIM/100CAM", isDirectory: true)
private let folderID = FolderIdentity(rawValue: "bookmark-folder-key")

private struct FileCombination: Sendable {
    let raw: Bool
    let jpeg: Bool
    let heif: Bool
    let primary: PhotoFormat

    static let all: [Self] = [
        Self(raw: true, jpeg: false, heif: false, primary: .raw),
        Self(raw: true, jpeg: true, heif: false, primary: .raw),
        Self(raw: true, jpeg: false, heif: true, primary: .raw),
        Self(raw: true, jpeg: true, heif: true, primary: .raw),
        Self(raw: false, jpeg: true, heif: false, primary: .jpeg),
        Self(raw: false, jpeg: false, heif: true, primary: .heif),
        // Unsupported JPEG+HIF follows generic precedence; it has no special policy.
        Self(raw: false, jpeg: true, heif: true, primary: .jpeg),
    ]

    func photo(rawExtension: String = "ARW", heifExtension: String = "HIF") throws -> PhotoSet {
        try PhotoSet(
            folderID: folderID, relativeFolderPath: "DCIM/100CAM",
            rawURL: raw ? directory.appendingPathComponent("IMG_0001.\(rawExtension)") : nil,
            jpegURL: jpeg ? directory.appendingPathComponent("img_0001.JpEg") : nil,
            heifURL: heif ? directory.appendingPathComponent("Img_0001.\(heifExtension)") : nil)
    }
}

@Test(arguments: FileCombination.all)
private func primarySelectionAndEveryMarkDestination(combination: FileCombination) throws {
    let photo = try combination.photo()
    #expect(photo.primary.format == combination.primary)
    #expect(
        photo.imageFiles.count
            == [combination.raw, combination.jpeg, combination.heif].filter { $0 }.count)
    #expect((photo.jpegCompanion != nil) == (combination.raw && combination.jpeg))
    #expect((photo.heifCompanion != nil) == (combination.heif && combination.primary != .heif))
    #expect(photo.role(of: photo.primary) == .primary)
    if let jpeg = photo.jpegCompanion { #expect(photo.role(of: jpeg) == .jpegCompanion) }
    if let heif = photo.heifCompanion { #expect(photo.role(of: heif) == .heifCompanion) }
    let other = try #require(PhotoFile(url: directory.appendingPathComponent("other.ARW")))
    #expect(photo.role(of: other) == nil)

    let expected: MarkDestination =
        combination.raw
        ? .xmpSidecar(directory.appendingPathComponent("IMG_0001.xmp")) : .cloveStorage
    #expect(photo.markPersistence.rating == expected)
    #expect(photo.markPersistence.label == expected)
    #expect(photo.markPersistence == MarkPersistence(for: photo))
    #expect(photo.sidecarURL == nil)
    #expect(photo.fileURLs == photo.imageFiles.map(\.url))
    #expect(!photo.fileURLs.contains { $0.pathExtension == "xmp" })
}

@Test(arguments: ["ARW", "arw"], ["HIF", "hif"])
private func extensionCaseNeverChangesActualSpelling(rawExtension: String, heifExtension: String)
    throws
{
    let combination = FileCombination(raw: true, jpeg: true, heif: true, primary: .raw)
    let photo = try combination.photo(rawExtension: rawExtension, heifExtension: heifExtension)
    #expect(photo.primary.url.lastPathComponent == "IMG_0001.\(rawExtension)")
    #expect(photo.jpegCompanion?.url.lastPathComponent == "img_0001.JpEg")
    #expect(photo.heifCompanion?.url.lastPathComponent == "Img_0001.\(heifExtension)")
    #expect(
        photo.markPersistence.rating
            == .xmpSidecar(directory.appendingPathComponent("IMG_0001.xmp")))
}

@Test private func discoveredSidecarSpellingAndMoveMembersArePreserved() throws {
    let raw = directory.appendingPathComponent("many.dots.ARW")
    let sidecar = directory.appendingPathComponent("MANY.DOTS.XMP")
    let jpeg = directory.appendingPathComponent("many.dots.jpg")
    let heif = directory.appendingPathComponent("many.dots.hif")
    let photo = try PhotoSet(
        folderID: folderID, relativeFolderPath: "DCIM/100CAM", rawURL: raw,
        jpegURL: jpeg, heifURL: heif, sidecarURL: sidecar)
    #expect(photo.sidecarURL == sidecar)
    #expect(photo.markPersistence.rating == .xmpSidecar(sidecar))
    #expect(photo.markPersistence.label == .xmpSidecar(sidecar))
    #expect(photo.fileURLs == [raw, jpeg, heif, sidecar])
    let newPhoto = try PhotoSet(folderID: folderID, relativeFolderPath: "DCIM/100CAM", rawURL: raw)
    #expect(
        newPhoto.markPersistence.rating
            == .xmpSidecar(directory.appendingPathComponent("many.dots.xmp")))
}

@Test private func standaloneDNGRemainsRAW() throws {
    let photo = try PhotoSet(
        folderID: folderID, relativeFolderPath: "",
        rawURL: directory.appendingPathComponent("ProRAW.DNG"))
    #expect(photo.primary.format == .raw)
    #expect(
        photo.markPersistence.rating == .xmpSidecar(directory.appendingPathComponent("ProRAW.xmp")))
    #expect(photo.markPersistence.label == photo.markPersistence.rating)
}

@Test private func invalidSetsAreRejectedWithoutIO() throws {
    #expect(throws: PhotoSetError.missingImage) {
        try PhotoSet(folderID: folderID, relativeFolderPath: "")
    }
    let raw = directory.appendingPathComponent("photo.ARW")
    #expect(throws: PhotoSetError.invalidFile(raw)) {
        try PhotoSet(folderID: folderID, relativeFolderPath: "", jpegURL: raw)
    }
    let unsupported = directory.appendingPathComponent("photo.mov")
    #expect(throws: PhotoSetError.invalidFile(unsupported)) {
        try PhotoSet(folderID: folderID, relativeFolderPath: "", rawURL: unsupported)
    }
    for jpeg in [
        directory.appendingPathComponent("other.jpg"), URL(fileURLWithPath: "/other/photo.jpg"),
    ] {
        #expect(throws: PhotoSetError.mismatchedMember(jpeg)) {
            try PhotoSet(folderID: folderID, relativeFolderPath: "", rawURL: raw, jpegURL: jpeg)
        }
    }
    for sidecar in [
        directory.appendingPathComponent("photo.ARW.xmp"),
        directory.appendingPathComponent("other.xmp"),
        directory.appendingPathComponent("photo.jpg"),
        URL(fileURLWithPath: "/other/photo.xmp"),
    ] {
        #expect(throws: PhotoSetError.invalidSidecar(sidecar)) {
            try PhotoSet(
                folderID: folderID, relativeFolderPath: "", rawURL: raw, sidecarURL: sidecar)
        }
    }
    for image in ["photo.jpg", "photo.hif"] {
        let url = directory.appendingPathComponent(image)
        let sidecar = directory.appendingPathComponent("photo.xmp")
        #expect(throws: PhotoSetError.invalidSidecar(sidecar)) {
            try PhotoSet(
                folderID: folderID, relativeFolderPath: "",
                jpegURL: image.hasSuffix("jpg") ? url : nil,
                heifURL: image.hasSuffix("hif") ? url : nil, sidecarURL: sidecar)
        }
    }
}
