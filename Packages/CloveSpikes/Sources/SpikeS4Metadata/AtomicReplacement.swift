import Darwin
import Foundation

/// Sibling temporary candidate, then one POSIX rename. The original path is
/// replaced only after the writer finishes; every failure cleans up its candidate.
/// This establishes local atomic replacement, not power-loss durability or Files-provider semantics.
enum AtomicReplacement {
    static func write(to url: URL, candidate: (URL) throws -> Void) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            ".s4-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try candidate(temporary)
        guard rename(temporary.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
