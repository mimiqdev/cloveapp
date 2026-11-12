import CloveCore
import SwiftUI
import UIKit

/// Public idiom separates a wide phone window from an iPad. Hinge presence is needed only
/// for the cover's rail; neither layout infers a physical hinge position.
struct DuoLayout: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var hasHinge = false

    private var showsCover: Bool {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CLOVE_TEST_LIBRARY"] == "1",
                ProcessInfo.processInfo.environment["CLOVE_TEST_DUO_VIEWPORT"] == "cover"
            {
                return true
            }
        #endif
        return UIDevice.current.userInterfaceIdiom == .phone && hasHinge && sizeClass != .regular
    }

    func body(content: Content) -> some View {
        observed(content)
            .environment(
                \.isDuoExpanded,
                UIDevice.current.userInterfaceIdiom == .phone && sizeClass == .regular
                    && verticalSizeClass != .compact
            )
            .environment(\.isDuoCover, showsCover)
    }

    @ViewBuilder private func observed(_ content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                hasHinge = context.hinge != nil
            }
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    @Entry var isDuoExpanded = false
    @Entry var isDuoCover = false
}

/// Temporary split plus the existing grid's tools. Detail supplies all marking actions.
struct DuoDetailLayout {
    var split: Binding<DuoSplit>
    var grid: AnyView
    var tools: AnyView
    var bottom: AnyView
}

struct DuoDock<Tools: View, Marks: View, Bottom: View>: View {
    let back: () -> Void
    let undo: () -> Void
    let canUndo: Bool
    var showsMarks = true
    @ViewBuilder var tools: Tools
    @ViewBuilder var marks: Marks
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 14) {
            GlassIconButton(
                label: "Back", symbol: "chevron.left", size: .duo,
                identifier: "clove.nav.back", action: back)
            capsule { tools }
            if showsMarks { capsule { marks } }
            Spacer(minLength: 8)
            capsule {
                GlassIconButton(
                    label: "Undo", symbol: "arrow.uturn.backward", size: .duo, showsGlass: false,
                    identifier: "clove.duo.undo", action: undo
                ).disabled(!canUndo)
                bottom
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(width: 64)
        .background(Color.clove.bg.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.duo.dock")
    }

    private func capsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2, content: content)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .frame(width: 41)
            .cloveGlass(in: Capsule())
    }
}

/// Pickers are anchored in the dock but drawn and hit-tested over the whole expanded container.
/// Keeping them in a narrow dock overlay lets the photo behind it consume their taps.
struct DuoDockPicker {
    var anchor: Anchor<CGRect>
    var content: AnyView
    var alignsBottom = false
}

struct DuoDockPickerKey: PreferenceKey {
    static var defaultValue: [DuoDockPicker] { [] }

    static func reduce(value: inout [DuoDockPicker], nextValue: () -> [DuoDockPicker]) {
        value += nextValue()
    }
}

struct DuoDockPickerOverlay: View {
    let picker: DuoDockPicker
    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let anchor = proxy[picker.anchor]
            picker.content
                .fixedSize()
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    size = $0
                }
                .position(
                    x: anchor.minX - 10 - size.width / 2,
                    y: picker.alignsBottom ? anchor.maxY - size.height / 2 : anchor.midY)
        }
    }
}

struct DuoDivider: View {
    @Binding var split: DuoSplit
    let contentWidth: CGFloat
    let back: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clove.bg.canvas)
            Rectangle().fill(Color.clove.separator).frame(width: 0.5)
            Capsule().fill(Color.clove.text.secondary).frame(width: 3, height: 40)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4).onEnded { value in
                let next = split.released(
                    translation: value.translation.width, contentWidth: contentWidth)
                if next == .grid { back() } else { split = next }
            }
        )
        .accessibilityLabel("Photo split")
        .accessibilityValue("Grid 30 percent, photo 70 percent")
        .accessibilityAdjustableAction { direction in
            if direction == .decrement { split = .photoOnly } else { back() }
        }
        .accessibilityIdentifier("clove.duo.divider")
    }
}
