import CloveCore
import SwiftUI

/// The shared visual tap-color picker: a glass capsule holding None (`circle.slash`) and the
/// colour dots (`design/handoff/components.md`, Label picker).
///
/// Both horizontal (`288 × 52` pt) and vertical (`52 × 288` pt) orientations preserve the exact
/// same top-to-bottom / left-to-right choice order (`None, Red, Yellow, Green, Blue, Purple`, plus
/// extended colours when enabled) with `44 × 44` pt hit targets and a visible selection ring.
/// The legacy iPad rail embeds an unglassed inline column (`showsGlass: false`).
struct LabelPicker: View {
    /// The photo's label, or nil when it has none (PRD Marking rules).
    let selection: LabelColour?

    /// True when a batch selection has differing labels, so no choice appears selected.
    var isMixed = false

    /// The labels to offer, in order; the five default labels plus Clear unless the screen adds
    /// the extended ones (PRD Marking rules).
    var labels: [LabelColour?] = Self.defaultLabels

    /// The identifier the screen's UI test uses; each dot is `"<identifier>.<label>"`.
    var identifier = "clove.mark.labelPicker"

    /// Applies a label, or clears it with nil (PRD Marking rules).
    let onPick: (LabelColour?) -> Void

    /// Layout orientation: `.horizontal` (`288 × 52`) or `.vertical` (`52 × 288`).
    var axis: Axis = .horizontal

    /// Floating popups draw the shared glass capsule; the iPad rail column omits glass.
    var showsGlass = true

    /// Neutralises dot fills when the iPad rail displays a rejected photo.
    var isNeutral = false

    /// None, then red, yellow, green, blue and purple (components.md).
    static let defaultLabels: [LabelColour?] =
        [nil] + LabelColour.allCases.filter { !$0.isExtended }

    static let targetExtent: CGFloat = 44
    static let itemSpacing: CGFloat = 3.2
    static let containerPadding: CGFloat = 4

    /// Reference dimensions (`288 × 52` horizontal, `52 × 288` vertical for 6 items).
    static func preferredSize(for axis: Axis, count: Int = defaultLabels.count) -> CGSize {
        let major =
            containerPadding * 2
            + CGFloat(max(count, 1)) * targetExtent
            + CGFloat(max(count - 1, 0)) * itemSpacing
        let minor = containerPadding * 2 + targetExtent
        return axis == .horizontal
            ? CGSize(width: major, height: minor)
            : CGSize(width: minor, height: major)
    }

    var body: some View {
        if showsGlass {
            dots(spacing: Self.itemSpacing, targetSize: Self.targetExtent)
                .padding(Self.containerPadding)
                .cloveGlass(in: Capsule())
        } else {
            dots(spacing: 0, targetSize: 32)
        }
    }

    private func dots(spacing: CGFloat, targetSize: CGFloat) -> some View {
        let layout =
            axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        return layout {
            ForEach(labels.indices, id: \.self) { index in
                dot(labels[index], targetSize: targetSize)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(identifier)
    }

    /// One dot; the current choice carries a ring (components.md).
    private func dot(_ label: LabelColour?, targetSize: CGFloat) -> some View {
        let isSelected = !isMixed && label == selection
        let ringSize = targetSize >= Self.targetExtent ? 34.0 : 32.0
        return Button {
            onPick(label)
        } label: {
            ZStack {
                if let label {
                    Circle().fill(
                        isNeutral ? Color.clove.rating.off : Color.clove.label.colour(for: label))
                } else {
                    Image(systemName: "circle.slash")
                        .font(.title3)
                        .foregroundStyle(Color.clove.text.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Color.clove.text.primary, lineWidth: 2)
                        .frame(width: ringSize, height: ringSize)
                }
            }
            .frame(minWidth: targetSize, minHeight: targetSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.map { "Label, \($0.rawValue)" } ?? "No label")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(label?.rawValue.lowercased() ?? "none")")
        .help(label.map { "Label, \($0.rawValue)" } ?? "No label")
    }

    private var accessibilityValue: String {
        if isMixed { return "Mixed" }
        return selection?.rawValue ?? "None"
    }
}

#Preview("Label picker") {
    VStack(spacing: 16) {
        LabelPicker(selection: .green, identifier: "preview.labelPicker") { _ in }
        LabelPicker(selection: nil, identifier: "preview.labelPicker.none") { _ in }
        LabelPicker(selection: nil, isMixed: true, identifier: "preview.labelPicker.mixed") { _ in }
        LabelPicker(
            selection: .orange, labels: [nil] + LabelColour.allCases,
            identifier: "preview.labelPicker.extended"
        ) { _ in }
        LabelPicker(
            selection: .blue, identifier: "preview.labelPicker.vertical",
            onPick: { _ in }, axis: .vertical)
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
