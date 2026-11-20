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
            Picker(
                AppLocalization.string("Appearance mode", language: language),
                selection: settingsBinding(store, \.appearance.mode)
            ) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(AppLocalization.appearanceTitle(mode, language: language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(AppLocalization.string("Appearance mode", language: language))
            .accessibilityIdentifier("clove.settings.appearance.mode")

            ThemePicker(selection: store.settings.appearance.family) { family in
                store.update { $0.appearance.family = family }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            if showsCategoryTitle {
                SettingsDetailTitleHeader(
                    title: SettingsCategory.appearance.title(language: language))
            }
        } footer: {
            Text(
                AppLocalization.string(
                    "Photos are never tinted. Only the app around them changes.", language: language
                )
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

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
                let isSelected = store.settings.language == option
                let optionTitle = AppLocalization.languageDisplayName(option, language: language)
                Button {
                    store.update { $0.language = option }
                } label: {
                    HStack(spacing: 12) {
                        Text(optionTitle)
                            .foregroundStyle(Color.clove.text.primary)
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
                .accessibilityLabel(optionTitle)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("clove.settings.language.\(option.rawValue)")
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
            if showsCategoryTitle {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDetailTitleHeader(
                        title: SettingsCategory.cullingAndMarking.title(language: language))
                    SettingsSectionHeader(
                        AppLocalization.string("Marking & gestures", language: language),
                        identifier: "markingGestures")
                }
            } else {
                SettingsSectionHeader(
                    AppLocalization.string("Marking & gestures", language: language),
                    identifier: "markingGestures")
            }
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
            if showsCategoryTitle {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDetailTitleHeader(
                        title: SettingsCategory.browsingAndGroups.title(language: language))
                    SettingsSectionHeader(
                        AppLocalization.string("Groups", language: language), identifier: "groups")
                }
            } else {
                SettingsSectionHeader(
                    AppLocalization.string("Groups", language: language), identifier: "groups")
            }
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
            Picker(
                AppLocalization.string("Show photos as", language: language),
                selection: Binding(
                    get: { store.photoDisplayMode },
                    set: { mode in store.update { $0.photoDisplayMode = mode } }
                )
            ) {
                Text(AppLocalization.string("RAW", language: language))
                    .tag(PhotoDisplayMode.rawFirst)
                Text(AppLocalization.string("Camera preview", language: language))
                    .tag(PhotoDisplayMode.cameraPreviewFirst)
            }
            .accessibilityLabel(AppLocalization.string("Show photos as", language: language))
            .accessibilityValue(
                AppLocalization.string(
                    store.photoDisplayMode == .rawFirst ? "RAW" : "Camera preview",
                    language: language)
            )
            .accessibilityIdentifier("clove.settings.photoDisplayMode")
        } header: {
            if showsCategoryTitle {
                SettingsDetailTitleHeader(
                    title: SettingsCategory.photoDisplay.title(language: language))
            }
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
                AppLocalization.string("Move Rejects", language: language),
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
            if showsCategoryTitle {
                SettingsDetailTitleHeader(
                    title: SettingsCategory.moveRejects.title(language: language))
            }
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

/// Nested Rating scale subpage under Culling & marking using cumulative SF Symbols stars.
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
                    let isSelected = store.settings.autoAdvance.destination == destination
                    Button {
                        store.update { $0.autoAdvance.destination = destination }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AutoAdvanceCopy.title(for: destination, language: language))
                                    .foregroundStyle(Color.clove.text.primary)
                                Text(
                                    AutoAdvanceCopy.subtitle(for: destination, language: language)
                                )
                                .font(.caption)
                                .foregroundStyle(Color.clove.text.secondary)
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
                    .accessibilityLabel(AutoAdvanceCopy.title(for: destination, language: language))
                    .accessibilityValue(
                        AutoAdvanceCopy.subtitle(for: destination, language: language)
                    )
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("clove.settings.autoAdvance.\(destination.rawValue)")
                }
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
    let onTapReset: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onTapReset) {
                Text(AppLocalization.string("Reset to defaults", language: language))
                    .foregroundStyle(Color.clove.reject)
            }
            .accessibilityIdentifier("clove.settings.reset")
        }
        .listRowBackground(theme.tokens.card.color)
    }
}

private struct CumulativeRatingStarsRow: View {
    let starCount: Int
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                let filled = index <= starCount
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(
                        filled && isEnabled ? Color.clove.rating.on : Color.clove.rating.off
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
    }
}

private struct SettingsSectionHeader: View {
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
