import Foundation
import Testing

import CloveCore

/// Which photos grouping's step 3 actually compares (PRD Similar groups steps 2–3).
@Suite("Grouping feature candidates")
struct GroupingFeatureCandidatesTests {
    @Test func selectsThePhotosOfATimeRun() {
        let photos = [
            groupingPhoto("a", at: 0),
            groupingPhoto("b", at: 0.4),
            groupingPhoto("c", at: 0.8),
        ]

        let candidates = GroupingFeatureCandidates.photos(in: photos)

        #expect(candidates.map(\.id) == photos.map(\.id))
    }

    @Test func leavesOutAPhotoWithNoNeighbourWithinTheGap() {
        let photos = [
            groupingPhoto("a", at: 0),
            groupingPhoto("b", at: 0.4),
            // G1's 2 s starting gap puts this photo in a run of its own.
            groupingPhoto("alone", at: 10),
        ]

        let candidates = GroupingFeatureCandidates.photos(in: photos)

        #expect(candidates.map(\.id.stem) == ["a", "b"])
    }

    @Test func leavesOutPhotosGroupingNeverGroups() {
        let fallback = groupingPhoto(
            "fallback", at: 0.6,
            time: .known(PhotoTime(fileCreation: groupingSeconds(0.6))))
        let photos = [
            groupingPhoto("a", at: 0),
            groupingPhoto("b", at: 0.4),
            fallback,
            // Same instants as the run, but no model means no body bucket can hold it.
            groupingPhoto("no-model", at: 0.5, model: nil),
        ]

        let candidates = GroupingFeatureCandidates.photos(in: photos)

        #expect(candidates.map(\.id.stem) == ["a", "b"])
    }

    @Test func keepsTwoBodiesApart() {
        // One photo per body within the gap is two runs of one, so neither needs features.
        let photos = [
            groupingPhoto("one", at: 0, serial: "1"),
            groupingPhoto("two", at: 0.4, serial: "2"),
        ]

        let candidates = GroupingFeatureCandidates.photos(in: photos)

        #expect(candidates.isEmpty)
    }

    @Test func ordersRunsAcrossBodiesByEarliestGridPhoto() {
        let photos = [
            groupingPhoto("b1", at: 10, model: "Alpha"),
            groupingPhoto("b2", at: 10.4, model: "Alpha"),
            groupingPhoto("a1", at: 0, model: "Zulu"),
            groupingPhoto("a2", at: 0.4, model: "Zulu"),
        ]

        let runs = GroupingFeatureCandidates.runs(in: photos)

        #expect(runs.map { $0.map(\.id.stem) } == [["a1", "a2"], ["b1", "b2"]])
    }
}
