import Foundation

/// Starts and stops the folder's security scope around the work that uses it.
///
/// G1 folder access requires balanced start and stop on every path, including failed opens and
/// cancelled work. A failed start must never be stopped: the API reports `false` when it holds no
/// scope, and the system has no error to report for that case (S1 failure table).
public protocol FolderAccessScope: Sendable {
    /// Acquires scope for `url`; `false` means no scope is held and `stopAccessing` must not run.
    func startAccessing(_ url: URL) -> Bool
    /// Releases a scope that this start acquired.
    func stopAccessing(_ url: URL)
}

/// The system security-scoped access used in the app (G1 folder access).
public struct SecurityScopedFolderAccess: FolderAccessScope {
    /// Creates the system scope handler.
    public init() {}

    /// Starts the system scope; the picker's grant travels in the bookmark on iOS (S1).
    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    /// Stops only a scope that `startAccessing` acquired.
    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
