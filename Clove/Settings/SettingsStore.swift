import CloveCore
import Foundation
import Observation

/// The app's live settings: one current ``AppSettings`` value, loaded and saved through C12's
/// ``SettingsPersistence`` (PRD Gesture-related settings, Grid, Similar groups, In-group culling,
/// Move rejects).
///
/// One store belongs to the app rather than to a scene, because a setting is app-wide while the
/// folder, photo, filter and selection are per scene (PRD P0-14). ``CloveApp`` creates it once,
/// hands it to the first scene and puts it in the SwiftUI environment, so the settings screen and
/// every screen that reads a setting observe the same value and a change shows at once.
///
/// Storage is injected, so a preview or a test can keep the work small and nothing here is a
/// global singleton.
///
/// A change is kept in memory even when storage does not confirm it, and ``saveFailureMessage``
/// says so on the settings screen in plain text. Showing that a setting did not persist is better
/// than silently applying it for this launch only, and never reporting an unconfirmed change as
/// successful is the rule every Clove write follows (PRD Failure and recovery).
@MainActor
@Observable
final class SettingsStore {
    /// C12's persistence over the storage this launch uses.
    private let persistence: SettingsPersistence
    private let rememberedAdvanceStorage: any SettingsStorage
    private static let rememberedAdvanceKey = "autoAdvance.lastEnabledDestination"
    private static let renderSamplesKey = "detail.rawRenderSamples"
    private let physicalMemory: UInt64
    private(set) var renderMeasurement: RAWRenderMeasurement

    /// The optional choice stays separate from the device measurement. Reset can
    /// therefore clear the choice without re-measuring this device.
    var photoDisplayMode: PhotoDisplayMode {
        PhotoDisplayDefault.mode(
            physicalMemory: physicalMemory,
            measurement: renderMeasurement, choice: settings.photoDisplayMode)
    }

    /// The last enabled destination, persisted so an off/on toggle survives an app relaunch.
    private(set) var rememberedAdvanceDestination: AutoAdvanceDestination

    /// The current settings every screen reads.
    ///
    /// It is the app-wide value: a reader observes a change here, and a writer changes it only
    /// through ``update(_:)`` or ``resetToDefaults()`` so the change is stored the same way.
    private(set) var settings: AppSettings

    /// Plain text saying that a change was kept in memory but not stored, or nil when the last
    /// change reached storage (PRD Failure and recovery).
    private(set) var saveFailureMessage: String?

    /// Loads the stored settings, defaulting each field C12 does not have a value for.
    init(
        persistence: SettingsPersistence = SettingsPersistence(
            storage: UserDefaultsSettingsStorage()),
        rememberedAdvanceStorage: any SettingsStorage = UserDefaultsSettingsStorage(),
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.persistence = persistence
        self.rememberedAdvanceStorage = rememberedAdvanceStorage
        self.physicalMemory = physicalMemory
        let samples =
            rememberedAdvanceStorage.string(forKey: Self.renderSamplesKey)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([Double].self, from: $0) } ?? []
        self.renderMeasurement = RAWRenderMeasurement(samples: samples)
        let loaded = persistence.load()
        self.settings = loaded
        let remembered = rememberedAdvanceStorage.string(forKey: Self.rememberedAdvanceKey)
            .flatMap(AutoAdvanceDestination.init(rawValue:))
        self.rememberedAdvanceDestination =
            loaded.autoAdvance.destination != .stay
            ? loaded.autoAdvance.destination
            : (remembered == .nextUnmarkedPhoto ? .nextUnmarkedPhoto : .nextPhoto)
        self.saveFailureMessage = nil
    }

    /// The store this launch uses.
    ///
    /// The sample launch keeps its settings in memory, so the UI test starts from C12's launch
    /// defaults and never writes the user's defaults; every other launch uses the app's standard
    /// defaults, which is also where a relaunch finds the stored settings.
    static func launch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SettingsStore {
        guard environment[TestLibrary.launchVariable] == "1" else {
            return SettingsStore()
        }
        return sample
    }

    /// A store that keeps its settings in memory, for the sample library and the previews.
    static var sample: SettingsStore {
        let storage = SampleSettingsStorage()
        return SettingsStore(
            persistence: SettingsPersistence(storage: storage), rememberedAdvanceStorage: storage)
    }

    /// Applies one change to a copy of the current settings and stores it.
    ///
    /// The change is applied in memory first and kept even when storage does not confirm it, so
    /// the setting the user just chose works for this session and the screen can say that it did
    /// not persist.
    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        if next.autoAdvance.destination != .stay {
            rememberedAdvanceDestination = next.autoAdvance.destination
        }
        rememberedAdvanceStorage.setString(
            rememberedAdvanceDestination.rawValue, forKey: Self.rememberedAdvanceKey)
        let rememberedSaved =
            rememberedAdvanceStorage.string(forKey: Self.rememberedAdvanceKey)
            == rememberedAdvanceDestination.rawValue
        settings = next
        if persistence.saveVerified(next) && rememberedSaved {
            saveFailureMessage = nil
        } else {
            saveFailureMessage =
                "This change couldn't be saved. It applies now, but Clove will forget it when it quits."
        }
    }

    /// Records successful screen renders, including one-ahead work, only until
    /// five exist. The current photo keeps its selected mode; the next arrival
    /// reads the newly measured default.
    func recordScreenRenderDurations(_ milliseconds: [Double]) {
        var next = renderMeasurement
        for sample in milliseconds.prefix(5) { next.record(milliseconds: sample) }
        guard next != renderMeasurement else { return }
        renderMeasurement = next
        guard let data = try? JSONEncoder().encode(next.samples),
            let text = String(data: data, encoding: .utf8)
        else { return }
        rememberedAdvanceStorage.setString(text, forKey: Self.renderSamplesKey)
        if rememberedAdvanceStorage.string(forKey: Self.renderSamplesKey) != text {
            saveFailureMessage =
                "This change couldn't be saved. It applies now, but Clove will forget it when it quits."
        }
    }

    /// Pauses auto-advance without replacing the user's last enabled destination.
    func setAutoAdvanceEnabled(_ enabled: Bool) {
        update { $0.autoAdvance.destination = enabled ? rememberedAdvanceDestination : .stay }
    }

    /// Restores every launch default C12 ships with and stores them.
    ///
    /// C12 defaults every setting, so the reset is the whole value: saving ``AppSettings()``
    /// returns every key to its launch value (PRD Gesture-related settings and the settings each
    /// default is documented on).
    func resetToDefaults() {
        update { $0 = AppSettings() }
    }
}
