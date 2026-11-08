import Foundation

public enum AccessPhase: String, Codable, Sendable {
    case bookmarkCreate, bookmarkResolve, startAccess, read, write, cleanup, resource, watch,
        storage
}

public enum AccessFailure: String, Codable, Sendable {
    case permission, missingLocation, disconnected, readOnly, full, unknown

    public var proposedCopyRow: String {
        switch self {
        case .permission: "Lost folder permission"
        case .missingLocation: "Remembered location unavailable"
        case .disconnected: "External drive disconnected during use"
        case .readOnly: "Read-only location or storage that does not permit writes"
        case .full: "Insufficient space"
        case .unknown: "Single-photo write failure (only for an actual mark write)"
        }
    }
}

/// Preserve the chain, rather than flattening every write failure into permission loss.
public struct AccessError: Codable, Sendable, Equatable {
    public var domain: String
    public var code: Int
    public var message: String
    public var underlying: [AccessError]

    public init(_ error: NSError, depth: Int = 0) {
        domain = error.domain
        code = error.code
        message = error.localizedDescription
        var children: [NSError] = []
        if let child = error.userInfo[NSUnderlyingErrorKey] as? NSError { children.append(child) }
        if let multiple = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            children.append(contentsOf: multiple)
        }
        underlying = depth < 8 ? children.map { AccessError($0, depth: depth + 1) } : []
    }

    public var summary: String {
        (["\(domain)/\(code): \(message)"] + underlying.map { "underlying: \($0.summary)" })
            .joined(separator: "; ")
    }

    /// Missing paths become a disconnect only with prior success on known external media.
    /// EACCES/EPERM do not prove revocation; EROFS alone establishes read-only storage.
    public func classify(knownExternal: Bool = false, previouslyReachable: Bool = false)
        -> AccessFailure
    {
        let chain = [self] + flattenedChildren
        if chain.contains(where: { $0.matches(posix: 28, cocoa: 640) }) { return .full }
        if chain.contains(where: { $0.matches(posix: 30, cocoa: 642) }) { return .readOnly }
        if chain.contains(where: {
            $0.matches(posix: 13, cocoa: 257) || $0.matches(posix: 1, cocoa: 513)
        }) {
            return .permission
        }
        if chain.contains(where: {
            ($0.domain == NSPOSIXErrorDomain && [2, 6, 19].contains($0.code))
                || ($0.domain == NSCocoaErrorDomain && [4, 260].contains($0.code))
        }) {
            return knownExternal && previouslyReachable ? .disconnected : .missingLocation
        }
        return .unknown
    }

    private var flattenedChildren: [AccessError] {
        underlying.flatMap { [$0] + $0.flattenedChildren }
    }

    private func matches(posix: Int, cocoa: Int) -> Bool {
        (domain == NSPOSIXErrorDomain && code == posix)
            || (domain == NSCocoaErrorDomain && code == cocoa)
    }
}

public struct AccessEvent: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var phase: AccessPhase
    public var detail: String
    public var error: AccessError?

    public init(_ phase: AccessPhase, _ detail: String, error: Error? = nil) {
        self.phase = phase
        self.detail = detail
        self.error = error.map { AccessError($0 as NSError) }
    }

    public var summary: String {
        "\(date.ISO8601Format()) [\(phase.rawValue)] \(detail)"
            + (error.map { " | \($0.summary)" } ?? "")
    }
}

public enum AccessMedia: String, Codable, Sendable, CaseIterable {
    case local, sdCard, externalSSD, filesProvider, unknown

    public var isExternal: Bool { self == .sdCard || self == .externalSSD }
}

public struct AccessRecent: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var bookmark: Data
    public var pathSummary: String
    public var volumeName: String?
    public var volumeUUID: String?
    public var media: AccessMedia
    /// S1 does not scan photos. Unknown counts must not look like an empty folder.
    public var photoCount: Int?
    public var lastOpened: Date

    public init(
        id: UUID = UUID(), bookmark: Data, pathSummary: String, volumeName: String? = nil,
        volumeUUID: String? = nil, media: AccessMedia = .unknown, photoCount: Int? = nil,
        lastOpened: Date = Date()
    ) {
        self.id = id
        self.bookmark = bookmark
        self.pathSummary = pathSummary
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.media = media
        self.photoCount = photoCount
        self.lastOpened = lastOpened
    }
}

public struct AccessRecents: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var records: [AccessRecent]

    public init(records: [AccessRecent] = []) { self.records = records }

    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard result.schemaVersion == 1 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return result
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

public enum AccessBookmark {
    /// iOS carries the picker's scope in the bookmark; .withSecurityScope is macOS-only.
    /// Default data retains more relocation information than .minimalBookmark.
    public static func encode(_ url: URL, minimal: Bool = false) throws -> Data {
        try url.bookmarkData(
            options: minimal ? [.minimalBookmark] : [], includingResourceValuesForKeys: nil,
            relativeTo: nil)
    }

    public static func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    /// Called while access to the resolved URL is held. Preserve identity and refresh metadata.
    public static func refreshed(_ record: AccessRecent, at url: URL) throws -> AccessRecent {
        var copy = record
        copy.bookmark = try encode(url)
        copy.pathSummary = url.path
        copy.lastOpened = Date()
        let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey])
        copy.volumeName = values?.volumeName
        copy.volumeUUID = values?.volumeUUIDString
        return copy
    }
}
