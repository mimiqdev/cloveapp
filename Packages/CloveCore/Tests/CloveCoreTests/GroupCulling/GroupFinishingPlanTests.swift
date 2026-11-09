import Foundation
import Testing

@testable import CloveCore

/// PRD In-group culling, finishing actions, and PRD P0-12: the plan each action produces.
@Suite("Group finishing plans")
struct GroupFinishingPlanTests {
    @Test func keepThisGivesAnUnratedPhotoTheLowestEnabledRating() throws {
        let current = groupCullingPhoto("current")
        let other = groupCullingPhoto("other")
        let group = groupCullingGroup("keep", members: [current, other])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: current,
            marks: [
                current: PhotoMarks(label: ColourLabel(colour: .blue)),
                other: PhotoMarks(rating: groupCullingRating(3)),
            ],
            enabledRatings: groupCullingTwoAndFour)

        #expect(plan.availability == .available)
        #expect(plan.groupID == group.id)
        #expect(plan.action == .keepThis)
        #expect(plan.currentPhoto == current)
        #expect(plan.keepRating == groupCullingRating(2))

        let kept = try #require(plan.keptPhoto)
        // PRD In-group culling, finishing actions: the lowest enabled level, not the default 1.
        #expect(kept.change == MarkChange(rating: groupCullingRating(2)))
        #expect(kept.marksBefore == PhotoMarks(label: ColourLabel(colour: .blue)))
        #expect(plan.rejects.isEmpty)
    }

    @Test func keepThisLeavesARatedPhotoUnchanged() {
        let current = groupCullingPhoto("current")
        let other = groupCullingPhoto("other")
        let group = groupCullingGroup("rated", members: [current, other])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: current,
            marks: [
                current: PhotoMarks(rating: groupCullingRating(4)),
                other: PhotoMarks(),
            ],
            enabledRatings: groupCullingTwoAndFour)

        // PRD In-group culling: an existing rating is left alone, and the other unmarked
        // photo is rejected.
        #expect(plan.keptPhoto == nil)
        #expect(plan.rejects.map(\.photo) == [other])
        #expect(plan.rejects.first?.change == MarkChange(reject: true))
    }

    @Test func keepThisClearsRejectAndKeepsAnExistingRating() throws {
        let current = groupCullingPhoto("current")
        let other = groupCullingPhoto("other")
        let group = groupCullingGroup("rejected", members: [current, other])

        let rated = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: current,
            marks: [
                current: PhotoMarks(
                    rating: groupCullingRating(3), isRejected: true),
                other: PhotoMarks(isRejected: true),
            ],
            enabledRatings: groupCullingTwoAndFour)
        let keptRated = try #require(rated.keptPhoto)
        // "Keep" means keep, so Reject is cleared and the rating stays (PRD In-group culling).
        #expect(keptRated.change == MarkChange(reject: false))

        let unrated = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: current,
            marks: [current: PhotoMarks(isRejected: true), other: PhotoMarks()],
            enabledRatings: groupCullingTwoAndFour)
        let keptUnrated = try #require(unrated.keptPhoto)
        #expect(
            keptUnrated.change
                == MarkChange(rating: groupCullingRating(2), reject: false))
    }

    @Test func keepThisWithNothingToChangeIsEmpty() {
        let current = groupCullingPhoto("current")
        let other = groupCullingPhoto("other")
        let group = groupCullingGroup("nothing", members: [current, other])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: current,
            marks: [
                current: PhotoMarks(rating: groupCullingRating(5)),
                other: PhotoMarks(label: ColourLabel(colour: .red)),
            ],
            enabledRatings: groupCullingTwoAndFour)

        #expect(plan.availability == .available)
        #expect(plan.isEmpty)
        #expect(plan.keptPhoto == nil)
        #expect(plan.rejects.isEmpty)
    }

    @Test func keepRatedIsUnavailableWithoutARatedPhoto() {
        let members = ["a", "b", "c", "d"].map { groupCullingPhoto($0) }
        let group = groupCullingGroup("unrated", members: members)
        let marks = groupCullingMarks([
            (members[0], PhotoMarks()),
            (members[1], PhotoMarks(label: ColourLabel(colour: .green))),
            (members[2], PhotoMarks(isRejected: true)),
            (members[3], PhotoMarks()),
        ])

        let plan = GroupFinishingPlan(
            group: group,
            action: .keepRated,
            currentPhoto: members[0],
            marks: marks,
            enabledRatings: groupCullingTwoAndFour)

        // PRD In-group culling: unavailable when no photo in the group is rated.
        #expect(plan.availability == .noRatedPhoto)
        #expect(!plan.availability.isAvailable)
        #expect(plan.isEmpty)
    }

    @Test func keepRatedRejectsOnlyUnmarkedPhotos() {
        let members = ["rated", "labelled", "rejected", "undecided"].map {
            groupCullingPhoto($0)
        }
        let group = groupCullingGroup("rated-kept", members: members)
        let marks = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(5))),
            (members[1], PhotoMarks(label: ColourLabel(colour: .yellow))),
            (members[2], PhotoMarks(isRejected: true)),
            (members[3], PhotoMarks()),
        ])

        let plan = GroupFinishingPlan(
            group: group,
            action: .keepRated,
            currentPhoto: members[3],
            marks: marks,
            enabledRatings: groupCullingTwoAndFour)

        #expect(plan.availability == .available)
        #expect(plan.keptPhoto == nil)
        // Keep rated acts on the whole group, so an unmarked current photo is rejected too.
        #expect(plan.rejects.map(\.photo) == [members[3]])
        #expect(plan.rejects.allSatisfy { $0.marksBefore.isUnmarked })
    }

    @Test func neitherActionRejectsRatedOrLabelledPhotosInALargeGroup() {
        let members = (0..<24).map { groupCullingPhoto(String(format: "photo-%02d", $0)) }
        let group = groupCullingGroup("large", members: members)
        var entries: [(PhotoIdentity, PhotoMarks)] = []
        for index in 0..<6 {
            entries.append((members[index], PhotoMarks(rating: groupCullingRating(2))))
        }
        for index in 6..<12 {
            entries.append(
                (members[index], PhotoMarks(label: ColourLabel(colour: .purple))))
        }
        for index in 12..<16 {
            entries.append((members[index], PhotoMarks(isRejected: true)))
        }
        let unmarked = Array(members[16...])
        let marks = groupCullingMarks(entries)

        let keepThis = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: marks,
            enabledRatings: groupCullingTwoAndFour)
        let keepRated = GroupFinishingPlan(
            group: group,
            action: .keepRated,
            currentPhoto: members[0],
            marks: marks,
            enabledRatings: groupCullingTwoAndFour)

        // PRD P0-12: in a group of 20 or more, neither action rejects a rated or labelled
        // photo, and the unmarked photos are exactly what is rejected.
        #expect(keepThis.rejects.map(\.photo) == unmarked)
        #expect(keepRated.rejects.map(\.photo) == unmarked)
        #expect(keepThis.rejects.allSatisfy { $0.change == MarkChange(reject: true) })
        #expect(keepRated.rejects.allSatisfy { $0.change == MarkChange(reject: true) })
        #expect(
            keepThis.changes.allSatisfy { change in
                group.members.contains(change.photo)
            })
        #expect(
            keepRated.changes.allSatisfy { change in
                group.members.contains(change.photo)
            })
    }

    @Test func keepThisIsUnavailableWhenTheCurrentPhotoIsOutsideTheGroup() {
        let first = groupCullingPhoto("first")
        let second = groupCullingPhoto("second")
        let outsider = groupCullingPhoto("outsider")
        let group = groupCullingGroup("outside", members: [first, second])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: outsider,
            marks: [first: PhotoMarks(), second: PhotoMarks(), outsider: PhotoMarks()],
            enabledRatings: groupCullingTwoAndFour)

        // PRD P0-12: keeping nothing and rejecting the whole group is not Keep this, which can
        // happen after C9 refinement moves the viewed photo (PRD P0-11).
        #expect(plan.availability == .currentPhotoNotInGroup)
        #expect(!plan.availability.isAvailable)
        #expect(plan.isEmpty)
        #expect(plan.keptPhoto == nil)
        #expect(plan.rejects.isEmpty)
    }

    @Test func plansNeverIncludePhotosOutsideTheGroup() {
        let first = groupCullingPhoto("first")
        let second = groupCullingPhoto("second")
        let outsider = groupCullingPhoto("outsider")
        let group = groupCullingGroup("bounded", members: [first, second])
        let marks = [
            first: PhotoMarks(rating: groupCullingRating(1)),
            second: PhotoMarks(),
            outsider: PhotoMarks(),
        ]

        // The current photo is a member, so Keep this plans inside the group only.
        let keepThis = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: first,
            marks: marks,
            enabledRatings: groupCullingTwoAndFour)
        // Keep rated has no keep change, so an outside current photo does not make it
        // unavailable; it still plans only members.
        let keepRated = GroupFinishingPlan(
            group: group,
            action: .keepRated,
            currentPhoto: outsider,
            marks: marks,
            enabledRatings: groupCullingTwoAndFour)

        #expect(keepThis.changes.map(\.photo) == [second])
        #expect(keepRated.changes.map(\.photo) == [second])
        for change in keepThis.changes + keepRated.changes {
            #expect(group.members.contains(change.photo))
            #expect(change.photo != outsider)
        }
    }
}
