import Foundation

/// The system error chain behind a folder-access failure, kept for diagnosis.
///
/// The S1 failure table records that a single Cocoa code can wrap a different POSIX cause, or
/// none at all. Preserving the chain lets a reopen failure stay one of P0-02's explicit states
/// without discarding the system's exact error.
public struct FolderErrorChain: Hashable, Sendable {
    /// The error domain, such as `NSCocoaErrorDomain` or `NSPOSIXErrorDomain` (S1 failure table).
    public let domain: String
    /// The numeric code within that domain.
    public let code: Int
    /// The localized description at this level.
    public let message: String
    /// Underlying errors Foundation reports, outermost first, bounded to eight levels (S1).
    public let underlying: [FolderErrorChain]

    /// Captures an error and its underlying chain; underlying errors are never flattened away.
    public init(_ error: any Error, depth: Int = 0) {
        let systemError = error as NSError
        domain = systemError.domain
        code = systemError.code
        message = systemError.localizedDescription
        var children: [NSError] = []
        if let child = systemError.userInfo[NSUnderlyingErrorKey] as? NSError {
            children.append(child)
        }
        if let multiple = systemError.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            children.append(contentsOf: multiple)
        }
        underlying = depth < 8 ? children.map { FolderErrorChain($0, depth: depth + 1) } : []
    }

    /// Each error in the chain, outermost first, for callers that classify every level.
    public var errors: [FolderErrorChain] {
        [self] + underlying.flatMap(\.errors)
    }

    /// The chain as one line, for logs and reports (S1 failure table).
    public var summary: String {
        var parts = ["\(domain)/\(code): \(message)"]
        for error in underlying { parts.append("underlying: \(error.summary)") }
        return parts.joined(separator: "; ")
    }

    /// Whether this level of the chain is the given domain and code.
    public func matches(domain: String, code: Int) -> Bool {
        self.domain == domain && self.code == code
    }
}

extension FolderErrorChain {
    /// Access denial, wherever it appears in the chain (S1 failure table: EACCES/EPERM).
    /// A denial can have several causes, so this only selects the permission state.
    var isPermissionDenied: Bool {
        errors.contains {
            $0.matches(domain: NSPOSIXErrorDomain, code: 13)
                || $0.matches(domain: NSPOSIXErrorDomain, code: 1)
                || $0.matches(domain: NSCocoaErrorDomain, code: 257)
                || $0.matches(domain: NSCocoaErrorDomain, code: 513)
        }
    }

    /// A path or volume that is gone, wherever it appears in the chain (S1 failure table).
    var isLocationUnavailable: Bool {
        errors.contains {
            $0.matches(domain: NSPOSIXErrorDomain, code: 2)
                || $0.matches(domain: NSPOSIXErrorDomain, code: 6)
                || $0.matches(domain: NSPOSIXErrorDomain, code: 19)
                || $0.matches(domain: NSCocoaErrorDomain, code: 4)
                || $0.matches(domain: NSCocoaErrorDomain, code: 260)
        }
    }
}
