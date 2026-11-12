/// The expanded phone's temporary presentation. It is deliberately absent from BrowsingState.
public enum DuoSplit: Sendable, Equatable {
    case grid
    case focus
    case photoOnly

    public var gridFraction: Double {
        switch self {
        case .grid: 1
        case .focus: 0.3
        case .photoOnly: 0
        }
    }

    /// A divider released past half the grid pane closes that pane; dragging the same distance
    /// right returns to the grid. Every other release returns to 30/70.
    public func released(translation: Double, contentWidth: Double) -> Self {
        guard contentWidth > 0 else { return self }
        let threshold = contentWidth * 0.3 / 2
        if translation <= -threshold { return .photoOnly }
        if translation >= threshold { return .grid }
        return .focus
    }
}
