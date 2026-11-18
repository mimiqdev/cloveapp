import CloveCore
import SwiftUI

struct DetailGestureGuideItem: Identifiable {
    let symbol: String
    let titleKey: String
    let subtitleKey: String

    var id: String { titleKey }

    static let coreItems: [DetailGestureGuideItem] = [
        DetailGestureGuideItem(
            symbol: "arrow.up",
            titleKey: "Swipe up to rate",
            subtitleKey: "Distance sets 1–5 stars"),
        DetailGestureGuideItem(
            symbol: "arrow.down",
            titleKey: "Swipe down to reject",
            subtitleKey: "Swipe down again to clear"),
        DetailGestureGuideItem(
            symbol: "arrow.left.arrow.right",
            titleKey: "Swipe left or right",
            subtitleKey: "Previous or next photo"),
        DetailGestureGuideItem(
            symbol: "plus.magnifyingglass",
            titleKey: "Double-tap",
            subtitleKey: "Zoom to 100% to check focus"),
        DetailGestureGuideItem(
            symbol: "rectangle.stack",
            titleKey: "Pull filmstrip down",
            subtitleKey: "Expand similar group; push up to fold"),
    ]
}

/// First-use glass overlay card summarizing Detail culling and navigation gestures.
struct DetailGestureGuideCard: View {
    let dismiss: () -> Void

    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 12 : 16) {
            Text(AppLocalization.string("Gesture guide", language: language))
                .font(.headline)
                .foregroundStyle(Color.clove.text.primary)

            ViewThatFits(in: .vertical) {
                rows
                ScrollView(.vertical, showsIndicators: false) {
                    rows
                }
            }

            Button(action: dismiss) {
                Text(AppLocalization.string("Got it", language: language))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompactHeight ? 38 : 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("clove.detail.gestureGuide.dismiss")
        }
        .padding(isCompactHeight ? 16 : 20)
        .frame(maxWidth: 340)
        .cloveGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.gestureGuide")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 12) {
            ForEach(DetailGestureGuideItem.coreItems) { item in
                DetailGestureGuideRow(item: item, compact: isCompactHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Reusable sheet presenting Clove's gesture guide from Settings.
struct DetailGestureGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DetailGestureGuideItem.coreItems) { item in
                        DetailGestureGuideRow(item: item, compact: false)
                            .padding(.vertical, 2)
                    }
                }
                .listRowBackground(theme.tokens.card.color)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationTitle(AppLocalization.string("Gesture guide", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done", language: language)) {
                        dismiss()
                    }
                    .foregroundStyle(Color.clove.accent)
                    .accessibilityIdentifier("clove.settings.gestureGuide.done")
                }
            }
        }
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("clove.settings.gestureGuide.sheet")
    }
}

private struct DetailGestureGuideRow: View {
    let item: DetailGestureGuideItem
    let compact: Bool

    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.clove.accent)
                .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                .background(
                    theme.tokens.accent.color.opacity(0.14),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string(item.titleKey, language: language))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.clove.text.primary)
                Text(AppLocalization.string(item.subtitleKey, language: language))
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
