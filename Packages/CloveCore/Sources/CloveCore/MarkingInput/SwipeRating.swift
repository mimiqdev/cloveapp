/// The distances of the swipe-up rating ladder (PRD Rating by swipe distance).
///
/// Both values are starting points. The step distance is the PRD's "initially about 60 pt" and
/// is still an open item for tuning; the dead zone is Clove's own choice for the travel that
/// still counts as a tap, so a slightly moving finger does not rate. They are in points on every
/// device and never scale with screen size, so iPhone and iPad feel the same. Change them here;
/// no other code holds a threshold.
public struct SwipeRatingRules: Hashable, Sendable {
    /// The travel, in points, between two step boundaries (PRD open item: about 60 pt).
    public var stepDistance: Double

    /// The travel, in points, that must pass before the first step (Clove's starting value).
    ///
    /// Inside it the gesture is still a tap and the step is 0, so returning to the start before
    /// release writes nothing (PRD Rating by swipe distance).
    public var deadZone: Double

    /// The launch starting values: a 40 pt dead zone, then 60 pt per step.
    public static let standard = SwipeRatingRules()

    /// Creates the ladder distances; the defaults are the launch starting values.
    ///
    /// A non-positive step distance would make the ladder undefined, so `step(forTravel:)`
    /// reports the dead zone only for it.
    public init(stepDistance: Double = 60, deadZone: Double = 40) {
        self.stepDistance = stepDistance
        self.deadZone = deadZone
    }

    /// The step for the vertical travel since touch-down, in points with up positive.
    ///
    /// Zero inside the dead zone, 1 at the first point past it, and one more step for every
    /// further `stepDistance`, so the boundaries sit at `deadZone + n * stepDistance` for
    /// n >= 0. Travel down is negative and never rates. The result is not capped here; use
    /// `step(forTravel:maximumStep:)` for the ladder the enabled ratings allow.
    public func step(forTravel travel: Double) -> Int {
        guard stepDistance > 0, travel > deadZone else { return 0 }
        let steps = (travel - deadZone) / stepDistance
        return steps < Double(Int.max) ? 1 + Int(steps) : Int.max
    }

    /// The step capped at the number of enabled ratings, so the ladder never passes the top
    /// enabled level (PRD Rating by swipe distance and Enabled rating levels).
    public func step(forTravel travel: Double, maximumStep: Int) -> Int {
        min(step(forTravel: travel), max(maximumStep, 0))
    }
}

/// One step boundary crossed while a swipe-up gesture is in progress.
///
/// The UI plays a light haptic and updates the rating shown near the finger for each report
/// (PRD Rating by swipe distance). No report means the finger stayed inside the current step.
public enum SwipeStepChange: Hashable, Sendable {
    /// Travel grew past a boundary; the gesture now reports this 1-based step.
    case raised(to: Int)

    /// Travel came back past a boundary, so the shown rating steps back down.
    case lowered(to: Int)

    /// The step the gesture reports after the change.
    public var step: Int {
        switch self {
        case .raised(let step), .lowered(let step): return step
        }
    }
}

/// The live state of one swipe-up gesture (PRD Rating by swipe distance).
///
/// Feed it the vertical travel since touch-down as the finger moves. `update(travel:)` reports
/// each step boundary crossed in either direction, and `release(atTravel:)` gives the rating the
/// release position decides; velocity is never read. The value writes nothing, holds no timers
/// and has no UI type, so a cancelled gesture is simply discarded by starting a new session.
public struct SwipeRatingSession: Hashable, Sendable {
    /// The levels a step may apply, which also cap the ladder (PRD Enabled rating levels).
    public let enabledRatings: EnabledRatings

    /// The distances this session measures with.
    public let rules: SwipeRatingRules

    /// The last travel reported, in points with up positive.
    public private(set) var travel: Double = 0

    /// The current step, or 0 inside the dead zone.
    public private(set) var step: Int = 0

    /// Starts a gesture at the touch-down point with no travel.
    public init(enabledRatings: EnabledRatings, rules: SwipeRatingRules = .standard) {
        self.enabledRatings = enabledRatings
        self.rules = rules
    }

    /// The highest step this session can reach (PRD Enabled rating levels).
    public var maximumStep: Int { enabledRatings.count }

    /// The enabled rating the finger is currently on, or nil at step 0.
    public var rating: Rating? { enabledRatings.rating(forSwipeStep: step) }

    /// The step this session maps a travel value to, capped at the enabled levels.
    public func step(forTravel travel: Double) -> Int {
        rules.step(forTravel: travel, maximumStep: maximumStep)
    }

    /// Moves the gesture to a new travel and reports the boundary it crossed, if any.
    ///
    /// Swiping back lowers the step (PRD Rating by swipe distance). Crossing nothing is
    /// reported as nil, so the UI only reacts at a boundary.
    @discardableResult
    public mutating func update(travel newTravel: Double) -> SwipeStepChange? {
        travel = newTravel
        let newStep = step(forTravel: newTravel)
        guard newStep != step else { return nil }
        let previousStep = step
        step = newStep
        return newStep > previousStep ? .raised(to: newStep) : .lowered(to: newStep)
    }

    /// Ends the gesture at the release position and returns the rating to apply.
    ///
    /// The release position decides, never velocity (PRD Rating by swipe distance). Nil means
    /// step 0, so the gesture writes nothing and the current mark stays untouched.
    public mutating func release(atTravel travel: Double) -> Rating? {
        update(travel: travel)
        return rating
    }
}
