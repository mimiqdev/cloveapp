import CoreGraphics
import Foundation
import ImageIO
import LabSupport
import Testing
import UniformTypeIdentifiers

@testable import RAWDisplayProbe

@Test func rawDisplayDescriptorMatchesThePlan() {
    #expect(RAWDisplayProbe.descriptor.id == "S8")
    #expect(!RAWDisplayProbe.descriptor.question.isEmpty)
}

@Suite(.serialized)
struct RAWDisplayFixtureTests {
    /// The fixture ARW, shared by the RAW size and colour tests.
    private let rawFixtureName = "sony-ilce-7s" + ".ARW"

    /// Copies the RAW and HEIF fixtures into a unique folder with a shared stem, so
    /// the probe's pair matching is exercised and nothing writes into the cache.
    private func fixturePair() throws -> (folder: URL, raw: URL, camera: URL) {
        let formats = try #require(Fixtures.set("formats"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-rawdisplay-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let raw = folder.appendingPathComponent(rawFixtureName)
        let camera = folder.appendingPathComponent("sony-ilce-7s.HEIC")
        try FileManager.default.copyItem(
            at: formats.appendingPathComponent(rawFixtureName), to: raw)
        try FileManager.default.copyItem(
            at: formats.appendingPathComponent("sony-ilce-7s.HEIC"), to: camera)
        return (folder, raw, camera)
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func rawScaledVariantsMatchTheRequestedLongEdge() throws {
        let formats = try #require(Fixtures.set("formats"))
        let url = formats.appendingPathComponent(rawFixtureName)
        let renderer = RAWDisplayRenderer()
        let native = try renderer.render(
            url: url,
            variant: RAWDisplayVariant(
                name: "native", scale: .native, draft: false, context: .reused, role: .native))
        #expect(native.error == nil)
        #expect(max(native.width, native.height) == max(native.nativeWidth, native.nativeHeight))
        for edge in [400, 1_500] {
            for draft in [false, true] {
                let timing = try renderer.render(
                    url: url,
                    variant: RAWDisplayVariant(
                        name: "scale-\(edge)-draft-\(draft)", scale: .longEdge(edge),
                        draft: draft, context: .reused, role: .grid))
                #expect(timing.error == nil)
                // The request is a long edge through scaleFactor, so the output must
                // arrive at that size rather than at native size.
                #expect(abs(max(timing.width, timing.height) - edge) <= 2)
                #expect(timing.width < native.width)
            }
        }
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func cameraPreviewVariantsMatchTheirRequestedSize() throws {
        let formats = try #require(Fixtures.set("formats"))
        let url = formats.appendingPathComponent("sony-ilce-7s.HEIC")
        let renderer = CameraPreviewRenderer()
        let full = try renderer.render(
            url: url, variant: CameraPreviewVariant(name: "full", kind: .fullDecode))
        #expect(full.error == nil)
        #expect(full.width == full.nativeWidth && full.height == full.nativeHeight)
        let half = try renderer.render(
            url: url, variant: CameraPreviewVariant(name: "half", kind: .subsample(2)))
        #expect(half.error == nil)
        #expect(abs(half.width - full.width / 2) <= 2)
        #expect(abs(half.height - full.height / 2) <= 2)
        let screen = try renderer.render(
            url: url, variant: CameraPreviewVariant(name: "screen", kind: .screenThumbnail(800)))
        #expect(screen.error == nil)
        #expect(abs(max(screen.width, screen.height) - 800) <= 2)
    }

    @Test func cameraPreviewDecodeAppliesOrientation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-rawdisplay-orientation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("oriented.jpg")
        let image = try solidImage(width: 40, height: 20, red: 10, green: 120, blue: 200)
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let renderer = CameraPreviewRenderer()
        let full = try renderer.render(
            url: url, variant: CameraPreviewVariant(name: "full", kind: .fullDecode))
        #expect(full.error == nil)
        // Orientation 6 swaps the edges, as the embedded preview does.
        #expect(full.width == 20 && full.height == 40)
        #expect(full.nativeWidth == 20 && full.nativeHeight == 40)
        let thumbnail = try renderer.render(
            url: url, variant: CameraPreviewVariant(name: "thumb", kind: .screenThumbnail(20)))
        #expect(thumbnail.error == nil)
        #expect(thumbnail.width == 10 && thumbnail.height == 20)
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func filesPairTheRAWWithItsCameraPreview() throws {
        let fixtures = try fixturePair()
        defer { try? FileManager.default.removeItem(at: fixtures.folder) }
        let pairs = try RAWDisplayFiles.pairs(in: fixtures.folder)
        #expect(pairs.count == 1)
        #expect(pairs.first?.cameraPreview?.lastPathComponent == "sony-ilce-7s.HEIC")
    }

    @Test(.enabled(if: Fixtures.set("formats") != nil))
    func suiteProducesABoundedReportOnOnePair() async throws {
        let fixtures = try fixturePair()
        defer { try? FileManager.default.removeItem(at: fixtures.folder) }
        var options = RAWDisplayOptions(screenLongEdge: 1_500)
        options.detailedFiles = 1
        options.cameraPreviewPairs = 1
        options.warmRepeats = 1
        options.colourFiles = 1
        options.swipePhotos = 2
        options.swipeDwells = [0]
        options.cacheFiles = 1
        let progress = ProgressRecorder()
        let report = try await RAWDisplaySuite.run(
            folder: fixtures.folder, options: options,
            progress: { update in await progress.record(update) })
        #expect(report.spike == "S8")
        #expect(!report.device.modelIdentifier.isEmpty)
        #expect(report.measurements.allSatisfy { $0.value.isFinite })
        let names = Set(report.measurements.map(\.name))
        for expected in [
            "render-first-bitmap", "render-summary-median", "colour-deltae00-mean",
            "swipe-preview", "swipe-renders-started", "cache-held-decoded-memory",
            "grid-folder-projection", "cache-encode", "cache-decode",
        ] {
            #expect(names.contains(expected), "missing \(expected)")
        }
        #expect(report.context["bestScreenVariant"] != "none")
        #expect(report.context["bestGridVariant"] != "none")
        #expect(await progress.last?.completed ?? 0 > 0)
        #expect(await progress.last?.message == "Finished")
    }

    /// Opt-in artifact collection uses the same suite as Clove Lab. Normal verify
    /// exercises the functions without running the full-resolution benchmarks.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["CLOVE_RAW_DISPLAY_REPORT"] != nil
                && Fixtures.set("formats") != nil))
    func collectReport() async throws {
        let fixtures = try fixturePair()
        defer { try? FileManager.default.removeItem(at: fixtures.folder) }
        var options = RAWDisplayOptions(screenLongEdge: 2_000)
        options.detailedFiles = 1
        options.cameraPreviewPairs = 1
        options.colourFiles = 1
        options.swipePhotos = 2
        var report = try await RAWDisplaySuite.run(folder: fixtures.folder, options: options)
        report.context["execution"] =
            "macOS swift test on the re-hosted fixture ARW+HEIC; screen long edge 2000 px is a stand-in, not a device screen"
        report.notes.append(
            "macOS numbers taken on a shared, loaded host with another worker; not physical-device data."
        )
        let path = try #require(ProcessInfo.processInfo.environment["CLOVE_RAW_DISPLAY_REPORT"])
        try report.write(to: URL(fileURLWithPath: path))

        // A short sustained pass exercises the second button's code path; it is not
        // long enough to say anything about heat or battery.
        var sustainedOptions = options
        sustainedOptions.sustainedMaximumRenders = 10
        sustainedOptions.sustainedMaximumSeconds = 10
        sustainedOptions.warmRepeats = 1
        var sustained = try await RAWDisplaySuite.runSustained(
            folder: fixtures.folder, options: sustainedOptions, batteryStartPercent: nil)
        sustained.context["execution"] =
            "macOS swift test; 10 render bound, no battery on macOS; not physical-device data"
        sustained.notes.append(
            "Short macOS sustained pass only proves the path runs; thermal and battery results require the device."
        )
        try sustained.write(
            to: URL(
                fileURLWithPath: path.replacingOccurrences(of: ".json", with: "-sustained.json")))
    }
}

/// Records the last progress update so the suite test can assert it reported work.
actor ProgressRecorder {
    private(set) var last: RAWDisplayProgress?

    func record(_ update: RAWDisplayProgress) {
        last = update
    }
}
