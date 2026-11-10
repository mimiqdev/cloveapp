import Foundation
import Testing

import CloveCore

/// How the storages G1 routes each field to combine into the marks a cell shows
/// (PRD P0-05, P0-07; G1 decisions 2, 5–6).
@Suite("Marks composition")
struct PhotoMarksCompositionTests {
    private let folder = FolderIdentity(rawValue: "marks-composition-tests")

    /// The persistence of a RAW set, whose rating and label live in its sidecar (decision 2).
    private func rawPersistence() throws -> MarkPersistence {
        let set = try PhotoSet(
            folderID: folder, relativeFolderPath: "DCIM/100CAM",
            rawURL: URL(fileURLWithPath: "/photos/DCIM/100CAM/MMQ05184.ARW"))
        return set.markPersistence
    }

    /// The persistence of a standalone JPEG, whose marks stay in Clove (decision 6).
    private func standalonePersistence() throws -> MarkPersistence {
        let set = try PhotoSet(
            folderID: folder, relativeFolderPath: "DCIM/100CAM",
            jpegURL: URL(fileURLWithPath: "/photos/DCIM/100CAM/IMG_0001.JPG"))
        return set.markPersistence
    }

    @Test func nothingReadReadsAsUnmarked() throws {
        let marks = PhotoMarks(stored: nil, xmp: nil, persistence: try rawPersistence())
        #expect(marks == PhotoMarks())
    }

    @Test func aRawSetsSidecarWinsAndRejectComesFromClove() throws {
        let marks = PhotoMarks(
            stored: CloveStoredMarks(isRejected: true),
            xmp: XMPMarks(
                rating: .rated(Rating(rawValue: 4) ?? .unrated),
                label: ColourLabel(colour: .red)),
            persistence: try rawPersistence())

        #expect(marks.rating.rawValue == 4)
        #expect(marks.label.colour == .red)
        #expect(marks.isRejected)
    }

    @Test func anExplicitSidecarClearNeverRevivesStoredMarks() throws {
        // A previously marked standalone JPEG keeps its identity when a RAW joins it, so Clove
        // may still hold the old marks. The RAW's explicit clear is the user's choice (decision 2).
        let marks = PhotoMarks(
            stored: CloveStoredMarks(
                rating: Rating(rawValue: 3) ?? .unrated, label: ColourLabel(colour: .green)),
            xmp: XMPMarks(rating: .rated(.unrated), label: .clear),
            persistence: try rawPersistence())

        #expect(marks.rating == .unrated)
        #expect(marks.label.isClear)
    }

    @Test func aStandaloneSetKeepsItsCloveStoredMarks() throws {
        let marks = PhotoMarks(
            stored: CloveStoredMarks(
                rating: Rating(rawValue: 3) ?? .unrated, label: ColourLabel(colour: .green)),
            xmp: XMPMarks(rating: .rated(Rating(rawValue: 5) ?? .unrated)),
            persistence: try standalonePersistence())

        // A standalone set is never given a sidecar, so a packet cannot override Clove (decision 6).
        #expect(marks.rating.rawValue == 3)
        #expect(marks.label.colour == .green)
        #expect(!marks.isRejected)
    }

    @Test func anExternalRatingIsNeverReject() throws {
        // G1 decision 5 keeps xmp:Rating −1 an external value, not Clove's Reject flag.
        let external = PhotoMarks(
            xmp: XMPMarks(rating: XMPRating(-1)), persistence: try rawPersistence())
        #expect(external.rating == .unrated)
        #expect(!external.isRejected)
    }

    @Test func anUnknownExternalLabelIsKept() throws {
        let marks = PhotoMarks(
            xmp: XMPMarks(label: ColourLabel(rawValue: "Chartreuse")),
            persistence: try rawPersistence())
        #expect(marks.label.rawValue == "Chartreuse")
        #expect(marks.label.colour == nil)
        #expect(!marks.label.isClear)
    }
}
