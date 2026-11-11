/// Fit-only photo navigation. Axis is chosen once at the start of a drag; marking retains
/// its own vertical thresholds. Travel and velocity are positive to the right.
public enum NavigationSwipeRules {
    public enum Axis: Sendable {
        case horizontal
        case vertical
    }

    public static func axis(horizontal: Double, vertical: Double) -> Axis {
        abs(horizontal) > abs(vertical) ? .horizontal : .vertical
    }

    /// A quarter-width drag or a deliberate flick advances one photo. Reversing velocity
    /// cannot flick in the opposite direction from the finger's travel.
    public static func step(
        travel: Double, velocity: Double, width: Double,
        hasPrevious: Bool, hasNext: Bool
    ) -> Int {
        guard width > 0, travel != 0 else { return 0 }
        let direction = travel < 0 ? 1 : -1
        guard direction == 1 ? hasNext : hasPrevious else { return 0 }
        let flick = abs(travel) >= 10 && abs(velocity) >= 600 && travel * velocity > 0
        return abs(travel) >= width * 0.25 || flick ? direction : 0
    }

    /// At an end, resistance grows smoothly and never lets the photo leave the viewport.
    public static func offset(
        travel: Double, width: Double, hasPrevious: Bool, hasNext: Bool
    ) -> Double {
        guard width > 0 else { return 0 }
        let hasNeighbour = travel < 0 ? hasNext : hasPrevious
        guard !hasNeighbour else { return travel }
        let distance = abs(travel) * 0.55
        let resisted = width * distance / (width + distance)
        return travel < 0 ? -resisted : resisted
    }
}
