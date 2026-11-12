import CloveCore
import SwiftUI

/// The vertical star bar: a narrow glass pill of five stars that fill from the bottom, with a ✕
/// chip below it for the swipe-down reject (`design/handoff/components.md`, Vertical star bar).
///
/// It opens on a swipe up in iPhone detail and on the Duo dock's star button. Dragging fills the
/// stars from the bottom to the top and only the release commits, so the mark is written once:
/// ``onPreview`` reports the live value while the drag runs, for the capsule's stars to mirror it,
/// and ``onCommit`` reports the value the gesture ends on (`design/handoff/interactions.md`, iPhone
/// Detail). A tap picks the star it lands on, and tapping the photo's current value clears it, the
/// same rule as the capsule's stars (PRD Marking rules).
///
/// All five levels always show, because the enabled-ratings setting affects input only (PRD
/// Enabled rating levels): a disabled star is dimmed, a drag settles on the nearest enabled level
/// below it, and a tap on it does nothing. The iPad rail version is 43 × 174 with a padding of 10
/// and a gap of 6, and leaves the chip out because the rail has its own Reject circle.
struct VerticalStarBar: View {
    /// The photo's rating.
    let rating: Rating

    /// The levels input may apply; all five by default, and every level still shows.
    var enabledRatings: EnabledRatings = .all

    /// The size components.md measures on the device.
    var size: ControlSize = .phone

    /// Whether the ✕ chip is drawn; the iPhone and Duo bar has it, the iPad rail does not.
    var showsRejectChip = true

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.starBar"

    /// The live value while a drag runs, before release (interactions.md).
    let onPreview: (Rating) -> Void

    /// The value the gesture ends on; the one mark to apply (interactions.md).
    let onCommit: (Rating) -> Void

    /// Rejects the photo, the same as a swipe down (PRD Marking rules, interactions.md).
    let onReject: () -> Void

    /// Touching the bar cancels the previous mark's pending auto-advance.
    var onBegin: () -> Void = {}

    /// The value the drag is showing, or nil when no drag has run since the last commit.
    @State private var preview: Rating?

    /// Whether the running gesture has moved past the tap slop at any point.
    ///
    /// The final translation is not enough: a drag that leaves a star and comes back to it would
    /// otherwise look like a tap and clear the rating.
    @State private var movedPastTapSlop = false

    /// Whether a drag is running. SwiftUI resets gesture state when a gesture ends or is cancelled,
    /// so a cancelled drag cannot leave its preview behind.
    @GestureState private var isDragging = false

    /// The value the stars fill to: the drag's live value while one runs, else the photo's rating.
    private var shownRating: Rating { preview ?? rating }
    private var metrics: VerticalStarBarMetrics { VerticalStarBarMetrics(size: size) }

    var body: some View {
        VStack(spacing: 10) {
            pill
            if showsRejectChip {
                rejectChip
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The glass pill of stars, top to bottom from five to one (components.md).
    private var pill: some View {
        GeometryReader { proxy in
            VerticalStarBarStars(
                rating: shownRating, enabledRatings: enabledRatings, size: size,
                identifier: identifier,
                onRate: size == .pad
                    ? { level in
                        onCommit(level == rating ? .unrated : level)
                    } : nil
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            // One gesture owns physical taps and drags; the buttons also support VoiceOver.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        trackMove(value.translation)
                        guard movedPastTapSlop else { return }
                        previewDrag(at: value.location.y, in: proxy.size.height)
                    }
                    .onEnded { value in
                        commit(value, in: proxy.size.height)
                    }
            )
            .onChange(of: isDragging) { _, dragging in
                if dragging {
                    onBegin()
                } else {
                    // A cancelled gesture ends without `onEnded`, so clear what it previewed.
                    preview = nil
                    movedPastTapSlop = false
                }
            }
            .modifier(
                StarBarAccessibility(
                    individualStars: size == .pad, value: accessibilityValue,
                    adjust: adjustRating))
        }
        .frame(width: metrics.width, height: metrics.height)
        .cloveGlass(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }

    /// The ✕ chip the swipe down lands on (components.md): a light, thin ✕ on its own glass chip.
    private var rejectChip: some View {
        Button(action: onReject) {
            Image(systemName: "xmark")
                .font(.subheadline)
                .foregroundStyle(Color.clove.text.secondary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .cloveGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reject")
        .accessibilityIdentifier("\(identifier).reject")
    }

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

    /// Applies what the gesture chose; nothing is applied before this call (interactions.md).
    ///
    /// A gesture that never moved past the tap slop is a tap: an enabled star is picked, the
    /// photo's current value clears even when its level is disabled, and any other disabled star
    /// does nothing (PRD Marking rules, PRD Enabled rating levels). A drag commits the last value
    /// it previewed, so a drag back to its start keeps the rating instead of clearing it.
    private func commit(_ value: DragGesture.Value, in height: CGFloat) {
        defer {
            preview = nil
            movedPastTapSlop = false
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
    /// It offers no value below the lowest level: clearing is the capsule's tap rule, and stepping
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
        guard let stars = rating.starCount else { return "Unrated" }
        return stars == 1 ? "1 star" : "\(stars) stars"
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
struct VerticalStarBarDisplay: View {
    let rating: Rating
    var enabledRatings: EnabledRatings = .all
    var isReject = false

    private let metrics = VerticalStarBarMetrics(size: .phone)
    private static let spacing: CGFloat = 10
    private static let chipSize: CGFloat = 40

    /// The whole read-out, including the gap and reject chip, for stage placement.
    static var size: CGSize {
        let metrics = VerticalStarBarMetrics(size: .phone)
        return CGSize(width: metrics.width, height: metrics.height + spacing + chipSize)
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            VerticalStarBarStars(rating: rating, enabledRatings: enabledRatings, size: .phone)
                .frame(width: metrics.width, height: metrics.height)
                .cloveGlass(in: RoundedRectangle(cornerRadius: metrics.cornerRadius))
            Image(systemName: "xmark")
                .font(.subheadline)
                .foregroundStyle(isReject ? Color.clove.reject : Color.clove.text.secondary)
                .frame(width: Self.chipSize, height: Self.chipSize)
                .cloveGlass(in: Circle())
        }
        .allowsHitTesting(false)
    }
}

/// Shared pixels for the interactive rail and the display-only swipe indicator.
private struct VerticalStarBarStars: View {
    let rating: Rating
    let enabledRatings: EnabledRatings
    let size: ControlSize
    var identifier = "clove.mark.starBar"
    var onRate: ((Rating) -> Void)?

    var body: some View {
        let metrics = VerticalStarBarMetrics(size: size)
        VStack(spacing: metrics.gap) {
            ForEach(EnabledRatings.all.levels.reversed(), id: \.rawValue) { level in
                let filled = level <= rating
                let label = "\(level.starCount ?? 0) stars"
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
            .font(.title3)
            .foregroundStyle(filled ? Color.clove.rating.on : Color.clove.rating.off)
            .opacity(enabledRatings.contains(level) ? 1 : 0.35)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StarBarAccessibility: ViewModifier {
    let individualStars: Bool
    let value: String
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    func body(content: Content) -> some View {
        if individualStars {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rating")
                .accessibilityValue(value)
                .accessibilityAdjustableAction(adjust)
        }
    }
}

private struct VerticalStarBarMetrics {
    let size: ControlSize

    /// The pill's width: 40 on iPhone, 43 on the iPad rail (components.md).
    var width: CGFloat {
        switch size {
        case .phone: 40
        case .pad: 43
        case .duo: 40
        }
    }

    /// The pill's height: five rows of 30 with a gap of 6 and a padding of 10; the iPad rail is
    /// 174 high with 26 pt rows (components.md).
    var height: CGFloat {
        switch size {
        case .phone: 5 * 30 + 4 * gap + 2 * padding
        case .pad: 174
        case .duo: 5 * 30 + 4 * gap + 2 * padding
        }
    }

    /// The corner radius: 22 on the iPad rail, half the width on iPhone (components.md).
    var cornerRadius: CGFloat {
        switch size {
        case .phone: width / 2
        case .pad: 22
        case .duo: width / 2
        }
    }

    /// The gap between the rows: 6 on the iPad rail (components.md).
    var gap: CGFloat { 6 }

    /// The pill's inner padding: 10 (components.md).
    var padding: CGFloat { 10 }
}

#Preview("Vertical star bar") {
    HStack(alignment: .top, spacing: 16) {
        VerticalStarBar(
            rating: Rating(rawValue: 2) ?? .unrated, identifier: "preview.starBar",
            onPreview: { _ in }, onCommit: { _ in }, onReject: {})
        VerticalStarBar(
            rating: Rating(rawValue: 2) ?? .unrated, size: .pad, showsRejectChip: false,
            identifier: "preview.starBar.pad", onPreview: { _ in }, onCommit: { _ in },
            onReject: {})
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
