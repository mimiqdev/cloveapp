import SwiftUI

/// The glass circle that opens Move Rejects.
///
/// It is 48 × 48 with `tray.and.arrow.down` at 22 pt, and it appears only when there are rejects
/// and the folder is not opening; the screen decides that. It carries no count and always opens
/// the confirmation sheet first, because nothing is destructive (design principles, PRD P0-10).
struct MoveRejectsButton: View {
    /// The identifier the screen's UI test uses.
    var identifier = "clove.move.rejects"

    /// What the tap does.
    let action: () -> Void

    @Environment(\.appLanguage) private var language

    var body: some View {
        Button(action: action) {
            Image(systemName: "tray.and.arrow.down")
                .font(.title2)
                .foregroundStyle(Color.clove.text.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .cloveGlass(in: Circle())
        }
        .buttonStyle(.cloveGlassPress)
        .accessibilityLabel(AppLocalization.string("Move rejects", language: language))
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Move Rejects") {
    MoveRejectsButton(identifier: "preview.moveRejects") {}
        .padding(24)
        .background(Rectangle().fill(Color.clove.bg.canvas))
}
