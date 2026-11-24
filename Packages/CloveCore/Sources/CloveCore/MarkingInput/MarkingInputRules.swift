/// Resolves one marking input into the change the detail view applies (PRD P0-06).
///
/// The rules are pure: each result depends only on the marks on screen, the settings and the
/// input value. A change that would leave the marks equal is reported as `.noChange`, so it
/// neither writes nor starts auto-advance (PRD P0-06 acceptance).
///
/// Gestures report no change while marking gestures are off, and a swipe that no zoomed gesture
/// mode claims never commits (PRD Gesture-related settings and Detail gestures). Keys and the
/// rating bar are not affected by either switch.
public struct MarkingInputRules: Hashable, Sendable {
    /// The settings the rules read: gestures, enabled ratings and auto-advance (PRD P0-06).
    public var settings: AppSettings

    /// The initial axis split; the session owns the continuous vertical ladder.
    public var markingSwipeRules: MarkingSwipeRules

    public init(
        settings: AppSettings = AppSettings(),
        markingSwipeRules: MarkingSwipeRules = .standard
    ) {
        self.settings = settings
        self.markingSwipeRules = markingSwipeRules
    }

    /// Claims vertical drags at fit, and while zoomed when single-finger drags rate
    /// (`zoomedGestures == .rateAndSwitch`).
    public func beginsSwipe(
        horizontalTravel: Double, verticalTravel: Double, isZoomed: Bool
    ) -> Bool {
        markingSwipeRules.beginsSwipe(
            horizontalTravel: horizontalTravel, verticalTravel: verticalTravel,
            isZoomed: isZoomed, gesturesEnabled: settings.gesturesEnabled,
            zoomedGestures: settings.zoomedGestures)
    }

    /// Whether a swipe with `touchCount` touches may commit at the current zoom state.
    public func allowsSwipe(isZoomed: Bool, touchCount: Int) -> Bool {
        guard settings.gesturesEnabled else { return false }
        guard isZoomed else { return touchCount == 1 }
        switch settings.zoomedGestures {
        case .rateAndSwitch: return touchCount == 1
        case .pan: return touchCount == 2
        }
    }

    public func swipeSession(
        startingRating: Rating,
        containerHeight: Double = MarkingSwipeRules.referenceContainerHeight
    ) -> MarkingSwipeSession {
        MarkingSwipeSession(
            startingRating: startingRating,
            enabledRatings: settings.enabledRatings,
            containerHeight: containerHeight)
    }

    /// Commits exactly the preview, once per release. No label change, no velocity at release.
    public func result(
        forSwipeRating rating: Rating, marks: PhotoMarks, isZoomed: Bool, touchCount: Int = 1,
        allowsMarking: Bool = true
    ) -> MarkingResult {
        guard allowsMarking, allowsSwipe(isZoomed: isZoomed, touchCount: touchCount) else {
            return .noChange
        }
        return markResult(
            MarkChange(rating: rating), kind: rating == .rejected ? .reject : .rating, marks: marks)
    }

    // MARK: - Keyboard and controls

    /// The result of the HUD's Reject toggle: on sets −1, off sets 0 (PRD Marking rules).
    ///
    /// The `↓` key only turns it on. The label is never touched, and a second toggle returns
    /// the photo to the other state.
    public func result(forRejectToggle marks: PhotoMarks, allowsMarking: Bool = true)
        -> MarkingResult
    {
        guard allowsMarking else { return .noChange }
        return markResult(
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
    /// `allowsMarking == false` (unexpanded collapsed group stack in Timeline) disables all
    /// marking keys while preserving navigation, undo, and group focus keys.
    public func result(
        for key: MarkingKey, marks: PhotoMarks, allowsMarking: Bool = true
    ) -> MarkingResult {
        switch key {
        case .rating(let rating):
            guard allowsMarking, settings.enabledRatings.canApply(rating) else { return .noChange }
            return markResult(
                ratingChange(applying: rating, to: marks), kind: .rating, marks: marks)
        case .colourLabel(let colour):
            guard allowsMarking else { return .noChange }
            return result(forLabel: ColourLabel(colour: colour), marks: marks)
        case .nextRating:
            guard allowsMarking, let next = settings.enabledRatings.next(after: marks.rating) else {
                return .noChange
            }
            return markResult(
                ratingChange(applying: next, to: marks), kind: .rating, marks: marks)
        case .reject:
            guard allowsMarking else { return .noChange }
            return markResult(MarkChange(rating: .rejected), kind: .reject, marks: marks)
        case .previousPhoto:
            return .previousPhoto
        case .nextPhoto:
            return .nextPhoto
        case .undo:
            return .undo
        case .toggleGroupFocus:
            return .toggleGroupFocus
        case .collapseGroup:
            return .collapseGroup
        }
    }

    /// The result of tapping a level in the rating bar (PRD Marking rules).
    ///
    /// Tapping the level already applied clears the rating, and only enabled levels may be
    /// applied (PRD Marking rules and Enabled rating levels). A rating of 1 to 5 replaces Reject
    /// with those stars, because the same value carries both; clearing a rating sets 0.
    public func result(
        forRating level: Rating, marks: PhotoMarks, allowsMarking: Bool = true
    ) -> MarkingResult {
        guard allowsMarking, settings.enabledRatings.canApply(level) else { return .noChange }
        let applied = level > .unrated && level == marks.rating ? Rating.unrated : level
        return markResult(ratingChange(applying: applied, to: marks), kind: .rating, marks: marks)
    }

    /// The result of choosing a label, from a key or the label bar (PRD Marking rules).
    ///
    /// Choosing the label that is already applied clears it, which matches the rating bar's
    /// tap-again-to-clear and Lightroom's label keys; choosing another replaces it. Choosing
    /// Clear on a photo whose label is already clear changes nothing. An unknown label written
    /// by another app is replaced by the chosen colour.
    public func result(
        forLabel label: ColourLabel, marks: PhotoMarks, allowsMarking: Bool = true
    ) -> MarkingResult {
        guard allowsMarking else { return .noChange }
        let applied = label == marks.label ? ColourLabel.clear : label
        return markResult(MarkChange(label: applied), kind: .colourLabel, marks: marks)
    }

    // MARK: - Auto-advance

    /// Where to go after a written mark, and the photo undo returns to (PRD Auto-advance).
    ///
    /// Call this only for a `.mark` result: a `.noChange` result carries no mark kind and
    /// advances nothing (PRD P0-06 acceptance). Clearing a mark back to `.unrated` or `.clear`
    /// stays on the current photo without advancing. `photos` is the ordered list the detail view is
    /// navigating, with the marks it shows. `group` is the group view's own answer; it replaces
    /// the policy's next photo because the group's Undecided rule and completion belong to the
    /// group view (PRD In-group culling). Without a target photo, or in a completed group, the
    /// view stays (PRD Auto-advance).
    public func autoAdvancePlan(
        after mark: MarkKind,
        change: MarkChange? = nil,
        from photo: PhotoIdentity,
        photos: [GridPhoto],
        group: GroupAdvance? = nil
    ) -> AutoAdvancePlan {
        let stay = AutoAdvancePlan(target: .stay, markedPhoto: photo)
        guard settings.autoAdvance.shouldAdvance(after: mark),
            change?.isClearing(for: mark) != true
        else { return stay }
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
                    PhotoFilter.unmarked.matches(
                        $0.marks, relativeFolderPath: $0.id.relativeFolderPath)
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
