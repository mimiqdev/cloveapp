import CloveCore
import SwiftUI

/// The system owns these items' sizing, chrome, placement and overflow. Input resolves
/// through the detail screen's existing mark, write and auto-advance actions.
@available(iOS 27.1, *)
struct DuoMarkControls: ToolbarContent {
    let photoID: PhotoIdentity
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    let canMark: Bool
    @Binding var showsStars: Bool
    @Binding var dragRating: Rating?
    let rate: (Rating) -> Void
    let label: (ColourLabel) -> Void
    let toggleReject: () -> Void
    let markingBegan: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            ToolbarRatingButton(
                marks: marks, settings: settings, previewRating: previewRating,
                showsStars: $showsStars, dragRating: $dragRating,
                rate: rate, markingBegan: markingBegan
            )
            .disabled(!canMark)
        }
        .axisBehavior(.verticalPreferred)
        .visibilityPriority(.high)
        ToolbarItem(placement: .bottomBar) {
            Button(
                marks.isRejected ? "Rejected" : "Reject",
                systemImage: marks.isRejected ? "flag.slash.fill" : "flag.slash"
            ) { toggleReject() }
            .tint(Color.clove.reject)
            .disabled(!canMark)
            .accessibilityValue(MarkSummary.text(for: marks))
            .accessibilityIdentifier("clove.duo.reject")
        }
        .axisBehavior(.verticalPreferred)
        .visibilityPriority(.high)
        ToolbarItem(placement: .bottomBar) {
            ToolbarLabelButton(
                marks: marks, settings: settings, label: label, markingBegan: markingBegan
            )
            .disabled(!canMark)
            .id(photoID)
        }
        .axisBehavior(.verticalPreferred)
        .visibilityPriority(.high)
    }
}

@available(iOS 27.1, *)
private struct ToolbarRatingButton: View {
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    @Binding var showsStars: Bool
    @Binding var dragRating: Rating?
    let rate: (Rating) -> Void
    let markingBegan: () -> Void
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    private var rating: Rating { dragRating ?? previewRating ?? marks.rating }

    var body: some View {
        Button(
            "Rating, \(rating.starCount ?? 0) stars",
            systemImage: (rating.starCount ?? 0) > 0 ? "star.fill" : "star"
        ) {
            markingBegan()
            showsStars.toggle()
        }
        .badge(rating.starCount ?? 0)
        .tint(Color.clove.rating.on)
        .accessibilityValue(MarkSummary.text(for: marks))
        .accessibilityIdentifier("clove.duo.rating")
        .popover(
            isPresented: $showsStars, attachmentAnchor: .rect(.bounds),
            arrowEdge: verticalEdge == .leading
                ? .leading : (verticalEdge == .trailing ? .trailing : .bottom)
        ) {
            VerticalStarBar(
                rating: rating, enabledRatings: settings.enabledRatings,
                size: .duo, showsRejectChip: false, identifier: "clove.duo.stars",
                onPreview: { dragRating = $0 },
                onCommit: {
                    rate($0)
                    dragRating = nil
                    showsStars = false
                }, onReject: {}, onBegin: markingBegan
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackgroundInteraction(.enabled)
        }
    }
}

@available(iOS 27.1, *)
private struct ToolbarLabelButton: View {
    let marks: PhotoMarks
    let settings: AppSettings
    let label: (ColourLabel) -> Void
    let markingBegan: () -> Void
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @State private var showsLabels = false

    var body: some View {
        Button(
            "Label, \(marks.label.isClear ? "None" : marks.label.rawValue)",
            systemImage: marks.label.colour == nil ? "circle" : "circle.fill"
        ) {
            markingBegan()
            showsLabels.toggle()
        }
        .tint(
            marks.label.colour.map { Color.clove.label.colour(for: $0) } ?? Color.clove.text.primary
        )
        .accessibilityValue(MarkSummary.text(for: marks))
        .accessibilityIdentifier("clove.duo.label")
        .popover(
            isPresented: $showsLabels, attachmentAnchor: .rect(.bounds),
            arrowEdge: verticalEdge == .leading
                ? .leading : (verticalEdge == .trailing ? .trailing : .bottom)
        ) {
            LabelPicker(
                selection: marks.label.colour,
                labels: [nil] + settings.availableLabels.map { Optional($0) },
                identifier: "clove.duo.labels"
            ) {
                label($0.map { ColourLabel(colour: $0) } ?? .clear)
                showsLabels = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}
