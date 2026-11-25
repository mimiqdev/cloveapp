/// The stable storage key of one launch setting.
///
/// Raw values are a persisted format: renaming one loses the stored value, so it falls back to
/// that field's default. The list is also the exact set `SettingsPersistence` writes, which a
/// test pins to keep removed settings from coming back.
enum SettingsKey: String, CaseIterable {
    case gesturesEnabled = "gestures.enabled"
    case enabledRatings = "ratings.enabled"
    case autoAdvanceDestination = "autoAdvance.destination"
    case autoAdvanceRating = "autoAdvance.trigger.rating"
    case autoAdvanceReject = "autoAdvance.trigger.reject"
    case autoAdvanceColourLabel = "autoAdvance.trigger.colourLabel"
    case photoDisplayMode = "detail.photoDisplayMode"
    case doubleTap = "detail.doubleTap"
    case zoomedGestures = "detail.zoomedGestures"
    case extendedColourLabels = "labels.extended"
    case confirmBatchActions = "batch.confirmActions"
    case rejectsFolderName = "rejects.folderName"
    case moveRejects = "rejects.moveEnabled"
    case similarGroups = "groups.similarEnabled"
    case groupingSensitivity = "groups.sensitivity"
    case groupingTimeWindow = "groups.timeWindow"
    case appearanceMode = "appearance.mode"
    case appearanceFamily = "appearance.family"
    case language = "app.language"
}

/// Reads and writes `AppSettings` through `SettingsStorage`, one key per field.
///
/// Every field falls back to its own `AppSettings` default when its key is missing or its text
/// is not understood, so one corrupt value never resets the other settings. A setting added in
/// a later version is simply absent from old storage and reads its default; add its key, decode
/// it with that default, and write it in `save`. Keys this version does not know are left
/// untouched. Legacy `appearance.matchSystem` / `appearance.theme` keys map explicitly when
/// neither new appearance key is present. A legacy `detail.doubleTap` value of `zoom` no longer
/// names a case and loads that field's default, which is the same behavior it asked for.
public struct SettingsPersistence: Sendable {
    private static let legacyMatchSystemKey = "appearance.matchSystem"
    private static let legacyThemeKey = "appearance.theme"

    private let storage: any SettingsStorage

    /// Uses the supplied store; production passes `UserDefaultsSettingsStorage()`.
    public init(storage: any SettingsStorage) {
        self.storage = storage
    }

    /// Loads every setting, defaulting only the fields whose stored value is absent or invalid.
    public func load() -> AppSettings {
        let defaults = AppSettings()
        let autoAdvanceDefaults = defaults.autoAdvance
        let triggerDefaults = autoAdvanceDefaults.triggers
        return AppSettings(
            gesturesEnabled: boolean(.gesturesEnabled) ?? defaults.gesturesEnabled,
            enabledRatings: enabledRatings() ?? defaults.enabledRatings,
            autoAdvance: AutoAdvance(
                destination: rawValue(.autoAdvanceDestination)
                    ?? autoAdvanceDefaults.destination,
                triggers: AutoAdvanceTriggers(
                    rating: boolean(.autoAdvanceRating) ?? triggerDefaults.rating,
                    reject: boolean(.autoAdvanceReject) ?? triggerDefaults.reject,
                    colourLabel: boolean(.autoAdvanceColourLabel) ?? triggerDefaults.colourLabel
                )
            ),
            doubleTap: rawValue(.doubleTap) ?? defaults.doubleTap,
            zoomedGestures: rawValue(.zoomedGestures) ?? defaults.zoomedGestures,
            extendedColourLabelsEnabled: boolean(.extendedColourLabels)
                ?? defaults.extendedColourLabelsEnabled,
            confirmBatchActions: boolean(.confirmBatchActions) ?? defaults.confirmBatchActions,
            rejectsFolderName: rejectsFolderName() ?? defaults.rejectsFolderName,
            moveRejectsEnabled: boolean(.moveRejects) ?? defaults.moveRejectsEnabled,
            similarGroupsEnabled: boolean(.similarGroups) ?? defaults.similarGroupsEnabled,
            groupingSensitivity: rawValue(.groupingSensitivity) ?? defaults.groupingSensitivity,
            groupingTimeWindow: rawValue(.groupingTimeWindow) ?? defaults.groupingTimeWindow,
            appearance: loadAppearance(defaults: defaults.appearance),
            photoDisplayMode: rawValue(.photoDisplayMode),
            language: rawValue(.language) ?? defaults.language
        )
    }

    /// Writes every key, replacing each setting's stored value.
    public func save(_ settings: AppSettings) {
        setBoolean(settings.gesturesEnabled, .gesturesEnabled)
        setText(settings.enabledRatings.storageText, .enabledRatings)
        setText(settings.autoAdvance.destination.rawValue, .autoAdvanceDestination)
        setBoolean(settings.autoAdvance.triggers.rating, .autoAdvanceRating)
        setBoolean(settings.autoAdvance.triggers.reject, .autoAdvanceReject)
        setBoolean(settings.autoAdvance.triggers.colourLabel, .autoAdvanceColourLabel)
        setText(settings.doubleTap.rawValue, .doubleTap)
        setText(settings.zoomedGestures.rawValue, .zoomedGestures)
        setBoolean(settings.extendedColourLabelsEnabled, .extendedColourLabels)
        setBoolean(settings.confirmBatchActions, .confirmBatchActions)
        setText(settings.rejectsFolderName.rawValue, .rejectsFolderName)
        setBoolean(settings.moveRejectsEnabled, .moveRejects)
        setBoolean(settings.similarGroupsEnabled, .similarGroups)
        setText(settings.groupingSensitivity.rawValue, .groupingSensitivity)
        setText(settings.groupingTimeWindow.rawValue, .groupingTimeWindow)
        setText(settings.appearance.mode.rawValue, .appearanceMode)
        setText(settings.appearance.family.rawValue, .appearanceFamily)
        setText(settings.language.rawValue, .language)
        storage.setString(
            settings.photoDisplayMode?.rawValue, forKey: SettingsKey.photoDisplayMode.rawValue)
    }

    /// Loads `appearance.mode` and `appearance.family` independently when present, falling back
    /// to an explicit legacy mapping when neither new key exists in storage.
    private func loadAppearance(defaults: AppearanceChoice) -> AppearanceChoice {
        let hasNewKeys = text(.appearanceMode) != nil || text(.appearanceFamily) != nil
        if hasNewKeys {
            return AppearanceChoice(
                mode: rawValue(.appearanceMode) ?? defaults.mode,
                family: rawValue(.appearanceFamily) ?? defaults.family
            )
        }

        // Legacy mapping (issue #296):
        // - matchSystem == "false": preserve the saved palette's family and Light/Dark mode.
        // - matchSystem == "true", absent, or corrupt: System + Default, never silently activating
        //   an inactive stored theme.
        if storage.string(forKey: Self.legacyMatchSystemKey) == "false" {
            let legacyTheme =
                storage.string(forKey: Self.legacyThemeKey).flatMap(CloveTheme.init(rawValue:))
                ?? .light
            let legacyMode: AppearanceMode = legacyTheme.appearance == .light ? .light : .dark
            return AppearanceChoice(mode: legacyMode, family: legacyTheme.family)
        }
        return defaults
    }

    /// Writes every key, then reads them back and reports whether storage kept the settings.
    ///
    /// The store that owns the live value keeps its in-memory copy either way and shows the
    /// failure in plain text, because a setting the user just chose must not seem saved when
    /// storage dropped it. The read-back goes through this same instance, so a store that silently
    /// refuses or rewrites a value is caught (PRD Failure and recovery: never report an
    /// unconfirmed change as successful).
    ///
    /// A value that equals its default cannot be distinguished from a dropped write, because
    /// ``load()`` falls back to that same default; nothing observable is lost in that case.
    @discardableResult
    public func saveVerified(_ settings: AppSettings) -> Bool {
        save(settings)
        return load() == settings
    }

    /// Reads text, or nil when the key is absent.
    private func text(_ key: SettingsKey) -> String? {
        storage.string(forKey: key.rawValue)
    }

    /// Reads a strict `true`/`false`; any other text is corrupt and falls back (PRD defaults).
    private func boolean(_ key: SettingsKey) -> Bool? {
        switch text(key) {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// Reads an enum raw value; an unknown value falls back to that field's default.
    private func rawValue<Value: RawRepresentable>(_ key: SettingsKey) -> Value?
    where Value.RawValue == String {
        text(key).flatMap { Value(rawValue: $0) }
    }

    /// Reads a strict enabled-rating list; any malformed part invalidates the field.
    private func enabledRatings() -> EnabledRatings? {
        text(.enabledRatings).flatMap { EnabledRatings(storageText: $0) }
    }

    /// Reads a validated folder name; invalid text is refused and the default is used.
    private func rejectsFolderName() -> RejectsFolderName? {
        text(.rejectsFolderName).flatMap { RejectsFolderName(rawValue: $0) }
    }

    /// Writes a strict boolean value.
    private func setBoolean(_ value: Bool, _ key: SettingsKey) {
        setText(value ? "true" : "false", key)
    }

    /// Writes text for one key.
    private func setText(_ value: String, _ key: SettingsKey) {
        storage.setString(value, forKey: key.rawValue)
    }
}
