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
    let arrival: ContinuousClock.Instant
    let task: Task<Void, Never>
    private let completion = SwipeRenderCompletion()

    init(
        index: Int, arrival: ContinuousClock.Instant,
        render: @escaping @Sendable () throws -> DisplayRenderTiming
    ) {
        self.index = index
        self.arrival = arrival
        let completion = self.completion
        task = Task {
            do {
                let timing = try render()
                completion.finish(.init(at: .now, timing: timing, error: nil))
            } catch {
                completion.finish(.init(at: .now, timing: nil, error: String(describing: error)))
            }
        }
    }

    var finished: SwipeRenderCompletion.Finished? { completion.value }
}

/// Walks photos the way the detail reader does: preview, a dwell, then the
/// screen-size RAW render in the background while the next photo arrives.
public enum RAWDisplaySwipes {
    /// Runs one walk per dwell and reports preview latency, arrival-to-render time,
    /// and renders that were abandoned before they could be shown.
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
            var shown = 0
            var wasted = 0
            do {
                for (index, photo) in photos.enumerated() {
                    try Task.checkCancellation()
                    let renderRunning = current.map { $0.finished == nil } ?? false
                    let preview = try measuring.embeddedPreview(
                        url: photo.preview, maxPixel: plan.previewPixels)
                    measurements.append(
                        LabMeasurement(
                            name: "swipe-preview", value: preview.milliseconds, unit: "ms",
                            tags: [
                                "dwellMs": String(dwell), "index": String(index),
                                "renderRunning": String(renderRunning),
                                "previewError": preview.error ?? "none",
                                "previewLongEdge": String(max(preview.width, preview.height)),
                            ]))
                    if dwell > 0 {
                        try await Task.sleep(for: .milliseconds(dwell))
                    }
                    let arrival = ContinuousClock.now
                    if let previous = current {
                        if let finished = previous.finished {
                            shown += 1
                            measurements.append(
                                LabMeasurement(
                                    name: "swipe-render-ready",
                                    value: milliseconds(finished.at, since: previous.arrival),
                                    unit: "ms",
                                    tags: [
                                        "dwellMs": String(dwell), "index": String(previous.index),
                                        "status": finished.error ?? "ok",
                                    ]))
                        } else {
                            // Superseded: cancel, wait for the decoder to drain, count it.
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
                    // The best screen-size variant, one at a time, as production would.
                    let variant = plan.screenVariant
                    let raw = photo.raw
                    current = SwipeRender(index: index, arrival: arrival) {
                        try measuring.renderRAW(url: raw, variant: variant)
                    }
                    started += 1
                }
                // The last photo stays on screen: wait for its render rather than
                // cancelling it, so the walk does not count the final render as waste.
                if let last = current {
                    await last.task.value
                    if let finished = last.finished {
                        shown += 1
                        measurements.append(
                            LabMeasurement(
                                name: "swipe-render-ready",
                                value: milliseconds(finished.at, since: last.arrival), unit: "ms",
                                tags: [
                                    "dwellMs": String(dwell), "index": String(last.index),
                                    "status": finished.error ?? "ok",
                                ]))
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
            let counts = ["dwellMs": String(dwell), "photos": String(photos.count)]
            measurements += [
                LabMeasurement(
                    name: "swipe-renders-started", value: Double(started), unit: "count",
                    tags: counts),
                LabMeasurement(
                    name: "swipe-renders-ready", value: Double(shown), unit: "count", tags: counts),
                LabMeasurement(
                    name: "swipe-renders-wasted", value: Double(wasted), unit: "count",
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
