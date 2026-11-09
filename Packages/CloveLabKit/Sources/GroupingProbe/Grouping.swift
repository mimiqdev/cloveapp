import Foundation

public struct GroupingPhoto: Sendable, Equatable {
    public var id: String
    public var model: String?
    public var serial: String?
    public var captureTime: Date?

    public init(id: String, model: String?, serial: String?, captureTime: Date?) {
        self.id = id
        self.model = model
        self.serial = serial
        self.captureTime = captureTime
    }

    /// Unknown identity is isolated per folder. Model-only is a documented,
    /// lossy fallback: two unidentified bodies of the same model can mix.
    public var body: String { "\(model ?? "unknown-model")|\(serial ?? "unknown-serial")" }
}

public struct GroupingParameters: Sendable {
    public var timeGap: Double
    public var distance: Double
    public init(timeGap: Double = 2, distance: Double = 0.5) {
        self.timeGap = timeGap
        self.distance = distance
    }
}

public struct GroupingBoundary: Sendable, Identifiable {
    public var left: String
    public var right: String
    public var gap: Double
    public var distance: Double?
    public var proposedSplit: Bool
    /// nil means unreviewed; never treat an untouched proposal as ground truth.
    public var expectedSplit: Bool?
    public var id: String { "\(left)\u{0}\(right)" }
}

public enum Grouping {
    /// Steps 1–3 of the PRD. The caller injects feature distance, so this is
    /// independent of Vision. Missing features conservatively split a run.
    /// Missing times are excluded, never synthesized from file timestamps.
    public static func groups(
        _ photos: [GroupingPhoto], parameters: GroupingParameters = .init(),
        distance: (String, String) -> Double?
    ) -> [[String]] {
        var result: [[String]] = []
        for body in orderedBodies(photos) {
            var run: [String] = []
            var prior: GroupingPhoto?
            for photo in body {
                if let prior,
                    let time = photo.captureTime, let priorTime = prior.captureTime,
                    shouldSplit(
                        gap: time.timeIntervalSince(priorTime),
                        distance: distance(prior.id, photo.id), parameters: parameters)
                {
                    if run.count >= 2 { result.append(run) }
                    run = []
                }
                run.append(photo.id)
                prior = photo
            }
            if run.count >= 2 { result.append(run) }
        }
        return result
    }

    public static func orderedBodies(_ photos: [GroupingPhoto]) -> [[GroupingPhoto]] {
        let bodies = Dictionary(grouping: photos.filter { $0.captureTime != nil }, by: \.body)
        return bodies.keys.sorted().map { key in
            bodies[key, default: []].sorted {
                if let left = $0.captureTime, let right = $1.captureTime, left != right {
                    return left < right
                }
                // Numeric filename order provides a deterministic tie break when
                // subseconds are missing; it does not invent capture precision.
                return $0.id.compare($1.id, options: [.numeric, .literal]) == .orderedAscending
            }
        }
    }

    public static func shouldSplit(
        gap: Double, distance: Double?, parameters: GroupingParameters
    ) -> Bool {
        guard gap.isFinite, gap >= 0, gap < parameters.timeGap,
            let distance, distance.isFinite, distance >= 0
        else { return true }
        return distance > parameters.distance
    }

    /// Boundary classification counts, not an accuracy promise or a test of
    /// group identity stability. Only explicitly reviewed labels participate.
    public static func sweep(_ boundaries: [GroupingBoundary]) -> [SweepResult] {
        [0.5, 1, 2, 3, 5].flatMap { gap in
            [0.1, 0.25, 0.5, 0.75, 1, 1.5].map { threshold in
                var result = SweepResult(timeGap: gap, distance: threshold)
                for boundary in boundaries {
                    guard let expected = boundary.expectedSplit else { continue }
                    result.reviewed += 1
                    let split = shouldSplit(
                        gap: boundary.gap, distance: boundary.distance,
                        parameters: .init(timeGap: gap, distance: threshold))
                    if split && !expected { result.wrongSplits += 1 }
                    if !split && expected { result.wrongMerges += 1 }
                }
                return result
            }
        }
    }
}

public struct SweepResult: Sendable {
    public var timeGap: Double
    public var distance: Double
    public var reviewed = 0
    public var wrongSplits = 0
    public var wrongMerges = 0
}
