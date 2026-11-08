import Foundation

/// Convenience for reading a folder handed over by the document picker, which
/// grants access only inside a security-scoped session.
enum SecurityScopedAccess {
    /// Runs `body` with access to `url` started, and stops it again on every
    /// exit path.
    ///
    /// URLs that are not security scoped, such as the app's own Documents
    /// folder, are passed through unchanged.
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body(url)
    }
}
