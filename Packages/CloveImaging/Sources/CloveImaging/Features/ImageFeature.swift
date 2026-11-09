import Foundation

/// The two kinds of visual feature a photo contributes to similar groups (PRD P0-11).
///
/// G1 "Grouping (C9/I3)" keeps them apart on purpose: a boundary is compared with Vision
/// prints when both sides have one, with difference hashes only when Vision could not run, and
/// never with one of each.
public enum ImageFeatureKind: String, Codable, Sendable, CaseIterable {
    /// A Vision image feature print from the orientation-applied preview (G1 "Vision feature
    /// per photo": `VNGenerateImageFeaturePrintRequest` revision 2, `scaleFit`).
    case visionPrint
    /// A 64-bit horizontal difference hash, the degraded fallback (G1 "Grouping (C9/I3)").
    case differenceHash
}

/// A Vision image feature print as plain scalars, so it can be cached and sent between tasks.
///
/// G1 "Grouping (C9/I3)" compares photos with a Vision distance computed from 400 px previews.
/// `VNFeaturePrintObservation` is a mutable, non-`Sendable` framework object, so the reader
/// copies its elements out once and this type answers the distance itself. For revision 2 the
/// distance Vision reports is the Euclidean distance between the elements; the feature tests
/// check that against `VNFeaturePrintObservation.computeDistance` on real fixtures, so a cached
/// print answers the same number a live observation would.
public struct VisionFeaturePrint: Sendable, Codable, Hashable {
    /// The `VNGenerateImageFeaturePrintRequest` revision that produced these elements. Part of
    /// G1's cache identity, so a new revision never reuses an older print.
    public let revision: Int
    /// The elements in Vision's own order; never exposed, so a distance cannot be edited.
    private let elements: [Float]

    /// Builds a print from elements a reader produced, including a test's injected reader.
    public init(revision: Int, elements: [Float]) {
        self.revision = revision
        self.elements = elements
    }

    /// The number of elements, used to reject prints that cannot be compared.
    public var elementCount: Int { elements.count }

    /// Bytes the elements occupy, which G1 asks the feature timing to report next to S5's
    /// numbers.
    public var byteCount: Int { elements.count * MemoryLayout<Float>.size }

    /// The Vision distance between two prints, or nil when they are not comparable.
    ///
    /// The caller never sees a threshold: G1 keeps the split value (0.5) in C9, so this answers
    /// only the raw distance. Prints from different request revisions are not comparable, and
    /// an absent answer makes the caller fall through to the hash instead.
    public func distance(to other: VisionFeaturePrint) -> Double? {
        guard revision == other.revision, elements.count == other.elements.count,
            !elements.isEmpty
        else { return nil }
        var sum = 0.0
        for index in elements.indices {
            let difference = Double(elements[index]) - Double(other.elements[index])
            sum += difference * difference
        }
        let value = sum.squareRoot()
        return value.isFinite ? value : nil
    }

    private enum CodingKeys: String, CodingKey {
        case revision, elements
    }

    /// Elements are written as raw four-byte values, not as property-list reals, so a print
    /// occupies its ``byteCount`` on disk and the cache budget holds thousands of photos.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        var data = Data(capacity: byteCount)
        for element in elements {
            withUnsafeBytes(of: element.bitPattern.bigEndian) { data.append(contentsOf: $0) }
        }
        try container.encode(data, forKey: .elements)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int.self, forKey: .revision)
        let data = try container.decode(Data.self, forKey: .elements)
        guard data.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
            throw DecodingError.dataCorruptedError(
                forKey: .elements, in: container,
                debugDescription: "A feature print holds four-byte elements.")
        }
        var bits = [UInt32](repeating: 0, count: data.count / MemoryLayout<UInt32>.size)
        _ = bits.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        elements = bits.map { Float(bitPattern: UInt32(bigEndian: $0)) }
    }
}

/// A 64-bit horizontal difference hash of an orientation-applied preview.
///
/// G1 "Grouping (C9/I3)" uses it only when Vision cannot run, with a starting cut-off of 12
/// differing bits that belongs to C9, not to this type.
public struct DifferenceHash: Sendable, Codable, Hashable {
    /// The 64 compared bits, row by row.
    public let bits: UInt64

    /// Wraps bits a reader or a test produced.
    public init(bits: UInt64) {
        self.bits = bits
    }

    /// The differing-bit count: lower means more similar (S5's fallback trials).
    public func distance(to other: DifferenceHash) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }
}

/// Why a Vision print could not be produced for one photo.
///
/// PRD P0-11 needs grouping to keep working when Vision is unavailable, and G1 "Grouping
/// (C9/I3)" asks the fallback to stay identifiable, so the reason is kept with the photo's
/// features instead of being thrown away or retried.
public struct FeatureFailure: Error, Sendable, Equatable, CustomStringConvertible {
    /// The error domain, for example `NSOSStatusErrorDomain` from the simulator's espresso
    /// failure.
    public let domain: String
    /// The domain-specific code, for example `-1`.
    public let code: Int
    /// The localized description, kept for logs and device checks.
    public let message: String

    /// Builds a failure from parts, as a reader or a test reports it.
    public init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }

    /// Records an error exactly as the framework reported it.
    public init(_ error: any Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code, message: error.localizedDescription)
    }

    /// `domain code: message`, as a log line or a device check reads it.
    public var description: String { "\(domain) \(code): \(message)" }
}

/// One photo's features: which kinds succeeded, and why Vision did not when it could not.
///
/// PRD P0-11 shows groups by time first and refines them with visual similarity, so a photo may
/// legitimately have only a hash. ``visionFailure`` is the record G1 "Grouping (C9/I3)" asks for
/// so a degraded run stays identifiable.
public struct ImageFeatures: Sendable, Equatable {
    /// The Vision print, when Vision ran for this photo.
    public let print: VisionFeaturePrint?
    /// The difference hash. Every photo computes one, because it is cheap and the fallback
    /// must not need a second preview read (G1 "Grouping (C9/I3)").
    public let differenceHash: DifferenceHash?
    /// Why Vision produced no print, when it was attempted and failed.
    public let visionFailure: FeatureFailure?

    /// Builds a record from whichever kinds succeeded and why Vision did not.
    public init(
        print: VisionFeaturePrint? = nil, differenceHash: DifferenceHash? = nil,
        visionFailure: FeatureFailure? = nil
    ) {
        self.print = print
        self.differenceHash = differenceHash
        self.visionFailure = visionFailure
    }

    /// The kinds that succeeded for this photo.
    public var kinds: Set<ImageFeatureKind> {
        var result: Set<ImageFeatureKind> = []
        if print != nil { result.insert(.visionPrint) }
        if differenceHash != nil { result.insert(.differenceHash) }
        return result
    }

    /// Approximate bytes this record occupies in memory or on disk, used for cache budgets.
    var approximateBytes: Int {
        (print?.byteCount ?? 0) + (differenceHash == nil ? 0 : 8)
            + (visionFailure.map { $0.description.utf8.count } ?? 0)
    }

    /// One boundary's distance, or nil when neither kind is usable (PRD P0-11 wants a split).
    ///
    /// G1 "Grouping (C9/I3)" decides the order and never mixes kinds: Vision prints when both
    /// photos have a comparable one, the hash when Vision is missing on either side, and no
    /// answer at all when neither kind is usable. Thresholds stay in C9.
    public func distance(to other: ImageFeatures) -> ImageFeatureDistance? {
        if let left = print, let right = other.print, let value = left.distance(to: right) {
            return .visionPrint(value)
        }
        if let left = differenceHash, let right = other.differenceHash {
            return .differenceHash(bits: left.distance(to: right))
        }
        return nil
    }
}

/// The raw distance between two photos' features, tagged with the kind that answered.
///
/// G1 "Grouping (C9/I3)" keeps the starting thresholds (Vision 0.5, dHash 12 bits) and the
/// split/join decision in C9, so this type reports only the number and its kind.
public enum ImageFeatureDistance: Sendable, Equatable {
    /// Vision's own distance between two prints.
    case visionPrint(Double)
    /// Differing bits between two difference hashes, the fallback (G1, degraded mode).
    case differenceHash(bits: Int)

    /// Which kind answered, so a caller can keep fallback results identifiable.
    public var kind: ImageFeatureKind {
        switch self {
        case .visionPrint: .visionPrint
        case .differenceHash: .differenceHash
        }
    }

    /// The scalar distance, so a caller can compare it with one threshold per ``kind``.
    public var value: Double {
        switch self {
        case .visionPrint(let value): value
        case .differenceHash(let bits): Double(bits)
        }
    }
}
