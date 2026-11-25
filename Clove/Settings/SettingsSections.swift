import CloveCore
import SwiftUI

/// Renders the preference sections for the given category; shared between compact detail screens
/// and the wide split's detail column (issue #264).
struct SettingsCategoryContent: View {
    let category: SettingsCategory
    let showsCategoryTitle: Bool
    let resetRevision: Int

    var body: some View {
        switch category {
        case .appearance:
            AppearanceSettingsSections(showsCategoryTitle: showsCategoryTitle)
        case .language:
            LanguageSettingsSections(showsCategoryTitle: showsCategoryTitle)
        case .cullingAndMarking:
            CullingAndMarkingSettingsSections(showsCategoryTitle: showsCategoryTitle)
        case .browsingAndGroups:
            BrowsingAndGroupsSettingsSections(showsCategoryTitle: showsCategoryTitle)
        case .photoDisplay:
            PhotoDisplaySettingsSections(showsCategoryTitle: showsCategoryTitle)
        case .moveRejects:
            MoveRejectsSettingsSections(
                showsCategoryTitle: showsCategoryTitle, resetRevision: resetRevision)
        }
    }
}

struct AppearanceSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            ForEach(AppearanceMode.allCases) { mode in
                let isSelected = store.settings.appearance.mode == mode
                SettingsCheckmarkRow(
                    title: AppLocalization.appearanceTitle(mode, language: language),
                    isSelected: isSelected,
                    identifier: "clove.settings.appearance.mode.\(mode.rawValue)"
                ) {
                    store.update { $0.appearance.mode = mode }
                }
            }
        } header: {
            SettingsCategorySectionHeader(
                categoryTitle: showsCategoryTitle
                    ? SettingsCategory.appearance.title(language: language) : nil,
                sectionTitle: AppLocalization.string("Appearance", language: language),
                identifier: "appearance")
        } footer: {
            Text(
                AppLocalization.string(
                    "System follows your device's appearance and keeps your selected theme.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            ThemePicker(selection: store.settings.appearance.family) { family in
                store.update { $0.appearance.family = family }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            SettingsSectionHeader(
                AppLocalization.string("Theme", language: language),
                identifier: "theme")
        } footer: {
            Text(
                AppLocalization.string(
                    "Each theme includes Light and Dark. Photos are never tinted.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }

        SettingsSaveFailureSection()
    }
}

struct LanguageSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            ForEach(AppLanguage.allCases) { option in
                SettingsCheckmarkRow(
                    title: AppLocalization.languageDisplayName(option, language: language),
                    isSelected: store.settings.language == option,
                    identifier: "clove.settings.language.\(option.rawValue)"
                ) {
                    store.update { $0.language = option }
                }
            }
        } header: {
            if showsCategoryTitle {
                SettingsDetailTitleHeader(
                    title: SettingsCategory.language.title(language: language))
            }
        } footer: {
            Text(
                AppLocalization.string(
                    "Language changes apply immediately. You can also set Clove's preferred language in iOS Settings.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }
}

struct CullingAndMarkingSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    let showsCategoryTitle: Bool

    @State private var showsGestureGuide = false

    private static let ratingLevels = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        Section {
            Toggle(
                AppLocalization.string("Marking gestures", language: language),
                isOn: settingsBinding(store, \.gesturesEnabled)
            )
            .accessibilityIdentifier("clove.settings.gesturesEnabled")

            Picker(
                AppLocalization.string("While zoomed", language: language),
                selection: settingsBinding(store, \.zoomedGestures)
            ) {
                Text(AppLocalization.string("Rate & switch", language: language))
                    .tag(ZoomedGestures.rateAndSwitch)
                Text(AppLocalization.string("Pan", language: language))
                    .tag(ZoomedGestures.pan)
            }
            .accessibilityLabel(AppLocalization.string("While zoomed", language: language))
            .accessibilityValue(zoomedGesturesTitle)
            .accessibilityIdentifier("clove.settings.zoomedGestures")

            Button {
                showsGestureGuide = true
            } label: {
                HStack(spacing: 12) {
                    Text(AppLocalization.string("Gesture guide", language: language))
                        .foregroundStyle(Color.clove.text.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.clove.text.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Gesture guide", language: language))
            .accessibilityIdentifier("clove.settings.gestureGuide")
            .sheet(isPresented: $showsGestureGuide) {
                DetailGestureGuideSheet()
            }
        } header: {
            SettingsCategorySectionHeader(
                categoryTitle: showsCategoryTitle
                    ? SettingsCategory.cullingAndMarking.title(language: language) : nil,
                sectionTitle: AppLocalization.string("Marking & gestures", language: language),
                identifier: "markingGestures")
        } footer: {
            Text(
                AppLocalization.string(
                    "Rate & switch keeps one-finger rating and photo switching at fit and while zoomed, and pans with two fingers. Pan pans with one finger and rates with two.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            NavigationLink(value: BrowseDestination.settingsSubpage(.ratingScale)) {
                HStack {
                    Text(AppLocalization.string("Rating scale", language: language))
                    Spacer(minLength: 12)
                    EnabledRatingSummaryStars(enabledRatings: store.settings.enabledRatings)
                }
            }
            .accessibilityLabel(AppLocalization.string("Rating scale", language: language))
            .accessibilityValue(enabledRatingsSpokenSummary)
            .accessibilityIdentifier("clove.settings.ratingScale")

            Toggle(
                AppLocalization.string("Extended color labels", language: language),
                isOn: settingsBinding(store, \.extendedColourLabelsEnabled)
            )
            .accessibilityIdentifier("clove.settings.extendedColourLabels")
        } header: {
            SettingsSectionHeader(
                AppLocalization.string("Rating scale & labels", language: language),
                identifier: "ratingLabels")
        } footer: {
            Text(
                AppLocalization.string(
                    "Extended labels add Orange and Pink to the five standard color labels.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            NavigationLink(value: BrowseDestination.settingsSubpage(.autoAdvanceDestination)) {
                LabeledContent(
                    AppLocalization.string("After marking", language: language),
                    value: AutoAdvanceCopy.title(
                        for: store.settings.autoAdvance.destination, language: language))
            }
            .accessibilityLabel(AppLocalization.string("After marking", language: language))
            .accessibilityValue(
                AutoAdvanceCopy.title(
                    for: store.settings.autoAdvance.destination, language: language)
            )
            .accessibilityIdentifier("clove.settings.autoAdvanceDestination")

            Toggle(
                AppLocalization.string("Ratings advance", language: language),
                isOn: settingsBinding(store, \.autoAdvance.triggers.rating)
            )
            .disabled(isAutoAdvanceOff)
            .accessibilityIdentifier("clove.settings.autoAdvanceRating")

            Toggle(
                AppLocalization.string("Reject advances", language: language),
                isOn: settingsBinding(store, \.autoAdvance.triggers.reject)
            )
            .disabled(isAutoAdvanceOff)
            .accessibilityIdentifier("clove.settings.autoAdvanceReject")

            Toggle(
                AppLocalization.string("Color labels advance", language: language),
                isOn: settingsBinding(store, \.autoAdvance.triggers.colourLabel)
            )
            .disabled(isAutoAdvanceOff)
            .accessibilityIdentifier("clove.settings.autoAdvanceColourLabel")
        } header: {
            SettingsSectionHeader(
                AppLocalization.string("Auto-advance", language: language),
                identifier: "autoAdvance")
        } footer: {
            Text(
                AppLocalization.string(
                    isAutoAdvanceOff
                        ? "Stay disables advancing after marking. Your trigger preferences are kept."
                        : "Chosen marks move to the selected destination after a brief pause.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            Toggle(
                AppLocalization.string("Confirm Save to Photos & Keywords", language: language),
                isOn: settingsBinding(store, \.confirmBatchActions)
            )
            .accessibilityIdentifier("clove.settings.confirmBatchActions")
        } header: {
            SettingsSectionHeader(
                AppLocalization.string("Batch actions", language: language),
                identifier: "batchActions")
        } footer: {
            Text(
                AppLocalization.string(
                    "When enabled, Save to Photos and Add Keywords show a confirmation sheet before applying. When off, they apply immediately.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }

    private var isAutoAdvanceOff: Bool {
        store.settings.autoAdvance.destination == .stay
    }

    private var zoomedGesturesTitle: String {
        switch store.settings.zoomedGestures {
        case .rateAndSwitch: AppLocalization.string("Rate & switch", language: language)
        case .pan: AppLocalization.string("Pan", language: language)
        }
    }

    private var enabledRatingsSpokenSummary: String {
        let levels = store.settings.enabledRatings.levels.compactMap(\.starCount)
        if levels.count == Self.ratingLevels.count {
            return AppLocalization.string("All 5 star levels", language: language)
        }
        let joined = levels.map { $0.formatted() }.joined(separator: ", ")
        return AppLocalization.format(
            levels.count == 1 ? "%@ star" : "%@ stars", language: language, joined)
    }
}

struct BrowsingAndGroupsSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            Toggle(
                AppLocalization.string("Similar groups", language: language),
                isOn: settingsBinding(store, \.similarGroupsEnabled)
            )
            .accessibilityIdentifier("clove.settings.similarGroupsEnabled")

            Picker(
                AppLocalization.string("Time window", language: language),
                selection: settingsBinding(store, \.groupingTimeWindow)
            ) {
                ForEach(GroupingTimeWindow.allCases) { window in
                    Text(AppLocalization.groupingTimeWindowTitle(window, language: language))
                        .tag(window)
                }
            }
            .disabled(!store.settings.similarGroupsEnabled)
            .accessibilityLabel(AppLocalization.string("Time window", language: language))
            .accessibilityValue(
                AppLocalization.groupingTimeWindowTitle(
                    store.settings.groupingTimeWindow, language: language)
            )
            .accessibilityIdentifier("clove.settings.groupingTimeWindow")

            Picker(
                AppLocalization.string("Similarity sensitivity", language: language),
                selection: settingsBinding(store, \.groupingSensitivity)
            ) {
                ForEach(GroupingSensitivity.allCases) { sensitivity in
                    Text(
                        AppLocalization.groupingSensitivityTitle(sensitivity, language: language)
                    )
                    .tag(sensitivity)
                }
            }
            .disabled(!store.settings.similarGroupsEnabled)
            .accessibilityLabel(
                AppLocalization.string("Similarity sensitivity", language: language)
            )
            .accessibilityValue(
                AppLocalization.groupingSensitivityTitle(
                    store.settings.groupingSensitivity, language: language)
            )
            .accessibilityIdentifier("clove.settings.groupingSensitivity")
        } header: {
            SettingsCategorySectionHeader(
                categoryTitle: showsCategoryTitle
                    ? SettingsCategory.browsingAndGroups.title(language: language) : nil,
                sectionTitle: AppLocalization.string("Groups", language: language),
                identifier: "groups")
        } footer: {
            Text(groupsFooterText)
                .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            Picker(
                AppLocalization.string("Double-tap", language: language),
                selection: settingsBinding(store, \.doubleTap)
            ) {
                Text(AppLocalization.string("Zoom to focus", language: language))
                    .tag(DoubleTapBehaviour.zoomToFocus)
                Text(AppLocalization.string("Zoom to tap point", language: language))
                    .tag(DoubleTapBehaviour.zoomToTapPoint)
                Text(AppLocalization.string("Off", language: language))
                    .tag(DoubleTapBehaviour.off)
            }
            .accessibilityLabel(AppLocalization.string("Double-tap", language: language))
            .accessibilityValue(doubleTapTitle)
            .accessibilityIdentifier("clove.settings.doubleTap")
        } header: {
            SettingsSectionHeader(
                AppLocalization.string("Detail zoom", language: language), identifier: "detailZoom")
        } footer: {
            Text(
                AppLocalization.string(
                    "Similar groups keep zoom and position between members. Leaving a group or switching standalone photos returns to fit.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }

    private var groupsFooterText: String {
        if !store.settings.similarGroupsEnabled {
            return AppLocalization.string(
                "Similar groups are off. Your time window and sensitivity preferences are kept.",
                language: language)
        }
        if store.settings.groupingSensitivity == .timeOnly {
            return AppLocalization.string(
                "Groups consecutive photos from the same camera within the time window, without checking visual similarity.",
                language: language)
        }
        return AppLocalization.string(
            "Groups consecutive photos from the same camera within the time window, then splits shots that look different.",
            language: language)
    }

    private var doubleTapTitle: String {
        switch store.settings.doubleTap {
        case .zoomToFocus: AppLocalization.string("Zoom to focus", language: language)
        case .zoomToTapPoint: AppLocalization.string("Zoom to tap point", language: language)
        case .off: AppLocalization.string("Off", language: language)
        }
    }
}

struct PhotoDisplaySettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            SettingsCheckmarkRow(
                title: AppLocalization.string("Camera preview", language: language),
                subtitle: AppLocalization.string("Quicker and lighter", language: language),
                isSelected: store.photoDisplayMode == .cameraPreviewFirst,
                identifier: "clove.settings.photoDisplayMode.cameraPreviewFirst"
            ) {
                store.update { $0.photoDisplayMode = .cameraPreviewFirst }
            }

            SettingsCheckmarkRow(
                title: AppLocalization.string("RAW", language: language),
                subtitle: AppLocalization.string("The file's own colors", language: language),
                isSelected: store.photoDisplayMode == .rawFirst,
                identifier: "clove.settings.photoDisplayMode.rawFirst"
            ) {
                store.update { $0.photoDisplayMode = .rawFirst }
            }
        } header: {
            SettingsCategorySectionHeader(
                categoryTitle: showsCategoryTitle
                    ? SettingsCategory.photoDisplay.title(language: language) : nil,
                sectionTitle: AppLocalization.string("Show photos as", language: language),
                identifier: "photoDisplay")
        } footer: {
            Text(
                AppLocalization.string(
                    "RAW shows the file's own colours; the camera's preview fills the wait. Camera preview is quicker and lighter.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }
}

struct MoveRejectsSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    let showsCategoryTitle: Bool
    let resetRevision: Int

    @State private var rejectsFolderNameDraft = ""

    var body: some View {
        Section {
            Toggle(
                AppLocalization.string("Offer Move Rejects", language: language),
                isOn: settingsBinding(store, \.moveRejectsEnabled)
            )
            .accessibilityIdentifier("clove.settings.moveRejectsEnabled")

            LabeledContent(AppLocalization.string("Folder name", language: language)) {
                TextField("_Rejected", text: $rejectsFolderNameDraft)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(AppLocalization.string("Folder name", language: language))
                    .accessibilityIdentifier("clove.settings.rejectsFolderName")
                    .onChange(of: rejectsFolderNameDraft) { _, text in
                        commitRejectsFolderName(text)
                    }
            }

            if let problem = rejectsFolderNameProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Color.clove.status.failed)
                    .accessibilityIdentifier("clove.settings.rejectsFolderNameProblem")
            }
        } header: {
            SettingsCategorySectionHeader(
                categoryTitle: showsCategoryTitle
                    ? SettingsCategory.moveRejects.title(language: language) : nil,
                sectionTitle: AppLocalization.string("Move rejects", language: language),
                identifier: "moveRejects")
        } footer: {
            Text(
                AppLocalization.string(
                    "Rejected photos are moved, never deleted. Marking and filtering Rejects still work when Move Rejects is off.",
                    language: language)
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)
        .onAppear {
            rejectsFolderNameDraft = store.settings.rejectsFolderName.rawValue
        }
        .onChange(of: store.settings.rejectsFolderName) { _, name in
            if rejectsFolderNameDraft != name.rawValue {
                rejectsFolderNameDraft = name.rawValue
            }
        }
        .onChange(of: resetRevision) { _, _ in
            rejectsFolderNameDraft = store.settings.rejectsFolderName.rawValue
        }

        SettingsSaveFailureSection()
    }

    private var rejectsFolderNameProblem: String? {
        do {
            _ = try RejectsFolderName.validated(rejectsFolderNameDraft)
            return nil
        } catch {
            return AppLocalization.string(error.message, language: language)
        }
    }

    private func commitRejectsFolderName(_ text: String) {
        guard let name = try? RejectsFolderName.validated(text) else { return }
        store.update { $0.rejectsFolderName = name }
    }
}

/// Nested Rating scale subpage under Culling & marking using filled SF Symbols stars.
struct RatingScaleSettingsList: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    private static let ratingLevels = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        List {
            Section {
                ForEach(Self.ratingLevels, id: \.rawValue) { rating in
                    let enabled = store.settings.enabledRatings.contains(rating)
                    let isLast = isLastEnabledRating(rating)
                    Toggle(isOn: enabledRatingBinding(rating)) {
                        CumulativeRatingStarsRow(
                            starCount: rating.starCount ?? 0, isEnabled: enabled)
                    }
                    .disabled(isLast)
                    .accessibilityLabel(ratingName(rating))
                    .accessibilityHint(
                        isLast
                            ? AppLocalization.string(
                                "At least one rating level must remain enabled.",
                                language: language) : ""
                    )
                    .accessibilityIdentifier("clove.settings.rating.\(rating.rawValue)")
                }
            } header: {
                SettingsSectionHeader(
                    AppLocalization.string("Enabled levels", language: language),
                    identifier: "enabledLevels")
            } footer: {
                Text(
                    AppLocalization.string(
                        "Quick swipe input follows the enabled levels. Keep at least one level enabled. Ratings read from other apps still show when their level is off.",
                        language: language)
                )
                .foregroundStyle(Color.clove.text.secondary)
            }
            .listRowBackground(theme.tokens.card.color)

            SettingsSaveFailureSection()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
        .foregroundStyle(Color.clove.text.primary)
    }

    private func enabledRatingBinding(_ rating: Rating) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledRatings.contains(rating) },
            set: { enabled in
                store.update {
                    $0.enabledRatings = $0.enabledRatings.with(rating, enabled: enabled)
                }
            })
    }

    private func isLastEnabledRating(_ rating: Rating) -> Bool {
        store.settings.enabledRatings.count == 1 && store.settings.enabledRatings.contains(rating)
    }

    private func ratingName(_ rating: Rating) -> String {
        AppLocalization.starCount(rating.starCount ?? 0, language: language)
    }
}

/// Nested Auto-advance destination subpage under Culling & marking.
struct AutoAdvanceDestinationSettingsList: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    var body: some View {
        List {
            Section {
                ForEach(AutoAdvanceDestination.allCases, id: \.rawValue) { destination in
                    SettingsCheckmarkRow(
                        title: AutoAdvanceCopy.title(for: destination, language: language),
                        subtitle: AutoAdvanceCopy.subtitle(for: destination, language: language),
                        isSelected: store.settings.autoAdvance.destination == destination,
                        identifier: "clove.settings.autoAdvance.\(destination.rawValue)"
                    ) {
                        store.update { $0.autoAdvance.destination = destination }
                    }
                }
            } header: {
                SettingsSectionHeader(
                    AppLocalization.string("After marking", language: language),
                    identifier: "afterMarking")
            } footer: {
                Text(
                    AppLocalization.string(
                        "Stay disables auto-advance after marking while preserving your trigger preferences.",
                        language: language)
                )
                .foregroundStyle(Color.clove.text.secondary)
            }
            .listRowBackground(theme.tokens.card.color)

            SettingsSaveFailureSection()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
        .foregroundStyle(Color.clove.text.primary)
    }
}

struct SettingsSaveFailureSection: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let message = store.saveFailureMessage {
            Section {
                Label(
                    AppLocalization.string(message, language: language),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(Color.clove.status.failed)
                .accessibilityIdentifier("clove.settings.saveFailure")
            }
            .listRowBackground(theme.tokens.card.color)
        }
    }
}

struct SettingsResetSection: View {
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    var showsFooter = true
    var usesCardBackground = true
    let onTapReset: () -> Void

    var body: some View {
        Section {
            Button(action: onTapReset) {
                Text(AppLocalization.string("Reset to defaults", language: language))
                    .foregroundStyle(Color.clove.text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clove.settings.reset")
        } footer: {
            if showsFooter {
                Text(
                    AppLocalization.string(
                        "Your preferences apply to every layout.", language: language)
                )
                .foregroundStyle(Color.clove.text.secondary)
            }
        }
        .listRowBackground(usesCardBackground ? theme.tokens.card.color : Color.clear)
    }
}

struct CumulativeRatingStarsRow: View {
    let starCount: Int
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(1, starCount), id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.body)
                    .foregroundStyle(
                        isEnabled ? Color.clove.rating.on : Color.clove.rating.off
                    )
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityHidden(true)
    }
}

private struct EnabledRatingSummaryStars: View {
    let enabledRatings: EnabledRatings
    private static let levels = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.levels, id: \.rawValue) { rating in
                let enabled = enabledRatings.contains(rating)
                Image(systemName: enabled ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.clove.rating.on : Color.clove.rating.off)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SettingsDetailTitleHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(Color.clove.text.primary)
            .textCase(nil)
            .reportHeaderControlFrame("clove.settings.detailTitle")
    }
}

private struct SettingsCategorySectionHeader: View {
    let categoryTitle: String?
    let sectionTitle: String
    let identifier: String

    var body: some View {
        if let categoryTitle {
            VStack(alignment: .leading, spacing: 12) {
                SettingsDetailTitleHeader(title: categoryTitle)
                SettingsSectionHeader(sectionTitle, identifier: identifier)
            }
        } else {
            SettingsSectionHeader(sectionTitle, identifier: identifier)
        }
    }
}

private struct SettingsCheckmarkRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.clove.text.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.clove.text.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)

        if let subtitle {
            button.accessibilityValue(subtitle)
        } else {
            button
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let identifier: String

    init(_ title: String, identifier: String) {
        self.title = title
        self.identifier = identifier
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.clove.text.secondary)
            .textCase(.uppercase)
            .accessibilityIdentifier("clove.settings.section.\(identifier)")
    }
}

enum AutoAdvanceCopy {
    static func title(
        for destination: AutoAdvanceDestination, language: ResolvedAppLanguage = .english
    ) -> String {
        switch destination {
        case .stay: AppLocalization.string("Stay", language: language)
        case .nextPhoto: AppLocalization.string("Next photo", language: language)
        case .nextUnmarkedPhoto:
            AppLocalization.string("Next unmarked photo", language: language)
        }
    }

    static func subtitle(
        for destination: AutoAdvanceDestination, language: ResolvedAppLanguage = .english
    ) -> String {
        switch destination {
        case .stay:
            AppLocalization.string(
                "Keep the current photo after marking.", language: language)
        case .nextPhoto:
            AppLocalization.string(
                "Move to the next photo in order.", language: language)
        case .nextUnmarkedPhoto:
            AppLocalization.string("Skip already marked photos.", language: language)
        }
    }
}

@MainActor
private func settingsBinding<Value>(
    _ store: SettingsStore, _ keyPath: WritableKeyPath<AppSettings, Value>
) -> Binding<Value> {
    Binding(
        get: { store.settings[keyPath: keyPath] },
        set: { value in store.update { $0[keyPath: keyPath] = value } })
}
