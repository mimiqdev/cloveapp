import Foundation
import Synchronization

/// Whether Vision can run in this session, as PRD P0-11 and G1 "Grouping (C9/I3)" report it.
///
/// A host that cannot run Vision fails the same way for every photo (S5 recorded
/// `NSOSStatusErrorDomain -1` on the iOS Simulator), so the app needs one answer for the whole
/// session and not one error per photo.
public enum FeaturePrintStatus: Sendable, Equatable {
    /// Vision has not failed yet in this session.
    case available
    /// Vision failed for the last photo, and the next photo still asks.
    case failing(FeatureFailure)
    /// Vision failed repeatedly; the session stopped asking, so remaining photos get the hash
    /// alone (the degraded mode G1 "Grouping (C9/I3)" describes).
    case givenUp(FeatureFailure, consecutiveFailures: Int)
}

/// Bounds how often one session asks Vision, so an unavailable framework costs a few attempts
/// and not one per photo.
///
/// G1 "Grouping (C9/I3)" falls back to the hash when Vision is unavailable; P0-11 needs that
/// fallback to stay responsive. The rule is consecutive failures: three in a row stop the
/// attempts for the rest of the session, and any success resets the count so a transient failure
/// does not degrade a whole folder. Attempts are counted, not retried, so no photo is ever asked
/// twice.
final class FeaturePrintSession: Sendable {
    /// Consecutive failures that stop Vision attempts for this session.
    static let defaultFailureLimit = 3

    private struct State {
        var consecutiveFailures = 0
        var lastFailure: FeatureFailure?
    }

    private let state = Mutex(State())
    let failureLimit: Int

    init(failureLimit: Int = FeaturePrintSession.defaultFailureLimit) {
        precondition(failureLimit > 0)
        self.failureLimit = failureLimit
    }

    /// Whether the next photo should ask Vision at all. False once the session gave up.
    var permitsAttempt: Bool {
        state.withLock { $0.consecutiveFailures < failureLimit }
    }

    /// The most recent Vision failure, kept so a skipped photo can still say why it fell back.
    var lastFailure: FeatureFailure? {
        state.withLock { $0.lastFailure }
    }

    var status: FeaturePrintStatus {
        state.withLock { state in
            guard let lastFailure = state.lastFailure else { return .available }
            if state.consecutiveFailures >= failureLimit {
                return .givenUp(lastFailure, consecutiveFailures: state.consecutiveFailures)
            }
            return .failing(lastFailure)
        }
    }

    func recordSuccess() {
        state.withLock { $0 = State() }
    }

    func recordFailure(_ failure: FeatureFailure) {
        state.withLock { state in
            state.consecutiveFailures += 1
            state.lastFailure = failure
        }
    }
}
