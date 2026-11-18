import SwiftUI
import UIKit

/// Stateless motion curves and Reduce Motion helpers shared across Clove's culling chrome.
///
/// Curves stay fast and non-blocking (`micro`, `chrome`, `progress`) so marking, gesture previews,
/// and navigation never slow down rapid culling. Under Reduce Motion, spatial scale, offset, and
/// spring transitions collapse to opacity-only transitions or `nil` (`instant`).
enum CloveMotion {
    static let microDuration: TimeInterval = 0.16
    static let chromeDuration: TimeInterval = 0.19
    static let progressDuration: TimeInterval = 0.22
    static let filmstripLevelDuration: TimeInterval = 0.24
    static let focusArrivalDuration: TimeInterval = 0.15

    static let pressScale: CGFloat = 0.95
    static let pressOpacity: Double = 0.88

    @MainActor
    static var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    static func micro(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: microDuration)
    }

    static func chrome(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: chromeDuration)
    }

    static func filmstripLevel(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: chromeDuration)
            : .spring(duration: filmstripLevelDuration, bounce: 0.12)
    }

    static func progress(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: progressDuration)
    }

    static func nudge(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.52)
    }

    /// Animates mark updates only when the target photo identity has already settled, so
    /// switching photos snaps marks and status glyphs on frame 0 without cross-photo animation.
    static func shouldAnimateMarkChange<ID: Equatable>(
        settledPhotoID: ID?,
        currentPhotoID: ID?
    ) -> Bool {
        guard let currentPhotoID else { return true }
        return settledPhotoID == currentPhotoID
    }

    static func scaleOpacityTransition(
        scale: CGFloat = 0.94,
        anchor: UnitPoint = .center,
        reduceMotion: Bool
    ) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: scale, anchor: anchor))
    }

    static func slideTransition(
        edge: Edge = .bottom,
        offset: CGFloat = 10,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let yOffset: CGFloat = edge == .top ? -offset : offset
        return .opacity.combined(with: .offset(y: yOffset))
    }

    static func bloomTransition(anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: scaleOpacityTransition(
                scale: 0.94, anchor: anchor, reduceMotion: reduceMotion),
            removal: .identity
        )
    }

    static func swipeFeedbackTransition(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: scaleOpacityTransition(
                scale: 0.94, anchor: .bottom, reduceMotion: reduceMotion),
            removal: .identity
        )
    }
}

/// Tactile press feedback for `.plain` floating glass controls without altering layout frames,
/// hit targets, or accessibility traits/identifiers.
struct CloveGlassPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressScale: CGFloat = CloveMotion.pressScale
    var pressOpacity: Double = CloveMotion.pressOpacity

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressScale : 1)
            .opacity(configuration.isPressed ? pressOpacity : 1)
            .animation(
                CloveMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CloveGlassPressButtonStyle {
    static var cloveGlassPress: CloveGlassPressButtonStyle {
        CloveGlassPressButtonStyle()
    }
}
