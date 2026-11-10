import Foundation
import Testing

import CloveCore

/// The revision a folder's group cache is keyed by (PRD Similar groups rules, PRD P0-11).
@Suite("Grouping input revision")
struct GroupingInputRevisionTests {
    private static let feature = "preview:400|feature:2"

    @Test func ignoresTheOrderTheScanDeliveredTheSetsIn() throws {
        let one = try folderGroupingSet("a")
        let two = try folderGroupingSet("b")

        let forward = GroupingInputRevision.scanned([one, two], feature: Self.feature)
        let backward = GroupingInputRevision.scanned([two, one], feature: Self.feature)

        #expect(forward == backward)
    }

    @Test func changesWhenAPrimaryFileChanges() throws {
        // A file replaced in place keeps its name and metadata keys but changes size or date.
        let before = try folderGroupingSet("a", size: 40 * 1024)
        let resized = try folderGroupingSet("a", size: 41 * 1024)
        let rewritten = try folderGroupingSet(
            "a", modified: groupingBase.addingTimeInterval(60))

        let original = GroupingInputRevision.scanned([before], feature: Self.feature)

        #expect(GroupingInputRevision.scanned([resized], feature: Self.feature) != original)
        #expect(GroupingInputRevision.scanned([rewritten], feature: Self.feature) != original)
    }

    @Test func changesWithTheFeatureToken() throws {
        let set = try folderGroupingSet("a")

        let visionTwo = GroupingInputRevision.scanned([set], feature: Self.feature)
        let otherPreview = GroupingInputRevision.scanned([set], feature: "preview:800|feature:2")

        #expect(visionTwo != otherPreview)
    }

    @Test func keepsOneSetInOneFolderStable() throws {
        let set = try folderGroupingSet("a")
        let otherFolder = try folderGroupingSet(
            "a", folder: FolderIdentity(rawValue: "another-folder"))

        #expect(
            GroupingInputRevision.scanned([set], feature: Self.feature)
                != GroupingInputRevision.scanned([otherFolder], feature: Self.feature))
    }
}
