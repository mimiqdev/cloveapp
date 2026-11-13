import CloveCore
import Foundation
import SwiftUI
import Testing

@testable import Clove

@MainActor
struct TapPickerTests {
    // MARK: - Geometry

    @Test func ratingAndLabelPickerMatchReferenceDimensions() {
        #expect(RatingPicker.preferredSize(for: .horizontal) == CGSize(width: 288, height: 52))
        #expect(RatingPicker.preferredSize(for: .vertical) == CGSize(width: 52, height: 288))
        #expect(
            LabelPicker.preferredSize(for: .horizontal, count: 6) == CGSize(width: 288, height: 52)
        )
        #expect(
            LabelPicker.preferredSize(for: .vertical, count: 6) == CGSize(width: 52, height: 288))
    }

    // MARK: - Adaptive placement

    @Test func placementDefaultsToHorizontalAboveAnchorAndClampsWithinSafeArea() {
        let horizontal = RatingPicker.preferredSize(for: .horizontal)
        let vertical = RatingPicker.preferredSize(for: .vertical)
        let container = CGSize(width: 390, height: 844)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        // Right-edge label button inside DetailMarkCapsule.
        let anchor = CGRect(x: 322, y: 740, width: 36, height: 36)

        let placement = TapPickerPlacement.resolve(
            anchor: anchor,
            containerSize: container,
            safeAreaInsets: insets,
            horizontalSize: horizontal,
            verticalSize: vertical,
            preferredEdge: .top)

        #expect(placement.axis == .horizontal)
        #expect(placement.frame.size == horizontal)
        #expect(placement.frame.maxY <= anchor.minY)
        #expect(placement.frame.maxX <= container.width - 12)
        #expect(placement.frame.minX >= 12)
    }

    @Test func placementFallsBackToVerticalWhenHorizontalDoesNotFitSafeWidth() {
        let container = CGSize(width: 320, height: 700)
        // Extended 8-colour picker (382.4 pt wide) does not fit inside a 320 pt pane.
        let horizontal = LabelPicker.preferredSize(for: .horizontal, count: 8)
        let vertical = LabelPicker.preferredSize(for: .vertical, count: 8)
        let anchor = CGRect(x: 250, y: 610, width: 36, height: 36)

        let placement = TapPickerPlacement.resolve(
            anchor: anchor,
            containerSize: container,
            horizontalSize: horizontal,
            verticalSize: vertical,
            preferredEdge: .top)

        #expect(placement.axis == .vertical)
        #expect(placement.frame.size == vertical)
        #expect(placement.frame.minX >= 12)
        #expect(placement.frame.maxX <= container.width - 12)
        #expect(placement.frame.minY >= 12)
        #expect(placement.frame.maxY <= anchor.minY)
    }

    @Test func placementUsesVerticalAndClearsDuoSecondaryRailOnVerticalEdges() {
        let horizontal = RatingPicker.preferredSize(for: .horizontal)
        let vertical = RatingPicker.preferredSize(for: .vertical)
        let container = CGSize(width: 400, height: 780)
        let insets = EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 64)
        let anchor = CGRect(x: 280, y: 360, width: 44, height: 44)

        let placement = TapPickerPlacement.resolve(
            anchor: anchor,
            containerSize: container,
            safeAreaInsets: insets,
            horizontalSize: horizontal,
            verticalSize: vertical,
            preferredEdge: .trailing)

        #expect(placement.axis == .vertical)
        #expect(placement.frame.size == vertical)
        #expect(placement.frame.maxX <= container.width - insets.trailing - 12)
    }

    // MARK: - Controller

    @Test func controllerTogglesSwitchesAndDismisses() {
        let controller = TapPickerController()
        let anchor = CGRect(x: 100, y: 500, width: 44, height: 44)
        let hSize = RatingPicker.preferredSize(for: .horizontal)
        let vSize = RatingPicker.preferredSize(for: .vertical)

        controller.toggle(
            id: "rating", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        #expect(controller.isPresented(id: "rating"))

        // Tapping same trigger toggles closed.
        controller.toggle(
            id: "rating", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        #expect(!controller.isPresented)

        // Switching from rating to label replaces active presentation cleanly.
        controller.toggle(
            id: "rating", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        controller.toggle(
            id: "label", anchor: anchor, horizontalSize: hSize, verticalSize: vSize
        ) { _, _ in EmptyView() }
        #expect(controller.isPresented(id: "label"))
        #expect(!controller.isPresented(id: "rating"))

        controller.updateAnchor(id: "label", anchor: CGRect(x: 150, y: 500, width: 44, height: 44))
        #expect(controller.active?.anchor.minX == 150)

        controller.dismiss()
        #expect(!controller.isPresented)
    }

    // MARK: - Behavioral rules

    @Test func clearRatingKeepsLabelAndClearsRejectWhileClearLabelKeepsStars() {
        let rules = MarkingInputRules()
        let ratedAndLabeled = PhotoMarks(
            rating: Rating(rawValue: 4) ?? .unrated,
            label: ColourLabel(colour: .blue))

        if case .mark(let clearRating, _) = rules.result(
            forRating: .unrated, marks: ratedAndLabeled)
        {
            let updated = ratedAndLabeled.applying(clearRating)
            #expect(updated.rating == .unrated)
            #expect(updated.label == ColourLabel(colour: .blue))
        } else {
            Issue.record("Expected Clear rating to produce a mark")
        }

        if case .mark(let clearLabel, _) = rules.result(forLabel: .clear, marks: ratedAndLabeled) {
            let updated = ratedAndLabeled.applying(clearLabel)
            #expect(updated.rating == (Rating(rawValue: 4) ?? .unrated))
            #expect(updated.label == .clear)
        } else {
            Issue.record("Expected Clear label to produce a mark")
        }

        let rejectedAndLabeled = PhotoMarks(
            rating: .rejected,
            label: ColourLabel(colour: .green))
        if case .mark(let clearReject, _) = rules.result(
            forRating: .unrated, marks: rejectedAndLabeled)
        {
            let updated = rejectedAndLabeled.applying(clearReject)
            #expect(updated.rating == .unrated)
            #expect(!updated.isRejected)
            #expect(updated.label == ColourLabel(colour: .green))
        } else {
            Issue.record("Expected Clear rating to clear Reject without touching label")
        }
    }

    @Test func enabledRatingsGateNewMarksButStillAllowClearingCurrentOrZero() {
        let oddRatings =
            EnabledRatings(
                EnabledRatings.all.levels.enumerated()
                    .filter { $0.offset.isMultiple(of: 2) }
                    .map(\.element)
            ) ?? .all
        var settings = AppSettings()
        settings.enabledRatings = oddRatings
        let rules = MarkingInputRules(settings: settings)
        let externalFourStars = PhotoMarks(rating: Rating(rawValue: 4) ?? .unrated)

        // Disabled level 2 does nothing.
        #expect(
            rules.result(forRating: Rating(rawValue: 2) ?? .unrated, marks: externalFourStars)
                == .noChange)

        // Tapping Clear (0) clears an externally applied disabled rating cleanly.
        if case .mark(let change, _) = rules.result(
            for: .rating(.unrated), marks: externalFourStars)
        {
            #expect(externalFourStars.applying(change).rating == .unrated)
        } else {
            Issue.record("Expected explicit 0 to clear externally applied disabled rating")
        }
    }

    @Test func batchSetOnlyAppliesSelectedValueAndMixedClearTouchesOnlyMarkedPhotos() {
        let folder = FolderIdentity(rawValue: "test")
        let p1 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "A"),
            fileName: "A.ARW",
            time: .unavailable,
            marks: PhotoMarks(
                rating: Rating(rawValue: 3) ?? .unrated, label: ColourLabel(colour: .red)))
        let p2 = GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: "B"),
            fileName: "B.ARW",
            time: .unavailable,
            marks: PhotoMarks(rating: Rating(rawValue: 5) ?? .unrated, label: .clear))

        // Setting 3 stars on mixed [3, 5] only updates p2 (never toggles p1 off).
        let ratePlan = BatchMarkPlan(
            action: .rating(Rating(rawValue: 3) ?? .unrated), photos: [p1, p2])
        #expect(ratePlan.photos == [p2.id])

        // Clearing labels on mixed [Red, Clear] only writes to p1 and keeps p1's 3-star rating.
        let clearLabelPlan = BatchMarkPlan(action: .label(.clear), photos: [p1, p2])
        #expect(clearLabelPlan.photos == [p1.id])
        #expect(clearLabelPlan.items.first?.change == MarkChange(label: .clear))

        // Clearing ratings on mixed [3, 5] writes .unrated to both while keeping labels untouched.
        let clearRatingPlan = BatchMarkPlan(action: .rating(.unrated), photos: [p1, p2])
        #expect(clearRatingPlan.photos == [p1.id, p2.id])
    }
}
