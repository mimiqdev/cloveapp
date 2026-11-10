import CloveCore
import SwiftUI

/// The handoff's Settings sections, followed by the supervisor's default section for existing
/// controls outside the frame (handoff screens.md §11; PRD Gesture-related settings).
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @State private var rejectsFolderNameDraft = ""
    @State private var lastAdvanceDestination: AutoAdvanceDestination = .nextPhoto

    private static let ratingLevels = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        List {
            appearanceSection
            cullingSection
            moveRejectsSection
            otherSettingsSection
            saveFailureSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
        .foregroundStyle(Color.clove.text.primary)
        .tint(theme.tokens.accent.color)
        .navigationBarTitleDisplayMode(.large)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings")
        .onAppear {
            rejectsFolderNameDraft = store.settings.rejectsFolderName.rawValue
            rememberAdvanceDestination(store.settings.autoAdvance.destination)
        }
        .onChange(of: store.settings.rejectsFolderName) { _, name in
            rejectsFolderNameDraft = name.rawValue
        }
        .onChange(of: store.settings.autoAdvance.destination) { _, destination in
            rememberAdvanceDestination(destination)
        }
    }

    private var appearanceSection: some View {
        Section {
            Toggle("Match system light/dark", isOn: binding(\.appearance.matchesSystemAppearance))
                .tint(theme.tokens.saved.color)
                .accessibilityIdentifier("clove.settings.appearance.matchSystem")
            ThemePicker(selection: theme) { tile in
                store.update { $0.appearance = $0.appearance.choosing(tile) }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            sectionHeader("Appearance", identifier: "appearance")
        } footer: {
            Text("Photos are never tinted. Only the app around them changes.")
                .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)
    }

    private var cullingSection: some View {
        Section {
            Toggle("Similar groups", isOn: binding(\.similarGroupsEnabled))
                .tint(theme.tokens.saved.color)
                .accessibilityIdentifier("clove.settings.similarGroupsEnabled")
            Toggle(
                "Auto-advance after marking",
                isOn: Binding(
                    get: { store.settings.autoAdvance.destination != .stay },
                    set: { enabled in
                        rememberAdvanceDestination(store.settings.autoAdvance.destination)
                        store.update {
                            $0.autoAdvance.destination = enabled ? lastAdvanceDestination : .stay
                        }
                    })
            )
            .tint(theme.tokens.saved.color)
            .accessibilityIdentifier("clove.settings.autoAdvanceEnabled")
            NavigationLink {
                List {
                    Section {
                        ForEach(Self.ratingLevels, id: \.rawValue) { rating in
                            Toggle(ratingName(rating), isOn: enabledRatingBinding(rating))
                                .disabled(isLastEnabledRating(rating))
                                .accessibilityIdentifier("clove.settings.rating.\(rating.rawValue)")
                        }
                    } footer: {
                        Text(
                            "Swipes follow the enabled levels. A rating another app wrote still shows when its level is off."
                        )
                    }
                    saveFailureSection
                }
                .navigationTitle("Rating scale")
                .scrollContentBackground(.hidden)
                .background(Color.clove.surface.sheet)
            } label: {
                LabeledContent(
                    "Rating scale", value: "\(store.settings.enabledRatings.count) stars")
            }
            .accessibilityIdentifier("clove.settings.ratingScale")
        } header: {
            sectionHeader("Culling", identifier: "culling")
        }
        .listRowBackground(theme.tokens.card.color)
    }

    private var moveRejectsSection: some View {
        Section {
            Toggle("Move Rejects", isOn: binding(\.moveRejectsEnabled))
                .tint(theme.tokens.saved.color)
                .accessibilityIdentifier("clove.settings.moveRejectsEnabled")
            NavigationLink {
                Form {
                    TextField("Folder name", text: $rejectsFolderNameDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("clove.settings.rejectsFolderName")
                        .onChange(of: rejectsFolderNameDraft) { _, text in
                            commitRejectsFolderName(text)
                        }
                    if let problem = rejectsFolderNameProblem {
                        Text(problem)
                            .foregroundStyle(Color.clove.status.failed)
                            .accessibilityIdentifier("clove.settings.rejectsFolderNameProblem")
                    }
                    saveFailureSection
                }
                .navigationTitle("Folder name")
            } label: {
                LabeledContent("Folder name", value: store.settings.rejectsFolderName.rawValue)
            }
        } header: {
            sectionHeader("Move rejects", identifier: "move")
        } footer: {
            Text("Rejected photos are moved, never deleted.")
                .foregroundStyle(Color.clove.text.secondary)
        }
        .listRowBackground(theme.tokens.card.color)
    }

    /// The supervisor's default placement pending the owner; these existing settings use system rows.
    private var otherSettingsSection: some View {
        Section {
            Toggle("Marking gestures", isOn: binding(\.gesturesEnabled))
                .accessibilityIdentifier("clove.settings.gesturesEnabled")
            Picker("After marking", selection: binding(\.autoAdvance.destination)) {
                Text("Stay").tag(AutoAdvanceDestination.stay)
                Text("Next photo").tag(AutoAdvanceDestination.nextPhoto)
                Text("Next unmarked photo").tag(AutoAdvanceDestination.nextUnmarkedPhoto)
            }
            .accessibilityIdentifier("clove.settings.autoAdvanceDestination")
            Toggle("Ratings advance", isOn: binding(\.autoAdvance.triggers.rating))
                .accessibilityIdentifier("clove.settings.autoAdvanceRating")
            Toggle("Reject advances", isOn: binding(\.autoAdvance.triggers.reject))
                .accessibilityIdentifier("clove.settings.autoAdvanceReject")
            Toggle("Color labels advance", isOn: binding(\.autoAdvance.triggers.colourLabel))
                .accessibilityIdentifier("clove.settings.autoAdvanceColourLabel")
            Picker("Double-tap", selection: binding(\.doubleTap)) {
                Text("Zoom to 100%").tag(DoubleTapBehaviour.zoom)
                Text("Off").tag(DoubleTapBehaviour.off)
            }
            .accessibilityIdentifier("clove.settings.doubleTap")
            Toggle("Keep zoom in groups", isOn: binding(\.keepZoom.inGroups))
                .accessibilityIdentifier("clove.settings.keepZoomInGroups")
            Toggle("Keep zoom in detail", isOn: binding(\.keepZoom.inDetail))
                .accessibilityIdentifier("clove.settings.keepZoomInDetail")
            Toggle("Extended color labels", isOn: binding(\.extendedColourLabelsEnabled))
                .accessibilityIdentifier("clove.settings.extendedColourLabels")
            Picker("Grid display", selection: binding(\.gridGroupDisplay)) {
                Text("Expanded").tag(GridGroupDisplay.expanded)
                Text("Collapsed").tag(GridGroupDisplay.collapsed)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("clove.settings.gridGroupDisplay")
            Picker("After a group is complete", selection: binding(\.groupCompletion)) {
                Text("Next group").tag(GroupCompletionBehaviour.nextGroup)
                Text("Stay").tag(GroupCompletionBehaviour.stay)
            }
            .accessibilityIdentifier("clove.settings.groupCompletion")
            Button("Reset to defaults") { store.resetToDefaults() }
                .accessibilityIdentifier("clove.settings.reset")
        } header: {
            sectionHeader("Gestures, zoom, navigation and color labels", identifier: "other")
        }
        .listRowBackground(theme.tokens.card.color)
    }

    @ViewBuilder private var saveFailureSection: some View {
        if let message = store.saveFailureMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.clove.status.failed)
                    .accessibilityIdentifier("clove.settings.saveFailure")
            }
        }
    }

    private func sectionHeader(_ title: String, identifier: String) -> some View {
        Text(title).font(.caption).foregroundStyle(Color.clove.text.secondary)
            .textCase(.uppercase)
            .accessibilityIdentifier("clove.settings.section.\(identifier)")
    }

    private func rememberAdvanceDestination(_ destination: AutoAdvanceDestination) {
        if destination != .stay { lastAdvanceDestination = destination }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } })
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

    private var rejectsFolderNameProblem: String? {
        do {
            _ = try RejectsFolderName.validated(rejectsFolderNameDraft)
            return nil
        } catch { return error.message }
    }

    private func commitRejectsFolderName(_ text: String) {
        guard let name = try? RejectsFolderName.validated(text) else { return }
        store.update { $0.rejectsFolderName = name }
    }

    private func ratingName(_ rating: Rating) -> String {
        rating.rawValue == 1 ? "1 star" : "\(rating.rawValue) stars"
    }
}
