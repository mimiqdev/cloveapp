import Testing

@testable import CloveCore

/// PRD In-group culling, group completion: when a group is finished and where the view goes.
@Suite("Group completion")
struct GroupCompletionTests {
    @Test func aGroupCompletesByItsMarksOnlyWhenEveryMemberIsRatedOrRejected() async {
        let tracker = GroupCompletionTracker()
        let members = ["a", "b", "c"].map { groupCullingPhoto($0) }
        let group = groupCullingGroup("marks", members: members)
        let partly = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(3))),
            (members[1], PhotoMarks(isRejected: true)),
            (members[2], PhotoMarks(label: ColourLabel(colour: .red))),
        ])
        let complete = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(3))),
            (members[1], PhotoMarks(isRejected: true)),
            (members[2], PhotoMarks(rating: groupCullingRating(1))),
        ])

        // PRD In-group culling, group completion: a label is still undecided.
        #expect(!(await tracker.isComplete(group, marks: partly)))
        #expect(await tracker.isComplete(group, marks: complete))
        #expect(!(await tracker.hasFinishingAction(on: group.id)))
    }

    @Test func aFinishingActionCompletesAGroupAndClearingItUndoesThat() async {
        let tracker = GroupCompletionTracker()
        let members = ["a", "b"].map { groupCullingPhoto($0) }
        let group = groupCullingGroup("action", members: members)
        let marks: [PhotoIdentity: PhotoMarks] = [:]

        #expect(!(await tracker.isComplete(group, marks: marks)))

        // PRD In-group culling: the action ran, so the group is complete even with no marks.
        await tracker.recordFinishingAction(on: group.id)
        #expect(await tracker.isComplete(group, marks: marks))
        #expect(await tracker.hasFinishingAction(on: group.id))

        // PRD P0-12: undoing the action clears the record.
        await tracker.clearFinishingAction(on: group.id)
        #expect(!(await tracker.isComplete(group, marks: marks)))
        #expect(!(await tracker.hasFinishingAction(on: group.id)))
    }

    @Test func theNextGroupSkipsCompletedGroupsAndStayReturnsNone() async {
        let tracker = GroupCompletionTracker()
        let first = groupCullingGroup("first", members: [groupCullingPhoto("a")])
        let second = groupCullingGroup(
            "second", members: [groupCullingPhoto("b"), groupCullingPhoto("c")])
        let third = groupCullingGroup(
            "third", members: [groupCullingPhoto("d"), groupCullingPhoto("e")])
        let fourth = groupCullingGroup(
            "fourth", members: [groupCullingPhoto("f"), groupCullingPhoto("g")])
        let groups = groupCullingGroups([first, second, third, fourth])
        let marks = groupCullingMarks([
            (second.members[0], PhotoMarks(rating: groupCullingRating(2))),
            (second.members[1], PhotoMarks(isRejected: true)),
        ])
        await tracker.recordFinishingAction(on: third.id)

        // PRD In-group culling: going to the next group skips completed groups.
        #expect(
            await tracker.nextIncompleteGroup(after: first.id, in: groups, marks: marks)
                == fourth)
        #expect(
            await tracker.groupAfterCompletion(
                of: first.id, in: groups, behaviour: .nextGroup, marks: marks)
                == fourth)
        // PRD In-group culling: staying keeps the completed group, so there is nowhere to go.
        #expect(
            await tracker.groupAfterCompletion(
                of: first.id, in: groups, behaviour: .stay, marks: marks)
                == nil)
        #expect(
            await tracker.previousIncompleteGroup(before: fourth.id, in: groups, marks: marks)
                == first)
        #expect(
            await tracker.nextIncompleteGroup(after: fourth.id, in: groups, marks: marks)
                == nil)
        #expect(
            await tracker.nextIncompleteGroup(
                after: GroupID(rawValue: "missing"), in: groups, marks: marks)
                == nil)
    }

    @Test func completionFollowsPhotosAcrossARefinement() async {
        let tracker = GroupCompletionTracker()
        let a = groupCullingPhoto("a")
        let b = groupCullingPhoto("b")
        let c = groupCullingPhoto("c")
        let d = groupCullingPhoto("d")
        let e = groupCullingPhoto("e")
        let original = groupCullingGroup("kept", members: [a, b])
        await tracker.recordFinishingAction(on: original.id)

        // C9 keeps a group's ID when its membership overlaps, and the score follows that ID.
        let refined = groupCullingGroup("kept", members: [a, b, c])
        // A group that gained a new ID is complete only when every member is rated or rejected.
        let changedID = groupCullingGroup("changed", members: [d, e])
        let changedIDComplete = groupCullingGroup("changed-complete", members: [d])
        let marks = groupCullingMarks([(d, PhotoMarks(rating: groupCullingRating(2)))])

        #expect(await tracker.isComplete(refined, marks: [:]))
        #expect(!(await tracker.isComplete(changedID, marks: marks)))
        #expect(await tracker.isComplete(changedIDComplete, marks: marks))
        // The finishing-action record is keyed by ID, so it never leaks onto another group.
        #expect(!(await tracker.hasFinishingAction(on: changedID.id)))
    }
}
