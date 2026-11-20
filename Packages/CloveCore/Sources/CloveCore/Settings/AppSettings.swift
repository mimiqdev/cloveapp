/// How a double-tap in the detail view behaves (PRD Gesture-related settings).
public enum DoubleTapBehaviour: String, CaseIterable, Hashable, Sendable {
    /// Zoom to 100% around the presented focus region, or the tapped point when none is offered;
    /// double-tapping again returns to fit (PRD Detail and marking).
    case zoomToFocus

    /// Zoom to 100% around the tapped point even when focus regions are presented, or back to fit.
    case zoomToTapPoint

    /// No double-tap action.
    case off
}

/// How drags behave while the detail preview is zoomed (PRD Gesture-related settings).
public enum ZoomedGestures: String, CaseIterable, Hashable, Sendable {
    /// Single-finger drags rate and switch photos as they do at fit; two-finger drags pan.
    case rateAndSwitch

    /// Single-finger drags pan the zoomed image; a two-finger vertical drag rates.
    case pan
}

/// Every launch setting from the PRD, with the default each one ships with.
///
/// The type is a Sendable value with no observation or UI framework types; the settings screen
/// wraps it in whatever state object it needs. Persistence lives in `SettingsPersistence` and
/// the derived marking rules on `EnabledRatings`, `AutoAdvance`, and `availableLabels`, so the
/// UI never re-derives them.
///
/// Settings that G1 and the PRD removed are deliberately absent: Reject is never exported to
/// XMP, there is no "Also write Rating −1" option, and embedded metadata writes are not a launch
/// setting (G1 decision 5, PRD Move rejects and PRD Explicitly out of launch scope).
public struct AppSettings: Hashable, Sendable {
    /// Whether marking gestures are active (PRD Gesture-related settings); on by default.
    public var gesturesEnabled: Bool

    /// The rating levels input may apply (PRD Enabled rating levels); all five are on by
    /// default and the set is never empty.
    public var enabledRatings: EnabledRatings

    /// The destination after marking and the marks that trigger it (PRD Auto-advance); next
    /// photo, with ratings and Reject triggering and colour labels not.
    public var autoAdvance: AutoAdvance

    /// Double-tap behavior in detail (PRD Gesture-related settings); zoom to focus by default.
    public var doubleTap: DoubleTapBehaviour

    /// How drags behave while the detail preview is zoomed; single-finger rate and switch by
    /// default.
    public var zoomedGestures: ZoomedGestures

    /// Whether Orange and Pink join the five default labels (PRD Marking rules); off by default.
    public var extendedColourLabelsEnabled: Bool

    /// The validated folder name Move rejects writes into (PRD Move rejects); `_Rejected` by
    /// default.
    public var rejectsFolderName: RejectsFolderName

    /// Whether Move rejects is offered (PRD Move rejects and P0-10); on by default. Reject
    /// itself still works for filtering when this is off.
    public var moveRejectsEnabled: Bool

    /// Whether similar groups are offered (PRD Similar groups and P0-11); on by default.
    public var similarGroupsEnabled: Bool

    /// How aggressively visual similarity splits time-adjacent photos into separate groups;
    /// `.standard` by default.
    public var groupingSensitivity: GroupingSensitivity

    /// Maximum capture-time gap between consecutive photos in a similar group; `2s` by default.
    public var groupingTimeWindow: GroupingTimeWindow

    /// The three-way appearance mode (Light, Dark, System) and paired theme family
    /// (`design/handoff/tokens/tokens.md`); System + Default by default.
    public var appearance: AppearanceChoice

    /// An explicit display choice. Absent means use the measured device default.
    public var photoDisplayMode: PhotoDisplayMode?

    /// User-selected app language preference; Follow System by default.
    public var language: AppLanguage

    /// Creates every setting, defaulting each one to its launch value.
    public init(
        gesturesEnabled: Bool = true,
        enabledRatings: EnabledRatings = .all,
        autoAdvance: AutoAdvance = AutoAdvance(),
        doubleTap: DoubleTapBehaviour = .zoomToFocus,
        zoomedGestures: ZoomedGestures = .rateAndSwitch,
        extendedColourLabelsEnabled: Bool = false,
        rejectsFolderName: RejectsFolderName = .defaultFolderName,
        moveRejectsEnabled: Bool = true,
        similarGroupsEnabled: Bool = true,
        groupingSensitivity: GroupingSensitivity = .standard,
        groupingTimeWindow: GroupingTimeWindow = .twoSeconds,
        appearance: AppearanceChoice = AppearanceChoice(),
        photoDisplayMode: PhotoDisplayMode? = nil,
        language: AppLanguage = .system
    ) {
        self.gesturesEnabled = gesturesEnabled
        self.enabledRatings = enabledRatings
        self.autoAdvance = autoAdvance
        self.doubleTap = doubleTap
        self.zoomedGestures = zoomedGestures
        self.extendedColourLabelsEnabled = extendedColourLabelsEnabled
        self.rejectsFolderName = rejectsFolderName
        self.moveRejectsEnabled = moveRejectsEnabled
        self.similarGroupsEnabled = similarGroupsEnabled
        self.groupingSensitivity = groupingSensitivity
        self.groupingTimeWindow = groupingTimeWindow
        self.appearance = appearance
        self.photoDisplayMode = photoDisplayMode
        self.language = language
    }

    /// The resolved thresholds derived from `groupingTimeWindow` and `groupingSensitivity`.
    public var groupingThresholds: GroupingThresholds {
        GroupingThresholds(timeWindow: groupingTimeWindow, sensitivity: groupingSensitivity)
    }

    /// The colour labels the marking HUD, menu, and keyboard offer (PRD Marking rules).
    ///
    /// Red, Yellow, Green, Blue, and Purple always appear; Orange and Pink join them only when
    /// extended colours are enabled. Clear is not a colour label and is offered separately.
    public var availableLabels: [LabelColour] {
        extendedColourLabelsEnabled
            ? LabelColour.allCases
            : LabelColour.allCases.filter { !$0.isExtended }
    }
}
