import Foundation
import Testing

import CloveCore

@Test func identitySurvivesRescansAndMembershipChanges() throws {
    let folder = FolderIdentity(rawValue: "opaque-bookmark-key")
    let directory = URL(fileURLWithPath: "/Photos/DCIM/100CAM", isDirectory: true)
    let alone = try PhotoSet(
        folderID: folder, relativeFolderPath: "DCIM/100CAM",
        jpegURL: directory.appendingPathComponent("img_0001.JPG"))
    let raw = try PhotoSet(
        folderID: folder, relativeFolderPath: "DCIM/100CAM",
        rawURL: directory.appendingPathComponent("IMG_0001.ARW"))
    let triple = try PhotoSet(
        folderID: folder, relativeFolderPath: "DCIM/100CAM",
        rawURL: directory.appendingPathComponent("IMG_0001.arw"),
        jpegURL: directory.appendingPathComponent("img_0001.JPG"),
        heifURL: directory.appendingPathComponent("Img_0001.HIF"),
        sidecarURL: directory.appendingPathComponent("IMG_0001.XMP"))
    #expect(alone.id == raw.id)
    #expect(raw.id == triple.id)
    #expect(
        triple.id
            == PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: "IMG_0001"))
    #expect(Set([alone.id, raw.id, triple.id]).count == 1)
    #expect([raw.id: PhotoMarks(rating: .rejected)][triple.id]?.isRejected == true)
}

@Test func identitySeparatesFoldersSubfoldersAndStems() {
    let folder = FolderIdentity(rawValue: "card-one")
    let id = PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: "IMG_0001")
    #expect(
        id
            != PhotoIdentity(
                folderID: FolderIdentity(rawValue: "card-two"), relativeFolderPath: "DCIM/100CAM",
                stem: "IMG_0001"))
    #expect(
        id != PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/101CAM", stem: "IMG_0001"))
    #expect(
        id != PhotoIdentity(folderID: folder, relativeFolderPath: "DCIM/100CAM", stem: "IMG_0002"))
    #expect(id != PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "IMG_0001"))
}

@Test func sessionDisplayHintsNeverEstablishIdentity() {
    let folder = FolderIdentity(rawValue: "persistent-key")
    var session = FolderSession(
        id: folder, displayURL: URL(fileURLWithPath: "/Volumes/CARD"), displayName: "CARD")
    session.displayURL = URL(fileURLWithPath: "/Volumes/CARD 1")
    session.displayName = "Renamed card"
    #expect(session.id == FolderIdentity(rawValue: "persistent-key"))
    let other = FolderSession(
        id: FolderIdentity(rawValue: "other-key"), displayURL: session.displayURL,
        displayName: session.displayName)
    #expect(session.id != other.id)
    #expect(folder.rawValue == "persistent-key")
}

// These generic constraints are compile-time checks of the entire public model surface.
@Test func domainValuesAreSendableAndHashable() {
    func requireValue<T: Sendable & Hashable>(_: T.Type) {}
    requireValue(FolderIdentity.self)
    requireValue(FolderSession.self)
    requireValue(PhotoIdentity.self)
    requireValue(PhotoFile.self)
    requireValue(PhotoFileRole.self)
    requireValue(PhotoFormat.self)
    requireValue(PhotoSet.self)
    requireValue(Rating.self)
    requireValue(LabelColour.self)
    requireValue(ColourLabel.self)
    requireValue(PhotoMarks.self)
    requireValue(MarkDestination.self)
    requireValue(MarkPersistence.self)
}
