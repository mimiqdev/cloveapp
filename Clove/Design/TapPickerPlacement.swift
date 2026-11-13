import Observation
import SwiftUI

/// Adaptive placement for floating tap pickers (`RatingPicker`, `LabelPicker`).
///
/// Horizontal anchored above the toolbar action is the default. Vertical is chosen automatically
/// when anchored along a vertical edge or when available horizontal space cannot hold the picker
/// cleanly inside safe areas and away from Duo's secondary action rail.
struct TapPickerPlacement: Equatable, Sendable {
    let axis: Axis
    let frame: CGRect

    static func resolve(
        anchor: CGRect,
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        horizontalSize: CGSize,
        verticalSize: CGSize,
        preferredEdge: Edge = .top,
        margin: CGFloat = 12,
        gap: CGFloat = 10
    ) -> TapPickerPlacement {
        let minX = safeAreaInsets.leading + margin
        let maxX = max(minX, containerSize.width - safeAreaInsets.trailing - margin)
        let minY = safeAreaInsets.top + margin
        let maxY = max(minY, containerSize.height - safeAreaInsets.bottom - margin)
        let safeBounds = CGRect(
            x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))

        let axis = chooseAxis(
            anchor: anchor,
            safeBounds: safeBounds,
            horizontalSize: horizontalSize,
            verticalSize: verticalSize,
            preferredEdge: preferredEdge,
            gap: gap)

        let size = axis == .horizontal ? horizontalSize : verticalSize
        let origin = chooseOrigin(
            axis: axis,
            size: size,
            anchor: anchor,
            safeBounds: safeBounds,
            preferredEdge: preferredEdge,
            gap: gap)

        return TapPickerPlacement(axis: axis, frame: CGRect(origin: origin, size: size))
    }

    private static func chooseAxis(
        anchor: CGRect,
        safeBounds: CGRect,
        horizontalSize: CGSize,
        verticalSize: CGSize,
        preferredEdge: Edge,
        gap: CGFloat
    ) -> Axis {
        let verticalFitsHeight = verticalSize.height <= safeBounds.height
        let horizontalFitsWidth = horizontalSize.width <= safeBounds.width

        if preferredEdge == .leading || preferredEdge == .trailing {
            return verticalFitsHeight ? .vertical : .horizontal
        }

        if !horizontalFitsWidth, verticalFitsHeight {
            return .vertical
        }

        let fitsAbove = anchor.minY - gap - horizontalSize.height >= safeBounds.minY
        let fitsBelow = anchor.maxY + gap + horizontalSize.height <= safeBounds.maxY
        if !fitsAbove && !fitsBelow && verticalFitsHeight {
            let fitsLeft = anchor.minX - gap - verticalSize.width >= safeBounds.minX
            let fitsRight = anchor.maxX + gap + verticalSize.width <= safeBounds.maxX
            if fitsLeft || fitsRight {
                return .vertical
            }
        }

        return .horizontal
    }

    private static func chooseOrigin(
        axis: Axis,
        size: CGSize,
        anchor: CGRect,
        safeBounds: CGRect,
        preferredEdge: Edge,
        gap: CGFloat
    ) -> CGPoint {
        switch axis {
        case .horizontal:
            let x = clamp(
                anchor.midX - size.width / 2,
                min: safeBounds.minX,
                max: max(safeBounds.minX, safeBounds.maxX - size.width))
            let aboveY = anchor.minY - gap - size.height
            let belowY = anchor.maxY + gap
            let rawY: CGFloat
            if preferredEdge == .bottom {
                rawY = belowY + size.height <= safeBounds.maxY ? belowY : aboveY
            } else {
                rawY =
                    aboveY >= safeBounds.minY
                    ? aboveY
                    : (belowY + size.height <= safeBounds.maxY ? belowY : aboveY)
            }
            let y = clamp(
                rawY,
                min: safeBounds.minY,
                max: max(safeBounds.minY, safeBounds.maxY - size.height))
            return CGPoint(x: x, y: y)

        case .vertical:
            let x: CGFloat
            if preferredEdge == .leading {
                let leftX = anchor.minX - gap - size.width
                let rightX = anchor.maxX + gap
                let rawX =
                    leftX >= safeBounds.minX
                    ? leftX
                    : (rightX + size.width <= safeBounds.maxX ? rightX : leftX)
                x = clamp(
                    rawX,
                    min: safeBounds.minX,
                    max: max(safeBounds.minX, safeBounds.maxX - size.width))
            } else if preferredEdge == .trailing {
                let rightX = anchor.maxX + gap
                let leftX = anchor.minX - gap - size.width
                let rawX =
                    rightX + size.width <= safeBounds.maxX
                    ? rightX
                    : (leftX >= safeBounds.minX ? leftX : rightX)
                x = clamp(
                    rawX,
                    min: safeBounds.minX,
                    max: max(safeBounds.minX, safeBounds.maxX - size.width))
            } else {
                let aboveY = anchor.minY - gap - size.height
                if aboveY >= safeBounds.minY {
                    x = clamp(
                        anchor.midX - size.width / 2,
                        min: safeBounds.minX,
                        max: max(safeBounds.minX, safeBounds.maxX - size.width))
                } else {
                    let leftX = anchor.minX - gap - size.width
                    let rightX = anchor.maxX + gap
                    let rawX: CGFloat
                    if leftX >= safeBounds.minX {
                        rawX = leftX
                    } else if rightX + size.width <= safeBounds.maxX {
                        rawX = rightX
                    } else {
                        rawX = anchor.midX - size.width / 2
                    }
                    x = clamp(
                        rawX,
                        min: safeBounds.minX,
                        max: max(safeBounds.minX, safeBounds.maxX - size.width))
                }
            }

            let rawY: CGFloat
            if preferredEdge == .leading || preferredEdge == .trailing {
                rawY = anchor.midY - size.height / 2
            } else {
                let aboveY = anchor.minY - gap - size.height
                rawY = aboveY >= safeBounds.minY ? aboveY : anchor.midY - size.height / 2
            }
            let y = clamp(
                rawY,
                min: safeBounds.minY,
                max: max(safeBounds.minY, safeBounds.maxY - size.height))
            return CGPoint(x: x, y: y)
        }
    }

    private static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}

enum TapPickerSpace {
    static let name = "clove.tapPicker.coordinateSpace"
}

/// Manages one active anchored tap picker inside a ``TapPickerContainer``.
@MainActor
@Observable
final class TapPickerController {
    struct Presentation {
        let id: String
        var anchor: CGRect
        let horizontalSize: CGSize
        let verticalSize: CGSize
        let preferredEdge: Edge
        let content: @MainActor (Axis, @escaping @MainActor () -> Void) -> AnyView
    }

    private(set) var active: Presentation?

    var isPresented: Bool { active != nil }

    func isPresented(id: String) -> Bool {
        active?.id == id
    }

    func toggle(
        id: String,
        anchor: CGRect,
        horizontalSize: CGSize,
        verticalSize: CGSize,
        preferredEdge: Edge = .top,
        @ViewBuilder content:
            @escaping @MainActor (Axis, @escaping @MainActor () -> Void) -> some View
    ) {
        if active?.id == id {
            active = nil
            return
        }
        active = Presentation(
            id: id,
            anchor: anchor,
            horizontalSize: horizontalSize,
            verticalSize: verticalSize,
            preferredEdge: preferredEdge,
            content: { axis, dismiss in AnyView(content(axis, dismiss)) })
    }

    func updateAnchor(id: String, anchor: CGRect) {
        guard var current = active, current.id == id else { return }
        current.anchor = anchor
        active = current
    }

    func dismiss() {
        active = nil
    }
}

extension EnvironmentValues {
    @Entry var tapPickerController: TapPickerController? = nil
}

private struct TapPickerContainerModifier<Trigger: Equatable>: ViewModifier {
    @State private var controller = TapPickerController()
    let dismissTrigger: Trigger

    func body(content: Content) -> some View {
        content
            .environment(\.tapPickerController, controller)
            .coordinateSpace(name: TapPickerSpace.name)
            .onChange(of: dismissTrigger) { _, _ in
                controller.dismiss()
            }
            .overlay {
                if let active = controller.active {
                    GeometryReader { proxy in
                        let placement = TapPickerPlacement.resolve(
                            anchor: active.anchor,
                            containerSize: proxy.size,
                            safeAreaInsets: proxy.safeAreaInsets,
                            horizontalSize: active.horizontalSize,
                            verticalSize: active.verticalSize,
                            preferredEdge: active.preferredEdge)
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .ignoresSafeArea()
                                .onTapGesture { controller.dismiss() }
                                .accessibilityHidden(true)
                            active.content(placement.axis) {
                                controller.dismiss()
                            }
                            .accessibilityAction(.escape) {
                                controller.dismiss()
                            }
                            .position(x: placement.frame.midX, y: placement.frame.midY)
                        }
                    }
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
    }
}

extension View {
    /// Installs an adaptive floating tap-picker host and outside-tap dismisser over this view.
    ///
    /// Changing `dismissWhen` automatically closes any open picker (for example, switching photos,
    /// losing write permission, or leaving selection mode).
    func tapPickerContainer<Trigger: Equatable>(dismissWhen trigger: Trigger) -> some View {
        modifier(TapPickerContainerModifier(dismissTrigger: trigger))
    }

    /// Installs an adaptive floating tap-picker host and outside-tap dismisser over this view.
    func tapPickerContainer() -> some View {
        modifier(TapPickerContainerModifier(dismissTrigger: 0))
    }
}
