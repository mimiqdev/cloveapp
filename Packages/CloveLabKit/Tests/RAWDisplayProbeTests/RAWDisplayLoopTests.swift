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
            pairs: pairs(2), folder: URL(fileURLWithPath: "/fixture"), variants: variants,
            warmRepeats: 2, measuring: measuring, step: { _ in })
        // One cold render per variant, then two warm renders per variant per file.
        #expect(measuring.count("raw-render") == 2 + 2 * 2 + 2 * 2)
        #expect(result.summaries.count == 2)
        #expect(result.summaries.allSatisfy { $0.samples == 4 && $0.failures == 0 })
        #expect(result.measurements.contains { $0.name == "render-summary-cold" })
        #expect(result.measurements.contains { $0.name == "render-file-warm-median" })
    }

    @Test func variantLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySuite.variantMeasurements(
                pairs: pairs(2), folder: URL(fileURLWithPath: "/fixture"),
                variants: RAWDisplayVariant.standard(screenLongEdge: 1_200), warmRepeats: 3,
                measuring: measuring, step: { _ in })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("raw-render") == 0)
    }

    @Test func swipeLoopStopsAtItsPhotoBound() async throws {
        let measuring = StubMeasuring()
        let plan = RAWDisplaySwipePlan(
            photos: (0..<3).map {
                RAWDisplaySwipePhoto(
                    raw: URL(fileURLWithPath: "/fixture/photo-\($0).ARW"),
                    preview: URL(fileURLWithPath: "/fixture/photo-\($0).HIF"))
            },
            screenVariant: RAWDisplayVariant(
                name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
                role: .screen),
            dwellMilliseconds: [20])
        let measurements = try await RAWDisplaySwipes.run(plan: plan, measuring: measuring)
        #expect(measuring.count("embedded-preview") == 3)
        // A render requested for the last photo can be cancelled before it starts.
        #expect(measuring.count("raw-render") <= 3)
        let started = measurements.filter { $0.name == "swipe-renders-started" }
        let shown = measurements.filter { $0.name == "swipe-renders-ready" }
        let wasted = measurements.filter { $0.name == "swipe-renders-wasted" }
        #expect(started.first?.value == 3.0)
        #expect((shown.first?.value ?? 0) + (wasted.first?.value ?? 0) == 3)
        #expect(measurements.contains { $0.name == "swipe-preview" })
    }

    @Test func swipeLoopSupersedesAnInFlightRender() async throws {
        let measuring = StubMeasuring(renderDelay: 0.05)
        let plan = RAWDisplaySwipePlan(
            photos: (0..<2).map {
                RAWDisplaySwipePhoto(
                    raw: URL(fileURLWithPath: "/fixture/photo-\($0).ARW"),
                    preview: URL(fileURLWithPath: "/fixture/photo-\($0).HIF"))
            },
            screenVariant: RAWDisplayVariant(
                name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
                role: .screen),
            dwellMilliseconds: [0])
        let measurements = try await RAWDisplaySwipes.run(plan: plan, measuring: measuring)
        let wasted = measurements.filter { $0.name == "swipe-renders-wasted" }
        #expect((wasted.first?.value ?? 0) >= 1)
        #expect(measurements.contains { $0.name == "swipe-render-abandoned" })
    }

    @Test func swipeLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring()
        let plan = RAWDisplaySwipePlan(
            photos: [
                RAWDisplaySwipePhoto(
                    raw: URL(fileURLWithPath: "/fixture/photo.ARW"),
                    preview: URL(fileURLWithPath: "/fixture/photo.HIF"))
            ],
            screenVariant: RAWDisplayVariant(
                name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
                role: .screen),
            dwellMilliseconds: [0])
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySwipes.run(plan: plan, measuring: measuring)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("embedded-preview") == 0)
    }

    @Test func sustainedLoopStopsAtItsRenderBound() async throws {
        let measuring = StubMeasuring()
        let plan = RAWDisplaySustainedPlan(
            file: URL(fileURLWithPath: "/fixture/photo.ARW"),
            variant: RAWDisplayVariant(
                name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
                role: .screen),
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
            file: URL(fileURLWithPath: "/fixture/photo.ARW"),
            variant: RAWDisplayVariant(
                name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
                role: .screen),
            maximumRenders: 300, maximumSeconds: 0)
        let measurements = try await RAWDisplaySustainedLoad.run(
            plan: plan, measuring: measuring)
        #expect(measuring.count("raw-render") == 0)
        #expect(measurements.contains { $0.name == "sustained-renders" && $0.value == 0 })
    }

    @Test func sustainedLoopStopsOnCancellation() async throws {
        let measuring = StubMeasuring(renderDelay: 0.02)
        let plan = RAWDisplaySustainedPlan(
            file: URL(fileURLWithPath: "/fixture/photo.ARW"),
            variant: RAWDisplayVariant(
                name: "screen", scale: .longEdge(1_200), draft: false, context: .reused,
                role: .screen),
            maximumRenders: 300, maximumSeconds: 60)
        let task = Task {
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return try await RAWDisplaySustainedLoad.run(plan: plan, measuring: measuring)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(measuring.count("raw-render") == 0)
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
