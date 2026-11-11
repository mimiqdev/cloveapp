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

/// One background render in the swipe simulation. The synchronous decoder cannot be
/// interrupted, so cancelling waits for it to drain before the next one can start.
private final class SwipeRender: @unchecked Sendable {
    let index: Int
    /// When the reader landed on this photo, before its preview request and dwell.
    let arrival: ContinuousClock.Instant
    /// When the background render was requested, after the dwell and any drain.
    let renderStarted: ContinuousClock.Instant
    let task: Task<Void, Never>
    private let completion = SwipeRenderCompletion()

    init(
        index: Int, arrival: ContinuousClock.Instant, renderStarted: ContinuousClock.Instant,
        render: @escaping @Sendable () throws -> DisplayRenderTiming
    ) {
        self.index = index
        self.arrival = arrival
        self.renderStarted = renderStarted
        let completion = self.completion
        task = Task {
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

/// Walks photos the way the detail reader does: arrive, request the preview, stay for
/// the dwell, then request the screen-size RAW render in the background and move on.
public enum RAWDisplaySwipes {
    /// Runs one walk per dwell. A render counts as ready only when it finished before
    /// the next arrival with pixels; one that was still running is superseded and
    /// drained; one that finished without pixels is failed.
    public static func run(
        plan: RAWDisplaySwipePlan, measuring: any RAWDisplayMeasuring,
        step: (String) async -> Void = { _ in }
    ) async throws -> [LabMeasurement] {
        let photos = plan.photos
        var measurements: [LabMeasurement] = []
        for dwell in plan.dwellMilliseconds {
            try Task.checkCancellation()
            await step("Swipe dwell \(dwell) ms")
            var current: SwipeRender?
            var started = 0
            var ready = 0
            var wasted = 0
            var failed = 0
            do {
                for (index, photo) in photos.enumerated() {
                    try Task.checkCancellation()
                    let arrival = ContinuousClock.now
                    // At arrival the previous photo's render may still be running;
                    // sampling that state here is what measures preview contention.
                    let previous = current
                    let renderRunning = previous.map { $0.finished == nil } ?? false
                    var preview = try measuring.embeddedPreview(
                        url: photo.preview, maxPixel: plan.previewPixels)
                    var previewSource = "camera-preview"
                    // The same fallback the detail pipeline needs: a camera HEIF with no
                    // usable embedded preview falls back to the RAW's own preview.
                    if preview.error != nil, photo.preview != photo.raw {
                        preview = try measuring.embeddedPreview(
                            url: photo.raw, maxPixel: plan.previewPixels)
                        previewSource = "raw-fallback"
                    }
                    measurements.append(
                        LabMeasurement(
                            name: "swipe-preview", value: preview.milliseconds, unit: "ms",
                            tags: [
                                "dwellMs": String(dwell), "index": String(index),
                                "renderRunning": String(renderRunning),
                                "previewSource": previewSource,
                                "previewError": preview.error ?? "none",
                                "previewLongEdge": String(max(preview.width, preview.height)),
                            ]))
                    if dwell > 0 {
                        try await Task.sleep(for: .milliseconds(dwell))
                    }
                    if let previous {
                        if let finished = previous.finished, finished.at <= arrival {
                            // It completed before the reader left this photo.
                            if finished.error == nil {
                                ready += 1
                                measurements.append(
                                    LabMeasurement(
                                        name: "swipe-render-ready",
                                        value: milliseconds(
                                            finished.at, since: previous.renderStarted),
                                        unit: "ms",
                                        tags: [
                                            "dwellMs": String(dwell),
                                            "index": String(previous.index), "status": "ok",
                                        ]))
                                measurements.append(
                                    LabMeasurement(
                                        name: "swipe-arrival-to-ready",
                                        value: milliseconds(finished.at, since: previous.arrival),
                                        unit: "ms",
                                        tags: [
                                            "dwellMs": String(dwell),
                                            "index": String(previous.index), "status": "ok",
                                        ]))
                            } else {
                                failed += 1
                                measurements.append(
                                    LabMeasurement(
                                        name: "swipe-render-failed",
                                        value: milliseconds(
                                            finished.at, since: previous.renderStarted),
                                        unit: "ms",
                                        tags: [
                                            "dwellMs": String(dwell),
                                            "index": String(previous.index),
                                            "status": finished.error ?? "noPixels",
                                        ]))
                            }
                        } else {
                            // Superseded after the reader moved on: cancel, drain, count it.
                            previous.task.cancel()
                            let drainStart = ContinuousClock.now
                            await previous.task.value
                            wasted += 1
                            measurements.append(
                                LabMeasurement(
                                    name: "swipe-render-abandoned",
                                    value: displayMilliseconds(since: drainStart), unit: "ms",
                                    tags: [
                                        "dwellMs": String(dwell), "index": String(previous.index),
                                        "status": "superseded-while-running",
                                    ]))
                        }
                    }
                    // Cancelling while the superseded render drained must not buy
                    // another full decode.
                    try Task.checkCancellation()
                    // The best screen-size variant, one at a time, as production would.
                    let variant = plan.screenVariant
                    let raw = photo.raw
                    let renderStarted = ContinuousClock.now
                    current = SwipeRender(
                        index: index, arrival: arrival, renderStarted: renderStarted
                    ) {
                        try measuring.renderRAW(url: raw, variant: variant)
                    }
                    started += 1
                }
                // The last photo stays on screen: wait for its render rather than
                // cancelling it, so the walk does not count the final render as waste.
                if let last = current {
                    await last.task.value
                    if let finished = last.finished {
                        if finished.error == nil {
                            ready += 1
                            measurements.append(
                                LabMeasurement(
                                    name: "swipe-render-ready",
                                    value: milliseconds(finished.at, since: last.renderStarted),
                                    unit: "ms",
                                    tags: [
                                        "dwellMs": String(dwell), "index": String(last.index),
                                        "status": "ok",
                                    ]))
                            measurements.append(
                                LabMeasurement(
                                    name: "swipe-arrival-to-ready",
                                    value: milliseconds(finished.at, since: last.arrival),
                                    unit: "ms",
                                    tags: [
                                        "dwellMs": String(dwell), "index": String(last.index),
                                        "status": "ok",
                                    ]))
                        } else {
                            failed += 1
                            measurements.append(
                                LabMeasurement(
                                    name: "swipe-render-failed",
                                    value: milliseconds(finished.at, since: last.renderStarted),
                                    unit: "ms",
                                    tags: [
                                        "dwellMs": String(dwell), "index": String(last.index),
                                        "status": finished.error ?? "noPixels",
                                    ]))
                        }
                    } else {
                        wasted += 1
                        measurements.append(
                            LabMeasurement(
                                name: "swipe-render-abandoned", value: 0, unit: "ms",
                                tags: [
                                    "dwellMs": String(dwell), "index": String(last.index),
                                    "status": "no-completion-record",
                                ]))
                    }
                }
            } catch {
                current?.task.cancel()
                await current?.task.value
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
