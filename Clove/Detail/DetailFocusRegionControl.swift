import SwiftUI
import UIKit

/// Theme colours resolved by the SwiftUI detail screen and applied by the UIKit zoom stage.
struct DetailFocusRegionColours: Equatable {
    let normal: UIColor
    let contrastEdge: UIColor
    let selected: UIColor
    let unavailable: UIColor

    static func == (first: Self, second: Self) -> Bool {
        first.normal.isEqual(second.normal)
            && first.contrastEdge.isEqual(second.contrastEdge)
            && first.selected.isEqual(second.selected)
            && first.unavailable.isEqual(second.unavailable)
    }
}

/// Camera-style focus overlay control (`autofocus` rectangle, `face` four-corner brackets,
/// `eye` small square). Screen-space stroke widths, eye square dimensions, and 44 pt hit targets
/// stay invariant through zoom without enlarging the visible marker to match its hit padding.
@MainActor
final class DetailFocusRegionControl: UIControl {
    static let normalScreenStrokeWidth: CGFloat = 1.25
    static let selectedScreenStrokeWidth: CGFloat = 1.5
    static let contrastEdgeExtraScreenWidth: CGFloat = 1.2
    static let eyeScreenSide: CGFloat = 16
    static let unavailableEyeScreenSide: CGFloat = 12
    static let minimumActionableScreenTarget: CGFloat = 44

    let region: DetailFocusRegion
    private let colours: DetailFocusRegionColours
    private let contrastOutline = CAShapeLayer()
    private let outline = CAShapeLayer()
    private var drawnRect: CGRect = .zero
    private var currentZoomScale: CGFloat = 1
    private var isInspectionSelected = false

    init(region: DetailFocusRegion, colours: DetailFocusRegionColours) {
        self.region = region
        self.colours = colours
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityIdentifier = region.id
        accessibilityLabel = region.kind.accessibilityName
        isExclusiveTouch = true

        for shape in [contrastOutline, outline] {
            shape.fillColor = nil
            shape.lineCap = .butt
            shape.lineJoin = .miter
            layer.addSublayer(shape)
        }

        if !region.isActionable {
            accessibilityTraits = [.image, .notEnabled]
            accessibilityValue = region.unavailableAccessibilityDescription
        } else {
            accessibilityTraits = .button
            accessibilityHint = "Shows 100% zoom centred on this region"
        }
        applyVisualStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var visualFrameInSuperview: CGRect {
        drawnRect.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    var drawnShapeBounds: CGRect { drawnRect }

    var primaryStrokeWidth: CGFloat { outline.lineWidth }

    var hasFill: Bool {
        outline.fillColor != nil || contrastOutline.fillColor != nil
    }

    func place(actualRect: CGRect, zoomScale: CGFloat = 1, isSelected: Bool = false) {
        let scale = max(zoomScale, 1)
        currentZoomScale = scale
        isInspectionSelected = isSelected && region.isActionable

        let visualRect: CGRect
        switch region.kind {
        case .autofocus, .face:
            visualRect = actualRect
        case .eye:
            let side =
                (region.isActionable ? Self.eyeScreenSide : Self.unavailableEyeScreenSide) / scale
            visualRect = CGRect(
                x: actualRect.midX - side / 2,
                y: actualRect.midY - side / 2,
                width: side,
                height: side)
        }

        let minLocalTarget = (region.isActionable ? Self.minimumActionableScreenTarget : 10) / scale
        let target = visualRect.insetBy(
            dx: min(0, (visualRect.width - minLocalTarget) / 2),
            dy: min(0, (visualRect.height - minLocalTarget) / 2))
        frame = target
        drawnRect = visualRect.offsetBy(dx: -target.minX, dy: -target.minY)

        if region.isActionable {
            accessibilityTraits = isInspectionSelected ? [.button, .selected] : .button
        }
        applyVisualStyle()
        setNeedsLayout()
    }

    private func applyVisualStyle() {
        let scale = max(currentZoomScale, 1)
        let screenStroke: CGFloat =
            !region.isActionable
            ? Self.normalScreenStrokeWidth
            : (isInspectionSelected
                ? Self.selectedScreenStrokeWidth : Self.normalScreenStrokeWidth)
        let primaryWidth = screenStroke / scale
        let contrastWidth = (screenStroke + Self.contrastEdgeExtraScreenWidth) / scale

        outline.lineWidth = primaryWidth
        contrastOutline.lineWidth = contrastWidth

        if !region.isActionable {
            let dash: [NSNumber] = [
                NSNumber(value: Double(4 / scale)), NSNumber(value: Double(3 / scale)),
            ]
            outline.strokeColor = colours.unavailable.cgColor
            outline.lineDashPattern = dash
            contrastOutline.strokeColor = colours.contrastEdge.withAlphaComponent(0.28).cgColor
            contrastOutline.lineDashPattern = dash
        } else {
            outline.strokeColor =
                (isInspectionSelected ? colours.selected : colours.normal).cgColor
            outline.lineDashPattern = nil
            contrastOutline.strokeColor = colours.contrastEdge.cgColor
            contrastOutline.lineDashPattern = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path: UIBezierPath
        switch region.kind {
        case .autofocus, .eye:
            path = UIBezierPath(rect: drawnRect)
        case .face:
            path = Self.cornerBracketPath(for: drawnRect, zoomScale: currentZoomScale)
        }
        contrastOutline.path = path.cgPath
        outline.path = path.cgPath
    }

    private static func cornerBracketPath(for rect: CGRect, zoomScale: CGFloat) -> UIBezierPath {
        let scale = max(zoomScale, 1)
        let minSide = min(rect.width, rect.height)
        let arm = min(max(minSide * 0.22, 8 / scale), min(24 / scale, minSide * 0.42))
        let path = UIBezierPath()

        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

        // Top-right
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        return path
    }
}
