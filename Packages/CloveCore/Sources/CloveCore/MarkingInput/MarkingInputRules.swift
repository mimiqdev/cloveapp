/// Resolves one marking input into the change the detail view applies (PRD P0-06).
///
/// The rules are pure: each result depends only on the marks on screen, the settings and the
/// input value. A change that would leave the marks equal is reported as `.noChange`, so it
/// neither writes nor starts auto-advance (PRD P0-06 acceptance).
///
/// Gestures report no change while marking gestures are off or the view is zoomed, because
/// vertical marking swipes are disabled while zoomed (PRD Gesture-related settings and Detail
/// gestures). Keys and the rating bar are not affected by either switch.
public struct MarkingInputRules: Hashable, Sendable {
    /// The settings the rules read: gestures, enabled ratings and auto-advance (PRD P0-06).
    public var settings: AppSettings

    /// The swipe-up distances (PRD Rating by swipe distance); starting values, tunable.
    public var swipeRatingRules: SwipeRatingRules

    /// The swipe-down Reject threshold (PRD Detail gestures); a starting value, tunable.
    public var rejectSwipeRules: RejectSwipeRules

    /// The drag that begins a marking swipe (PRD Detail gestures); a starting value, tunable.
    public var markingSwipeRules: MarkingSwipeRules

    /// Creates the rules from the current settings and the gesture constants.
    public init(
        settings: AppSettings = AppSettings(),
        swipeRatingRules: SwipeRatingRules = .standard,
        rejectSwipeRules: RejectSwipeRules = .standard,
        markingSwipeRules: MarkingSwipeRules = .standard
    ) {
        self.settings = settings
        self.swipeRatingRules = swipeRatingRules
        self.rejectSwipeRules = rejectSwipeRules
        self.markingSwipeRules = markingSwipeRules
    }

    // MARK: - Swipe-up rating

    /// The marking swipe a drag on the detail preview begins as, or nil when it begins none
    /// (PRD Detail gestures).
    ///
    /// This is the preview's one question as a drag starts: marking gestures off (PRD
    /// Gesture-related settings), a zoomed view and a more horizontal than vertical drag all
    /// answer nil, and the recognizer then leaves the drag alone. The step ladder is separate,
    /// because it is read on every sample of a swipe that did begin.
    public func beginSwipe(
        horizontalTravel: Double,
        verticalTravel: Double,
        isZoomed: Bool
    ) -> MarkingSwipe? {
        markingSwipeRules.swipe(
            horizontalTravel: horizontalTravel,
            verticalTravel: verticalTravel,
            isZoomed: isZoomed,
            gesturesEnabled: settings.gesturesEnabled)
    }

    /// Starts a swipe-up gesture that measures with this rule set.
    ///
    /// The session reports the live step for the rating shown near the finger and the per-step
    /// haptic; the release result comes from `result(forSwipeUpTravel:marks:isZoomed:)`, which
    /// applies `settings.enabledRatings`.
    public func swipeRatingSession() -> SwipeRatingSession {
        SwipeRatingSession(enabledRatings: settings.enabledRatings, rules: swipeRatingRules)
    }

    /// The result of releasing a swipe-up at this travel, in points with up positive.
    ///
    /// The release position decides (PRD Rating by swipe distance). Step 0 writes nothing, and
    /// a short flick past the dead zone gives the lowest enabled step. The applied rating is the
    /// enabled level for the step, so a current rating that another app wrote at a disabled
    /// level is still replaced by the step's enabled level. The ladder starts at 0 and never
    /// produces Reject, so a swipe on a rejected photo replaces −1 with stars (PRD Detail
    /// gestures); a swipe never clears a rating.
    public func result(
        forSwipeUpTravel travel: Double,
        marks: PhotoMarks,
        isZoomed: Bool
    ) -> MarkingResult {
        guard settings.gesturesEnabled, !isZoomed else { return .noChange }
        let step = swipeRatingRules.step(
            forTravel: travel, maximumStep: settings.enabledRatings.count)
        guard step > 0, let rating = settings.enabledRatings.rating(forSwipeStep: step) else {
            return .noChange
        }
        return markResult(ratingChange(applying: rating, to: marks), kind: .rating, marks: marks)
    }

    // MARK: - Swipe-down Reject

    /// Starts a swipe-down gesture that measures with this rule set.
    public func rejectSwipeSession() -> RejectSwipeSession {
        RejectSwipeSession(rules: rejectSwipeRules)
    }

    /// The result of releasing a swipe-down at this travel, in points with up positive.
    ///
    /// Past the threshold the photo is rejected, which sets the rating to −1 and replaces any
    /// stars; released back inside it, nothing happens (PRD Detail gestures). A photo that is
    /// already rejected yields no change, because applying the same Reject leaves the marks equal
    /// (PRD P0-06 acceptance).
    public func result(
        forSwipeDownTravel travel: Double,
        marks: PhotoMarks,
        isZoomed: Bool
    ) -> MarkingResult {
        guard settings.gesturesEnabled, !isZoomed,
            rejectSwipeRules.isPastThreshold(travel: travel)
        else { return .noChange }
        return markResult(MarkChange(rating: .rejected), kind: .reject, marks: marks)
    }

    // MARK: - Keyboard and controls

    /// The result of the HUD's Reject toggle: on sets −1, off sets 0 (PRD Marking rules).
    ///
    /// This is the one Reject input that can clear the mark; the swipe down and the `↓` key only
    /// turn it on. The label is never touched, and a second toggle in either direction returns
    /// the photo to the other state.
    public func result(forRejectToggle marks: PhotoMarks) -> MarkingResult {
        markResult(
            MarkChange(rating: marks.isRejected ? .unrated : .rejected), kind: .reject,
            marks: marks)
    }

    /// The result of one key from the PRD keyboard table.
    ///
    /// `0` clears and `1`–`5` set only enabled levels (PRD keyboard table and Enabled rating
    /// levels). `↑` uses the enabled ladder's next value (PRD keyboard table). A label key sets
    /// that label, or clears it when it is already applied. `↓` rejects, which sets −1. `←` and
    /// `→` navigate. `⌘Z` is reported as undo for C5. A rating key behaves like the rating bar
    /// rather than the bar's toggle: pressing the level already applied changes nothing.
    public func result(for key: MarkingKey, marks: PhotoMarks) -> MarkingResult {
        switch key {
        case .rating(let rating):
            guard settings.enabledRatings.canApply(rating) else { return .noChange }
            return markResult(
                ratingChange(applying: rating, to: marks), kind: .rating, marks: marks)
        case .colourLabel(let colour):
            return result(forLabel: ColourLabel(colour: colour), marks: marks)
        case .nextRating:
            guard let next = settings.enabledRatings.next(after: marks.rating) else {
                return .noChange
            }
            return markResult(
                ratingChange(applying: next, to: marks), kind: .rating, marks: marks)
        case .reject:
            return markResult(MarkChange(rating: .rejected), kind: .reject, marks: marks)
        case .previousPhoto:
            return .previousPhoto
        case .nextPhoto:
            return .nextPhoto
        case .undo:
            return .undo
        }
    }

    /// The result of tapping a level in the rating bar (PRD Marking rules).
    ///
    /// Tapping the level already applied clears the rating, and only enabled levels may be
    /// applied (PRD Marking rules and Enabled rating levels). A rating of 1 to 5 replaces Reject
    /// with those stars, because the same value carries both; clearing a rating sets 0.
    public func result(forRating level: Rating, marks: PhotoMarks) -> MarkingResult {
        guard settings.enabledRatings.canApply(level) else { return .noChange }
        let applied = level > .unrated && level == marks.rating ? Rating.unrated : level
        return markResult(ratingChange(applying: applied, to: marks), kind: .rating, marks: marks)
    }

    /// The result of choosing a label, from a key or the label bar (PRD Marking rules).
    ///
    /// Choosing the label that is already applied clears it, which matches the rating bar's
    /// tap-again-to-clear and Lightroom's label keys; choosing another replaces it. Choosing
    /// Clear on a photo whose label is already clear changes nothing. An unknown label written
    /// by another app is replaced by the chosen colour.
    public func result(forLabel label: ColourLabel, marks: PhotoMarks) -> MarkingResult {
        let applied = label == marks.label ? ColourLabel.clear : label
        return markResult(MarkChange(label: applied), kind: .colourLabel, marks: marks)
    }

    // MARK: - Auto-advance

    /// Where to go after a written mark, and the photo undo returns to (PRD Auto-advance).
    ///
    /// Call this only for a `.mark` result: a `.noChange` result carries no mark kind and
    /// advances nothing (PRD P0-06 acceptance). `photos` is the ordered list the detail view is
    /// navigating, with the marks it shows. `group` is the group view's own answer; it replaces
    /// the policy's next photo because the group's Undecided rule and completion belong to the
    /// group view (PRD In-group culling). Without a target photo, or in a completed group, the
    /// view stays (PRD Auto-advance).
    public func autoAdvancePlan(
        after mark: MarkKind,
        from photo: PhotoIdentity,
        photos: [GridPhoto],
        group: GroupAdvance? = nil
    ) -> AutoAdvancePlan {
        let stay = AutoAdvancePlan(target: .stay, markedPhoto: photo)
        guard settings.autoAdvance.shouldAdvance(after: mark) else { return stay }
        if let group {
            guard case .nextUndecidedPhoto(let next) = group, next != photo else { return stay }
            return AutoAdvancePlan(target: .groupUndecidedPhoto(next), markedPhoto: photo)
        }
        guard let index = photos.firstIndex(where: { $0.id == photo }) else { return stay }
        switch settings.autoAdvance.destination {
        case .stay:
            return stay
        case .nextPhoto:
            guard let next = photos.dropFirst(index + 1).first else { return stay }
            return AutoAdvancePlan(target: .nextPhoto(next.id), markedPhoto: photo)
        case .nextUnmarkedPhoto:
            guard
                let next = photos.dropFirst(index + 1).first(where: {
                    PhotoFilter.unmarked.matches($0.marks)
                })
            else { return stay }
            return AutoAdvancePlan(target: .nextUnmarkedPhoto(next.id), markedPhoto: photo)
        }
    }

    // MARK: - Shared pieces

    /// The change that applies `rating`.
    ///
    /// The rating is the photo's one Reject value, so setting stars or 0 replaces −1 in the same
    /// change; nothing else is touched.
    private func ratingChange(applying rating: Rating, to marks: PhotoMarks) -> MarkChange {
        MarkChange(rating: rating)
    }

    /// A change that would leave the marks equal is reported as no change (PRD P0-06).
    private func markResult(
        _ change: MarkChange,
        kind: MarkKind,
        marks: PhotoMarks
    ) -> MarkingResult {
        marks.applying(change) == marks ? .noChange : .mark(change, kind)
    }
}
