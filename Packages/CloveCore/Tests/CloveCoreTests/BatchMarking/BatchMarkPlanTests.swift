import Foundation
import Testing

import CloveCore

/// PRD P0-09, PRD Marking rules and PRD P0-06: one bar action resolved into the change each
/// selected photo receives. These tests pin that a batch photo gets the same result a
/// single-photo control would give it, and that a photo with nothing to change writes nothing.
@Suite("Batch mark plan")
struct BatchMarkPlanTests {
    /// Every photo gets the rating, and a rejected photo also clears Reject (PRD Marking rules).
    @Test func aRatingSetsEveryPhotoAndClearsRejectOnRejectedPhotos() {
        let photos = [
            BatchMarkFixtures.gridPhoto("a", stars: 5),
            BatchMarkFixtures.gridPhoto("b", stars: 3, rejected: true),
            BatchMarkFixtures.gridPhoto("c"),
        ]
        let plan = BatchMarkPlan(action: .rating(BatchMarkFixtures.stars(2)), photos: photos)

        #expect(plan.photos == photos.map(\.id))
        #expect(
            plan.items.map(\.change) == [
                MarkChange(rating: BatchMarkFixtures.stars(2)),
                MarkChange(rating: BatchMarkFixtures.stars(2), reject: false),
                MarkChange(rating: BatchMarkFixtures.stars(2)),
            ])
    }

    /// Only a level Settings enables applies; a disabled level writes nothing
    /// (PRD Enabled rating levels).
    @Test func aDisabledRatingWritesNothing() {
        let settings = AppSettings(enabledRatings: BatchMarkFixtures.enabled([1, 2]))
        let photos = [BatchMarkFixtures.gridPhoto("a")]

        #expect(
            BatchMarkPlan(
                action: .rating(BatchMarkFixtures.stars(4)), photos: photos, settings: settings
            ).isEmpty)
        #expect(
            BatchMarkPlan(
                action: .rating(BatchMarkFixtures.stars(2)), photos: photos, settings: settings
            ).items.count == 1)
        // Zero clears, and clearing is never one of the enabled levels.
        #expect(
            !BatchMarkPlan(
                action: .rating(.unrated),
                photos: [BatchMarkFixtures.gridPhoto("a", stars: 3)], settings: settings
            ).isEmpty)
    }

    /// Clearing a rating keeps Reject, because only applying 1–5 stars says "keep this photo"
    /// (PRD Marking rules).
    @Test func clearingARatingKeepsReject() throws {
        let photo = BatchMarkFixtures.gridPhoto("a", stars: 3, rejected: true)
        let plan = BatchMarkPlan(action: .rating(.unrated), photos: [photo])
        let item = try #require(plan.items.first)
        #expect(item.change == MarkChange(rating: .unrated))
        #expect(item.change.reject == nil)
    }

    /// A photo that already carries the rating has nothing to write (PRD P0-06's no-change
    /// rule), so a batch never rewrites a mark it would not change.
    @Test func aPhotoThatAlreadyCarriesTheRatingGetsNothing() {
        let photos = [
            BatchMarkFixtures.gridPhoto("a", stars: 3),
            BatchMarkFixtures.gridPhoto("b"),
        ]
        let plan = BatchMarkPlan(action: .rating(BatchMarkFixtures.stars(3)), photos: photos)
        #expect(plan.photos == [BatchMarkFixtures.photo("b")])
    }

    /// A label is set on the photos that do not carry it, and a photo that already carries it
    /// gets nothing: the batch sets a mark instead of toggling it off.
    @Test func aLabelSetsAndSkipsPhotosThatAlreadyCarryIt() {
        let red = ColourLabel(colour: .red)
        let blue = ColourLabel(colour: .blue)
        let photos = [
            BatchMarkFixtures.gridPhoto("a", label: red),
            BatchMarkFixtures.gridPhoto("b"),
        ]

        let plan = BatchMarkPlan(action: .label(red), photos: photos)
        #expect(plan.photos == [BatchMarkFixtures.photo("b")])
        #expect(plan.items.map(\.change) == [MarkChange(label: red)])

        let other = BatchMarkPlan(action: .label(blue), photos: photos)
        #expect(other.photos == photos.map(\.id))
    }

    /// Clear removes the label from the labelled photos only (PRD Marking rules).
    @Test func clearRemovesTheLabelFromLabelledPhotos() {
        let photos = [
            BatchMarkFixtures.gridPhoto("a", label: ColourLabel(colour: .green)),
            BatchMarkFixtures.gridPhoto("b"),
        ]
        let plan = BatchMarkPlan(action: .label(.clear), photos: photos)
        #expect(plan.photos == [BatchMarkFixtures.photo("a")])
        #expect(plan.items.map(\.change) == [MarkChange(label: .clear)])
    }

    /// Orange and Pink apply only while extended colours are on (PRD Marking rules).
    @Test func anExtendedLabelNeedsTheSetting() {
        let orange = ColourLabel(colour: .orange)
        let photos = [BatchMarkFixtures.gridPhoto("a")]

        #expect(BatchMarkPlan(action: .label(orange), photos: photos).isEmpty)
        let extended = AppSettings(extendedColourLabelsEnabled: true)
        #expect(
            BatchMarkPlan(action: .label(orange), photos: photos, settings: extended)
                .items.map(\.change) == [MarkChange(label: orange)])
    }

    /// Reject keeps every rating, and a photo already rejected gets nothing (PRD Marking rules,
    /// G1 decision 5).
    @Test func rejectKeepsTheRatingAndSkipsRejectedPhotos() throws {
        let photos = [
            BatchMarkFixtures.gridPhoto("a", stars: 4),
            BatchMarkFixtures.gridPhoto("b", stars: 2, rejected: true),
        ]
        let plan = BatchMarkPlan(action: .reject, photos: photos)
        let item = try #require(plan.items.first)
        #expect(plan.items.count == 1)
        #expect(item.photo == BatchMarkFixtures.photo("a"))
        #expect(item.change == MarkChange(reject: true))
    }
}
