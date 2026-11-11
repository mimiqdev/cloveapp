/// How a double-tap in the detail view behaves (PRD Gesture-related settings).
public enum DoubleTapBehaviour: String, CaseIterable, Hashable, Sendable {
    /// Zoom to 100% around the tapped point, or back to fit (PRD Detail and marking).
    case zoom

    /// No double-tap action.
    case off
}

/// How similar groups appear in the grid (PRD Grid, similar-group display).
public enum GridGroupDisplay: String, CaseIterable, Hashable, Sendable {
    /// Show every photo with each group outlined and counted; the launch default (PRD Grid).
    case expanded

    /// Show one cover cell per group with its count (PRD Grid).
    case collapsed
}

/// Whether navigation keeps the current zoom level and position (PRD Gesture-related settings
/// and In-group culling).
public struct KeepZoom: Hashable, Sendable {
    /// Keep zoom in regular detail while navigating photos; off by default (PRD Gesture-related
    /// settings).
    public var inDetail: Bool

    /// Regular detail starts at fit unless the person enables retained zoom.
    public init(inDetail: Bool = false) {
        self.inDetail = inDetail
    }
}

/// Every launch setting from the PRD, with the default each one ships with.
///
/// The type is a Sendable value with no observation or UI framework types; the settings screen
/// wraps it in whatever state object it needs. Persistence lives in `SettingsPersistence` and
/// the derived marking rules on `EnabledRatings`, `AutoAdvance`, and `availableLabels`, so the
/// UI never re-derives them.
///
/// Settings that G1 and the PRD removed are deliberately absent: Reject is never exported to
/// XMP, there is no "Also write Rating −1" option, embedded metadata writes are not a launch
/// setting, and there is no grouping-sensitivity setting (G1 decision 5, PRD Move rejects and
/// PRD Explicitly out of launch scope).
public struct AppSettings: Hashable, Sendable {
    /// Whether marking gestures are active (PRD Gesture-related settings); on by default.
    public var gesturesEnabled: Bool

    /// The rating levels input may apply (PRD Enabled rating levels); all five are on by
    /// default and the set is never empty.
    public var enabledRatings: EnabledRatings

    /// The destination after marking and the marks that trigger it (PRD Auto-advance); next
    /// photo, with ratings and Reject triggering and colour labels not.
    public var autoAdvance: AutoAdvance

    /// Double-tap behavior in detail (PRD Gesture-related settings); zoom by default.
    public var doubleTap: DoubleTapBehaviour

    /// Whether regular detail keeps its zoom level while navigating. Groups always sync zoom.
    public var keepZoom: KeepZoom

    /// Whether Orange and Pink join the five default labels (PRD Marking rules); off by default.
    public var extendedColourLabelsEnabled: Bool

    /// The validated folder name Move rejects writes into (PRD Move rejects); `_Rejected` by
    /// default.
    public var rejectsFolderName: RejectsFolderName

    /// Whether Move rejects is offered (PRD Move rejects and P0-10); on by default. Reject
    /// itself still works for filtering when this is off.
    public var moveRejectsEnabled: Bool

    /// Whether similar groups are offered (PRD Similar groups and P0-11); on by default. There
    /// is no grouping-sensitivity setting (PRD Explicitly out of launch scope).
    public var similarGroupsEnabled: Bool

    /// How groups appear in the grid (PRD Grid, similar-group display); expanded by default.
    public var gridGroupDisplay: GridGroupDisplay

    /// Whether the system appearance picks the theme, and the chosen theme otherwise
    /// (`design/handoff/tokens/tokens.md`); matching the system, with Light chosen, by default.
    public var appearance: AppearanceChoice

    /// Creates every launch setting, defaulting each one to its PRD launch value.
    public init(
        gesturesEnabled: Bool = true,
        enabledRatings: EnabledRatings = .all,
        autoAdvance: AutoAdvance = AutoAdvance(),
        doubleTap: DoubleTapBehaviour = .zoom,
        keepZoom: KeepZoom = KeepZoom(),
        extendedColourLabelsEnabled: Bool = false,
        rejectsFolderName: RejectsFolderName = .defaultFolderName,
        moveRejectsEnabled: Bool = true,
        similarGroupsEnabled: Bool = true,
        gridGroupDisplay: GridGroupDisplay = .expanded,
        appearance: AppearanceChoice = AppearanceChoice()
    ) {
        self.gesturesEnabled = gesturesEnabled
        self.enabledRatings = enabledRatings
        self.autoAdvance = autoAdvance
        self.doubleTap = doubleTap
        self.keepZoom = keepZoom
        self.extendedColourLabelsEnabled = extendedColourLabelsEnabled
        self.rejectsFolderName = rejectsFolderName
        self.moveRejectsEnabled = moveRejectsEnabled
        self.similarGroupsEnabled = similarGroupsEnabled
        self.gridGroupDisplay = gridGroupDisplay
        self.appearance = appearance
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
