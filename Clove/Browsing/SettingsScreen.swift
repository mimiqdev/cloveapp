import CloveCore
import SwiftUI

/// Clove's settings: every launch setting C12 holds, with system controls (PRD Gesture-related
/// settings, Enabled rating levels, Auto-advance, Similar groups, In-group culling, Move rejects).
///
/// Controls are grouped the way PRD Gestures and keyboard lists their settings. Each control
/// writes through the app-wide ``SettingsStore``, so the open session follows a change at once and
/// the next launch reads the stored value.
///
/// Design placeholder: system lists, pickers, toggles and fields stand in for the visual design,
/// and the PRD's wording stands in for approved copy. The Appearance section is the design
/// handoff's (`design/handoff/screens.md`, Settings).
struct SettingsScreen: View {
    /// The app-wide settings every scene shares (PRD Gesture-related settings).
    @Environment(SettingsStore.self) private var store

    /// The theme in effect, which picks the tile that carries the ring (tokens.md).
    @Environment(\.cloveTheme) private var theme

    /// The rejects folder name as typed, which may not be valid yet.
    ///
    /// The draft is separate from the stored name so an invalid name can be explained where it was
    /// typed without being saved; only a name ``RejectsFolderName`` accepts reaches the store.
    @State private var rejectsFolderNameDraft = ""

    /// The rating levels the Gestures section offers, in order (PRD Enabled rating levels).
    private static let ratingLevels = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        List {
            appearanceSection
            gesturesSection
            autoAdvanceSection
            doubleTapSection
            zoomSection
            colourLabelsSection
            moveRejectsSection
            similarGroupsSection
            saveFailureSection
            resetSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings")
        .onAppear { rejectsFolderNameDraft = store.settings.rejectsFolderName.rawValue }
        .onChange(of: store.settings.rejectsFolderName) { _, name in
            // Reset to defaults and any other stored change replace the draft. Typing a valid name
            // already stored it, so its draft is equal and is left alone, while invalid text keeps
            // its place and its explanation.
            rejectsFolderNameDraft = name.rawValue
        }
    }

    /// Whether the system picks the theme, and the eight theme tiles (`design/handoff/screens.md`,
    /// Settings Appearance; tokens.md).
    ///
    /// The ring follows the theme in effect, so it sits on Light or Dark while Match system is on.
    /// Picking either of those changes nothing then; picking another theme stops matching the
    /// system (interactions.md, Theme switching).
    private var appearanceSection: some View {
        Section {
            Toggle("Match system light/dark", isOn: binding(\.appearance.matchesSystemAppearance))
                .accessibilityIdentifier("clove.settings.appearance.matchSystem")
            ThemePicker(selection: theme) { tile in
                store.update { $0.appearance = $0.appearance.choosing(tile) }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("Appearance")
        } footer: {
            Text("Photos are never tinted. Only the app around them changes.")
        }
    }

    /// Gestures on or off, and the rating levels input may apply (PRD Gesture-related settings,
    /// Enabled rating levels).
    private var gesturesSection: some View {
        Section {
            Toggle("Marking gestures", isOn: binding(\.gesturesEnabled))
                .accessibilityIdentifier("clove.settings.gesturesEnabled")
            ForEach(Self.ratingLevels, id: \.rawValue) { rating in
                Toggle(ratingName(rating), isOn: enabledRatingBinding(rating))
                    .disabled(isLastEnabledRating(rating))
                    .accessibilityIdentifier("clove.settings.rating.\(rating.rawValue)")
            }
        } header: {
            Text("Gestures")
        } footer: {
            Text(
                "Swipes follow the enabled levels. A rating another app wrote still shows when its level is off."
            )
        }
    }

    /// Where the view goes after marking, and which marks move it (PRD Auto-advance).
    private var autoAdvanceSection: some View {
        Section {
            Picker("After marking", selection: binding(\.autoAdvance.destination)) {
                Text("Stay").tag(AutoAdvanceDestination.stay)
                Text("Next photo").tag(AutoAdvanceDestination.nextPhoto)
                Text("Next unmarked photo").tag(AutoAdvanceDestination.nextUnmarkedPhoto)
            }
            .accessibilityIdentifier("clove.settings.autoAdvanceDestination")
            // Ratings and Reject advance by default; colour labels do not (PRD Auto-advance).
            Toggle("Ratings advance", isOn: binding(\.autoAdvance.triggers.rating))
                .accessibilityIdentifier("clove.settings.autoAdvanceRating")
            Toggle("Reject advances", isOn: binding(\.autoAdvance.triggers.reject))
                .accessibilityIdentifier("clove.settings.autoAdvanceReject")
            Toggle("Color labels advance", isOn: binding(\.autoAdvance.triggers.colourLabel))
                .accessibilityIdentifier("clove.settings.autoAdvanceColourLabel")
        } header: {
            Text("Auto-advance")
        } footer: {
            Text("Clove pauses about 0.3 seconds after a mark, then moves.")
        }
    }

    /// What a double-tap in detail does (PRD Gesture-related settings, Detail and marking).
    private var doubleTapSection: some View {
        Section {
            Picker("Double-tap", selection: binding(\.doubleTap)) {
                Text("Zoom to 100%").tag(DoubleTapBehaviour.zoom)
                Text("Off").tag(DoubleTapBehaviour.off)
            }
            .accessibilityIdentifier("clove.settings.doubleTap")
        } header: {
            Text("Double-tap")
        } footer: {
            Text("Zooming goes to 100% around the tapped point; double-tap again for fit.")
        }
    }

    /// Whether navigating keeps the current zoom (PRD Gesture-related settings, In-group culling).
    private var zoomSection: some View {
        Section {
            Toggle("Keep zoom in groups", isOn: binding(\.keepZoom.inGroups))
                .accessibilityIdentifier("clove.settings.keepZoomInGroups")
            Toggle("Keep zoom in detail", isOn: binding(\.keepZoom.inDetail))
                .accessibilityIdentifier("clove.settings.keepZoomInDetail")
        } header: {
            Text("Zoom")
        } footer: {
            Text("Keeping zoom navigates at the same zoom level and position.")
        }
    }

    /// Whether Orange and Pink join the five default labels (PRD Marking rules).
    private var colourLabelsSection: some View {
        Section {
            Toggle("Extended color labels", isOn: binding(\.extendedColourLabelsEnabled))
                .accessibilityIdentifier("clove.settings.extendedColourLabels")
        } header: {
            Text("Color labels")
        } footer: {
            Text("Adds Orange and Pink to Red, Yellow, Green, Blue and Purple.")
        }
    }

    /// Move rejects on or off, and the folder it writes into (PRD Move rejects, P0-10).
    ///
    /// Reject still works for filtering while the move is off, and a rename applies to the next
    /// folder that opens.
    private var moveRejectsSection: some View {
        Section {
            Toggle("Move rejects", isOn: binding(\.moveRejectsEnabled))
                .accessibilityIdentifier("clove.settings.moveRejectsEnabled")
            TextField("Rejects folder", text: $rejectsFolderNameDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("clove.settings.rejectsFolderName")
                .onChange(of: rejectsFolderNameDraft) { _, text in
                    commitRejectsFolderName(text)
                }
            if let problem = rejectsFolderNameProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("clove.settings.rejectsFolderNameProblem")
            }
        } header: {
            Text("Move rejects")
        } footer: {
            Text(
                "Rejected photos move into this folder under the open folder, with their JPEG and HIF companions and XMP. Originals are never deleted."
            )
        }
    }

    /// Similar groups on or off, how the grid draws them and what a completed group does
    /// (PRD Similar groups, Grid, In-group culling).
    private var similarGroupsSection: some View {
        Section {
            Toggle("Similar groups", isOn: binding(\.similarGroupsEnabled))
                .accessibilityIdentifier("clove.settings.similarGroupsEnabled")
            Picker("Grid display", selection: binding(\.gridGroupDisplay)) {
                Text("Expanded").tag(GridGroupDisplay.expanded)
                Text("Collapsed").tag(GridGroupDisplay.collapsed)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("clove.settings.gridGroupDisplay")
            // Expanded is the launch default, and next group is the default completion (PRD Grid,
            // In-group culling).
            Picker("After a group is complete", selection: binding(\.groupCompletion)) {
                Text("Next group").tag(GroupCompletionBehaviour.nextGroup)
                Text("Stay").tag(GroupCompletionBehaviour.stay)
            }
            .accessibilityIdentifier("clove.settings.groupCompletion")
        } header: {
            Text("Similar groups")
        } footer: {
            Text(
                "Expanded shows every photo with its group outlined; collapsed shows one cover per group."
            )
        }
    }

    /// Says a failed save in plain text instead of losing the change silently (PRD Failure and
    /// recovery).
    @ViewBuilder
    private var saveFailureSection: some View {
        if let message = store.saveFailureMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("clove.settings.saveFailure")
            }
        }
    }

    /// Puts every setting back to its launch default (PRD Gesture-related settings and each
    /// setting's own default).
    private var resetSection: some View {
        Section {
            Button("Reset to defaults") { store.resetToDefaults() }
                .accessibilityIdentifier("clove.settings.reset")
        }
    }

    /// A control's binding to one setting, read from the store and written through it.
    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } })
    }

    /// One rating level's switch, which C12 refuses to turn off when it is the last one
    /// (PRD Enabled rating levels).
    private func enabledRatingBinding(_ rating: Rating) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledRatings.contains(rating) },
            set: { isOn in
                store.update { $0.enabledRatings = $0.enabledRatings.with(rating, enabled: isOn) }
            })
    }

    /// Whether this is the only enabled level, so its switch is disabled rather than springing
    /// back (PRD Enabled rating levels).
    private func isLastEnabledRating(_ rating: Rating) -> Bool {
        store.settings.enabledRatings.count == 1 && store.settings.enabledRatings.contains(rating)
    }

    /// The plain-text problem with the typed rejects folder name, or nil when it can be saved
    /// (PRD Move rejects).
    private var rejectsFolderNameProblem: String? {
        do {
            _ = try RejectsFolderName.validated(rejectsFolderNameDraft)
            return nil
        } catch {
            return error.message
        }
    }

    /// Stores a typed rejects folder name when it is valid, leaving an invalid one unsaved
    /// (PRD Move rejects).
    private func commitRejectsFolderName(_ text: String) {
        guard let name = try? RejectsFolderName.validated(text) else { return }
        store.update { $0.rejectsFolderName = name }
    }

    /// A rating level's row title (PRD Enabled rating levels).
    private func ratingName(_ rating: Rating) -> String {
        rating.rawValue == 1 ? "1 star" : "\(rating.rawValue) stars"
    }
}
