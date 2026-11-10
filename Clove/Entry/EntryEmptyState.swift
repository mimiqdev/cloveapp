import CloveCore
import SwiftUI

/// The first-launch layout, reused for the suggested empty-folder default (handoff screens.md).
struct EntryEmptyState: View {
    var isEmptyFolder = false
    let openFolder: () -> Void
    @Environment(\.cloveTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                frame.rotationEffect(.degrees(-9)).offset(x: -46, y: 22)
                frame.rotationEffect(.degrees(-6)).offset(x: 48, y: 6)
                frame
            }
            .frame(height: 190)
            .padding(.bottom, 26)
            Text(isEmptyFolder ? "No photos in this folder." : "Cull where your photos live.")
                .font(.title2.bold())
                .foregroundStyle(Color.clove.text.primary)
                .multilineTextAlignment(.center)
            if !isEmptyFolder {
                Text("Open a folder on a card, drive or Files. Nothing is imported or copied.")
                    .font(.subheadline)
                    .foregroundStyle(Color.clove.text.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 12)
            }
            Button(action: openFolder) {
                Label("Open folder", systemImage: "folder")
                    .font(.headline)
                    .foregroundStyle(CloveTheme.dark.tokens.primaryText.color)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(Color.clove.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clove.entry.pickFolder")
            .padding(.top, 40)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.canvas)
    }

    private var frame: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.clove.surface.card)
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(Color.clove.separator, lineWidth: 1)
            }
            .frame(width: 96, height: 128)
            .shadow(color: theme.tokens.primaryText.color.opacity(0.08), radius: 8, y: 6)
    }
}
