import CloveCore
import SwiftUI

/// The vertical star bar: a narrow glass pill of five stars that fill from the bottom, with a ✕
/// chip below it for the swipe-down reject (`design/handoff/components.md`, Vertical star bar).
///
/// It opens on a swipe up in iPhone detail and on the Duo dock's star button. Tapping or dragging
/// sets the rating: the bottom star is one and the top is five, and dragging past the current value
/// keeps filling, which is how the gesture's distance reads. The iPad rail version is 43 × 174 with
/// a padding of 10 and a gap of 6, and leaves the chip out because the rail has its own Reject
/// circle.
struct VerticalStarBar: View {
    /// The photo's rating.
    let rating: Rating

    /// The levels the bar offers, ascending; the settings' enabled levels by default.
    var levels: [Rating] = EnabledRatings.all.levels

    /// The size components.md measures on the device.
    var size: ControlSize = .phone

    /// Whether the ✕ chip is drawn; the iPhone and Duo bar has it, the iPad rail does not.
    var showsRejectChip = true

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.starBar"

    /// Applies a rating, or clears it (PRD Marking rules).
    let onRate: (Rating) -> Void

    /// Rejects the photo, the same as a swipe down (PRD Marking rules, interactions.md).
    let onReject: () -> Void

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
            VStack(spacing: gap) {
                ForEach(levels.reversed(), id: \.rawValue) { level in
                    star(level)
                }
            }
            .padding(padding)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onRate(rating(at: value.location.y, in: proxy.size.height))
                    }
            )
        }
        .frame(width: width, height: height)
        .cloveGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// One star; the filled ones start at the bottom (components.md).
    private func star(_ level: Rating) -> some View {
        let isFilled = level <= rating
        return Button {
            onRate(level == rating ? .unrated : level)
        } label: {
            Image(systemName: isFilled ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isFilled ? Color.clove.rating.on : Color.clove.rating.off)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.rawValue) stars")
        .accessibilityAddTraits(level == rating ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).star.\(level.rawValue)")
    }

    /// The ✕ chip the swipe down lands on (components.md).
    private var rejectChip: some View {
        Button(action: onReject) {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(Color.clove.text.primary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .cloveGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reject")
        .accessibilityIdentifier("\(identifier).reject")
    }

    /// The rating for a drag at `y`: the stars fill from the bottom (components.md).
    private func rating(at y: CGFloat, in height: CGFloat) -> Rating {
        let innerHeight = max(height - 2 * padding, 1)
        let filled = Int(
            ((innerHeight - (y - padding)) / innerHeight * CGFloat(levels.count)).rounded(.up))
        return levels[min(max(filled, 1), levels.count) - 1]
    }

    /// The pill's width: 40 on iPhone and 43 on the iPad rail (components.md).
    private var width: CGFloat {
        switch size {
        case .phone: 40
        case .pad: 43
        case .duo: 40
        }
    }

    /// The pill's height: five rows of 30 with a gap of 6 and a padding of 10; the iPad rail is
    /// 174 high with 26 pt rows (components.md).
    private var height: CGFloat {
        switch size {
        case .phone: 5 * 30 + 4 * gap + 2 * padding
        case .pad: 174
        case .duo: 5 * 30 + 4 * gap + 2 * padding
        }
    }

    /// The corner radius: 22 on the iPad rail, half the width on iPhone (components.md).
    private var cornerRadius: CGFloat {
        switch size {
        case .phone: width / 2
        case .pad: 22
        case .duo: width / 2
        }
    }

    /// The gap between the rows: 6 on the iPad rail (components.md).
    private var gap: CGFloat { 6 }

    /// The pill's inner padding: 10 (components.md).
    private var padding: CGFloat { 10 }
}

#Preview("Vertical star bar") {
    HStack(alignment: .top, spacing: 16) {
        VerticalStarBar(
            rating: Rating(rawValue: 2) ?? .unrated, identifier: "preview.starBar",
            onRate: { _ in }, onReject: {})
        VerticalStarBar(
            rating: Rating(rawValue: 2) ?? .unrated, size: .pad, showsRejectChip: false,
            identifier: "preview.starBar.pad", onRate: { _ in }, onReject: {})
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
