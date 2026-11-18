import CloveCore
import SwiftUI

/// The first-launch layout, reused for the suggested empty-folder default (handoff screens.md).
struct EntryEmptyState: View {
    var isEmptyFolder = false
    let openFolder: () -> Void
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.canvas)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZStack {
                frame.rotationEffect(.degrees(-9)).offset(x: -46, y: 22)
                frame.rotationEffect(.degrees(6)).offset(x: 48, y: 6)
                frame
            }
            .scaleEffect(isCompactHeight ? 0.56 : 1)
            .frame(height: isCompactHeight ? 96 : 190)
            .padding(.bottom, isCompactHeight ? 10 : 26)

            Text(
                AppLocalization.string(
                    isEmptyFolder
                        ? "No photos in this folder."
                        : "Cull where your photos live.",
                    language: language)
            )
            .font(.title2.bold())
            .foregroundStyle(Color.clove.text.primary)
            .multilineTextAlignment(.center)

            if !isEmptyFolder {
                Text(
                    AppLocalization.string(
                        "Open a folder on a card, drive or Files. Nothing is imported or copied.",
                        language: language)
                )
                .font(.subheadline)
                .foregroundStyle(Color.clove.text.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .padding(.top, isCompactHeight ? 6 : 12)

                highlightsBlock
                    .padding(.top, isCompactHeight ? 12 : 20)
            }

            Button(action: openFolder) {
                // Text-only, filled with the accent, centred inside the shared 168 × 48 bounds
                // (owner decision, 2026-11-13, #227).
                Text(AppLocalization.string("Open folder", language: language))
                    .font(.headline)
                    .frame(width: 168, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("clove.entry.pickFolder")
            .padding(.top, isCompactHeight ? 14 : (isEmptyFolder ? 40 : 28))
        }
        .padding(isCompactHeight ? 12 : 20)
    }

    private var highlightsBlock: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 8 : 12) {
            highlightRow(
                symbol: "externaldrive",
                text: "Browse cards and folders in place")
            highlightRow(
                symbol: "hand.draw",
                text: "Swipe up to rate, swipe down to reject, double-tap for 100% focus")
            highlightRow(
                symbol: "doc.badge.gearshape",
                text: "RAW marks save to XMP sidecars for Lightroom and Capture One")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompactHeight ? 10 : 12)
        .frame(maxWidth: 340, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clove.surface.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.clove.separator, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.entry.highlights")
    }

    private func highlightRow(symbol: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.clove.accent)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            Text(AppLocalization.string(text, language: language))
                .font(.footnote)
                .foregroundStyle(Color.clove.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
