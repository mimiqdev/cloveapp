import CloveCore
import SwiftUI

/// The shared three-action marking family: Reject, Rating and Label in one compact native glass
/// group (`design/handoff/components.md`, Marking toolbar; owner decision, 2026-11-13, #227).
///
/// The frame is 168 × 48 with a hairline between the actions. Reject draws `flag.slash` off and
/// `flag.slash.fill` in `reject` when on, so it never reads as a Close button. The rating action
/// shows an outlined star when unrated and `star.fill` plus the 1–5 value when rated, with the
/// whole icon-and-number group centred in a fixed one-digit slot; tapping it opens the shared
/// tap-rating picker (#229), whose explicit Clear and tap-current-to-clear keep every value
/// reachable. The label action opens the shared colour-label picker. The pickers present through
/// the ``TapPickerController`` the screen hosts, so they adapt their orientation to the available
/// space and dismiss on an outside tap; a plain popover is the fallback when no host exists.
/// Every action goes through the closures, so the screen applies C13's rules and writes the mark;
/// the toolbar knows nothing about the library.
struct MarkingToolbar: View {
    /// The photo's rating (PRD P0-04).
    let rating: Rating

    /// The photo's label, or nil when it has none (PRD Marking rules).
    let label: LabelColour?

    /// Whether the photo's rating is −1 (PRD Marking rules; `docs/decisions/reject-as-rating.md`).
    let isRejected: Bool

    /// The levels input may apply; all five by default, and every level still shows
    /// (PRD Enabled rating levels).
    var enabledRatings: EnabledRatings = .all

    /// The labels the picker offers, in order (PRD Marking rules).
    var labels: [LabelColour?] = LabelPicker.defaultLabels

    /// The identifier the screen's UI test uses; the actions are `"<identifier>.reject"`,
    /// `".rating"` and `".label"`, the pickers `".stars"` and `".labels"`.
    var identifier = "clove.mark.toolbar"

    /// The label picker's identifier, which predates the toolbar's own naming.
    var labelPickerIdentifier: String?

    /// True when a batch selection has differing values, so no picker target appears selected.
    var isMixed = false

    /// Single-photo controls clear when tapping the already-selected star; batch controls keep
    /// set-only semantics and clear through the picker's explicit Clear action.
    var allowsTapCurrentToClear = true

    /// Applies a rating the picker resolved, or clears it with unrated (PRD Marking rules).
    let onRate: (Rating) -> Void

    /// Toggles Reject (PRD Marking rules).
    let onReject: () -> Void

    /// Applies a label, or clears it with nil (PRD Marking rules).
    let onLabel: (LabelColour?) -> Void

    /// Input began: drop whatever the last mark was about to do (PRD Auto-advance).
    var onBegin: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            MarkRejectAction(
                isRejected: isRejected, identifier: "\(identifier).reject", onToggle: onReject)
            Rectangle().fill(Color.clove.separator).frame(width: 1, height: 24)
            MarkRatingAction(
                rating: rating, enabledRatings: enabledRatings, isMixed: isMixed,
                allowsTapCurrentToClear: allowsTapCurrentToClear,
                identifier: "\(identifier).rating", pickerIdentifier: "\(identifier).stars",
                onRate: onRate, onBegin: onBegin)
            Rectangle().fill(Color.clove.separator).frame(width: 1, height: 24)
            MarkLabelAction(
                label: label, labels: labels, isMixed: isMixed,
                identifier: "\(identifier).label",
                pickerIdentifier: labelPickerIdentifier ?? "\(identifier).labels",
                onPick: onLabel, onBegin: onBegin)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .cloveGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The control's frame: 168 × 48 (components.md, Marking toolbar).
    private static let size = CGSize(width: 168, height: 48)
}

/// The Reject action of the marking family: `flag.slash` off in the theme's neutral foreground,
/// `flag.slash.fill` in `reject` when on, so it never reads as a Close button (owner decision,
/// 2026-11-13, #227).
struct MarkRejectAction: View {
    /// Whether the photo's rating is −1 (PRD Marking rules).
    let isRejected: Bool

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.reject"

    /// Toggles Reject (PRD Marking rules).
    let onToggle: () -> Void

    /// The theme in effect, for the neutral glyph colour that is not a token (tokens.md).
    @Environment(\.cloveTheme) private var theme

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isRejected ? "flag.slash.fill" : "flag.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    isRejected
                        ? AnyShapeStyle(Color.clove.reject)
                        : AnyShapeStyle(theme.tokens.primaryText.color)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRejected ? "Rejected" : "Reject")
        .accessibilityAddTraits(isRejected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .help(isRejected ? "Rejected" : "Reject")
    }
}

/// The Rating action: an outlined star when unrated, `star.fill` plus the value when rated,
/// centred as one icon-and-number group in a fixed one-digit slot (components.md). Tapping it
/// opens the shared tap-rating picker, whose Clear action and tap-current-to-clear keep every
/// value reachable (owner decisions, 2026-11-13, #227 and #229).
struct MarkRatingAction: View {
    /// The photo's rating.
    let rating: Rating

    /// The levels input may apply; all five by default, and every level still shows.
    let enabledRatings: EnabledRatings

    /// True when a batch selection has differing ratings, so no target appears selected.
    var isMixed = false

    /// Whether tapping the already-selected star clears the rating; batch controls clear through
    /// the picker's explicit Clear instead.
    var allowsTapCurrentToClear = true

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.rating"

    /// The picker's identifier; its targets are `"<pickerIdentifier>.clear"` and `".1"…"5"`.
    var pickerIdentifier = "clove.mark.stars"

    /// Applies a rating the picker resolved, or clears it with unrated (PRD Marking rules).
    let onRate: (Rating) -> Void

    /// Input began: drop whatever the last mark was about to do (PRD Auto-advance).
    var onBegin: () -> Void = {}

    @Environment(\.tapPickerController) private var tapPicker
    @State private var anchor: CGRect = .zero
    @State private var fallbackOpen = false

    /// The value the photo carries, 1–5 stars or unrated (`copy.md` `a11y.rating`).
    private var stars: Int { rating.starCount ?? 0 }

    private var accessibilityRating: String {
        stars == 1 ? "1 star" : stars > 1 ? "\(stars) stars" : "Unrated"
    }

    var body: some View {
        Button {
            onBegin()
            openPicker()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: stars > 0 ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        stars > 0
                            ? AnyShapeStyle(Color.clove.rating.on)
                            : AnyShapeStyle(Color.clove.text.secondary))
                if stars > 0 {
                    // A fixed one-digit slot with monospaced digits, so 1 and 5 stay balanced
                    // and the icon-and-number group stays centred (components.md).
                    Text(stars.formatted())
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.clove.text.primary)
                        .frame(width: 9)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(TapPickerSpace.name))
            } action: { rect in
                anchor = rect
                tapPicker?.updateAnchor(id: pickerIdentifier, anchor: rect)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rating")
        .accessibilityValue(accessibilityRating)
        .accessibilityIdentifier(identifier)
        .help(accessibilityRating)
        .popover(isPresented: $fallbackOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ratingPicker(axis: .horizontal) { fallbackOpen = false }
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Presents the shared tap-rating picker above the action, hosted by the screen's
    /// ``TapPickerController`` when there is one, or in a popover otherwise.
    private func openPicker() {
        guard let tapPicker else {
            fallbackOpen.toggle()
            return
        }
        tapPicker.toggle(
            id: pickerIdentifier,
            anchor: anchor,
            horizontalSize: RatingPicker.preferredSize(for: .horizontal),
            verticalSize: RatingPicker.preferredSize(for: .vertical),
            preferredEdge: .top
        ) { axis, dismiss in
            ratingPicker(axis: axis, dismiss: dismiss)
        }
    }

    private func ratingPicker(axis: Axis, dismiss: @escaping () -> Void) -> some View {
        RatingPicker(
            selection: rating,
            isMixed: isMixed,
            enabledRatings: enabledRatings,
            allowsTapCurrentToClear: allowsTapCurrentToClear,
            axis: axis,
            identifier: pickerIdentifier
        ) { chosen in
            onRate(chosen)
            dismiss()
        }
    }
}

/// The Label action: the current label's colour, or an outlined circle for none, opening the
/// shared colour-label picker (components.md; #229's picker family).
struct MarkLabelAction: View {
    /// The photo's label, or nil when it has none (PRD Marking rules).
    let label: LabelColour?

    /// The labels to offer, in order (PRD Marking rules).
    var labels: [LabelColour?] = LabelPicker.defaultLabels

    /// True when a batch selection has differing labels, so no choice appears selected.
    var isMixed = false

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.label"

    /// The picker's identifier; each dot is `"<pickerIdentifier>.<label>"`.
    var pickerIdentifier = "clove.mark.labels"

    /// Applies a label, or clears it with nil (PRD Marking rules).
    let onPick: (LabelColour?) -> Void

    /// Input began: drop whatever the last mark was about to do (PRD Auto-advance).
    var onBegin: () -> Void = {}

    @Environment(\.tapPickerController) private var tapPicker
    @State private var anchor: CGRect = .zero
    @State private var fallbackOpen = false

    var body: some View {
        Button {
            onBegin()
            openPicker()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.clove.label.colour(for: label))
                    .overlay {
                        Circle().strokeBorder(
                            Color.clove.text.secondary, lineWidth: 1.5 * (label == nil ? 1 : 0))
                    }
            }
            .frame(width: 16, height: 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(TapPickerSpace.name))
            } action: { rect in
                anchor = rect
                tapPicker?.updateAnchor(id: pickerIdentifier, anchor: rect)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.map { "Label, \($0.rawValue)" } ?? "Label")
        .accessibilityAddTraits(label != nil ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .help(label.map { "Label, \($0.rawValue)" } ?? "Label")
        .popover(isPresented: $fallbackOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            labelPicker(axis: .horizontal) { fallbackOpen = false }
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Presents the shared colour-label picker above the action, hosted by the screen's
    /// ``TapPickerController`` when there is one, or in a popover otherwise.
    private func openPicker() {
        guard let tapPicker else {
            fallbackOpen.toggle()
            return
        }
        tapPicker.toggle(
            id: pickerIdentifier,
            anchor: anchor,
            horizontalSize: LabelPicker.preferredSize(for: .horizontal, count: labels.count),
            verticalSize: LabelPicker.preferredSize(for: .vertical, count: labels.count),
            preferredEdge: .top
        ) { axis, dismiss in
            labelPicker(axis: axis, dismiss: dismiss)
        }
    }

    private func labelPicker(axis: Axis, dismiss: @escaping () -> Void) -> some View {
        LabelPicker(
            selection: label, isMixed: isMixed, labels: labels, identifier: pickerIdentifier,
            onPick: { colour in
                onPick(colour)
                dismiss()
            }, axis: axis)
    }
}

#Preview("Marking toolbar") {
    VStack(spacing: 16) {
        MarkingToolbar(
            rating: .unrated, label: nil, isRejected: false, identifier: "preview.toolbar.none",
            onRate: { _ in }, onReject: {}, onLabel: { _ in })
        MarkingToolbar(
            rating: Rating(rawValue: 3) ?? .unrated, label: .green, isRejected: false,
            identifier: "preview.toolbar.marked", onRate: { _ in }, onReject: {}, onLabel: { _ in })
        MarkingToolbar(
            rating: .rejected, label: nil, isRejected: true, identifier: "preview.toolbar.rejected",
            onRate: { _ in }, onReject: {}, onLabel: { _ in })
    }
    .padding(24)
    .tapPickerContainer()
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
