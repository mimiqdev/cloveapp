import CloveCore
import SwiftUI

/// The top marking HUD: current marks, the rating bar, colour labels, Reject and Undo
/// (PRD P0-04, PRD Detail and marking).
///
/// PRD Detail and marking keeps marks at the top so the hand never hides them, and PRD P0-04
/// names the controls: ratings, labels, Reject and Undo. Only the enabled rating levels appear
/// (PRD Enabled rating levels), and the label menu offers the extended colours only when the
/// setting is on (PRD Marking rules). Every tap goes through ``MarkingInputRules`` and then
/// ``BrowsingModel/apply(_:to:)``, so tapping the applied rating clears it and the same label
/// clears itself (C13's rules).
///
/// Design placeholder: system buttons and a menu stand in for the design's glass HUD. U7 replaces
/// the save-state words and U8 enables Undo.
struct DetailMarkingHUD: View {
    /// The photo whose marks the HUD shows (PRD P0-04).
    let photo: GridPhoto

    /// C12's settings: which ratings and labels may be applied, and the double-tap choice is not
    /// read here but the value is passed whole so U11 has one place to wire.
    let settings: AppSettings

    /// U1's save-state summary, which U7 replaces with its own copy (PRD P0-08).
    let saveState: String

    /// The current zoom, for focus inspection: Fit, 100% or a percentage.
    let zoomName: String

    /// Applies one rating tap through C13's rating-bar rule (PRD Marking rules).
    let rate: (Rating) -> Void

    /// Applies one colour-label choice through C13's label rule (PRD Marking rules).
    let label: (ColourLabel) -> Void

    /// Toggles Reject independently of the rating (PRD Marking rules).
    let toggleReject: () -> Void

    /// C5's undo through the one model call U8 adds; the button stays disabled until then.
    let undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The file name, the marks and the two states the screen keeps current (PRD P0-04, P0-08).
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("clove.detail.fileName")
                Text(MarkSummary.text(for: photo.marks))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clove.detail.marks")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(zoomName)
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("clove.detail.zoom")
                Text(saveState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clove.detail.saveState")
            }
        }
    }

    /// The rating bar, the label menu, Reject and Undo (PRD P0-04).
    private var controls: some View {
        HStack(spacing: 4) {
            ForEach(settings.enabledRatings.levels, id: \.self) { rating in
                Button {
                    rate(rating)
                } label: {
                    Image(systemName: rating == photo.marks.rating ? "star.fill" : "star")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rating.rawValue) stars")
                .accessibilityIdentifier("clove.detail.rate.\(rating.rawValue)")
            }
            Spacer(minLength: 8)
            labelMenu
            Button(action: toggleReject) {
                Image(systemName: photo.marks.isRejected ? "xmark.circle.fill" : "xmark.circle")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(photo.marks.isRejected ? Color.red : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reject")
            .accessibilityValue(photo.marks.isRejected ? "On" : "Off")
            .accessibilityIdentifier("clove.detail.reject")
            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo")
            .accessibilityIdentifier("clove.detail.undo")
            .disabled(true)
        }
    }

    /// The labels the settings allow, plus Clear (PRD Marking rules).
    private var labelMenu: some View {
        Menu {
            Button("Clear") { label(.clear) }
            Divider()
            ForEach(settings.availableLabels, id: \.self) { colour in
                Button(colour.rawValue) { label(ColourLabel(colour: colour)) }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.title3)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel("Colour label")
        .accessibilityIdentifier("clove.detail.label")
    }
}
