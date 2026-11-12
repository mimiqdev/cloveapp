import CloveCore
import SwiftUI

/// The label picker: a glass capsule holding a dot for none and for each of the five labels
/// (`design/handoff/components.md`, Label picker).
///
/// The current dot is ringed. Picking a dot closes the picker in the screen that presents it, and
/// the two extended labels appear only when C12's extended colors are on.
struct LabelPicker: View {
    /// The photo's label, or nil when it has none (PRD Marking rules).
    let selection: LabelColour?

    /// The labels to offer, in order; the five default labels plus Clear unless the screen adds
    /// the extended ones (PRD Marking rules).
    var labels: [LabelColour?] = Self.defaultLabels

    /// The identifier the screen's UI test uses; each dot is `"<identifier>.<label>"`.
    var identifier = "clove.mark.labelPicker"

    /// Applies a label, or clears it with nil (PRD Marking rules).
    let onPick: (LabelColour?) -> Void

    /// The rail presents the same dots in a column, without the capsule's glass surround.
    var axis: Axis = .horizontal
    var isNeutral = false

    /// None, then red, yellow, green, blue and purple (components.md).
    static let defaultLabels: [LabelColour?] =
        [nil] + LabelColour.allCases.filter { !$0.isExtended }

    var body: some View {
        if axis == .horizontal {
            dots
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .cloveGlass(in: Capsule())
        } else {
            dots
        }
    }

    private var dots: some View {
        let layout =
            axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            ForEach(labels.indices, id: \.self) { index in
                dot(labels[index])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// One dot; the current choice carries a ring (components.md).
    private func dot(_ label: LabelColour?) -> some View {
        Button {
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
                if label == selection {
                    Circle()
                        .strokeBorder(Color.clove.text.primary, lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.map { "Label, \($0.rawValue)" } ?? "No label")
        .accessibilityAddTraits(label == selection ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(label?.rawValue.lowercased() ?? "none")")
        .help(label.map { "Label, \($0.rawValue)" } ?? "No label")
    }
}

#Preview("Label picker") {
    VStack(spacing: 12) {
        LabelPicker(selection: .green, identifier: "preview.labelPicker") { _ in }
        LabelPicker(
            selection: .orange, labels: [nil] + LabelColour.allCases,
            identifier: "preview.labelPicker.extended"
        ) { _ in }
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
