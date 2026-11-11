import Foundation
import LabSupport

/// One photo the swipe simulation walks: the RAW and the preview the reader sees.
public struct RAWDisplaySwipePhoto: Sendable, Hashable {
    public var raw: URL
    /// Embedded preview source: the photo's camera HEIF when present, else the RAW.
    public var preview: URL

    public init(raw: URL, preview: URL) {
        self.raw = raw
        self.preview = preview
    }
}

/// What the swipe simulation walks and which background render it starts.
public struct RAWDisplaySwipePlan: Sendable {
    public var photos: [RAWDisplaySwipePhoto]
    /// The fastest screen-size RAW variant measured earlier in the run.
    public var screenVariant: RAWDisplayVariant
    public var dwellMilliseconds: [Int]
    /// Embedded preview request size, the same order of magnitude as I2's placeholder.
    public var previewPixels: Int

    public init(
        photos: [RAWDisplaySwipePhoto], screenVariant: RAWDisplayVariant,
        dwellMilliseconds: [Int], previewPixels: Int = 2_000
    ) {
        self.photos = photos
        self.screenVariant = screenVariant
        self.dwellMilliseconds = dwellMilliseconds
        self.previewPixels = previewPixels
    }
}

/// Completion of one background render, recorded where the render finishes so the
/// walk can tell "finished while the reader stayed" from "still running".
private final class SwipeRenderCompletion: @unchecked Sendable {
    struct Finished {
        var at: ContinuousClock.Instant
        var timing: DisplayRenderTiming?
        var error: String?
    }

    private let lock = NSLock()
    private var finished: Finished?

    var value: Finished? { lock.withLock { finished } }

    func finish(_ finished: Finished?) {
        lock.withLock { self.finished = finished }
    }
}

/// Tracks the walks' renders so cancellation can stop the whole queue, including
/// renders created after the cancel arrived.
private final class SwipeRenderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var renders: [SwipeRender] = []
    private var stopped = false

    var isStopped: Bool { lock.withLock { stopped } }

    func add(_ render: SwipeRender) {
        let cancelNow = lock.withLock { () -> Bool in
            renders.append(render)
            return stopped
        }
        if cancelNow { render.task.cancel() }
    }

    var last: SwipeRender? { lock.withLock { renders.last } }

    func stop() {
        let all = lock.withLock { () -> [SwipeRender] in
            stopped = true
            return renders
        }
        for render in all { render.task.cancel() }
    }
}

/// One background render in the swipe simulation. Renders are chained so a single
/// decoder is busy at a time: a render that is still running when the reader leaves
/// keeps running, and the next photo's render waits behind it. The synchronous
/// decoder cannot be interrupted, but a queued render that is cancelled before it
/// starts does no decode at all.
private final class SwipeRender: @unchecked Sendable {
    let index: Int
    /// When the reader landed on this photo, before its preview request.
    let arrival: ContinuousClock.Instant
    /// When this render was requested, before any wait for the previous render.
    let renderRequested: ContinuousClock.Instant
    let task: Task<Void, Never>
    private let completion = SwipeRenderCompletion()

    init(
        index: Int, arrival: ContinuousClock.Instant, renderRequested: ContinuousClock.Instant,
        after previous: SwipeRender?, registry: SwipeRenderRegistry,
        render: @escaping @Sendable () throws -> DisplayRenderTiming
    ) {
        self.index = index
        self.arrival = arrival
        self.renderRequested = renderRequested
        let completion = self.completion
        task = Task {
            if let previous { await previous.task.value }
            guard !Task.isCancelled, !registry.isStopped else { return }
            do {
                let timing = try render()
                // A render that returned no pixels is a failure, not a ready image.
                completion.finish(.init(at: .now, timing: timing, error: timing.error))
            } catch {
                completion.finish(.init(at: .now, timing: nil, error: String(describing: error)))
            }
        }
    }

    var finished: SwipeRenderCompletion.Finished? { completion.value }
}

/// Walks photos the way the detail reader does. The dwell is the time spent on the
/// photo: arrive, request the preview, start the screen-size render right away, wait
/// out the dwell, then leave. A render is ready when it finished before leaving;
/// otherwise it keeps running and counts as wasted, and the next photo's preview is
/// the contended case.
public enum RAWDisplaySwipes {
    /// Runs one walk per dwell and reports preview latency, arrival-to-ready time and
    /// how many renders finished inside their dwell. Every started render is
    /// classified exactly once as ready, failed or wasted.
    public static func run(
        plan: RAWDisplaySwipePlan, measuring: any RAWDisplayMeasuring,
        step: (String) async -> Void = { _ in }
    ) async throws -> [LabMeasurement] {
        let photos = plan.photos
        var measurements: [LabMeasurement] = []
        for dwell in plan.dwellMilliseconds {
            try Task.checkCancellation()
            let registry = SwipeRenderRegistry()
            var started = 0
            var ready = 0
            var wasted = 0
            var failed = 0
            do {
                try await withTaskCancellationHandler {
                    for (index, photo) in photos.enumerated() {
                        try Task.checkCancellation()
                        await step("Swipe \(dwell) ms: photo \(index + 1)/\(photos.count)")
                        let arrival = ContinuousClock.now
                        // The dwell is the whole time on the photo, so the deadline is
                        // fixed at arrival and the preview does not extend it.
                        let leaving = arrival + .milliseconds(dwell)
                        let previous = registry.last
                        let renderRunning = previous.map { $0.finished == nil } ?? false
                        let orientation = displaySourceOrientation(url: photo.raw)
                        let previewStart = ContinuousClock.now
                        var preview = try measuring.embeddedPreview(
                            url: photo.preview, maxPixel: plan.previewPixels)
                        let firstAttemptMS = preview.milliseconds
                        var previewSource = "camera-preview"
                        // The same fallback the detail pipeline needs: a camera HEIF with
                        // no usable embedded preview falls back to the RAW's own preview.
                        if preview.error != nil, photo.preview != photo.raw {
                            preview = try measuring.embeddedPreview(
                                url: photo.raw, maxPixel: plan.previewPixels)
                            previewSource = "raw-fallback"
                        }
                        // Total wall time: a failed first attempt still cost time.
                        measurements.append(
                            LabMeasurement(
                                name: "swipe-preview",
                                value: displayMilliseconds(since: previewStart), unit: "ms",
                                tags: [
                                    "dwellMs": String(dwell), "index": String(index),
                                    "orientation": String(orientation),
                                    "renderRunning": String(renderRunning),
                                    "previewSource": previewSource,
                                    "previewAttempt": String(format: "%.3f", firstAttemptMS),
                                    "previewError": preview.error ?? "none",
                                    "previewLongEdge": String(max(preview.width, preview.height)),
                                ]))
                        // The render starts right away and runs while the reader stays.
                        let variant = plan.screenVariant
                        let raw = photo.raw
                        let renderRequested = ContinuousClock.now
                        let current = SwipeRender(
                            index: index, arrival: arrival, renderRequested: renderRequested,
                            after: previous, registry: registry
                        ) {
                            try measuring.renderRAW(url: raw, variant: variant)
                        }
                        registry.add(current)
                        started += 1
                        if ContinuousClock.now < leaving {
                            try await Task.sleep(for: ContinuousClock.now.duration(to: leaving))
                        }
                        if let finished = current.finished, finished.at <= leaving {
                            if finished.error == nil {
                                ready += 1
                                measurements.append(
                                    LabMeasurement(
                                        name: "swipe-render-ready",
                                        value: milliseconds(
                                            finished.at, since: renderRequested),
                                        unit: "ms",
                                        tags: [
                                            "dwellMs": String(dwell), "index": String(index),
                                            "orientation": String(orientation),
                                            "status": "ok",
                                        ]))
                                measurements.append(
                                    LabMeasurement(
                                        name: "swipe-arrival-to-ready",
                                        value: milliseconds(finished.at, since: arrival),
                                        unit: "ms",
                                        tags: [
                                            "dwellMs": String(dwell), "index": String(index),
                                            "orientation": String(orientation),
                                            "status": "ok",
                                        ]))
                            } else {
                                failed += 1
                                measurements.append(
                                    LabMeasurement(
                                        name: "swipe-render-failed",
                                        value: milliseconds(
                                            finished.at, since: renderRequested),
                                        unit: "ms",
                                        tags: [
                                            "dwellMs": String(dwell), "index": String(index),
                                            "orientation": String(orientation),
                                            "status": finished.error ?? "noPixels",
                                        ]))
                            }
                        } else {
                            wasted += 1
                            measurements.append(
                                LabMeasurement(
                                    name: "swipe-render-wasted",
                                    value: displayMilliseconds(since: renderRequested),
                                    unit: "ms",
                                    tags: [
                                        "dwellMs": String(dwell), "index": String(index),
                                        "orientation": String(orientation),
                                        "status": "still-running-at-dwell-end",
                                    ]))
                        }
                    }
                    // One render at a time: let the chained decodes drain so nothing leaks.
                    if let last = registry.last {
                        await last.task.value
                    }
                } onCancel: {
                    registry.stop()
                }
            } catch {
                registry.stop()
                if let last = registry.last {
                    await last.task.value
                }
                throw error
            }
            // A cancel that arrived while the last render was draining still has to
            // stop the walk rather than return a completed report.
            try Task.checkCancellation()
            let counts = ["dwellMs": String(dwell), "photos": String(photos.count)]
            measurements += [
                LabMeasurement(
                    name: "swipe-renders-started", value: Double(started), unit: "count",
                    tags: counts),
                LabMeasurement(
                    name: "swipe-renders-ready", value: Double(ready), unit: "count", tags: counts),
                LabMeasurement(
                    name: "swipe-renders-wasted", value: Double(wasted), unit: "count",
                    tags: counts),
                LabMeasurement(
                    name: "swipe-renders-failed", value: Double(failed), unit: "count",
                    tags: counts),
            ]
        }
        return measurements
    }

    private static func milliseconds(
        _ end: ContinuousClock.Instant, since start: ContinuousClock.Instant
    ) -> Double {
        let duration = start.duration(to: end).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }
}
