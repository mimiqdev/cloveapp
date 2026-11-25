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
    let onDismiss: () -> Void

    @State private var showsResetConfirmation = false
    @State private var resetRevision = 0
    @State private var measuredWidth: CGFloat = 0

    init(
        navigation: SettingsNavigationState = SettingsNavigationState(),
        availableWidth: CGFloat = 0,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.navigation = navigation
        self.availableWidth = availableWidth
        self.onDismiss = onDismiss
    }

    /// Matches the outer regular-width `.insetGrouped` margin so both sides of the central divider
    /// stay visually symmetric without clipping scroll indicators.
    private static let splitDividerInset: CGFloat = 20
    private static let detailMaxCardWidth: CGFloat = 640
    private static let dividerWidth: CGFloat = 1

    private var effectiveWidth: CGFloat {
        measuredWidth > 0 ? measuredWidth : availableWidth
    }

    private var isWide: Bool {
        SettingsLayoutMode.isWide(
            horizontalSizeClass: horizontalSizeClass, availableWidth: effectiveWidth)
    }

    private var sidebarWidth: CGFloat {
        effectiveWidth >= 960 ? 296 : 276
    }

    private var detailPaneWidth: CGFloat {
        max(0, effectiveWidth - sidebarWidth - Self.dividerWidth)
    }

    private var detailTrailingInset: CGFloat {
        guard detailPaneWidth > Self.splitDividerInset * 2 + Self.detailMaxCardWidth else {
            return Self.splitDividerInset
        }
        return detailPaneWidth - Self.splitDividerInset - Self.detailMaxCardWidth
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
        .navigationBarTitleDisplayMode(.large)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { width in
            if abs(measuredWidth - width) > 0.5 {
                measuredWidth = width
            }
        }
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
            ForEach(SettingsCategoryGroup.allCases) { group in
                Section {
                    ForEach(group.categories) { category in
                        let categoryTitle = category.title(language: language)
                        let categorySubtitle = category.subtitle(language: language)
                        NavigationLink(value: BrowseDestination.settingsCategory(category)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(categoryTitle)
                                    .foregroundStyle(Color.clove.text.primary)
                                Text(categorySubtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Color.clove.text.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityLabel(categoryTitle)
                        .accessibilityValue(
                            compactSummary(for: category) ?? categorySubtitle
                        )
                        .accessibilityIdentifier(category.identifier)
                    }
                } header: {
                    SettingsSectionHeader(
                        group.title(language: language), identifier: group.identifier)
                }
                .listRowBackground(theme.tokens.card.color)
            }

            SettingsResetSection { showsResetConfirmation = true }
            SettingsSaveFailureSection()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
    }

    private var wideSplit: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(AppLocalization.string("Settings", language: language))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.clove.text.primary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("clove.settings.sidebarTitle")
                        .reportHeaderControlFrame("clove.settings.sidebarTitle")
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44, alignment: .leading)
                .padding(.horizontal, Self.splitDividerInset)
                .padding(.top, 16)
                .padding(.bottom, 8)

                List {
                    ForEach(SettingsCategory.allCases) { category in
                        let isSelected = navigation.selectedCategory == category
                        let categoryTitle = category.title(language: language)
                        Section {
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
                                isSelected ? theme.tokens.card.color : Color.clear
                            )
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .accessibilityIdentifier(category.identifier)
                        }
                    }

                    SettingsResetSection(showsFooter: false, usesCardBackground: false) {
                        showsResetConfirmation = true
                    }
                    SettingsSaveFailureSection()
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(4)
                .contentMargins(.top, 4, for: .scrollContent)
                .contentMargins(.horizontal, Self.splitDividerInset, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(Color.clove.surface.sheet)
            }
            .frame(width: sidebarWidth)

            Rectangle()
                .fill(Color.clove.separator)
                .frame(width: Self.dividerWidth)
                .ignoresSafeArea(.container, edges: .vertical)
                .reportHeaderControlFrame("clove.settings.wideDivider")

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(navigation.selectedCategory.title(language: language))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.clove.text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                        .reportHeaderControlFrame("clove.settings.detailTitle")
                    Spacer(minLength: 8)
                    Button {
                        onDismiss()
                    } label: {
                        Text(AppLocalization.string("Done", language: language))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.clove.accent)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel(AppLocalization.string("Done", language: language))
                    .accessibilityIdentifier("clove.nav.back")
                    .reportHeaderControlFrame("clove.settings.done")
                }
                .padding(.horizontal, Self.splitDividerInset)
                .padding(.top, 16)
                .padding(.bottom, 8)

                List {
                    SettingsCategoryContent(
                        category: navigation.selectedCategory,
                        showsCategoryTitle: false,
                        resetRevision: resetRevision)
                }
                .id(navigation.selectedCategory)
                .listStyle(.insetGrouped)
                .contentMargins(.leading, Self.splitDividerInset, for: .scrollContent)
                .contentMargins(.trailing, detailTrailingInset, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(Color.clove.surface.sheet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .navigationBarTitleDisplayMode(.large)
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
        .navigationBarTitleDisplayMode(.large)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings.subpage.\(subpage.rawValue)")
    }
}
