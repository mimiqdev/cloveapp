import CloveCore
import Observation
import SwiftUI
import UIKit

/// The live feedback one marking swipe shows near the finger (PRD Rating by swipe distance).
///
/// The step ladder itself belongs to C13 (``SwipeRatingSession``); this value only carries what
/// the preview draws while the finger moves, so the screen's other state — the pixels, the zoom,
/// the filmstrip — is not rewritten on every touch sample. Step 0 shows nothing, which is also
/// what a system cancel and a return to the start look like (PRD Rating by swipe distance).
@MainActor
@Observable
final class DetailSwipeFeedback {
    /// The enabled rating the finger is on, or nil inside the dead zone (PRD Enabled rating
    /// levels).
    var rating: Rating?

    /// Whether releasing now would reject (PRD Detail gestures: swipe down past the threshold).
    var isReject = false

    /// Where the finger is, in the preview's own coordinate space.
    var location: CGPoint = .zero

    /// Whether the badge shows at all; back at the start it shows nothing.
    var isShowing: Bool { rating != nil || isReject }

    /// Hides the badge, for a release, a system cancel and a return to the start.
    func clear() {
        rating = nil
        isReject = false
    }
}

/// The rating or Reject badge that follows the finger during a marking swipe (PRD P0-06,
/// PRD Rating by swipe distance).
///
/// Design placeholder: a capsule of system stars, and the Reject symbol, stand in for the visual
/// design's own indicator. The position near the finger, the stars for the enabled level the
/// finger is on and the light haptic at each step are the behaviour P0-06 fixes.
struct DetailSwipeFeedbackBadge: View {
    /// The live state the swipe writes as the finger moves.
    let feedback: DetailSwipeFeedback

    var body: some View {
        GeometryReader { proxy in
            if feedback.isShowing {
                indicator
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .position(badgeCentre(in: proxy.size))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("clove.detail.swipeFeedback")
                    .accessibilityLabel(indicatorName)
            }
        }
    }

    /// The badge sits just above the finger, and inside the preview, so the hand never covers the
    /// step it is on (PRD Rating by swipe distance; PRD Detail and marking keeps marks out from
    /// under the hand).
    ///
    /// Design placeholder: the lift and the half extents are the indicator's own size, which the
    /// visual design replaces.
    private func badgeCentre(in size: CGSize) -> CGPoint {
        let lift: CGFloat = 56
        let halfWidth: CGFloat = 70
        let halfHeight: CGFloat = 20
        return CGPoint(
            x: min(max(feedback.location.x, halfWidth), max(size.width - halfWidth, halfWidth)),
            y: min(
                max(feedback.location.y - lift, halfHeight),
                max(size.height - halfHeight, halfHeight)))
    }

    /// The rating the finger is on, or the Reject symbol past the threshold (PRD P0-15 colours).
    @ViewBuilder private var indicator: some View {
        if feedback.isReject {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        } else if let rating = feedback.rating {
            HStack(spacing: 2) {
                ForEach(0..<rating.rawValue, id: \.self) { _ in
                    Image(systemName: "star.fill")
                }
            }
            .font(.title3)
            .foregroundStyle(.orange)
        }
    }

    /// What VoiceOver reads for the badge, which is the same words the marks use.
    private var indicatorName: String {
        if feedback.isReject { return "Reject" }
        return "\(feedback.rating?.rawValue ?? 0) stars"
    }
}

/// The light haptics one marking swipe plays (PRD Rating by swipe distance).
///
/// A selection generator ticks once per rating step boundary, up or down, so swiping back lowers
/// the rating with the same feedback as raising it. The Reject threshold is not a rating step, so
/// it gets one light impact when it is entered or left (PRD Detail gestures). Both generators are
/// prepared as the swipe begins, so the first tick is not late.
@MainActor
final class MarkingSwipeHaptics {
    private let step = UISelectionFeedbackGenerator()
    private let threshold = UIImpactFeedbackGenerator(style: .light)

    /// Warms both generators as a marking swipe begins.
    func prepare() {
        step.prepare()
        threshold.prepare()
    }

    /// One rating step boundary crossed, in either direction (PRD Rating by swipe distance).
    func crossedStep() {
        step.selectionChanged()
        step.prepare()
    }

    /// The Reject threshold entered or left (PRD Detail gestures).
    func crossedRejectThreshold() {
        threshold.impactOccurred()
        threshold.prepare()
    }
}
