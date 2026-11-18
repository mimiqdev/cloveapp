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
    var labelPopoverTrigger: Int = 0

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            ToolbarRatingButton(
                photoID: photoID, marks: marks, settings: settings, previewRating: previewRating,
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
                photoID: photoID, marks: marks, settings: settings, label: label,
                markingBegan: markingBegan, labelPopoverTrigger: labelPopoverTrigger
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
    let photoID: PhotoIdentity
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    @Binding var showsStars: Bool
    @Binding var dragRating: Rating?
    let rate: (Rating) -> Void
    let markingBegan: () -> Void
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @State private var isAnchorReady = false

    private var rating: Rating { dragRating ?? previewRating ?? marks.rating }

    private var arrowEdge: Edge {
        verticalEdge == .leading ? .leading : (verticalEdge == .trailing ? .trailing : .bottom)
    }

    private var dismissTrigger: DuoPopoverDismissTrigger {
        DuoPopoverDismissTrigger(
            photoID: photoID,
            arrowEdge: arrowEdge,
            horizontalSizeClass: horizontalSizeClass,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            hasFoldRegion: hasFoldRegion,
            isEnabled: isEnabled)
    }

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
            isPresented: Binding(
                get: { showsStars && isAnchorReady && scenePhase == .active && isEnabled },
                set: { showsStars = $0 }),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: arrowEdge
        ) {
            RatingPicker(
                selection: rating,
                enabledRatings: settings.enabledRatings,
                allowsTapCurrentToClear: dragRating == nil,
                axis: verticalEdge == nil ? .horizontal : .vertical,
                identifier: "clove.duo.stars",
                photoID: photoID
            ) { chosen in
                rate(chosen)
                dragRating = nil
                showsStars = false
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackgroundInteraction(.enabled)
        }
        .onChange(of: dismissTrigger) { _, _ in
            showsStars = false
            dragRating = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                showsStars = false
                dragRating = nil
            }
        }
        .onAppear {
            isAnchorReady = true
        }
        .onDisappear {
            isAnchorReady = false
            showsStars = false
            dragRating = nil
        }
    }
}

@available(iOS 27.1, *)
private struct ToolbarLabelButton: View {
    let photoID: PhotoIdentity
    let marks: PhotoMarks
    let settings: AppSettings
    let label: (ColourLabel) -> Void
    let markingBegan: () -> Void
    var labelPopoverTrigger: Int = 0
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @State private var showsLabels = false
    @State private var isAnchorReady = false

    private var arrowEdge: Edge {
        verticalEdge == .leading ? .leading : (verticalEdge == .trailing ? .trailing : .bottom)
    }

    private var dismissTrigger: DuoPopoverDismissTrigger {
        DuoPopoverDismissTrigger(
            photoID: photoID,
            arrowEdge: arrowEdge,
            horizontalSizeClass: horizontalSizeClass,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            hasFoldRegion: hasFoldRegion,
            isEnabled: isEnabled)
    }

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
            isPresented: Binding(
                get: { showsLabels && isAnchorReady && scenePhase == .active && isEnabled },
                set: { showsLabels = $0 }),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: arrowEdge
        ) {
            LabelPicker(
                selection: marks.label.colour,
                labels: [nil] + settings.availableLabels.map { Optional($0) },
                identifier: "clove.duo.labels",
                onPick: {
                    label($0.map { ColourLabel(colour: $0) } ?? .clear)
                    showsLabels = false
                },
                axis: verticalEdge == nil ? .horizontal : .vertical,
                photoID: photoID
            )
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: labelPopoverTrigger) { _, _ in
            if isAnchorReady, scenePhase == .active, isEnabled {
                showsLabels = true
            }
        }
        .onChange(of: dismissTrigger) { _, _ in
            showsLabels = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                showsLabels = false
            }
        }
        .onAppear {
            isAnchorReady = true
        }
        .onDisappear {
            isAnchorReady = false
            showsLabels = false
        }
    }
}

@available(iOS 27.1, *)
private struct DuoPopoverDismissTrigger: Equatable {
    let photoID: PhotoIdentity
    let arrowEdge: Edge
    let horizontalSizeClass: UserInterfaceSizeClass?
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let hasFoldRegion: Bool
    let isEnabled: Bool
}
