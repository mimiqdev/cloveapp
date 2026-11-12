import CloveCore
import SwiftUI

/// The dock resolves input through DetailMarkingView's existing mark and auto-advance path.
struct DuoMarkControls: View {
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    let rate: (Rating) -> Void
    let label: (ColourLabel) -> Void
    let toggleReject: () -> Void
    let markingBegan: () -> Void

    @State private var showsStars = false
    @State private var showsLabels = false
    @State private var dragRating: Rating?
    @State private var initialRating: Rating?
    @GestureState private var isDragging = false

    private var rating: Rating { dragRating ?? previewRating ?? marks.rating }

    var body: some View {
        VStack(spacing: 2) {
            ratingButton
            RejectCircle(
                isRejected: marks.isRejected, size: .duo,
                identifier: "clove.duo.reject", onToggle: toggleReject)
            LabelCircle(
                label: marks.label.colour, identifier: "clove.duo.label"
            ) {
                markingBegan()
                showsStars = false
                showsLabels.toggle()
            }
            .anchorPreference(key: DuoDockPickerKey.self, value: .bounds) { anchor in
                showsLabels ? [DuoDockPicker(anchor: anchor, content: AnyView(labelPicker))] : []
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.duo.marks")
        .accessibilityValue(MarkSummary.text(for: marks))
        .onChange(of: marks) { _, _ in
            dragRating = nil
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging {
                dragRating = nil
                initialRating = nil
            }
        }
    }

    private var ratingButton: some View {
        VStack(spacing: 1) {
            Image(systemName: (rating.starCount ?? 0) > 0 ? "star.fill" : "star")
                .foregroundStyle(Color.clove.rating.on)
            Text("\(rating.starCount ?? 0)")
                .font(.caption2)
                .foregroundStyle(Color.clove.text.primary)
        }
        .frame(width: 36, height: 48)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { value in
                    if initialRating == nil {
                        initialRating = marks.rating
                        markingBegan()
                        showsLabels = false
                    }
                    guard abs(value.translation.height) > 4 else { return }
                    showsStars = true
                    let start = initialRating?.starCount ?? 0
                    let steps = Int((-value.translation.height / 30).rounded())
                    let value = min(5, max(0, start + steps))
                    dragRating =
                        settings.enabledRatings.levels.last {
                            ($0.starCount ?? 0) <= value
                        } ?? .unrated
                }
                .onEnded { _ in
                    if let dragRating {
                        rate(dragRating)
                        showsStars = false
                    } else {
                        showsStars.toggle()
                    }
                    dragRating = nil
                    initialRating = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating.starCount ?? 0) stars")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showsStars.toggle() }
        .accessibilityIdentifier("clove.duo.rating")
        .anchorPreference(key: DuoDockPickerKey.self, value: .bounds) { anchor in
            showsStars
                ? [DuoDockPicker(anchor: anchor, content: AnyView(starPicker), alignsBottom: true)]
                : []
        }
    }

    private var labelPicker: some View {
        LabelPicker(
            selection: marks.label.colour,
            labels: [nil] + settings.availableLabels.map { Optional($0) },
            identifier: "clove.duo.labels"
        ) {
            label($0.map { ColourLabel(colour: $0) } ?? .clear)
            showsLabels = false
        }
    }

    private var starPicker: some View {
        VerticalStarBar(
            rating: rating, enabledRatings: settings.enabledRatings,
            size: .duo, showsRejectChip: false, identifier: "clove.duo.stars",
            onPreview: { dragRating = $0 },
            onCommit: {
                rate($0)
                dragRating = nil
                showsStars = false
            }, onReject: toggleReject, onBegin: markingBegan)
    }
}
