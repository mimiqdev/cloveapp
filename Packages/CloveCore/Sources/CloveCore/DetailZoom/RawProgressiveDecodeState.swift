import Foundation
import Observation

/// Display phase for the 250 ms delay-gated 100% RAW progressive decode indicator.
public enum RawProgressiveDecodePhase: Hashable, Sendable {
    /// No progressive decode cue is shown (idle, fit zoom, non-RAW, or full resolution settled).
    case idle
    /// Full-res RAW decode started, inside the 250 ms delay gate; UI matches `.idle`.
    case gating
    /// Gate elapsed (> 250 ms) while full-res decode is still running; UI shows spinner + `Preview`.
    case decodingPreview
    /// Decode failed, no higher resolution exists, or location disconnected; UI shows `Preview only`.
    case previewOnly

    /// Whether the inline decode spinner should be displayed.
    public var showsSpinner: Bool {
        self == .decodingPreview
    }

    /// Whether the static preview-only fallback label should be displayed.
    public var isPreviewOnly: Bool {
        self == .previewOnly
    }

    /// Whether a progressive RAW decode is actively tracked (gated or visible).
    public var isInFlight: Bool {
        self == .gating || self == .decodingPreview
    }
}

/// Token identifying a single 100% RAW upgrade attempt so stale completions are ignored.
public struct RawProgressiveDecodeToken: Hashable, Sendable {
    public let id: UUID
    public let photoID: PhotoIdentity

    public init(id: UUID = UUID(), photoID: PhotoIdentity) {
        self.id = id
        self.photoID = photoID
    }
}

/// Domain inputs deciding whether a 100% zoom upgrade tracks progressive RAW decoding.
public struct RawProgressiveDecodeEligibility: Hashable, Sendable {
    public let primaryFormat: PhotoFormat
    public let hasCameraCompanion: Bool
    public let displayMode: PhotoDisplayMode
    public let shownHasRAW: Bool
    public let shownIsNativeRAW: Bool
    public let shownIsScreenRAW: Bool
    public let shownIsBestAvailable: Bool
    public let isPreviewOnly: Bool
    public let isLocationLost: Bool

    public init(
        primaryFormat: PhotoFormat,
        hasCameraCompanion: Bool,
        displayMode: PhotoDisplayMode,
        shownHasRAW: Bool,
        shownIsNativeRAW: Bool,
        shownIsScreenRAW: Bool,
        shownIsBestAvailable: Bool,
        isPreviewOnly: Bool,
        isLocationLost: Bool
    ) {
        self.primaryFormat = primaryFormat
        self.hasCameraCompanion = hasCameraCompanion
        self.displayMode = displayMode
        self.shownHasRAW = shownHasRAW
        self.shownIsNativeRAW = shownIsNativeRAW
        self.shownIsScreenRAW = shownIsScreenRAW
        self.shownIsBestAvailable = shownIsBestAvailable
        self.isPreviewOnly = isPreviewOnly
        self.isLocationLost = isLocationLost
    }

    /// True when zooming to 100% requests a RAW decode that is not yet available.
    public var shouldTrackFullResolutionUpgrade: Bool {
        guard !isPreviewOnly, !isLocationLost else { return false }
        guard primaryFormat == .raw, shownHasRAW else { return false }
        guard !shownIsNativeRAW, !shownIsBestAvailable else { return false }
        switch displayMode {
        case .rawFirst:
            return true
        case .cameraPreviewFirst:
            // With a camera companion in camera-preview-first mode, 100% decodes the full raster
            // companion rather than RAW unless the companion failed and fell back to screen RAW.
            return !hasCameraCompanion || shownIsScreenRAW
        }
    }

    /// True when a RAW photo at 100% already cannot obtain full resolution (failed or disconnected).
    public var shouldShowStaticPreviewOnly: Bool {
        guard primaryFormat == .raw else { return false }
        guard !shownIsNativeRAW, !shownIsBestAvailable else { return false }
        return isPreviewOnly || isLocationLost
    }
}

/// Pure state transitions for the 250 ms delay-gated 100% RAW progressive decode cue.
public struct RawProgressiveDecodeState: Hashable, Sendable {
    public private(set) var phase: RawProgressiveDecodePhase = .idle
    public private(set) var activeToken: RawProgressiveDecodeToken?

    public init() {}

    /// Starts gating a new 100% RAW upgrade for `photoID` and returns its matching token.
    public mutating func begin(for photoID: PhotoIdentity) -> RawProgressiveDecodeToken {
        let token = RawProgressiveDecodeToken(photoID: photoID)
        activeToken = token
        phase = .gating
        return token
    }

    /// Transitions from `.gating` to `.decodingPreview` when the 250 ms gate elapses.
    @discardableResult
    public mutating func revealAfterGate(for token: RawProgressiveDecodeToken) -> Bool {
        guard activeToken == token, phase == .gating else { return false }
        phase = .decodingPreview
        return true
    }

    /// Marks the decode complete, settling back to `.idle` regardless of whether the gate elapsed.
    @discardableResult
    public mutating func complete(for token: RawProgressiveDecodeToken) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        phase = .idle
        return true
    }

    /// Marks the active decode failed or unavailable, stopping any spinner into `.previewOnly`.
    @discardableResult
    public mutating func fail(for token: RawProgressiveDecodeToken) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        phase = .previewOnly
        return true
    }

    /// Cancels an active token silently into `.idle` (for superseded/deferred requests).
    @discardableResult
    public mutating func cancel(for token: RawProgressiveDecodeToken) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        phase = .idle
        return true
    }

    /// Forces static `.previewOnly` (for example, when entering 100% on an already-failed RAW
    /// or when the backing storage disconnects mid-decode).
    public mutating func enterPreviewOnly() {
        activeToken = nil
        phase = .previewOnly
    }

    /// Cancels tracking and clears `.previewOnly` immediately back to `.idle`.
    public mutating func reset() {
        activeToken = nil
        phase = .idle
    }
}

/// Main-actor controller owning the 250 ms delay-gate task for Detail and Compare readouts.
@MainActor
@Observable
public final class RawProgressiveDecodeController {
    /// Default 250 ms quiet period before surfacing `Preview` + spinner.
    public nonisolated static let defaultGateDelay: Duration = .milliseconds(250)

    private var state = RawProgressiveDecodeState()
    private var gateTask: Task<Void, Never>?
    private let gateDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Current display phase observed by SwiftUI readouts.
    public var phase: RawProgressiveDecodePhase { state.phase }

    /// Token for the currently tracked upgrade, or `nil` when settled/idle.
    public var activeToken: RawProgressiveDecodeToken? { state.activeToken }

    public init(
        gateDelay: Duration = RawProgressiveDecodeController.defaultGateDelay,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.gateDelay = gateDelay
        self.sleep = sleep
    }

    /// Starts the 250 ms delay gate for a 100% RAW upgrade unless `photoID` already has an
    /// active in-flight token, returning the active token to report completion/failure against.
    @discardableResult
    public func beginUpgrade(for photoID: PhotoIdentity) -> RawProgressiveDecodeToken {
        if let existing = state.activeToken, existing.photoID == photoID, state.phase.isInFlight {
            return existing
        }
        gateTask?.cancel()
        let token = state.begin(for: photoID)
        let delayDuration = gateDelay
        let sleeper = sleep
        gateTask = Task { @MainActor [weak self] in
            do {
                try await sleeper(delayDuration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.state.revealAfterGate(for: token)
            if self.state.activeToken == token {
                self.gateTask = nil
            }
        }
        return token
    }

    /// Resolves a completed full-res upgrade; transitions `.gating` or `.decodingPreview` to `.idle`.
    public func complete(token: RawProgressiveDecodeToken) {
        guard state.complete(for: token) else { return }
        gateTask?.cancel()
        gateTask = nil
    }

    /// Marks the active decode failed, stopping any spinner immediately and entering `.previewOnly`.
    public func fail(token: RawProgressiveDecodeToken) {
        guard state.fail(for: token) else { return }
        gateTask?.cancel()
        gateTask = nil
    }

    /// Clears a superseded or pipeline-cancelled attempt without triggering `.previewOnly`.
    public func cancel(token: RawProgressiveDecodeToken) {
        guard state.cancel(for: token) else { return }
        gateTask?.cancel()
        gateTask = nil
    }

    /// Clears any active tracking for `photoID` when full resolution arrives out-of-band.
    public func completeIfTracking(photoID: PhotoIdentity) {
        guard let token = state.activeToken, token.photoID == photoID else { return }
        complete(token: token)
    }

    /// Forces `.previewOnly` (for example on drive disconnection or zooming into a failed RAW).
    public func enterPreviewOnly() {
        gateTask?.cancel()
        gateTask = nil
        state.enterPreviewOnly()
    }

    /// Immediately stops the gate timer and resets to `.idle` (on photo change, Fit zoom, or exit).
    public func reset() {
        gateTask?.cancel()
        gateTask = nil
        state.reset()
    }
}
