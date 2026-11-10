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
    case doubleTap = "detail.doubleTap"
    case keepZoomInGroups = "zoom.keepInGroups"
    case keepZoomInDetail = "zoom.keepInDetail"
    case extendedColourLabels = "labels.extended"
    case rejectsFolderName = "rejects.folderName"
    case moveRejects = "rejects.moveEnabled"
    case similarGroups = "groups.similarEnabled"
    case gridGroupDisplay = "grid.groupDisplay"
    case groupCompletion = "groups.completion"
    case appearanceMatchesSystem = "appearance.matchSystem"
    case appearanceTheme = "appearance.theme"
}

/// Reads and writes `AppSettings` through `SettingsStorage`, one key per field.
///
/// Every field falls back to its own `AppSettings` default when its key is missing or its text
/// is not understood, so one corrupt value never resets the other settings. A setting added in
/// a later version is simply absent from old storage and reads its default; add its key, decode
/// it with that default, and write it in `save`. No migration step is required. Keys this
/// version does not know are left untouched.
public struct SettingsPersistence: Sendable {
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
            keepZoom: KeepZoom(
                inGroups: boolean(.keepZoomInGroups) ?? defaults.keepZoom.inGroups,
                inDetail: boolean(.keepZoomInDetail) ?? defaults.keepZoom.inDetail
            ),
            extendedColourLabelsEnabled: boolean(.extendedColourLabels)
                ?? defaults.extendedColourLabelsEnabled,
            rejectsFolderName: rejectsFolderName() ?? defaults.rejectsFolderName,
            moveRejectsEnabled: boolean(.moveRejects) ?? defaults.moveRejectsEnabled,
            similarGroupsEnabled: boolean(.similarGroups) ?? defaults.similarGroupsEnabled,
            gridGroupDisplay: rawValue(.gridGroupDisplay) ?? defaults.gridGroupDisplay,
            groupCompletion: rawValue(.groupCompletion) ?? defaults.groupCompletion,
            appearance: AppearanceChoice(
                matchesSystemAppearance: boolean(.appearanceMatchesSystem)
                    ?? defaults.appearance.matchesSystemAppearance,
                theme: rawValue(.appearanceTheme) ?? defaults.appearance.theme
            )
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
        setBoolean(settings.keepZoom.inGroups, .keepZoomInGroups)
        setBoolean(settings.keepZoom.inDetail, .keepZoomInDetail)
        setBoolean(settings.extendedColourLabelsEnabled, .extendedColourLabels)
        setText(settings.rejectsFolderName.rawValue, .rejectsFolderName)
        setBoolean(settings.moveRejectsEnabled, .moveRejects)
        setBoolean(settings.similarGroupsEnabled, .similarGroups)
        setText(settings.gridGroupDisplay.rawValue, .gridGroupDisplay)
        setText(settings.groupCompletion.rawValue, .groupCompletion)
        setBoolean(settings.appearance.matchesSystemAppearance, .appearanceMatchesSystem)
        setText(settings.appearance.theme.rawValue, .appearanceTheme)
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
