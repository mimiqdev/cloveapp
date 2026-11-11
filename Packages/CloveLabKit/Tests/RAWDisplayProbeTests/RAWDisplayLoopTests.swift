import Foundation
import Testing

@testable import RAWDisplayProbe

@Suite(.serialized)
struct RAWDisplayLoopTests {
    private func pairs(_ count: Int) -> [RAWDisplayPair] {
        (0..<count).map { index in
            RAWDisplayPair(
                raw: URL(fileURLWithPath: "/fixture/photo-\(index).ARW"),
                cameraPreview: URL(fileURLWithPath: "/fixture/photo-\(index).HIF"))
        }
    }

    private func screenVariant() -> RAWDisplayVariant {
        RAWDisplayVariant(
            name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
            role: .screen)
    }

    private func swipePlan(photos: Int, dwell: Int) -> RAWDisplaySwipePlan {
        RAWDisplaySwipePlan(
            photos: (0..<photos).map {
                RAWDisplaySwipePhoto(
                    raw: URL(fileURLWithPath: "/fixture/photo-\($0).ARW"),
                    preview: URL(fileURLWithPath: "/fixture/photo-\($0).HIF"))
            },
            screenVariant: screenVariant(), dwellMilliseconds: [dwell])
    }

    @Test func variantLoopStopsAtItsRenderBound() async throws {
        let measuring = StubMeasuring()
        let variants = [
            RAWDisplayVariant(
                name: "first", scale: .native, draft: false, context: .fresh, role: .native),
            RAWDisplayVariant(
                name: "second", scale: .longEdge(400), draft: true, context: .reused,
                role: .grid),
        ]
        let result = try await RAWDisplaySuite.variantMeasurements(
            pairs: pairs(2), labels: RAWDisplayFileLabels(pairs: pairs(2)), variants: variants,
            warmRepeats: 2, measuring: measuring, step: { _ in })
        // One startup render, one cold render per variant, then two warm renders per
        // variant per file.
        #expect(measuring.count("raw-render") == 1 + 2 + 2 * 2 + 2 * 2)
        #expect(result.summaries.count == 2)
        #expect(result.summaries.allSatisfy { $0.samples == 4 && $0.failures == 0 })
        #expect(
            result.measurements.contains {
                $0.name == "render-first-bitmap" && $0.tags["phase"] == "startup"
            })
        #expect(result.measurements.contains { $0.name == "render-summary-cold" })
        #expect(result.measurements.contains { $0.name == "render-file-warm-median" })
    }

    @Test func variantLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySuite.variantMeasurements(
                pairs: pairs(2), labels: RAWDisplayFileLabels(pairs: pairs(2)),
                variants: RAWDisplayVariant.standard(screenLongEdge: 1_200), warmRepeats: 3,
                measuring: measuring, step: { _ in })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("raw-render") == 0)
    }

    @Test func swipeLoopStopsAtItsPhotoBound() async throws {
        let measuring = StubMeasuring()
        let measurements = try await RAWDisplaySwipes.run(
            plan: swipePlan(photos: 3, dwell: 20), measuring: measuring)
        #expect(measuring.count("embedded-preview") == 3)
        // A render requested for the last photo can be cancelled before it starts.
        #expect(measuring.count("raw-render") <= 3)
        let started = measurements.filter { $0.name == "swipe-renders-started" }
        let ready = measurements.filter { $0.name == "swipe-renders-ready" }
        let wasted = measurements.filter { $0.name == "swipe-renders-wasted" }
        let failed = measurements.filter { $0.name == "swipe-renders-failed" }
        #expect(started.first?.value == 3.0)
        #expect(
            (ready.first?.value ?? 0) + (wasted.first?.value ?? 0) + (failed.first?.value ?? 0) == 3
        )
        #expect(measurements.contains { $0.name == "swipe-preview" })
    }

    @Test func swipeCountsAReadyRenderWhenTheDwellOutlastsIt() async throws {
        let measuring = StubMeasuring(renderDelay: 0.005)
        let measurements = try await RAWDisplaySwipes.run(
            plan: swipePlan(photos: 3, dwell: 100), measuring: measuring)
        #expect(measurements.contains { $0.name == "swipe-renders-ready" && $0.value == 3 })
        #expect(measurements.contains { $0.name == "swipe-renders-wasted" && $0.value == 0 })
        #expect(measurements.filter { $0.name == "swipe-render-ready" }.count == 3)
        #expect(measurements.filter { $0.name == "swipe-arrival-to-ready" }.count == 3)
        #expect(
            measurements.filter { $0.name == "swipe-preview" }.allSatisfy {
                $0.tags["renderRunning"] == "false"
            })
    }

    @Test func swipeCountsAWastedRenderWhenTheDwellIsShorter() async throws {
        let measuring = StubMeasuring(renderDelay: 0.2)
        let measurements = try await RAWDisplaySwipes.run(
            plan: swipePlan(photos: 2, dwell: 5), measuring: measuring)
        #expect(measurements.contains { $0.name == "swipe-renders-wasted" && $0.value == 2 })
        #expect(measurements.contains { $0.name == "swipe-renders-ready" && $0.value == 0 })
        #expect(measurements.filter { $0.name == "swipe-render-wasted" }.count == 2)
        // The second photo's preview is requested while the first render is running.
        #expect(
            measurements.contains {
                $0.name == "swipe-preview" && $0.tags["index"] == "1"
                    && $0.tags["renderRunning"] == "true"
            })
        #expect(measuring.count("raw-render") == 2)
    }

    @Test func swipeCountsAWastedRenderWhenThePreviewOutlastsTheDwell() async throws {
        // The dwell deadline starts at arrival, so a slow preview eats the time the
        // render would have had.
        let measuring = StubMeasuring(renderDelay: 0.005, previewDelay: 0.04)
        let measurements = try await RAWDisplaySwipes.run(
            plan: swipePlan(photos: 1, dwell: 30), measuring: measuring)
        #expect(measurements.contains { $0.name == "swipe-renders-wasted" && $0.value == 1 })
        #expect(measurements.contains { $0.name == "swipe-renders-ready" && $0.value == 0 })
    }

    @Test func swipeCancellationDuringTheLastRenderDrainsIt() async throws {
        let (entered, continuation) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let measuring = StubMeasuring(renderEntered: continuation, renderRelease: release)
        defer { continuation.finish() }
        let task = Task {
            try await RAWDisplaySwipes.run(
                plan: swipePlan(photos: 1, dwell: 0), measuring: measuring)
        }
        var iterator = entered.makeAsyncIterator()
        await iterator.next()
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        // The in-flight render drained and no new render was admitted.
        #expect(measuring.count("raw-render") == 1)
        #expect(measuring.count("render-drained") == 1)
    }

    @Test func swipeCancellationStopsQueuedRenders() async throws {
        let (previews, continuation) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let measuring = StubMeasuring(
            renderRelease: release, previewEntered: continuation)
        defer { continuation.finish() }
        let task = Task {
            try await RAWDisplaySwipes.run(
                plan: swipePlan(photos: 4, dwell: 0), measuring: measuring)
        }
        var iterator = previews.makeAsyncIterator()
        for _ in 0..<4 {
            await iterator.next()
        }
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        // Only the first decoder ran; the queued renders were cancelled before entry.
        #expect(measuring.count("raw-render") == 1)
        #expect(measuring.count("render-drained") == 1)
    }

    @Test func swipePreviewTimeIncludesTheFallbackAttempt() async throws {
        let measuring = StubMeasuring(previewDelay: 0.02, previewFailsForCamera: true)
        let measurements = try await RAWDisplaySwipes.run(
            plan: swipePlan(photos: 1, dwell: 100), measuring: measuring)
        let preview = try #require(measurements.first { $0.name == "swipe-preview" })
        // Two 20 ms attempts; the failed camera request still cost time.
        #expect(preview.value >= 30)
        #expect(preview.tags["previewSource"] == "raw-fallback")
        #expect(preview.tags["orientation"] != nil)
    }

    @Test func swipeLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySwipes.run(
                plan: swipePlan(photos: 1, dwell: 0), measuring: measuring)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("embedded-preview") == 0)
    }

    @Test func cameraPreviewLoopStopsAtItsRenderBound() async throws {
        let measuring = StubMeasuring()
        let variants = [
            CameraPreviewVariant(name: "full", kind: .fullDecode),
            CameraPreviewVariant(name: "half", kind: .subsample(2)),
        ]
        let result = try await RAWDisplaySuite.cameraPreviewMeasurements(
            pairs: pairs(2), labels: RAWDisplayFileLabels(pairs: pairs(2)), variants: variants,
            warmRepeats: 1, measuring: measuring, step: { _ in })
        // One cold render per variant, then one warm render per variant per file.
        #expect(measuring.count("camera-render") == 2 * (1 + 1) + (2 - 1) * 2 * 1)
        #expect(result.summaries.count == 2)
        #expect(result.summaries.allSatisfy { $0.samples == 2 })
    }

    @Test func cameraPreviewLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySuite.cameraPreviewMeasurements(
                pairs: [
                    RAWDisplayPair(
                        raw: URL(fileURLWithPath: "/fixture/photo.ARW"),
                        cameraPreview: URL(fileURLWithPath: "/fixture/photo.HIF"))
                ],
                labels: RAWDisplayFileLabels(pairs: pairs(1)),
                variants: [CameraPreviewVariant(name: "full", kind: .fullDecode)],
                warmRepeats: 1, measuring: measuring, step: { _ in })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("camera-render") == 0)
    }

    @Test func colourComparisonStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try RAWDisplaySuite.colourMeasurements(
                file: URL(fileURLWithPath: "/fixture/photo.ARW"), cameraPreview: nil,
                labels: RAWDisplayFileLabels(pairs: pairs(1)),
                variants: RAWDisplayVariant.standard(screenLongEdge: 1_200),
                measuring: measuring)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("raw-image") == 0)
    }

    @Test func discoveryStopsOnCancellation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-rawdisplay-discovery-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["photo-1.ARW", "photo-1.HIF", "photo-2.ARW"] {
            try Data([1]).write(to: folder.appendingPathComponent(name))
        }
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try RAWDisplayFiles.pairs(in: folder)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cacheLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-rawdisplay-cache-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplayCacheCost.measurements(
                files: [URL(fileURLWithPath: "/fixture/photo.ARW")],
                labels: RAWDisplayFileLabels(pairs: pairs(1)), variant: screenVariant(),
                measuring: measuring, directory: directory)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("raw-image") == 0)
    }

    @Test func cacheLoopStopsAtItsHeldImageBound() async throws {
        let measuring = StubMeasuring()
        let files = (0..<9).map { URL(fileURLWithPath: "/fixture/photo-\($0).ARW") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-rawdisplay-cache-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let measurements = try await RAWDisplayCacheCost.measurements(
            files: files, labels: RAWDisplayFileLabels(pairs: pairs(9)),
            variant: screenVariant(), measuring: measuring, directory: directory)
        #expect(measuring.count("raw-image") == 6)
        #expect(measurements.contains { $0.name == "cache-held-images" && $0.value == 6 })
        #expect(measurements.contains { $0.name == "cache-held-resident" && $0.value >= 0 })
        #expect(measurements.contains { $0.name == "cache-held-resident-absolute" })
        #expect(measurements.contains { $0.name == "cache-held-render-peak" })
        #expect(measurements.filter { $0.name == "cache-encode" }.count == 12)
    }

    @Test func sustainedLoopStopsAtItsRenderBound() async throws {
        let measuring = StubMeasuring()
        let plan = RAWDisplaySustainedPlan(
            file: URL(fileURLWithPath: "/fixture/photo.ARW"), variant: screenVariant(),
            maximumRenders: 3, maximumSeconds: 60, batteryStartPercent: 84)
        let measurements = try await RAWDisplaySustainedLoad.run(
            plan: plan, measuring: measuring)
        #expect(measuring.count("raw-render") == 3)
        #expect(measurements.filter { $0.name == "sustained-render" }.count == 3)
        #expect(measurements.contains { $0.name == "battery-start" && $0.value == 84 })
        #expect(measurements.contains { $0.name == "sustained-renders" && $0.value == 3 })
        #expect(measurements.contains { $0.name == "thermal-start" })
    }

    @Test func sustainedLoopHonoursAZeroDurationBound() async throws {
        let measuring = StubMeasuring()
        let plan = RAWDisplaySustainedPlan(
            file: URL(fileURLWithPath: "/fixture/photo.ARW"), variant: screenVariant(),
            maximumRenders: 300, maximumSeconds: 0)
        let measurements = try await RAWDisplaySustainedLoad.run(
            plan: plan, measuring: measuring)
        #expect(measuring.count("raw-render") == 0)
        #expect(measurements.contains { $0.name == "sustained-renders" && $0.value == 0 })
    }

    @Test func sustainedLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring(renderDelay: 0.02)
        let plan = RAWDisplaySustainedPlan(
            file: URL(fileURLWithPath: "/fixture/photo.ARW"), variant: screenVariant(),
            maximumRenders: 300, maximumSeconds: 60)
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySustainedLoad.run(plan: plan, measuring: measuring)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("raw-render") == 0)
    }

    @Test func fileLabelsUseIndicesAndExtensions() {
        let labels = RAWDisplayFileLabels(pairs: [
            RAWDisplayPair(
                raw: URL(fileURLWithPath: "/fixture/a.ARW"),
                cameraPreview: URL(fileURLWithPath: "/fixture/a.HIF")),
            RAWDisplayPair(
                raw: URL(fileURLWithPath: "/fixture/nested/b.NEF"), cameraPreview: nil),
        ])
        #expect(labels.label(for: URL(fileURLWithPath: "/fixture/a.ARW")) == "raw-01.ARW")
        #expect(labels.label(for: URL(fileURLWithPath: "/fixture/a.HIF")) == "raw-01.HIF")
        #expect(labels.label(for: URL(fileURLWithPath: "/fixture/nested/b.NEF")) == "raw-02.NEF")
        #expect(
            labels.label(for: URL(fileURLWithPath: "/fixture/other.ARW"))
                == "file-unknown.ARW")
    }

    @Test func gridProjectionUsesTheBriefFolderSize() {
        let measurements = RAWDisplayGridEstimate.measurements(
            perPhotoMilliseconds: 10, variantName: "grid", folderPhotos: 2_000)
        let projections = measurements.filter { $0.name == "grid-folder-projection" }
        #expect(projections.count == 2)
        #expect(projections.contains { $0.tags["concurrency"] == "1" && $0.value == 20 })
        #expect(projections.contains { $0.tags["concurrency"] == "2" && $0.value == 10 })
    }
}
