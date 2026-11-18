/// The temporary presentation of a photo in detail on wide layouts. It is deliberately absent
/// from ``BrowsingState`` so presentation stays session-only and never persists across closes.
public enum DetailPresentation: Sendable, Equatable {
    case grid
    case photoPreview
    case focus

    public var gridFraction: Double {
        switch self {
        case .grid: 1
        case .photoPreview: 0.3
        case .focus: 0
        }
    }

    public var showsPhotoGrid: Bool {
        self == .photoPreview
    }

    public var showsFilmstrip: Bool {
        self == .focus
    }

    /// Toggles between Photo Preview (30/70 grid + photo) and Focus View (photo + filmstrip)
    /// while keeping the same current photo open.
    public var toggled: Self {
        switch self {
        case .grid, .focus: .photoPreview
        case .photoPreview: .focus
        }
    }

    /// A divider released past half the grid pane closes that pane into Focus View; dragging the
    /// same distance right returns to Grid View. Every other release settles at Photo Preview
    /// (30/70).
    public func released(translation: Double, contentWidth: Double) -> Self {
        guard contentWidth > 0 else { return self }
        let threshold = contentWidth * 0.3 / 2
        if translation <= -threshold { return .focus }
        if translation >= threshold { return .grid }
        return .photoPreview
    }
}

/// Shared availability policy deciding whether Photo Preview (30/70 grid + photo) can fit in the
/// current container without colliding with compact widths or reserved fold regions.
public struct DetailPresentationPolicy: Sendable, Equatable {
    public static let wideWidthThreshold: Double = 680
    public static let duoExpandedWidthThreshold: Double = 600
    public static let minimumHeight: Double = 420

    public let isRegularWidth: Bool
    public let isPhone: Bool
    public let isDuoExpanded: Bool
    public let isDuoCover: Bool
    public let hasFoldRegion: Bool
    public let availableWidth: Double
    public let availableHeight: Double

    public init(
        isRegularWidth: Bool,
        isPhone: Bool = false,
        isDuoExpanded: Bool,
        isDuoCover: Bool,
        hasFoldRegion: Bool,
        availableWidth: Double,
        availableHeight: Double
    ) {
        self.isRegularWidth = isRegularWidth
        self.isPhone = isPhone
        self.isDuoExpanded = isDuoExpanded
        self.isDuoCover = isDuoCover
        self.hasFoldRegion = hasFoldRegion
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
    }

    /// Whether the current layout can present both the 30% folder grid and the 70% photo stage.
    /// Compact widths, ordinary phones (even at regular landscape width), Duo cover, and narrow
    /// iPad windows retain Focus View.
    public var supportsPhotoPreview: Bool {
        if isPhone, !isDuoExpanded, !isDuoCover, !hasFoldRegion {
            return false
        }
        guard isRegularWidth, !isDuoCover else { return false }
        if isDuoExpanded {
            if hasFoldRegion { return true }
            return availableWidth == 0 || availableWidth >= Self.duoExpandedWidthThreshold
        }
        let wideEnough = availableWidth == 0 || availableWidth >= Self.wideWidthThreshold
        let tallEnough = availableHeight == 0 || availableHeight >= Self.minimumHeight
        return wideEnough && tallEnough
    }

    /// Resolves the active presentation for a stored wide preference so incidental shrinking to
    /// compact width falls back to Focus View without erasing the user's wide choice.
    public func effectivePresentation(for preferred: DetailPresentation) -> DetailPresentation {
        guard supportsPhotoPreview else {
            return preferred == .grid ? .grid : .focus
        }
        return preferred
    }
}
