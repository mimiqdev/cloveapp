import CloveCore
import SwiftUI

/// The shared quick-rating ladder: a narrow native glass column of five stars that fill from the
/// bottom (owner decision, 2026-11-13, #227).
///
/// It opens on a swipe up in iPhone detail, from the marking toolbar's rating action, and on the
/// Duo cover's rating button. Dragging fills the stars from the bottom to the top and only the
/// release commits, so the mark is written once: ``onPreview`` reports the live value while the
/// drag runs, for the toolbar's rating action to mirror it, and ``onCommit`` reports the value
/// the gesture ends on. A tap picks the star it
/// lands on, and tapping the photo's current value clears it, the same rule as the toolbar
/// (PRD Marking rules). The optional chip below the ladder is the swipe-down reject stage:
/// `flag.slash` in the theme's secondary text, distinct from the `star.slash` clear stage.
///
/// All five levels always show, because the enabled-ratings setting affects input only (PRD
/// Enabled rating levels): a disabled star is dimmed, a drag settles on the nearest enabled level
/// below it, and a tap on it does nothing.
struct VerticalStarBar: View {
    /// The photo's rating.
    let rating: Rating

    /// The levels input may apply; all five by default, and every level still shows.
    var enabledRatings: EnabledRatings = .all

    /// The size components.md measures on the device.
    var size: ControlSize = .phone

    /// Whether the reject chip is drawn below the star column.
    var showsRejectChip = true

    /// Whether each star is its own tappable button, for the popover a marking action opens;
    /// the swipe ladder keeps one gesture for taps and drags (components.md).
    var selectableStars = false

    /// The identifier the screen's UI test uses; each star is `"<identifier>.<n>"`.
    var identifier = "clove.mark.starBar"

    /// Optional photo identity so cross-photo switches snap marks instead of animating.
    var photoID: PhotoIdentity? = nil

    /// The live value while a drag runs, before release (interactions.md).
    let onPreview: (Rating) -> Void

    /// The value the gesture ends on; the one mark to apply (interactions.md).
    let onCommit: (Rating) -> Void

    /// Rejects the photo, the same as a swipe down (PRD Marking rules, interactions.md).
    let onReject: () -> Void

    /// Touching the bar cancels the previous mark's pending auto-advance.
    var onBegin: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @State private var settledPhotoID: PhotoIdentity?

    /// The value the drag is showing, or nil when no drag has run since the last commit.
    @State private var preview: Rating?

    /// Whether the running gesture has moved past the tap slop at any point.
    ///
    /// The final translation is not enough: a drag that leaves a star and comes back to it would
    /// otherwise look like a tap and clear the rating.
    @State private var movedPastTapSlop = false

    /// Whether `onBegin` has already been fired for the active drag gesture.
    @State private var didBeginDrag = false

    /// Whether a drag is running. SwiftUI resets gesture state when a gesture ends or is cancelled,
    /// so a cancelled drag cannot leave its preview behind.
    @GestureState private var isDragging = false

    /// The value the stars fill to: the drag's live value while one runs, else the photo's rating.
    private var shownRating: Rating { preview ?? rating }
    private var metrics: VerticalStarBarMetrics { VerticalStarBarMetrics(size: size) }
    private var shouldAnimateMarks: Bool {
        CloveMotion.shouldAnimateMarkChange(settledPhotoID: settledPhotoID, currentPhotoID: photoID)
    }

    var body: some View {
        let markAnimation = shouldAnimateMarks ? CloveMotion.micro(reduceMotion: reduceMotion) : nil
        VStack(spacing: metrics.chipGap) {
            pill
                .animation(markAnimation, value: shownRating)
            if showsRejectChip {
                rejectChip
                    .animation(markAnimation, value: isRejectStage)
            }
        }
        .onChange(of: photoID, initial: true) { _, newID in
            settledPhotoID = newID
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The glass ladder of stars, top to bottom from five to one (components.md).
    private var pill: some View {
        GeometryReader { proxy in
            if selectableStars {
                // A popover ladder is tap-only: plain buttons, no drag machinery, so a tap
                // commits once through the button's own action.
                VerticalStarBarStars(
                    rating: shownRating, enabledRatings: enabledRatings, size: size,
                    identifier: identifier,
                    onRate: { level in
                        onCommit(level == rating ? .unrated : level)
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .modifier(
                    StarBarAccessibility(
                        individualStars: true, value: accessibilityValue,
                        adjust: adjustRating))
            } else {
                interactiveLadder(in: proxy.size)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .cloveGlass(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }

    /// The swipe ladder: one gesture owns physical taps and drags; the buttons also
    /// support VoiceOver (components.md).
    private func interactiveLadder(in extent: CGSize) -> some View {
        VerticalStarBarStars(
            rating: shownRating, enabledRatings: enabledRatings, size: size,
            identifier: identifier,
            onRate: size == .pad
                ? { level in
                    onBegin()
                    onCommit(level == rating ? .unrated : level)
                } : nil
        )
        .frame(width: extent.width, height: extent.height)
        .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    beginDragIfNeeded()
                    trackMove(value.translation)
                    guard movedPastTapSlop else { return }
                    previewDrag(at: value.location.y, in: extent.height)
                }
                .onEnded { value in
                    commit(value, in: extent.height)
                }
        )
        .onChange(of: isDragging) { _, dragging in
            guard !dragging else { return }
            // A cancelled gesture ends without `onEnded`, so clear what it previewed.
            preview = nil
            movedPastTapSlop = false
            didBeginDrag = false
        }
        .modifier(
            StarBarAccessibility(
                individualStars: size == .pad, value: accessibilityValue,
                adjust: adjustRating))
    }

    /// The reject stage the swipe down lands on (components.md): `flag.slash` on its own native
    /// glass chip, filled in `reject` when the swipe has reached it.
    private var rejectChip: some View {
        let rejectTitle = AppLocalization.string("Reject", language: language)
        return Button(action: onReject) {
            Image(systemName: isRejectStage ? "flag.slash.fill" : "flag.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isRejectStage ? Color.clove.reject : Color.clove.text.secondary)
                .frame(width: metrics.chip, height: metrics.chip)
                .contentShape(Circle())
                .cloveGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rejectTitle)
        .accessibilityIdentifier("\(identifier).reject")
        .help(rejectTitle)
    }

    /// Whether the ladder is showing the reject stage: only the display variant can, while a
    /// swipe previews −1.
    private var isRejectStage: Bool { shownRating == .rejected }

    /// Fills the bar and reports the live value while a drag runs (interactions.md).
    private func previewDrag(at y: CGFloat, in height: CGFloat) {
        guard let next = enabledRating(at: y, in: height), next != shownRating else { return }
        preview = next
        onPreview(next)
    }

    /// Remembers that the gesture moved at all, so a drag back to its start is not a tap.
    private func trackMove(_ translation: CGSize) {
        guard
            abs(translation.height) >= Self.tapSlop
                || abs(translation.width) >= Self.tapSlop
        else { return }
        movedPastTapSlop = true
    }

    /// Fires `onBegin` once per touch sequence before any commit can schedule a new advance.
    private func beginDragIfNeeded() {
        guard !didBeginDrag else { return }
        didBeginDrag = true
        onBegin()
    }

    /// Applies what the gesture chose; nothing is applied before this call (interactions.md).
    ///
    /// A gesture that never moved past the tap slop is a tap: an enabled star is picked, the
    /// photo's current value clears even when its level is disabled, and any other disabled star
    /// does nothing (PRD Marking rules, PRD Enabled rating levels). A drag commits the last value
    /// it previewed, so a drag back to its start keeps the rating instead of clearing it.
    private func commit(_ value: DragGesture.Value, in height: CGFloat) {
        beginDragIfNeeded()
        defer {
            preview = nil
            movedPastTapSlop = false
            didBeginDrag = false
        }
        guard movedPastTapSlop else {
            let drawn = drawnLevel(at: value.location.y, in: height)
            guard enabledRatings.contains(drawn) || drawn == rating else { return }
            onCommit(drawn == rating ? .unrated : drawn)
            return
        }
        guard let live = preview else { return }
        onCommit(live)
    }

    /// Steps the rating from VoiceOver, since the bar is one adjustable control.
    ///
    /// It offers no value below the lowest level: clearing is the toolbar's tap rule, and stepping
    /// down from one star stays at one (PRD Marking rules).
    private func adjustRating(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            guard let level = enabledRatings.levels.first(where: { $0 > rating }) else { return }
            onCommit(level)
        case .decrement:
            guard let level = enabledRatings.levels.last(where: { $0 < rating }) else { return }
            onCommit(level)
        @unknown default:
            return
        }
    }

    /// The rating the bar reports to VoiceOver (copy.md `a11y.rating`).
    private var accessibilityValue: String {
        AppLocalization.ratingTitle(rating, language: language)
    }

    /// The star a drag at `y` points at: the stars fill from the bottom (components.md).
    private func drawnLevel(at y: CGFloat, in height: CGFloat) -> Rating {
        let levels = EnabledRatings.all.levels
        let innerHeight = max(height - 2 * metrics.padding, 1)
        let filled = Int(
            ((innerHeight - (y - metrics.padding)) / innerHeight * CGFloat(levels.count)).rounded(
                .up))
        return levels[min(max(filled, 1), levels.count) - 1]
    }

    /// The enabled level a drag at `y` applies: the nearest one at or below the star it points at,
    /// or nil under the lowest enabled level (PRD Enabled rating levels).
    private func enabledRating(at y: CGFloat, in height: CGFloat) -> Rating? {
        let drawn = drawnLevel(at: y, in: height)
        return enabledRatings.levels.last { $0 <= drawn }
    }

    /// How far a gesture may move and still count as a tap.
    private static let tapSlop: CGFloat = 4
}

/// A read-out for photo swipes. It installs no gestures, buttons or adjustable actions.
///
/// The ladder mirrors the interactive bar's native glass styling, and the chip below it names the
/// stage the swipe is on: `flag.slash` in secondary text during 1–5 star rating swipes,
/// `star.slash` in secondary text while the swipe previews clear (all stars empty), and
/// `flag.slash.fill` in `reject` while it previews Reject (owner decision, 2026-11-13, #227).
struct VerticalStarBarDisplay: View {
    enum ChipStage: Equatable, Sendable {
        case ratingSwipe
        case clear
        case reject

        var symbolName: String {
            switch self {
            case .ratingSwipe: "flag.slash"
            case .clear: "star.slash"
            case .reject: "flag.slash.fill"
            }
        }

        var token: ThemeToken {
            switch self {
            case .ratingSwipe, .clear: .secondaryText
            case .reject: .reject
            }
        }
    }

    let rating: Rating
    var enabledRatings: EnabledRatings = .all
    var isReject = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let metrics = VerticalStarBarMetrics(size: .phone)

    /// The whole read-out, including the gap and reject chip, for stage placement.
    var stageSize: CGSize {
        CGSize(
            width: metrics.width,
            height: metrics.height + metrics.chipGap + metrics.chip)
    }

    /// The whole read-out's size for callers that cannot hold an instance; the ladder's
    /// geometry is fixed, so it never reads the theme or the rating.
    static var size: CGSize {
        VerticalStarBarDisplay(rating: .unrated).stageSize
    }

    static func chipStage(for rating: Rating, isReject: Bool) -> ChipStage {
        if isReject || rating == .rejected {
            return .reject
        }
        if rating.starCount != nil {
            return .ratingSwipe
        }
        return .clear
    }

    var body: some View {
        let stepAnimation = CloveMotion.micro(reduceMotion: reduceMotion)
        let chipStage = Self.chipStage(for: rating, isReject: isReject)
        VStack(spacing: metrics.chipGap) {
            VerticalStarBarStars(rating: rating, enabledRatings: enabledRatings, size: .phone)
                .frame(width: metrics.width, height: metrics.height)
                .cloveGlass(in: RoundedRectangle(cornerRadius: metrics.cornerRadius))
                .animation(stepAnimation, value: rating)
            Image(systemName: chipStage.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CloveColour(chipStage.token))
                .frame(width: metrics.chip, height: metrics.chip)
                .cloveGlass(in: Circle())
                .animation(stepAnimation, value: chipStage)
        }
        .allowsHitTesting(false)
    }
}

/// Shared pixels for the interactive ladder and the display-only swipe indicator.
private struct VerticalStarBarStars: View {
    let rating: Rating
    let enabledRatings: EnabledRatings
    let size: ControlSize
    var identifier = "clove.mark.starBar"
    var onRate: ((Rating) -> Void)?

    @Environment(\.appLanguage) private var language

    private var metrics: VerticalStarBarMetrics { VerticalStarBarMetrics(size: size) }

    var body: some View {
        VStack(spacing: metrics.gap) {
            ForEach(EnabledRatings.all.levels.reversed(), id: \.rawValue) { level in
                let filled = level <= rating
                let label = AppLocalization.starCount(level.starCount ?? 0, language: language)
                if let onRate {
                    Button {
                        onRate(level)
                    } label: {
                        star(filled: filled, level: level)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabledRatings.contains(level) && level != rating)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(level == rating ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).\(level.rawValue)")
                    .help(label)
                } else {
                    star(filled: filled, level: level)
                }
            }
        }
        .padding(metrics.padding)
    }

    private func star(filled: Bool, level: Rating) -> some View {
        Image(systemName: filled ? "star.fill" : "star")
            .font(.system(size: metrics.symbol, weight: .semibold))
            .foregroundStyle(filled ? Color.clove.rating.on : Color.clove.rating.off)
            .opacity(enabledRatings.contains(level) ? 1 : 0.35)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
private struct StarBarAccessibility: ViewModifier {
    let individualStars: Bool
    let value: String
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    @Environment(\.appLanguage) private var language

    func body(content: Content) -> some View {
        if individualStars {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AppLocalization.string("Rating", language: language))
                .accessibilityValue(value)
                .accessibilityAdjustableAction(adjust)
        }
    }
}

/// The ladder's geometry: 48 × 204 with a 44 pt chip and about 10 pt of gap (`components.md`).
private struct VerticalStarBarMetrics {
    let size: ControlSize

    /// The ladder's width: 48 pt (`components.md`).
    var width: CGFloat { 48 }

    /// The ladder's height: 204 pt with five rows, gap 7, and padding 10 (`components.md`).
    var height: CGFloat { 204 }

    /// The corner radius: 24 pt (`components.md`).
    var cornerRadius: CGFloat { 24 }

    /// The gap between the rows (components.md).
    var gap: CGFloat { 7 }

    /// The ladder's inner padding (components.md).
    var padding: CGFloat { 10 }

    /// The star symbol's point size (components.md).
    var symbol: CGFloat { 15 }

    /// The reject chip: 44 pt (`components.md`).
    var chip: CGFloat { 44 }

    /// The gap between the ladder and the chip, about 10 pt (components.md).
    var chipGap: CGFloat { 10 }
}

#Preview("Quick-rating ladder") {
    HStack(alignment: .top, spacing: 16) {
        VerticalStarBar(
            rating: Rating(rawValue: 2) ?? .unrated, identifier: "preview.starBar",
            onPreview: { _ in }, onCommit: { _ in }, onReject: {})
        VerticalStarBarDisplay(rating: Rating(rawValue: 3) ?? .unrated)
        VerticalStarBarDisplay(rating: .unrated)
        VerticalStarBarDisplay(rating: .rejected, isReject: true)
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
