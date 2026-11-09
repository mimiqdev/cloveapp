import Foundation

/// A refused operation on a folder session (G1 folder access).
public enum FolderSessionError: Error, Hashable, Sendable {
    /// The session already ended, so its scope no longer covers new work.
    case ended
}

/// Holds one folder's security scope and the work that relies on it.
///
/// G1 folder access keeps the scope until the session ends. Opening returns this value, the
/// session carries the C1 `FolderSession` and the validated root for C2, and ending waits for
/// admitted work to drain before the scope is released. Start and stop stay balanced on every
/// path: a failed open stops what it started, and a cancelled operation still drains.
public actor FolderAccessSession {
    /// The C1 folder session used by photo identities and Clove-stored marks (G1 decision 5).
    public nonisolated let folder: FolderSession
    /// The validated folder root for scanning; never a display hint (PRD P0-01; C2).
    public nonisolated let rootURL: URL
    /// The Recent that owns this session (PRD P0-02).
    public nonisolated let recentID: UUID
    /// How this open established identity; `.weak` is accepted provisionally until #29.
    /// A pick is verified when the folder supplied both keys, and weak when it did not.
    public nonisolated let identityCheck: FolderIdentityCheck

    private let scope: any FolderAccessScope
    private var scopeIsHeld: Bool
    private var admittedWork = 0
    private var ended = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    /// Takes ownership of a scope that the caller already acquired for `rootURL`.
    ///
    /// The caller passes `scopeIsHeld` from the start result, so a failed start is never stopped.
    init(
        folder: FolderSession,
        rootURL: URL,
        recentID: UUID,
        identityCheck: FolderIdentityCheck,
        scope: any FolderAccessScope,
        scopeIsHeld: Bool
    ) {
        self.folder = folder
        self.rootURL = rootURL
        self.recentID = recentID
        self.identityCheck = identityCheck
        self.scope = scope
        self.scopeIsHeld = scopeIsHeld
    }

    /// Whether the session has ended; admitted work is refused after that.
    public var isEnded: Bool { ended }

    /// Runs work under the session's scope and keeps ending from releasing it early.
    ///
    /// The operation is admitted before it starts and released when it returns or throws, including
    /// cancellation, so `end` can wait for a stable count. Calling this after `end` throws
    /// `FolderSessionError.ended` instead of running unscoped work.
    public func withAdmittedWork<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        guard !ended else { throw FolderSessionError.ended }
        admittedWork += 1
        do {
            let value = try await work()
            finishAdmittedWork()
            return value
        } catch {
            finishAdmittedWork()
            throw error
        }
    }

    /// Ends the session: waits for admitted work, then releases the scope exactly once.
    ///
    /// Callers must not call this from inside admitted work, which would wait for itself.
    public func end() async {
        guard !ended else { return }
        ended = true
        if admittedWork > 0 {
            await withCheckedContinuation { continuation in drainWaiters.append(continuation) }
        }
        releaseScope()
    }

    private func finishAdmittedWork() {
        admittedWork -= 1
        guard admittedWork == 0 else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func releaseScope() {
        guard scopeIsHeld else { return }
        scope.stopAccessing(rootURL)
        scopeIsHeld = false
    }

    deinit {
        // A dropped session must not leak its grant; deinit cannot wait for work, which is why
        // callers end sessions explicitly.
        if scopeIsHeld { scope.stopAccessing(rootURL) }
    }
}
