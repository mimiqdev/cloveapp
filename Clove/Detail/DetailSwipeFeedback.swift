import CloveCore
import Observation
import SwiftUI
import UIKit

/// The session's live preview. Nil hides it; zero shows the star bar with no filled stars.
/// Pixels, zoom and filmstrip state do not change with each touch sample.
@MainActor
@Observable
final class DetailSwipeFeedback {
    /// The original touch in stage coordinates, captured once when the marking swipe begins.
    var startLocation: CGPoint = .zero

    /// The live rating, including zero (clear) and −1 (Reject).
    var rating: Rating?

    var isReject: Bool { rating == .rejected }
    var isShowing: Bool { rating != nil }

    /// A release or system cancellation hides the preview.
    func clear() {
        rating = nil
    }
}

/// Glyphs only, including an empty star bar for clear; words belong to the VoiceOver label.
struct DetailSwipeFeedbackBadge: View {
    let feedback: DetailSwipeFeedback
    var enabledRatings: EnabledRatings = .all
    let controlsHeight: CGFloat
    let chromeIsVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            if feedback.isShowing {
                VerticalStarBarDisplay(
                    rating: feedback.rating ?? .unrated, enabledRatings: enabledRatings,
                    isReject: feedback.isReject
                )
                .position(
                    Self.position(
                        in: proxy.size, startLocation: feedback.startLocation,
                        controlsHeight: controlsHeight,
                        chromeIsVisible: chromeIsVisible)
                )
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("clove.detail.swipeFeedback")
                .accessibilityLabel(
                    feedback.isReject
                        ? "Reject"
                        : (feedback.rating == .unrated
                            ? "Clear rating" : "\(feedback.rating?.starCount ?? 0) stars"))
            }
        }
    }

    static func position(
        in size: CGSize, startLocation: CGPoint, controlsHeight: CGFloat, chromeIsVisible: Bool
    ) -> CGPoint {
        let bar = VerticalStarBarDisplay.size
        let inset: CGFloat = 8
        // 24 pt from the finger's edge, allowing 22 pt from its centre to that edge.
        let offset = 46 + bar.width / 2
        let proposedX = startLocation.x + (startLocation.x < size.width / 3 ? offset : -offset)
        let minX = inset + bar.width / 2
        let maxX = max(minX, size.width - inset - bar.width / 2)
        // The stage begins below the header and is already inside the screen's safe area.
        let minY = inset + bar.height / 2
        let maxY = max(
            minY,
            size.height - (chromeIsVisible ? controlsHeight : 0) - inset - bar.height / 2)
        return CGPoint(
            x: min(max(proposedX, minX), maxX),
            y: min(max(startLocation.y, minY), maxY))
    }
}

/// Starting strengths, tuned with the distances on an iPhone.
@MainActor
final class MarkingSwipeHaptics {
    private static let stepStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light
    private static let clearStyle: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    private static let rejectStyle: UIImpactFeedbackGenerator.FeedbackStyle = .heavy
    private static let stepIntensity: CGFloat = 0.5
    private static let clearIntensity: CGFloat = 0.7
    private static let rejectIntensity: CGFloat = 1

    private let step = UIImpactFeedbackGenerator(style: stepStyle)
    private let clear = UIImpactFeedbackGenerator(style: clearStyle)
    private let reject = UIImpactFeedbackGenerator(style: rejectStyle)

    func prepare() {
        step.prepare()
        clear.prepare()
        reject.prepare()
    }

    func crossed(_ haptic: MarkingStageCrossing.Haptic) {
        switch haptic {
        case .step:
            step.impactOccurred(intensity: Self.stepIntensity)
            step.prepare()
        case .clear:
            clear.impactOccurred(intensity: Self.clearIntensity)
            clear.prepare()
        case .reject:
            reject.impactOccurred(intensity: Self.rejectIntensity)
            reject.prepare()
        }
    }
}
