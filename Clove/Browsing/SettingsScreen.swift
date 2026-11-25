import CloveCore
import SwiftUI

/// Adaptive Settings container: compact push home below the wide threshold, category-list +
/// detail split at wide widths (issue #264).
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var navigation: SettingsNavigationState
    let availableWidth: CGFloat

    @State private var showsResetConfirmation = false
    @State private var resetRevision = 0

    init(
        navigation: SettingsNavigationState = SettingsNavigationState(),
        availableWidth: CGFloat = 0
    ) {
        self.navigation = navigation
        self.availableWidth = availableWidth
    }

    /// Matches the outer regular-width `.insetGrouped` margin so both sides of the central divider
    /// stay visually symmetric without clipping scroll indicators.
    private static let splitDividerInset: CGFloat = 20

    private var isWide: Bool {
        SettingsLayoutMode.isWide(
            horizontalSizeClass: horizontalSizeClass, availableWidth: availableWidth)
    }

    private var sidebarWidth: CGFloat {
        availableWidth >= 960 ? 296 : 276
    }

    var body: some View {
        Group {
            if isWide {
                wideSplit
            } else {
                compactHome
            }
        }
        .background(Color.clove.surface.sheet)
        .foregroundStyle(Color.clove.text.primary)
        .navigationBarTitleDisplayMode(isWide ? .inline : .large)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings")
        .onAppear {
            navigation.enteredSettings(isWide: isWide)
        }
        .onChange(of: isWide) { _, wide in
            navigation.layoutChanged(isWide: wide)
        }
        .alert(
            AppLocalization.string("Reset settings to defaults?", language: language),
            isPresented: $showsResetConfirmation
        ) {
            Button(AppLocalization.string("Cancel", language: language), role: .cancel) {}
            Button(AppLocalization.string("Reset", language: language), role: .destructive) {
                store.resetToDefaults()
                resetRevision += 1
            }
        } message: {
            Text(
                AppLocalization.string(
                    "Preferences return to launch defaults. Photos and their marks stay untouched.",
                    language: language))
        }
    }

    private var compactHome: some View {
        List {
            Section {
                ForEach(SettingsCategory.allCases) { category in
                    let categoryTitle = category.title(language: language)
                    NavigationLink(value: BrowseDestination.settingsCategory(category)) {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .foregroundStyle(Color.clove.accent)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(categoryTitle)
                                .foregroundStyle(Color.clove.text.primary)
                            Spacer(minLength: 8)
                            if let summary = compactSummary(for: category) {
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.clove.text.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .accessibilityLabel(categoryTitle)
                    .accessibilityValue(compactSummary(for: category) ?? "")
                    .accessibilityIdentifier(category.identifier)
                }
            }
            .listRowBackground(theme.tokens.card.color)

            SettingsResetSection { showsResetConfirmation = true }
            SettingsSaveFailureSection()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
    }

    private var wideSplit: some View {
        HStack(spacing: 0) {
            List {
                Section {
                    ForEach(SettingsCategory.allCases) { category in
                        let isSelected = navigation.selectedCategory == category
                        let categoryTitle = category.title(language: language)
                        Button {
                            navigation.selectCategory(category, wide: true)
                        } label: {
                            Label {
                                Text(categoryTitle)
                                    .reportHeaderControlFrame("\(category.identifier).title")
                            } icon: {
                                Image(systemName: category.symbol)
                            }
                            .foregroundStyle(
                                isSelected ? Color.clove.accent : Color.clove.text.primary
                            )
                            .fontWeight(isSelected ? .medium : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            isSelected
                                ? theme.tokens.primaryText.color.opacity(0.08)
                                : theme.tokens.card.color
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier(category.identifier)
                    }
                }
                .listRowBackground(theme.tokens.card.color)

                SettingsResetSection { showsResetConfirmation = true }
                SettingsSaveFailureSection()
            }
            .listStyle(.insetGrouped)
            .contentMargins(.trailing, Self.splitDividerInset, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.clove.surface.sheet)
            .frame(width: sidebarWidth)

            Rectangle()
                .fill(Color.clove.separator)
                .frame(width: 0.5)
                .ignoresSafeArea(.container, edges: .bottom)
                .reportHeaderControlFrame("clove.settings.wideDivider")

            List {
                SettingsCategoryContent(
                    category: navigation.selectedCategory,
                    showsCategoryTitle: true,
                    resetRevision: resetRevision)
            }
            .id(navigation.selectedCategory)
            .listStyle(.insetGrouped)
            .contentMargins(.leading, Self.splitDividerInset, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.clove.surface.sheet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clove.surface.sheet)
    }

    private func compactSummary(for category: SettingsCategory) -> String? {
        switch category {
        case .appearance:
            let mode = AppLocalization.appearanceTitle(
                store.settings.appearance.mode, language: language)
            let family = AppLocalization.themeTitle(
                store.settings.appearance.family, language: language)
            return "\(mode) · \(family)"
        case .language:
            if store.settings.language == .system {
                return AppLocalization.string("Follow System", language: language)
            }
            return AppLocalization.resolvedLanguageAutonym(store.resolvedLanguage)
        case .cullingAndMarking:
            return nil
        case .browsingAndGroups:
            return nil
        case .photoDisplay:
            return AppLocalization.string(
                store.photoDisplayMode == .rawFirst ? "RAW" : "Camera preview",
                language: language)
        case .moveRejects:
            return store.settings.moveRejectsEnabled
                ? store.settings.rejectsFolderName.rawValue
                : AppLocalization.string("Off", language: language)
        }
    }
}

/// Pushed category detail screen in compact layouts.
struct SettingsCategoryScreen: View {
    let category: SettingsCategory
    @Environment(\.appLanguage) private var language

    var body: some View {
        List {
            SettingsCategoryContent(
                category: category,
                showsCategoryTitle: false,
                resetRevision: 0)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
        .foregroundStyle(Color.clove.text.primary)
        .navigationTitle(category.title(language: language))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings.detail")
    }
}

/// Nested subpage under Culling & marking (Rating scale or After marking destination).
struct SettingsSubpageScreen: View {
    let subpage: SettingsSubpage
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            switch subpage {
            case .ratingScale:
                RatingScaleSettingsList()
            case .autoAdvanceDestination:
                AutoAdvanceDestinationSettingsList()
            }
        }
        .navigationTitle(subpage.title(language: language))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings.subpage.\(subpage.rawValue)")
    }
}
