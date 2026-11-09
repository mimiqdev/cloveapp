import Foundation
import Synchronization

import CloveCore

/// A calendar clock the tests move by hand, so last-opened times are exact.
final class TestClock: Sendable {
    private let state = Mutex(Date(timeIntervalSinceReferenceDate: 1_000_000))

    var now: Date {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    func advance(_ seconds: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// Counts start and stop calls so a test can prove the scope stayed balanced.
final class ScopeRecorder: FolderAccessScope, Sendable {
    struct State {
        var startCount = 0
        var stopCount = 0
        var startedURLs: [URL] = []
        var stoppedURLs: [URL] = []
    }

    private let grantsAccess: Bool
    private let state = Mutex(State())

    init(grantsAccess: Bool = true) {
        self.grantsAccess = grantsAccess
    }

    var startCount: Int { state.withLock { $0.startCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var startedURLs: [URL] { state.withLock { $0.startedURLs } }
    var stoppedURLs: [URL] { state.withLock { $0.stoppedURLs } }

    func startAccessing(_ url: URL) -> Bool {
        state.withLock {
            $0.startCount += 1
            $0.startedURLs.append(url)
        }
        return grantsAccess
    }

    func stopAccessing(_ url: URL) {
        state.withLock {
            $0.stopCount += 1
            $0.stoppedURLs.append(url)
        }
    }
}

/// A location reader that can fail its validating read with a chosen provider error.
struct FailingReadLocationReader: FolderLocationReading {
    let domain: String
    let code: Int

    func facts(for url: URL) -> FolderLocationFacts {
        FileSystemLocationReader().facts(for: url)
    }

    func listContents(of url: URL) throws -> [URL] {
        throw NSError(
            domain: domain, code: code,
            userInfo: [NSLocalizedDescriptionKey: "The provider refused the read."])
    }
}

/// Waits for `condition` or a timeout, for events that hop between tasks.
func waitUntil(
    timeout: Duration = .seconds(3), _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline { return }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Waits for an asynchronous condition or a timeout.
func waitForCondition(
    timeout: Duration = .seconds(3), _ condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        if ContinuousClock.now >= deadline { return }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// An async gate: admitted work waits here until the test lets it continue.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int { waiters.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
