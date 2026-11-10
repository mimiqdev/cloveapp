import CloveCore
import SwiftUI

/// The group view's header: the undecided count, the Undecided only switch and the two finishing
/// actions (PRD In-group culling, layout and finishing actions; PRD P0-12).
///
/// The count is C10's "Undecided N / M total", where undecided means no rating and no Reject, so a
/// colour label alone does not lower it (PRD In-group culling, layout). Keep this, reject the rest
/// and Keep rated, reject the rest are C10's two actions and are offered only while they may run:
/// Keep rated is unavailable with no rated photo in the group (PRD In-group culling, finishing
/// actions).
///
/// Design placeholder: system buttons and a switch stand in for the visual design's culling bar.
struct GroupCullingHeader: View {
    /// C10's "Undecided N / M total" (PRD In-group culling, layout).
    let headerText: String

    /// Whether the group view asks for Undecided only (PRD In-group culling).
    @Binding var undecidedOnly: Bool

    /// Whether Keep this, reject the rest may run (PRD In-group culling).
    let keepThisAvailable: Bool

    /// Whether Keep rated, reject the rest may run (PRD In-group culling).
    let keepRatedAvailable: Bool

    /// Runs Keep this, reject the rest (PRD P0-12).
    let keepThis: () -> Void

    /// Runs Keep rated, reject the rest (PRD P0-12).
    let keepRated: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headerText)
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("clove.group.undecided")
                Spacer(minLength: 8)
                Toggle("Undecided only", isOn: $undecidedOnly)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .fixedSize()
                    .accessibilityIdentifier("clove.group.undecidedOnly")
            }
            HStack(spacing: 8) {
                Button("Keep this, reject the rest", action: keepThis)
                    .disabled(!keepThisAvailable)
                    .accessibilityIdentifier("clove.group.keepThis")
                Button("Keep rated, reject the rest", action: keepRated)
                    .disabled(!keepRatedAvailable)
                    .accessibilityIdentifier("clove.group.keepRated")
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
