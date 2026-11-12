import Foundation
import Testing

@testable import CloveCore

/// PRD In-group culling, comparison and elimination: moving inside one group's member order.
@Suite("Group photo navigation")
struct GroupPhotoNavigationTests {
    /// Four members: unmarked, rated, rejected and label-only, in member order.
    private let members = ["a", "b", "c", "d"].map { groupCullingPhoto($0) }
    private var group: SimilarGroup {
        groupCullingGroup("navigation", members: members)
    }
    private var marks: [PhotoIdentity: PhotoMarks] {
        groupCullingMarks([
            (members[0], PhotoMarks()),
            (members[1], PhotoMarks(rating: groupCullingRating(2))),
            (members[2], PhotoMarks(rating: .rejected)),
            (members[3], PhotoMarks(label: ColourLabel(colour: .blue))),
        ])
    }

    @Test func nextUndecidedWrapsToTheStartOfTheGroup() {
        let navigation = GroupPhotoNavigation(group: group)

        // d is the last member; the only earlier undecided photo is a.
        #expect(
            navigation.nextUndecidedPhoto(
                after: members[3], marks: marks, visiblePhotos: Set(members)) == members[0])
        #expect(
            navigation.nextUndecidedPhoto(
                after: members[1], marks: marks, visiblePhotos: Set(members)) == members[0])
    }

    @Test func nextUndecidedReturnsNothingWhenNoneIsLeft() {
        let navigation = GroupPhotoNavigation(group: group)
        let allMarked = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(1))),
            (members[1], PhotoMarks(rating: groupCullingRating(2))),
            (members[2], PhotoMarks(rating: .rejected)),
            (members[3], PhotoMarks(rating: groupCullingRating(5))),
        ])

        // PRD In-group culling: after marking, there is no next undecided photo.
        #expect(
            navigation.nextUndecidedPhoto(
                after: members[0], marks: allMarked, visiblePhotos: Set(members)) == nil)

        // The current photo is never its own answer, even when it is still undecided.
        let onlyCurrentUndecided = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(2))),
            (members[1], PhotoMarks()),
            (members[2], PhotoMarks(rating: .rejected)),
            (members[3], PhotoMarks(rating: groupCullingRating(4))),
        ])
        #expect(
            navigation.nextUndecidedPhoto(
                after: members[1], marks: onlyCurrentUndecided, visiblePhotos: Set(members)) == nil)
        #expect(
            navigation.nextUndecidedPhoto(
                after: members[1], marks: onlyCurrentUndecided, visiblePhotos: Set(members))
                != members[1])
    }

    @Test func advanceVisitsUnmarkedMembersThenTheNextGridCellIncludingAfterFinishing() {
        let outside = groupCullingPhoto("outside")
        let ordered = [members[0], outside, members[1], members[2], members[3]].map {
            GridPhoto(id: $0, fileName: $0.stem, time: .pending)
        }
        let groups = [BrowsingGroup(id: group.id, members: members)]
        let visible = Set(ordered.map(\.id))
        let navigation = GroupPhotoNavigation(group: group)
        let next = navigation.advance(
            after: members[3], marks: marks, orderedPhotos: ordered,
            groups: groups, visiblePhotos: visible)
        #expect(next == .nextUndecidedPhoto(members[0]))
        let rules = MarkingInputRules(settings: AppSettings())
        #expect(
            rules.autoAdvancePlan(after: .reject, from: members[3], photos: ordered, group: next)
                .target == .groupUndecidedPhoto(members[0]))

        var completed = marks
        completed[members[0]] = PhotoMarks(rating: .rejected)
        #expect(
            navigation.advance(
                after: members[0], marks: completed, orderedPhotos: ordered,
                groups: groups, visiblePhotos: visible) == .nextUndecidedPhoto(outside))
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: members[0], marks: marks)
        for change in plan.changes {
            completed[change.photo] = change.marksBefore.applying(change.change)
        }
        #expect(
            navigation.advance(
                after: members[0], marks: completed, orderedPhotos: ordered,
                groups: groups, visiblePhotos: [outside]) == .nextUndecidedPhoto(outside))
        #expect(
            navigation.photoAfterGroup(orderedPhotos: ordered, groups: groups, visiblePhotos: [])
                == nil)
    }

    @Test func ratingFilterLimitsGroupEntryAdvanceAndFinishing() {
        let outside = groupCullingPhoto("outside")
        let marks = [
            members[0]: PhotoMarks(rating: groupCullingRating(5)),
            outside: PhotoMarks(rating: groupCullingRating(3)),
        ]
        let photos = (members + [outside]).map {
            GridPhoto(id: $0, fileName: $0.stem, time: .pending, marks: marks[$0] ?? PhotoMarks())
        }
        let filter = PhotoFilter.ratedAtLeast(groupCullingRating(3))
        let visible = Set(photos.filter { filter.matches($0.marks) }.map(\.id))
        let published = BrowsingGroup(id: group.id, members: members)
        let shown = published.visible(in: visible)
        #expect(shown.members == [members[0]])
        #expect(
            (shown.members.first { (marks[$0] ?? PhotoMarks()).isUnmarked } ?? shown.members.first)
                == members[0])
        let navigation = GroupPhotoNavigation(group: published)
        #expect(
            navigation.nextUndecidedPhoto(after: members[0], marks: marks, visiblePhotos: visible)
                == nil)
        #expect(
            navigation.advance(
                after: members[0], marks: marks, orderedPhotos: photos,
                groups: [published], visiblePhotos: visible) == .nextUndecidedPhoto(outside))
        let plan = GroupFinishingPlan(
            group: shown, action: .rejectUnmarked, currentPhoto: members[0], marks: marks)
        #expect(plan.isEmpty)
        #expect(
            GroupFinishingPlan(
                group: published, action: .rejectUnmarked,
                currentPhoto: members[0], marks: marks
            ).rejects.count == 3)
    }

    @Test func aPhotoOutsideTheGroupHasNoNeighbours() {
        let navigation = GroupPhotoNavigation(group: group)
        let outsider = groupCullingPhoto("outsider")

        #expect(
            navigation.nextUndecidedPhoto(
                after: outsider, marks: marks, visiblePhotos: Set(members)) == nil)
    }
}
