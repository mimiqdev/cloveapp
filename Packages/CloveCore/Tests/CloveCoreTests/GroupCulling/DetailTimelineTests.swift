import Foundation
import Testing

import CloveCore

/// Issue #304 decisions 2, 3, 4, 5: unified Representative Photo priority, 2-visible-member
/// threshold, Timeline vs Group Focus navigation, and first-pass vs second-pass auto-advance.
@Suite("Detail timeline and group focus")
struct DetailTimelineTests {
    @Test func representativePriorityOrdersStarThenLabelThenUnmarkedThenFirstVisible() throws {
        let three = try MarkingFixtures.stars(3)
        let five = try MarkingFixtures.stars(5)
        let p0 = photo("p0", time: capture(seconds(0)), marks: PhotoMarks(rating: .rejected))
        let p1 = photo(
            "p1", time: capture(seconds(1)),
            marks: PhotoMarks(rating: .rejected, label: ColourLabel(colour: .red)))
        let p2 = photo("p2", time: capture(seconds(2)), marks: PhotoMarks())
        let p3 = photo(
            "p3", time: capture(seconds(3)), marks: PhotoMarks(label: ColourLabel(colour: .blue)))
        let p4 = photo("p4", time: capture(seconds(4)), marks: PhotoMarks(rating: three))
        let p5 = photo("p5", time: capture(seconds(5)), marks: PhotoMarks(rating: three))
        let p6 = photo("p6", time: capture(seconds(6)), marks: PhotoMarks(rating: five))

        // Highest star wins over everything; ties pick first in visibleMembers order.
        #expect(BrowsingGroup.representative(of: [p0, p1, p2, p3, p4, p5, p6])?.id == p6.id)
        #expect(BrowsingGroup.representative(of: [p0, p4, p5])?.id == p4.id)
        // Non-rejected labelled beats unmarked and rejected+labelled.
        #expect(BrowsingGroup.representative(of: [p0, p1, p2, p3])?.id == p3.id)
        // Unmarked beats rejected / rejected+labelled.
        #expect(BrowsingGroup.representative(of: [p0, p1, p2])?.id == p2.id)
        // All rejected falls back to first visible member.
        #expect(BrowsingGroup.representative(of: [p0, p1])?.id == p0.id)
    }

    @Test func visibleMemberResolutionPreservesActiveOrderAndRequiresTwoMembers() {
        let a = photo("a", time: capture(seconds(0)), fileName: "C.ARW")
        let b = photo("b", time: capture(seconds(1)), fileName: "A.ARW")
        let c = photo("c", time: capture(seconds(2)), fileName: "B.ARW")
        let d = photo("d", time: capture(seconds(3)), fileName: "D.ARW")
        let burst = BrowsingGroup(id: GroupID(rawValue: "g"), members: [a.id, b.id, c.id])

        // Reversed filename order [b, c, a, d] keeps b first in visibleMembers.
        let filenameOrdered = [b, c, a, d]
        let timeline = DetailTimeline(photos: filenameOrdered, groups: [burst])
        #expect(timeline.slots.count == 2)
        #expect(
            timeline.activeGroup(with: burst.id)?.visibleMembers.map(\.id) == [b.id, c.id, a.id])
        #expect(timeline.activeGroup(with: burst.id)?.representative.id == b.id)

        // Filter leaving 1 visible member degrades to standalone photo slot.
        let filteredOne = DetailTimeline(photos: [a, d], groups: [burst])
        #expect(filteredOne.slots.count == 2)
        #expect(filteredOne.activeGroups.isEmpty)
        #expect(filteredOne.slots[0].activeGroup == nil)
        #expect(filteredOne.activeGroup(containing: a.id) == nil)
    }

    @Test func timelineStepsAcrossSlotsWhileGroupFocusBoundsWithinMembers() throws {
        let s0 = photo("s0", time: capture(seconds(0)))
        let g0 = photo("g0", time: capture(seconds(1)))
        let g1 = photo(
            "g1", time: capture(seconds(2)), marks: PhotoMarks(rating: try MarkingFixtures.stars(4))
        )
        let g2 = photo("g2", time: capture(seconds(3)))
        let s1 = photo("s1", time: capture(seconds(4)))
        let burst = BrowsingGroup(id: GroupID(rawValue: "burst"), members: [g0.id, g1.id, g2.id])
        let timeline = DetailTimeline(photos: [s0, g0, g1, g2, s1], groups: [burst])

        // Timeline has 3 slots: s0, burst (rep g1), s1.
        #expect(timeline.slots.count == 3)
        #expect(timeline.stagePhotos.map(\.id) == [s0.id, g1.id, s1.id])
        #expect(timeline.steppedPhoto(from: s0.id, offset: 1, expandedGroup: nil) == g1.id)
        #expect(timeline.steppedPhoto(from: g1.id, offset: 1, expandedGroup: nil) == s1.id)
        #expect(timeline.steppedPhoto(from: g1.id, offset: -1, expandedGroup: nil) == s0.id)
        #expect(timeline.steppedPhoto(from: s0.id, offset: -1, expandedGroup: nil) == nil)
        #expect(timeline.steppedPhoto(from: s1.id, offset: 1, expandedGroup: nil) == nil)

        // Group Focus steps strictly across [g0, g1, g2] without leaving group.
        #expect(timeline.stageOrder(expandedGroup: burst.id).map(\.id) == [g0.id, g1.id, g2.id])
        #expect(timeline.steppedPhoto(from: g0.id, offset: -1, expandedGroup: burst.id) == nil)
        #expect(timeline.steppedPhoto(from: g0.id, offset: 1, expandedGroup: burst.id) == g1.id)
        #expect(timeline.steppedPhoto(from: g1.id, offset: 1, expandedGroup: burst.id) == g2.id)
        #expect(timeline.steppedPhoto(from: g2.id, offset: 1, expandedGroup: burst.id) == nil)
    }

    @Test func firstPassAdvancesThroughUnmarkedThenExitsOnFinalUnmarkedAndRejectUnmarked() throws {
        let four = try MarkingFixtures.stars(4)
        let g0 = photo("g0", time: capture(seconds(0)), marks: PhotoMarks(rating: four))
        let g1 = photo("g1", time: capture(seconds(1)))  // unmarked
        let g2 = photo("g2", time: capture(seconds(2)))  // unmarked
        let nextBurst0 = photo("nb0", time: capture(seconds(3)), marks: PhotoMarks(rating: four))
        let nextBurst1 = photo("nb1", time: capture(seconds(4)))  // unmarked inside next stack
        let sNext = photo("sNext", time: capture(seconds(5)))
        let burst = BrowsingGroup(id: GroupID(rawValue: "b1"), members: [g0.id, g1.id, g2.id])
        let nextBurst = BrowsingGroup(
            id: GroupID(rawValue: "b2"), members: [nextBurst0.id, nextBurst1.id])
        let photos = [g0, g1, g2, nextBurst0, nextBurst1, sNext]
        let timeline = DetailTimeline(photos: photos, groups: [burst, nextBurst])
        let nextPhotoRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextPhoto)))
        let nextUnmarkedRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextUnmarkedPhoto)))
        let stayRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .stay)))

        // Marking g1 when g2 is still unmarked advances to g2 in Group Focus.
        let midPlan = timeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: g1.id, expandedGroup: burst.id,
            rules: nextPhotoRules)
        #expect(midPlan.target == .groupUndecidedPhoto(g2.id))
        #expect(!midPlan.exitsGroupFocus)

        // Marking last unmarked g1 (if g2 was already rejected) exits to next Timeline slot (rep nextBurst0).
        let g2Marked = photo("g2", time: capture(seconds(2)), marks: PhotoMarks(rating: .rejected))
        let oneUnmarkedTimeline = DetailTimeline(
            photos: [g0, g1, g2Marked, nextBurst0, nextBurst1, sNext], groups: [burst, nextBurst])
        let lastNextPlan = oneUnmarkedTimeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: g1.id, expandedGroup: burst.id,
            rules: nextPhotoRules)
        #expect(lastNextPlan.target == .nextPhoto(nextBurst0.id))
        #expect(lastNextPlan.exitsGroupFocus)

        // .stay stays in Group Focus without collapsing.
        let lastStayPlan = oneUnmarkedTimeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: g1.id, expandedGroup: burst.id,
            rules: stayRules)
        #expect(lastStayPlan.target == .stay)
        #expect(!lastStayPlan.exitsGroupFocus)

        // Finishing Reject k unmarked exits to next Timeline slot (.nextUnmarkedPhoto lands on nextBurst's rep).
        let finishNextUnmarked = timeline.finishingAdvancePlan(
            groupID: burst.id, from: g0.id, rules: nextUnmarkedRules)
        #expect(finishNextUnmarked.target == .nextUnmarkedPhoto(nextBurst0.id))
        #expect(finishNextUnmarked.exitsGroupFocus)

        // When no later Timeline slot exists, exiting Group Focus still sets exitsGroupFocus = true.
        let tailOnly = DetailTimeline(photos: [g0, g1, g2Marked], groups: [burst])
        let tailLastPlan = tailOnly.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: g1.id, expandedGroup: burst.id,
            rules: nextPhotoRules)
        #expect(tailLastPlan.target == .stay)
        #expect(tailLastPlan.exitsGroupFocus)
        #expect(tailLastPlan.advances)
    }

    @Test func secondPassReviewNeverAutoCollapsesOrEjectsFromGroup() throws {
        let three = try MarkingFixtures.stars(3)
        let four = try MarkingFixtures.stars(4)
        let g0 = photo("g0", time: capture(seconds(0)), marks: PhotoMarks(rating: three))
        let g1 = photo("g1", time: capture(seconds(1)), marks: PhotoMarks(rating: .rejected))
        let g2 = photo("g2", time: capture(seconds(2)), marks: PhotoMarks(rating: four))
        let sAfter = photo("sAfter", time: capture(seconds(3)))
        let burst = BrowsingGroup(id: GroupID(rawValue: "b"), members: [g0.id, g1.id, g2.id])
        let timeline = DetailTimeline(photos: [g0, g1, g2, sAfter], groups: [burst])

        let nextPhotoRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextPhoto)))
        let nextUnmarkedRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextUnmarkedPhoto)))
        let stayRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .stay)))

        // .nextUnmarkedPhoto and .stay keep the user on the current member without collapsing.
        for rules in [nextUnmarkedRules, stayRules] {
            let plan = timeline.autoAdvancePlan(
                after: .rating, change: MarkChange(rating: four), from: g2.id,
                expandedGroup: burst.id, rules: rules)
            #expect(plan.target == .stay)
            #expect(!plan.exitsGroupFocus)
        }

        // .nextPhoto steps within visibleMembers and stops at the end without ejecting to sAfter.
        let stepPlan = timeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: g0.id,
            expandedGroup: burst.id, rules: nextPhotoRules)
        #expect(stepPlan.target == .groupUndecidedPhoto(g1.id))
        #expect(!stepPlan.exitsGroupFocus)

        let endPlan = timeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: three), from: g2.id,
            expandedGroup: burst.id, rules: nextPhotoRules)
        #expect(endPlan.target == .stay)
        #expect(!endPlan.exitsGroupFocus)
    }

    @Test func timelineStandaloneAutoAdvanceStepsAcrossSlotsAndFindsUnmarkedStacks() throws {
        let four = try MarkingFixtures.stars(4)
        let s0 = photo("s0", time: capture(seconds(0)))
        let decided0 = photo("d0", time: capture(seconds(1)), marks: PhotoMarks(rating: four))
        let decided1 = photo("d1", time: capture(seconds(2)), marks: PhotoMarks(rating: .rejected))
        let pending0 = photo("p0", time: capture(seconds(3)), marks: PhotoMarks(rating: four))
        let pending1 = photo("p1", time: capture(seconds(4)))  // unmarked inside later stack
        let dGroup = BrowsingGroup(id: GroupID(rawValue: "d"), members: [decided0.id, decided1.id])
        let pGroup = BrowsingGroup(id: GroupID(rawValue: "p"), members: [pending0.id, pending1.id])
        let timeline = DetailTimeline(
            photos: [s0, decided0, decided1, pending0, pending1], groups: [dGroup, pGroup])

        let nextPhotoRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextPhoto)))
        let nextUnmarkedRules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextUnmarkedPhoto)))

        let nextSlotPlan = timeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: s0.id, expandedGroup: nil,
            rules: nextPhotoRules)
        #expect(nextSlotPlan.target == .nextPhoto(decided0.id))

        let nextUnmarkedSlotPlan = timeline.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: four), from: s0.id, expandedGroup: nil,
            rules: nextUnmarkedRules)
        #expect(nextUnmarkedSlotPlan.target == .nextUnmarkedPhoto(pending0.id))
    }

    @Test func filmstripVerticalGestureRequires24ptAndVerticalDominance() {
        // Expand requires vertical <= -24 and |vertical| > 1.5 * |horizontal|.
        #expect(!FilmstripVerticalGesture.shouldExpand(horizontal: 0, vertical: -23.9))
        #expect(FilmstripVerticalGesture.shouldExpand(horizontal: 0, vertical: -24))
        #expect(FilmstripVerticalGesture.shouldExpand(horizontal: 15, vertical: -24))
        #expect(!FilmstripVerticalGesture.shouldExpand(horizontal: 16, vertical: -24))
        #expect(!FilmstripVerticalGesture.shouldExpand(horizontal: 0, vertical: 30))

        // Collapse requires vertical >= 24 and |vertical| > 1.5 * |horizontal|.
        #expect(!FilmstripVerticalGesture.shouldCollapse(horizontal: 0, vertical: 23.9))
        #expect(FilmstripVerticalGesture.shouldCollapse(horizontal: 0, vertical: 24))
        #expect(FilmstripVerticalGesture.shouldCollapse(horizontal: -15, vertical: 24))
        #expect(!FilmstripVerticalGesture.shouldCollapse(horizontal: -16, vertical: 24))
        #expect(!FilmstripVerticalGesture.shouldCollapse(horizontal: 0, vertical: -30))
    }
}
