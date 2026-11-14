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
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            Toggle(
                "Match system light/dark",
                isOn: settingsBinding(store, \.appearance.matchesSystemAppearance)
            )
            .accessibilityIdentifier("clove.settings.appearance.matchSystem")
            ThemePicker(selection: theme) { tile in
                store.update { $0.appearance = $0.appearance.choosing(tile) }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            if showsCategoryTitle {
                SettingsDetailTitleHeader(title: SettingsCategory.appearance.title)
            }
        } footer: {
            Text("Photos are never tinted. Only the app around them changes.")
                .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }
}

struct CullingAndMarkingSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    let showsCategoryTitle: Bool

    private static let ratingLevels = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        Section {
            Toggle(
                "Marking gestures",
                isOn: settingsBinding(store, \.gesturesEnabled)
            )
            .accessibilityIdentifier("clove.settings.gesturesEnabled")

            Picker(
                "Zoomed rating swipe",
                selection: settingsBinding(store, \.zoomedRatingSwipe)
            ) {
                Text("Two-finger swipe").tag(ZoomedRatingSwipe.twoFinger)
                Text("Single-finger axis lock").tag(ZoomedRatingSwipe.singleFingerAxisLock)
            }
            .accessibilityLabel("Zoomed rating swipe")
            .accessibilityValue(
                store.settings.zoomedRatingSwipe == .twoFinger
                    ? "Two-finger swipe" : "Single-finger axis lock"
            )
            .accessibilityIdentifier("clove.settings.zoomedRatingSwipe")
        } header: {
            if showsCategoryTitle {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDetailTitleHeader(title: SettingsCategory.cullingAndMarking.title)
                    SettingsSectionHeader("Marking & gestures", identifier: "markingGestures")
                }
            } else {
                SettingsSectionHeader("Marking & gestures", identifier: "markingGestures")
            }
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            NavigationLink(value: BrowseDestination.settingsSubpage(.ratingScale)) {
                HStack {
                    Text("Rating scale")
                    Spacer(minLength: 12)
                    EnabledRatingSummaryStars(enabledRatings: store.settings.enabledRatings)
                }
            }
            .accessibilityLabel("Rating scale")
            .accessibilityValue(enabledRatingsSpokenSummary)
            .accessibilityIdentifier("clove.settings.ratingScale")

            Toggle(
                "Extended color labels",
                isOn: settingsBinding(store, \.extendedColourLabelsEnabled)
            )
            .accessibilityIdentifier("clove.settings.extendedColourLabels")
        } header: {
            SettingsSectionHeader("Rating scale & labels", identifier: "ratingLabels")
        } footer: {
            Text("Extended labels add Orange and Pink to the five standard color labels.")
                .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            NavigationLink(value: BrowseDestination.settingsSubpage(.autoAdvanceDestination)) {
                LabeledContent(
                    "After marking",
                    value: AutoAdvanceCopy.title(for: store.settings.autoAdvance.destination))
            }
            .accessibilityLabel("After marking")
            .accessibilityValue(AutoAdvanceCopy.title(for: store.settings.autoAdvance.destination))
            .accessibilityIdentifier("clove.settings.autoAdvanceDestination")

            Toggle(
                "Ratings advance",
                isOn: settingsBinding(store, \.autoAdvance.triggers.rating)
            )
            .disabled(isAutoAdvanceOff)
            .accessibilityIdentifier("clove.settings.autoAdvanceRating")

            Toggle(
                "Reject advances",
                isOn: settingsBinding(store, \.autoAdvance.triggers.reject)
            )
            .disabled(isAutoAdvanceOff)
            .accessibilityIdentifier("clove.settings.autoAdvanceReject")

            Toggle(
                "Color labels advance",
                isOn: settingsBinding(store, \.autoAdvance.triggers.colourLabel)
            )
            .disabled(isAutoAdvanceOff)
            .accessibilityIdentifier("clove.settings.autoAdvanceColourLabel")
        } header: {
            SettingsSectionHeader("Auto-advance", identifier: "autoAdvance")
        } footer: {
            Text(
                isAutoAdvanceOff
                    ? "Stay disables advancing after marking. Your trigger preferences are kept."
                    : "Chosen marks move to the selected destination after a brief pause."
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }

    private var isAutoAdvanceOff: Bool {
        store.settings.autoAdvance.destination == .stay
    }

    private var enabledRatingsSpokenSummary: String {
        let levels = store.settings.enabledRatings.levels.compactMap(\.starCount)
        if levels.count == Self.ratingLevels.count {
            return "All 5 star levels"
        }
        let joined = levels.map(String.init).joined(separator: ", ")
        return levels.count == 1 ? "\(joined) star" : "\(joined) stars"
    }
}

struct BrowsingAndGroupsSettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            Toggle(
                "Similar groups",
                isOn: settingsBinding(store, \.similarGroupsEnabled)
            )
            .accessibilityIdentifier("clove.settings.similarGroupsEnabled")

            VStack(alignment: .leading, spacing: 8) {
                Text("Grid display")
                Picker("Grid display", selection: settingsBinding(store, \.gridGroupDisplay)) {
                    Text("Expanded").tag(GridGroupDisplay.expanded)
                    Text("Collapsed").tag(GridGroupDisplay.collapsed)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Grid display")
                .accessibilityIdentifier("clove.settings.gridGroupDisplay")
            }
            .padding(.vertical, 2)
        } header: {
            if showsCategoryTitle {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsDetailTitleHeader(title: SettingsCategory.browsingAndGroups.title)
                    SettingsSectionHeader("Groups", identifier: "groups")
                }
            } else {
                SettingsSectionHeader("Groups", identifier: "groups")
            }
        }
        .listRowBackground(theme.tokens.card.color)

        Section {
            Picker("Double-tap", selection: settingsBinding(store, \.doubleTap)) {
                Text("Zoom to 100%").tag(DoubleTapBehaviour.zoom)
                Text("Off").tag(DoubleTapBehaviour.off)
            }
            .accessibilityLabel("Double-tap")
            .accessibilityValue(store.settings.doubleTap == .zoom ? "Zoom to 100%" : "Off")
            .accessibilityIdentifier("clove.settings.doubleTap")

            Toggle(
                "Keep zoom in detail",
                isOn: settingsBinding(store, \.keepZoom.inDetail)
            )
            .accessibilityIdentifier("clove.settings.keepZoomInDetail")
        } header: {
            SettingsSectionHeader("Detail zoom", identifier: "detailZoom")
        } footer: {
            Text(
                "Similar groups still synchronize zoom between members, even when keeping zoom between other photos is off."
            )
            .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)

        SettingsSaveFailureSection()
    }
}

struct PhotoDisplaySettingsSections: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    let showsCategoryTitle: Bool

    var body: some View {
        Section {
            Picker(
                "Show photos as",
                selection: Binding(
                    get: { store.photoDisplayMode },
                    set: { mode in store.update { $0.photoDisplayMode = mode } }
                )
            ) {
                Text("RAW").tag(PhotoDisplayMode.rawFirst)
                Text("Camera preview").tag(PhotoDisplayMode.cameraPreviewFirst)
            }
            .accessibilityLabel("Show photos as")
            .accessibilityValue(store.photoDisplayMode == .rawFirst ? "RAW" : "Camera preview")
            .accessibilityIdentifier("clove.settings.photoDisplayMode")
        } header: {
            if showsCategoryTitle {
                SettingsDetailTitleHeader(title: SettingsCategory.photoDisplay.title)
            }
        } footer: {
            Text(
                "RAW shows the file's own colours; the camera's preview fills the wait. Camera preview is quicker and lighter."
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
    let showsCategoryTitle: Bool
    let resetRevision: Int

    @State private var rejectsFolderNameDraft = ""

    var body: some View {
        Section {
            Toggle(
                "Move Rejects",
                isOn: settingsBinding(store, \.moveRejectsEnabled)
            )
            .accessibilityIdentifier("clove.settings.moveRejectsEnabled")

            LabeledContent("Folder name") {
                TextField("_Rejected", text: $rejectsFolderNameDraft)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Folder name")
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
                SettingsDetailTitleHeader(title: SettingsCategory.moveRejects.title)
            }
        } footer: {
            Text(
                "Rejected photos are moved, never deleted. Marking and filtering Rejects still work when Move Rejects is off."
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
            return error.message
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
                        isLast ? "At least one rating level must remain enabled." : ""
                    )
                    .accessibilityIdentifier("clove.settings.rating.\(rating.rawValue)")
                }
            } footer: {
                Text(
                    "Quick swipe input follows the enabled levels. Keep at least one level enabled. Ratings read from other apps still show when their level is off."
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
        let stars = rating.starCount ?? 0
        return stars == 1 ? "1 star" : "\(stars) stars"
    }
}

/// Nested Auto-advance destination subpage under Culling & marking.
struct AutoAdvanceDestinationSettingsList: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme

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
                                Text(AutoAdvanceCopy.title(for: destination))
                                    .foregroundStyle(Color.clove.text.primary)
                                Text(AutoAdvanceCopy.subtitle(for: destination))
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
                    .accessibilityLabel(AutoAdvanceCopy.title(for: destination))
                    .accessibilityValue(AutoAdvanceCopy.subtitle(for: destination))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("clove.settings.autoAdvance.\(destination.rawValue)")
                }
            } footer: {
                Text(
                    "Stay disables auto-advance after marking while preserving your trigger preferences."
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

    var body: some View {
        if let message = store.saveFailureMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.clove.status.failed)
                    .accessibilityIdentifier("clove.settings.saveFailure")
            }
            .listRowBackground(theme.tokens.card.color)
        }
    }
}

struct SettingsResetSection: View {
    @Environment(\.cloveTheme) private var theme
    let onTapReset: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onTapReset) {
                Text("Reset to defaults")
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
    static func title(for destination: AutoAdvanceDestination) -> String {
        switch destination {
        case .stay: "Stay"
        case .nextPhoto: "Next photo"
        case .nextUnmarkedPhoto: "Next unmarked photo"
        }
    }

    static func subtitle(for destination: AutoAdvanceDestination) -> String {
        switch destination {
        case .stay: "Keep the current photo after marking."
        case .nextPhoto: "Move to the next photo in order."
        case .nextUnmarkedPhoto: "Skip already marked photos."
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
