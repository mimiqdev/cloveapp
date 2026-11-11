import CloveCore
import Observation
import SwiftUI
import UIKit

/// The live rating read-out for a marking swipe (PRD Rating by swipe distance).
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

    /// Whether the badge shows at all; back at the start it shows nothing.
    var isShowing: Bool { rating != nil || isReject }

    /// Hides the badge, for a release, a system cancel and a return to the start.
    func clear() {
        rating = nil
        isReject = false
    }
}

/// The handoff's vertical ladder mirrors the gesture's existing resolved step.
/// It has no gesture of its own here; release still commits through the original input rules.
struct DetailSwipeFeedbackBadge: View {
    let feedback: DetailSwipeFeedback
    var enabledRatings: EnabledRatings = .all
    var bottomInset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            if feedback.isShowing {
                VerticalStarBarDisplay(
                    rating: feedback.rating ?? .unrated, enabledRatings: enabledRatings,
                    isReject: feedback.isReject
                )
                .position(
                    x: max(proxy.size.width - 36, 20),
                    y: max(0, proxy.size.height - bottomInset) / 2
                )
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("clove.detail.swipeFeedback")
                .accessibilityLabel(
                    feedback.isReject ? "Reject" : "\(feedback.rating?.starCount ?? 0) stars")
            }
        }
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
