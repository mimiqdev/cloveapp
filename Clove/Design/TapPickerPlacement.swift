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

    static func bloomAnchor(
        for frame: CGRect,
        anchor: CGRect,
        preferredEdge: Edge = .top
    ) -> UnitPoint {
        guard frame.width > 0, frame.height > 0 else { return .center }
        let normalizedX = clamp((anchor.midX - frame.minX) / frame.width, min: 0, max: 1)
        let normalizedY = clamp((anchor.midY - frame.minY) / frame.height, min: 0, max: 1)
        if frame.maxY <= anchor.minY + 1 {
            return UnitPoint(x: normalizedX, y: 1)
        }
        if frame.minY >= anchor.maxY - 1 {
            return UnitPoint(x: normalizedX, y: 0)
        }
        if frame.maxX <= anchor.minX + 1 {
            return UnitPoint(x: 1, y: normalizedY)
        }
        if frame.minX >= anchor.maxX - 1 {
            return UnitPoint(x: 0, y: normalizedY)
        }
        switch preferredEdge {
        case .top: return UnitPoint(x: normalizedX, y: 1)
        case .bottom: return UnitPoint(x: normalizedX, y: 0)
        case .leading: return UnitPoint(x: 1, y: normalizedY)
        case .trailing: return UnitPoint(x: 0, y: normalizedY)
        }
    }
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

    let coordinateSpaceName = UUID().uuidString
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

struct TapPickerTriggerRequest: Equatable {
    let id: String
    let nonce: Int
}

struct TapPickerFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension EnvironmentValues {
    @Entry var tapPickerController: TapPickerController? = nil
    @Entry var tapPickerTriggerRequest: TapPickerTriggerRequest? = nil
}

private struct TapPickerContainerModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = TapPickerController()
    let dismissTrigger: Trigger
    let margin: CGFloat
    let gap: CGFloat

    func body(content: Content) -> some View {
        content
            .environment(\.tapPickerController, controller)
            .onChange(of: dismissTrigger) { _, _ in
                controller.dismiss()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    controller.dismiss()
                }
            }
            .onDisappear {
                controller.dismiss()
            }
            .overlay {
                Group {
                    if let active = controller.active {
                        GeometryReader { proxy in
                            let overlayFrame = proxy.frame(
                                in: .named(controller.coordinateSpaceName))
                            let localAnchor = active.anchor.offsetBy(
                                dx: -overlayFrame.minX,
                                dy: -overlayFrame.minY)
                            // GeometryReader without ignoresSafeArea() already excludes safe areas
                            // from proxy.size, while proxy.safeAreaInsets still reports iOS 27's
                            // vertical-toolbar / container margin inset.
                            let placement = TapPickerPlacement.resolve(
                                anchor: localAnchor,
                                containerSize: proxy.size,
                                horizontalSize: active.horizontalSize,
                                verticalSize: active.verticalSize,
                                preferredEdge: active.preferredEdge,
                                margin: margin,
                                gap: gap)
                            let bloomAnchor = TapPickerPlacement.bloomAnchor(
                                for: placement.frame,
                                anchor: localAnchor,
                                preferredEdge: active.preferredEdge)
                            ZStack(alignment: .topLeading) {
                                active.content(placement.axis) {
                                    controller.dismiss()
                                }
                                .transition(
                                    CloveMotion.bloomTransition(
                                        anchor: bloomAnchor, reduceMotion: reduceMotion)
                                )
                                .id(active.id)
                                .position(x: placement.frame.midX, y: placement.frame.midY)
                            }
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height,
                                alignment: .topLeading
                            )
                            .background {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .ignoresSafeArea()
                                    .onTapGesture { controller.dismiss() }
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .animation(
                    controller.active != nil ? CloveMotion.chrome(reduceMotion: reduceMotion) : nil,
                    value: controller.active?.id
                )
            }
            .coordinateSpace(name: controller.coordinateSpaceName)
    }
}

extension View {
    /// Installs an adaptive floating tap-picker host and outside-tap dismisser over this view.
    ///
    /// Changing `dismissWhen` automatically closes any open picker (for example, switching photos,
    /// losing write permission, or leaving selection mode).
    func tapPickerContainer<Trigger: Equatable>(
        dismissWhen trigger: Trigger, margin: CGFloat = 12, gap: CGFloat = 10
    ) -> some View {
        modifier(TapPickerContainerModifier(dismissTrigger: trigger, margin: margin, gap: gap))
    }

    /// Installs an adaptive floating tap-picker host and outside-tap dismisser over this view.
    func tapPickerContainer(margin: CGFloat = 12, gap: CGFloat = 10) -> some View {
        modifier(TapPickerContainerModifier(dismissTrigger: 0, margin: margin, gap: gap))
    }

    func reportTapPickerFrame(_ identifier: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TapPickerFramesPreferenceKey.self,
                    value: [identifier: proxy.frame(in: .global)])
            }
        }
    }
}
