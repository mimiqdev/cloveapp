import CloveCore
import Foundation

/// The in-memory library the UI test and previews browse (PRD P0-13).
///
/// It stands in for folder access, the scan, the order and writes until U2 and U3 replace the
/// ``FolderLibrary`` seam. It holds one fake folder with a few dozen photos, some marks and two
/// groups, keeps every change in memory, and writes nothing anywhere.
///
/// The sample is selected with the launch environment value ``launchVariable``; without it the
/// app browses an empty library and entry says no folder is open.
@MainActor
final class TestLibrary: FolderLibrary {
    /// The launch environment value that selects the sample library: set it to `1`.
    static let launchVariable = "CLOVE_TEST_LIBRARY"

    /// The library this launch browses: the sample when the launch value asks for it (PRD P0-13).
    static func forLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any FolderLibrary {
        environment[launchVariable] == "1" ? sample : TestLibrary()
    }

    /// The fake folder's durable key, spelled so a saved scene never looks like a real folder.
    static let folderKey = FolderIdentity(rawValue: "clove.test-library")

    let folder = TestLibrary.folderKey
    let groups: [BrowsingGroup]

    private var stored: [GridPhoto]

    /// The folder's photos with their marks, in the sample's capture order (PRD P0-03).
    var photos: [GridPhoto] { stored }

    /// An empty library: no folder holds anything until entry opens one.
    init() {
        stored = []
        groups = []
    }

    /// A fixed library, for the sample below and the previews.
    init(photos: [GridPhoto], groups: [BrowsingGroup]) {
        stored = photos
        self.groups = groups
    }

    /// Applies marks to one photo, keeping them for the rest of the run (PRD P0-05).
    func apply(_ marks: PhotoMarks, to photo: PhotoIdentity) {
        guard let index = stored.firstIndex(where: { $0.id == photo }) else { return }
        stored[index].marks = marks
    }

    /// The sample: 36 photos across two capture folders, a few marks and two bursts (PRD P0-03).
    static var sample: TestLibrary {
        let captureBase = Date(timeIntervalSince1970: 1_760_000_000)
        let photos = (0..<36).map { index -> GridPhoto in
            let stem = String(format: "MMQ%05d", 2678 + index)
            let path = index < 18 ? "DCIM/100CAM" : "DCIM/101CAM"
            let id = PhotoIdentity(
                folderID: folderKey, relativeFolderPath: path, stem: stem)
            return GridPhoto(
                id: id,
                fileName: "\(stem).ARW",
                time: .known(
                    PhotoTime(
                        captureTime: captureBase.addingTimeInterval(Double(index) * 4),
                        hasUTCOffset: true)),
                marks: sampleMarks[index])
        }
        return TestLibrary(photos: photos, groups: sampleGroups)
    }

    /// Two bursts from the sample, so the grid offers a group view (PRD P0-11).
    private static var sampleGroups: [BrowsingGroup] {
        [
            BrowsingGroup(
                id: GroupID(rawValue: "burst-2678"),
                members: samplePhotos(2678...2680)),
            BrowsingGroup(
                id: GroupID(rawValue: "burst-2696"),
                members: samplePhotos(2696...2698)),
        ]
    }

    /// Identities of the sample photos for the given stems, in ascending order.
    private static func samplePhotos(_ numbers: ClosedRange<Int>) -> [PhotoIdentity] {
        numbers.map { number in
            PhotoIdentity(
                folderID: folderKey,
                relativeFolderPath: number < 2696 ? "DCIM/100CAM" : "DCIM/101CAM",
                stem: String(format: "MMQ%05d", number))
        }
    }

    /// A few saved marks, so the flow has something to show (PRD P0-05).
    private static let sampleMarks: [PhotoMarks] = {
        var marks = Array(repeating: PhotoMarks(), count: 36)
        marks[0] = PhotoMarks(rating: stars(5), label: ColourLabel(colour: .red))
        marks[1] = PhotoMarks(rating: stars(3))
        marks[4] = PhotoMarks(label: ColourLabel(colour: .green))
        marks[7] = PhotoMarks(isRejected: true)
        marks[21] = PhotoMarks(rating: stars(2), label: ColourLabel(colour: .purple))
        return marks
    }()

    /// A rating for the sample, which only uses values the camera's 0–5 range holds (PRD P0-05).
    private static func stars(_ count: Int) -> Rating {
        guard let rating = Rating(rawValue: count) else {
            preconditionFailure("a sample rating must be within 0–5")
        }
        return rating
    }
}
