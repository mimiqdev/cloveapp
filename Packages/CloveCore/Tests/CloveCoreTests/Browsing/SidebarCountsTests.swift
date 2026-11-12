import CloveCore
import Testing

@Suite struct SidebarCountsTests {
    @Test func countsMarksAndExactContainingFolders() throws {
        let photos = [
            photo("a", time: .unavailable, path: "", marks: marks()),
            photo("b", time: .unavailable, path: "DCIM/10", marks: marks(rejected: true)),
            photo("c", time: .unavailable, path: "DCIM/2", marks: marks(stars: 2)),
            photo(
                "d", time: .unavailable, path: "DCIM/2",
                marks: marks(stars: 5, label: ColourLabel(colour: .red))),
            photo(
                "e", time: .unavailable, path: "DCIM/2/child",
                marks: marks(label: ColourLabel(colour: .green))),
            photo(
                "f", time: .unavailable, path: "DCIM/10",
                marks: marks(label: ColourLabel(rawValue: "External"))),
            photo(
                "g", time: .unavailable, path: "DCIM/10",
                marks: marks(label: ColourLabel(colour: .blue), rejected: true)),
            photo(
                "h", time: .unavailable, path: "DCIM/10",
                marks: marks(label: ColourLabel(colour: .yellow))),
            photo(
                "i", time: .unavailable, path: "DCIM/10",
                marks: marks(label: ColourLabel(colour: .purple))),
        ]
        let counts = SidebarCounts(photos: photos)
        #expect(counts.all == 9)
        #expect(counts.unmarked == 1)
        #expect(counts.rejected == 2)
        for (minimum, expected) in [(1, 2), (2, 2), (3, 1), (4, 1), (5, 1)] {
            let rating = try #require(Rating(rawValue: minimum))
            #expect(counts.ratings[rating] == expected)
        }
        #expect(counts.labels == [.red: 1, .green: 1, .blue: 1, .yellow: 1, .purple: 1])
        #expect(counts.folders == ["": 1, "DCIM/2": 2, "DCIM/10": 5, "DCIM/2/child": 1])
        #expect(counts.subfolders == ["DCIM/2", "DCIM/2/child", "DCIM/10"])

        var changed = photos
        changed[0].marks = marks(stars: 3, label: ColourLabel(colour: .red))
        let updated = SidebarCounts(photos: changed)
        #expect(updated.unmarked == 0)
        #expect(updated.labels[.red] == 2)
        #expect(updated.ratings[try #require(Rating(rawValue: 3))] == 2)
    }

    @Test func emptyAndSingleFolderHaveNoInventedLocations() {
        let empty = SidebarCounts(photos: [])
        #expect(empty.all == 0)
        #expect(empty.subfolders.isEmpty)
        #expect(empty.labels.isEmpty)
        #expect(empty.ratings.values.allSatisfy { $0 == 0 })
        let single = SidebarCounts(photos: [photo("a", time: .unavailable, path: "DCIM/100CAM")])
        #expect(single.folders.count == 1)
        #expect(single.subfolders == ["DCIM/100CAM"])
    }

    @Test func subfolderFilterKeepsOnlyDirectPhotosInTheirOrder() {
        let photos = [
            photo("c", time: capture(seconds(3)), path: "DCIM/100CAM"),
            photo("a", time: capture(seconds(1)), path: "DCIM/100CAM"),
            photo("b", time: capture(seconds(2)), path: "DCIM/100CAM/child"),
            photo("d", time: .unavailable, path: "DCIM/101CAM"),
        ]
        let ordering = PhotoOrdering(photos: photos)
        #expect(ordering.photos(matching: .subfolder("DCIM/100CAM")).map(\.id.stem) == ["a", "c"])
        #expect(ordering.photos(matching: .subfolder("missing")).isEmpty)
    }

    @Test func subfolderRoundTripAndMissingFolderRestore() throws {
        var saved = BrowsingFixtures.saved
        saved.filter = .subfolder(BrowsingFixtures.beta.relativeFolderPath)
        let decoded = BrowsingState.decoded(from: try #require(saved.encoded()))
        #expect(decoded == saved)
        #expect(decoded.restored(from: .available(BrowsingFixtures.contents)).state == saved)
        saved.filter = .subfolder("gone")
        let restored = saved.restored(from: .available(BrowsingFixtures.contents)).state
        #expect(restored.filter == .all)
        #expect(restored.currentPhoto == saved.currentPhoto)
        #expect(restored.selection == saved.selection)
    }

    @Test func pendingSubfolderWaitsForItsPhotosOrScanEnd() {
        let shown = BrowsingState(folder: BrowsingFixtures.folder, route: .grid)
        var saved = shown
        saved.filter = .subfolder("DCIM/100CAM")
        let pending = PendingBrowsingRestore(saved: saved, shown: shown)
        let empty = FolderContents(folder: BrowsingFixtures.folder, photos: [])
        #expect(pending.decision(current: shown, contents: empty, scanFinished: false) == .wait)
        guard
            case .apply(let restored) = pending.decision(
                current: shown, contents: empty, scanFinished: true)
        else {
            Issue.record("A completed scan must resolve the missing subfolder")
            return
        }
        #expect(restored.state.filter == .all)
        let found = FolderContents(
            folder: BrowsingFixtures.folder,
            photos: [
                PhotoIdentity(
                    folderID: BrowsingFixtures.folder, relativeFolderPath: "DCIM/100CAM", stem: "a")
            ])
        #expect(
            pending.decision(current: shown, contents: found, scanFinished: false)
                == .apply(RestoredBrowsing(state: saved)))
    }
}
