import SwiftUI
import UIKit

/// Theme colours resolved by the SwiftUI detail screen and applied by the UIKit zoom stage.
struct DetailFocusRegionColours: Equatable {
    let autofocus: UIColor
    let face: UIColor
    let eye: UIColor
    let unavailable: UIColor

    static func == (first: Self, second: Self) -> Bool {
        first.autofocus.isEqual(second.autofocus)
            && first.face.isEqual(second.face)
            && first.eye.isEqual(second.eye)
            && first.unavailable.isEqual(second.unavailable)
    }
}

/// A region's visible rectangle and its touch target are separate: an eye can stay accurately
/// drawn while its valid target still meets the system's 44-point touch size.
@MainActor
final class DetailFocusRegionControl: UIControl {
    let region: DetailFocusRegion
    private let outline = CAShapeLayer()
    private var drawnRect: CGRect = .zero

    init(region: DetailFocusRegion, colours: DetailFocusRegionColours) {
        self.region = region
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityIdentifier = region.id
        accessibilityLabel = region.kind.accessibilityName
        isExclusiveTouch = true
        layer.addSublayer(outline)
        outline.fillColor = colours.colour(for: region).withAlphaComponent(0.08).cgColor
        outline.strokeColor = colours.colour(for: region).cgColor
        outline.lineWidth = region.isActionable ? 2 : 1.5
        if !region.isActionable {
            outline.lineDashPattern = [4, 3]
            accessibilityTraits = [.image, .notEnabled]
            accessibilityValue = region.unavailableAccessibilityDescription
        } else {
            accessibilityTraits = .button
            accessibilityHint = "Shows 100% zoom centred on this region"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func place(actualRect: CGRect) {
        let target =
            region.isActionable
            ? actualRect.insetBy(
                dx: min(0, (actualRect.width - 44) / 2),
                dy: min(0, (actualRect.height - 44) / 2))
            : actualRect.insetBy(
                dx: min(0, (actualRect.width - 10) / 2),
                dy: min(0, (actualRect.height - 10) / 2))
        frame = target
        drawnRect = actualRect.offsetBy(dx: -target.minX, dy: -target.minY)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path: UIBezierPath
        switch region.kind {
        case .autofocus:
            path = UIBezierPath(rect: drawnRect)
        case .face:
            path = UIBezierPath(
                roundedRect: drawnRect, cornerRadius: min(8, drawnRect.width / 4))
        case .eye:
            path = UIBezierPath(ovalIn: drawnRect)
        }
        outline.path = path.cgPath
    }
}

private extension DetailFocusRegionColours {
    func colour(for region: DetailFocusRegion) -> UIColor {
        guard region.isActionable else { return unavailable }
        switch region.kind {
        case .autofocus: return autofocus
        case .face: return face
        case .eye: return eye
        }
    }
}
