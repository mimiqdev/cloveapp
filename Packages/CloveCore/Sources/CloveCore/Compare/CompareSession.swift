import Foundation

/// How the challenger pane (B) changes during a side-by-side comparison.
public enum CompareMode: Hashable, Sendable {
    /// Steps B through a timeline or group scope using `<` / `>`, filmstrip, and `Set as A`.
    case stepping
    /// Compares two specific photos chosen from the grid without stepping or promoting.
    case fixedPair
}

/// Which side of the split view holds the active focus for marking and undo.
public enum CompareSide: Hashable, Sendable {
    /// Reference photo (left/leading pane A).
    case reference
    /// Challenger photo (right/trailing pane B).
    case challenger
}

/// Where a comparison session originated.
public enum CompareScopeKind: Hashable, Sendable {
    /// Comparison stepped across the visible Detail Timeline.
    case timeline
    /// Comparison stepped across one expanded group's visible members.
    case group(GroupID)
    /// Comparison locked to a two-photo Grid selection.
    case fixedPair
}

/// Pure state and stepping transitions for side-by-side dual-photo comparison.
public struct CompareSession: Hashable, Sendable {
    /// Whether B can step through a scope or both panes are locked to a fixed pair.
    public let mode: CompareMode
    /// Origin scope kind for the session.
    public let scopeKind: CompareScopeKind
    /// Ordered unique photos participating in the session.
    public private(set) var scope: [PhotoIdentity]
    /// Photo currently shown in reference pane A.
    public private(set) var reference: PhotoIdentity
    /// Photo currently shown in challenger pane B.
    public private(set) var challenger: PhotoIdentity
    /// Which pane currently receives marks, Undo, and active visual emphasis.
    public var activeSide: CompareSide
    /// Whether pan and zoom gestures mirror across both panes.
    public var isSyncLocked: Bool

    /// Creates a stepping comparison starting on `current` within `rawScope`.
    /// Requires at least two unique photos with `current` present in `rawScope`.
    public init?(
        steppingFrom current: PhotoIdentity, in rawScope: [PhotoIdentity], kind: CompareScopeKind
    ) {
        guard kind != .fixedPair else { return nil }
        let uniqueScope = Self.deduplicated(rawScope)
        guard uniqueScope.count >= 2, let currentIndex = uniqueScope.firstIndex(of: current) else {
            return nil
        }
        let challengerIndex =
            currentIndex + 1 < uniqueScope.count ? currentIndex + 1 : currentIndex - 1
        self.mode = .stepping
        self.scopeKind = kind
        self.scope = uniqueScope
        self.reference = current
        self.challenger = uniqueScope[challengerIndex]
        self.activeSide = .challenger
        self.isSyncLocked = true
    }

    /// Creates a fixed-pair comparison from two distinct selected photos in grid order.
    public init?(fixedPair first: PhotoIdentity, second: PhotoIdentity) {
        guard first != second else { return nil }
        self.mode = .fixedPair
        self.scopeKind = .fixedPair
        self.scope = [first, second]
        self.reference = first
        self.challenger = second
        self.activeSide = .reference
        self.isSyncLocked = true
    }

    /// Photo currently targeted by marking and Undo.
    public var activePhoto: PhotoIdentity {
        photo(for: activeSide)
    }

    /// Photo on the non-active pane.
    public var inactivePhoto: PhotoIdentity {
        photo(for: activeSide == .reference ? .challenger : .reference)
    }

    /// Returns the photo displayed on `side`.
    public func photo(for side: CompareSide) -> PhotoIdentity {
        switch side {
        case .reference: reference
        case .challenger: challenger
        }
    }

    /// Returns which side displays `photo`, or `nil` if it is neither pane.
    public func side(of photo: PhotoIdentity) -> CompareSide? {
        if photo == reference { return .reference }
        if photo == challenger { return .challenger }
        return nil
    }

    /// Scope photos excluding `reference` that B can display in stepping mode.
    public var eligibleChallengers: [PhotoIdentity] {
        guard mode == .stepping else { return [] }
        return scope.filter { $0 != reference }
    }

    /// Whether stepping B backward (`<`) can move to an earlier candidate.
    public var canStepPreviousChallenger: Bool {
        guard mode == .stepping, let index = eligibleChallengers.firstIndex(of: challenger) else {
            return false
        }
        return index > 0
    }

    /// Whether stepping B forward (`>`) can move to a later candidate.
    public var canStepNextChallenger: Bool {
        guard mode == .stepping, let index = eligibleChallengers.firstIndex(of: challenger) else {
            return false
        }
        return index + 1 < eligibleChallengers.count
    }

    /// Whether `Set as A` is available in the current mode.
    public var canPromoteChallenger: Bool {
        mode == .stepping
    }

    /// Switches active focus to `side`.
    public mutating func selectSide(_ side: CompareSide) {
        activeSide = side
    }

    /// Toggles pan/zoom synchronization between panes.
    public mutating func toggleSyncLock() {
        isSyncLocked.toggle()
    }

    /// Steps B by `offset` within `eligibleChallengers` (skipping A).
    @discardableResult
    public mutating func stepChallenger(offset: Int) -> Bool {
        guard mode == .stepping, offset != 0 else { return false }
        let candidates = eligibleChallengers
        guard let currentIndex = candidates.firstIndex(of: challenger) else { return false }
        let nextIndex = currentIndex + offset
        guard candidates.indices.contains(nextIndex) else { return false }
        challenger = candidates[nextIndex]
        return true
    }

    /// Replaces B directly with `candidate` when in stepping mode and distinct from A.
    @discardableResult
    public mutating func selectChallenger(_ candidate: PhotoIdentity) -> Bool {
        guard mode == .stepping, candidate != reference, scope.contains(candidate) else {
            return false
        }
        challenger = candidate
        return true
    }

    /// Promotes B to A and loads the next available challenger in scope.
    /// When scope has exactly two photos, cleanly swaps A and B without changing marks.
    @discardableResult
    public mutating func promoteChallengerToReference() -> Bool {
        guard mode == .stepping else { return false }
        let previousReference = reference
        let promotedReference = challenger
        reference = promotedReference

        if scope.count == 2 {
            challenger = previousReference
            return true
        }

        guard let promotedIndex = scope.firstIndex(of: promotedReference) else {
            challenger = previousReference
            return true
        }

        // Prefer a distinct third candidate wrapping forward past the newly promoted reference.
        var fallback: PhotoIdentity?
        for step in 1..<scope.count {
            let candidate = scope[(promotedIndex + step) % scope.count]
            guard candidate != promotedReference else { continue }
            if candidate != previousReference {
                challenger = candidate
                return true
            }
            if fallback == nil {
                fallback = candidate
            }
        }

        challenger = fallback ?? previousReference
        return true
    }

    /// Reconciles the session against the photos still loaded in the folder (never filtered view state).
    /// Returns `false` if the pair or minimum 2-photo scope can no longer be maintained.
    public mutating func reconcile(available: Set<PhotoIdentity>) -> Bool {
        if mode == .fixedPair {
            return available.contains(reference) && available.contains(challenger)
        }

        let remaining = scope.filter { available.contains($0) }
        guard remaining.count >= 2 else { return false }

        let oldScope = scope
        let hasReference = available.contains(reference)
        let hasChallenger = available.contains(challenger)

        switch (hasReference, hasChallenger) {
        case (true, true):
            scope = remaining
            return true
        case (true, false):
            let oldChallengerIndex = oldScope.firstIndex(of: challenger) ?? 0
            guard
                let replacement = Self.replacementChallenger(
                    afterOldIndex: oldChallengerIndex,
                    inOldScope: oldScope,
                    remaining: remaining,
                    excluding: reference
                )
            else {
                return false
            }
            scope = remaining
            challenger = replacement
            return true
        case (false, true):
            let newReference = challenger
            let oldReferenceIndex = oldScope.firstIndex(of: reference) ?? 0
            guard
                let replacement = Self.replacementChallenger(
                    afterOldIndex: oldReferenceIndex,
                    inOldScope: oldScope,
                    remaining: remaining,
                    excluding: newReference
                )
            else {
                return false
            }
            scope = remaining
            reference = newReference
            challenger = replacement
            return true
        case (false, false):
            return false
        }
    }

    private static func replacementChallenger(
        afterOldIndex oldIndex: Int,
        inOldScope oldScope: [PhotoIdentity],
        remaining: [PhotoIdentity],
        excluding excluded: PhotoIdentity
    ) -> PhotoIdentity? {
        let remainingSet = Set(remaining)
        for index in (oldIndex + 1)..<oldScope.count {
            let candidate = oldScope[index]
            if candidate != excluded && remainingSet.contains(candidate) {
                return candidate
            }
        }
        for index in stride(from: min(oldIndex - 1, oldScope.count - 1), through: 0, by: -1) {
            let candidate = oldScope[index]
            if candidate != excluded && remainingSet.contains(candidate) {
                return candidate
            }
        }
        return remaining.first { $0 != excluded }
    }

    private static func deduplicated(_ rawScope: [PhotoIdentity]) -> [PhotoIdentity] {
        var seen: Set<PhotoIdentity> = []
        var unique: [PhotoIdentity] = []
        unique.reserveCapacity(rawScope.count)
        for photo in rawScope where seen.insert(photo).inserted {
            unique.append(photo)
        }
        return unique
    }
}

/// Layout-derived Compare availability and chrome density across wide form factors.
public struct CompareLayoutPolicy: Hashable, Sendable {
    /// Minimum horizontal width required to display two side-by-side panes comfortably.
    public static let minimumCompareWidth = 500.0
    /// Minimum horizontal width for portrait/square regular-width layouts such as full-screen iPad.
    public static let minimumRegularWidthCompare = 560.0
    /// Minimum vertical height required before adding a bottom filmstrip row below the panes.
    public static let minimumFilmstripHeight = 500.0

    /// Available viewport width in points.
    public let availableWidth: Double
    /// Available viewport height in points.
    public let availableHeight: Double
    /// Whether the horizontal size class is regular (wide).
    public let isRegularWidth: Bool
    /// Whether the vertical size class is compact (typical landscape phone).
    public let isCompactHeight: Bool
    /// Whether the dual-screen hardware is unfolded into dual-pane layout.
    public let isDuoExpanded: Bool
    /// Whether the dual-screen hardware is folded to its single cover display.
    public let isDuoCover: Bool

    public init(
        availableWidth: Double,
        availableHeight: Double,
        isRegularWidth: Bool,
        isCompactHeight: Bool,
        isDuoExpanded: Bool,
        isDuoCover: Bool
    ) {
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.isRegularWidth = isRegularWidth
        self.isCompactHeight = isCompactHeight
        self.isDuoExpanded = isDuoExpanded
        self.isDuoCover = isDuoCover
    }

    /// Whether the container currently has a wider-than-tall landscape aspect.
    public var isLandscape: Bool {
        availableWidth > availableHeight
    }

    /// True on unfolded Duo (landscape and regular-width portrait), iPad (regular-width or
    /// landscape split), and landscape iPhone; false on Duo Cover, portrait iPhone, and compact
    /// portrait Split View / Slide Over strips.
    public var supportsCompare: Bool {
        guard !isDuoCover, availableWidth > 0, availableHeight > 0 else {
            return false
        }
        if isRegularWidth && !isCompactHeight && availableWidth >= Self.minimumRegularWidthCompare {
            return true
        }
        return isLandscape && availableWidth >= Self.minimumCompareWidth
    }

    /// Shows the compact bottom filmstrip on iPad and unfolded Duo; omits it on landscape phone.
    public var showsFilmstrip: Bool {
        guard supportsCompare else { return false }
        return !isCompactHeight && availableHeight >= Self.minimumFilmstripHeight
    }
}

/// Pure horizontal pane geometry for side-by-side Compare panes, honoring any vertical fold hinge.
public struct CompareSplitGeometry: Hashable, Sendable {
    /// Width assigned to reference pane A (leading).
    public let referenceWidth: Double
    /// Width of the gap or physical hinge clearing separating pane A and pane B.
    public let dividerWidth: Double
    /// Width assigned to challenger pane B (trailing).
    public let challengerWidth: Double

    /// Computes pane widths across `containerWidth` while keeping each pane strictly on its own
    /// side of `verticalFoldMinX...verticalFoldMaxX` when a vertical display division is present.
    public static func layout(
        containerWidth: Double,
        verticalFoldMinX: Double?,
        verticalFoldMaxX: Double?,
        defaultGap: Double = 10,
        innerMargin: Double = 4
    ) -> CompareSplitGeometry {
        guard containerWidth > 0 else {
            return CompareSplitGeometry(referenceWidth: 0, dividerWidth: 0, challengerWidth: 0)
        }
        if let foldMinX = verticalFoldMinX,
            let foldMaxX = verticalFoldMaxX,
            foldMaxX > foldMinX,
            foldMinX > 0,
            foldMaxX < containerWidth
        {
            let referenceWidth = max(0, foldMinX - innerMargin)
            let challengerWidth = max(0, containerWidth - foldMaxX - innerMargin)
            let dividerWidth = max(0, containerWidth - referenceWidth - challengerWidth)
            return CompareSplitGeometry(
                referenceWidth: referenceWidth,
                dividerWidth: dividerWidth,
                challengerWidth: challengerWidth)
        }
        let gap = min(defaultGap, containerWidth)
        let paneWidth = max(0, (containerWidth - gap) / 2)
        return CompareSplitGeometry(
            referenceWidth: paneWidth,
            dividerWidth: gap,
            challengerWidth: paneWidth)
    }
}
