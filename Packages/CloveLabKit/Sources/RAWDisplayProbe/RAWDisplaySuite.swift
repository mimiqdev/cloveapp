import Foundation
import LabSupport
import PreviewProbe

/// Progress for the Lab screen: one step per render or comparison.
public struct RAWDisplayProgress: Sendable {
    public var completed: Int
    public var total: Int
    public var message: String

    public init(completed: Int, total: Int, message: String) {
        self.completed = completed
        self.total = total
        self.message = message
    }
}

/// Bounds and inputs for one display measurement run.
public struct RAWDisplayOptions: Sendable {
    /// The device screen's long edge in pixels, read in the Lab app layer.
    public var screenLongEdge: Int
    /// Detailed RAW renders use this many files from the start of sorted order.
    public var detailedFiles = 12
    /// Camera HEIF variants use this many RAW + HEIF pairs, as allowed when the run
    /// would otherwise exceed about ten minutes.
    public var cameraPreviewPairs = 6
    /// Repeats per variant per file, after the variant's first (cold) render.
    public var warmRepeats = 3
    /// RAW colour comparisons use this many of the detailed files.
    public var colourFiles = 3
    public var swipePhotos = 20
    public var swipeDwells = [0, 300, 800]
    public var cacheFiles = 6
    public var gridLongEdge = 400
    public var projectedFolderPhotos = 2_000
    public var sustainedMaximumRenders = 300
    public var sustainedMaximumSeconds = 300.0
    /// Test override; `nil` renders the standard RAW variant list.
    public var variants: [RAWDisplayVariant]?
    /// Test override; `nil` renders the standard camera HEIF variant list.
    public var cameraVariants: [CameraPreviewVariant]?

    public init(screenLongEdge: Int) {
        self.screenLongEdge = screenLongEdge
    }
}

/// A variant's aggregate row: warm repeats across the detailed files, plus the cold
/// observation when it produced pixels.
struct DisplayVariantSummary: Sendable {
    var name: String
    var role: String
    var scaleMethod: String
    var requestedLongEdge: Int
    var draft: Bool?
    var context: String?
    var outputLongEdge: Int
    var warmMedian: Double
    var warmP90: Double
    var samples: Int
    var failures: Int
    var coldMilliseconds: Double?
}

/// Runs the display measurements in the brief's order and writes one report.
public enum RAWDisplaySuite {
    /// The full run: RAW variants, camera HEIF variants, colour agreement, swipes,
    /// cache cost and the grid projection. The sustained load is a separate entry
    /// point so the owner can run it on its own button.
    public static func run(
        folder: URL,
        options: RAWDisplayOptions,
        measuring: any RAWDisplayMeasuring = LiveRAWDisplayMeasuring(),
        progress: @escaping @Sendable (RAWDisplayProgress) async -> Void = { _ in }
    ) async throws -> LabReport {
        let pairs = try RAWDisplayFiles.pairs(in: folder)
        let variants =
            options.variants ?? RAWDisplayVariant.standard(screenLongEdge: options.screenLongEdge)
        let cameraVariants =
            options.cameraVariants
            ?? CameraPreviewVariant.standard(screenLongEdge: options.screenLongEdge)
        let detailed = Array(pairs.prefix(max(0, options.detailedFiles)))
        let cameraPairs = Array(
            pairs.filter { $0.cameraPreview != nil }.prefix(max(0, options.cameraPreviewPairs)))
        let colourPairs = Array(detailed.prefix(max(0, options.colourFiles)))
        let photos = pairs.prefix(max(0, options.swipePhotos)).map {
            RAWDisplaySwipePhoto(raw: $0.raw, preview: $0.cameraPreview ?? $0.raw)
        }
        let samples = max(0, options.warmRepeats)
        let total = max(
            1,
            plannedRenders(files: detailed.count, variants: variants.count, samples: samples)
                + plannedRenders(
                    files: cameraPairs.count, variants: cameraVariants.count, samples: samples)
                + colourPairs.count + cameraPairs.count
                + options.swipeDwells.count
                + min(options.cacheFiles, detailed.count) + 1
        )
        let runStart = ContinuousClock.now
        var completed = 0
        let step: (String) async -> Void = { message in
            completed += 1
            await progress(
                .init(completed: min(completed, total), total: total, message: message))
        }

        let rawPhase = try await variantMeasurements(
            pairs: detailed, folder: folder, variants: variants, warmRepeats: samples,
            measuring: measuring, step: step)
        let cameraPhase = try await cameraPreviewMeasurements(
            pairs: cameraPairs, folder: folder, variants: cameraVariants, warmRepeats: samples,
            measuring: measuring, step: step)
        var measurements = rawPhase.measurements + cameraPhase.measurements

        // Colour: reduced RAW variants against the native render, then the camera
        // preview the reader sees today against that render.
        for pair in colourPairs {
            try Task.checkCancellation()
            await step("Colour: \(RAWDisplayFiles.relativePath(pair.raw, in: folder))")
            measurements += try autoreleasepool {
                try colourMeasurements(
                    file: pair.raw, cameraPreview: pair.cameraPreview, folder: folder,
                    variants: variants, measuring: measuring)
            }
        }
        for pair in cameraPairs {
            try Task.checkCancellation()
            await step(
                "Camera preview colour: \(RAWDisplayFiles.relativePath(pair.raw, in: folder))")
            measurements += try autoreleasepool {
                try cameraPreviewColourMeasurements(
                    pair: pair, folder: folder, variants: cameraVariants,
                    measuring: measuring)
            }
        }

        // Swipes and cache need the fastest screen-size variant measured above.
        let bestScreen = bestVariant(in: rawPhase.summaries, role: .screen)
        let screenVariant =
            variants.first { $0.name == bestScreen?.name }
            ?? variants.first { $0.role == .screen }
            ?? RAWDisplayVariant.standard(screenLongEdge: options.screenLongEdge)[2]
        if !photos.isEmpty, !options.swipeDwells.isEmpty {
            measurements += try await RAWDisplaySwipes.run(
                plan: .init(
                    photos: Array(photos), screenVariant: screenVariant,
                    dwellMilliseconds: options.swipeDwells),
                measuring: measuring, step: step)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "clove-rawdisplay-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        measurements += try await RAWDisplayCacheCost.measurements(
            files: detailed.map(\.raw), folder: folder, variant: screenVariant,
            measuring: measuring, directory: directory, step: step)

        let bestGrid = bestVariant(in: rawPhase.summaries, role: .grid)
        if let bestGrid, bestGrid.samples > 0 {
            measurements += RAWDisplayGridEstimate.measurements(
                perPhotoMilliseconds: bestGrid.warmMedian, variantName: bestGrid.name,
                folderPhotos: options.projectedFolderPhotos)
        }

        measurements.append(
            LabMeasurement(
                name: "run-duration", value: displayMilliseconds(since: runStart), unit: "ms",
                tags: ["phase": "display-suite"]))
        await step("Finished")
        return LabReport(
            spike: RAWDisplayProbe.descriptor.id,
            context: context(
                folder: folder, pairs: pairs, detailed: detailed, cameraPairs: cameraPairs,
                colourPairs: colourPairs, variants: variants, cameraVariants: cameraVariants,
                options: options, bestScreen: bestScreen, bestGrid: bestGrid),
            measurements: measurements,
            notes: notes(options: options))
    }

    /// The sustained-load entry point: picks the faster screen-size variant with a
    /// short selection pass, then renders it back to back.
    public static func runSustained(
        folder: URL,
        options: RAWDisplayOptions,
        batteryStartPercent: Double?,
        measuring: any RAWDisplayMeasuring = LiveRAWDisplayMeasuring(),
        progress: @escaping @Sendable (RAWDisplayProgress) async -> Void = { _ in }
    ) async throws -> LabReport {
        let pairs = try RAWDisplayFiles.pairs(in: folder)
        guard let file = pairs.first?.raw else { throw RAWDisplayRunError.noRAWFiles }
        let screenVariants = RAWDisplayVariant.standard(screenLongEdge: options.screenLongEdge)
            .filter { $0.role == .screen }
        guard let fallback = screenVariants.first else { throw RAWDisplayRunError.noRAWFiles }
        let samples = max(1, options.warmRepeats)
        let total = screenVariants.count * (1 + samples) + options.sustainedMaximumRenders + 2
        var completed = 0
        let step: (String) async -> Void = { message in
            completed += 1
            await progress(
                .init(completed: min(completed, total), total: total, message: message))
        }
        let selection = try await variantMeasurements(
            pairs: Array(pairs.prefix(1)), folder: folder, variants: screenVariants,
            warmRepeats: samples, measuring: measuring, step: step)
        let best = selection.summaries.filter { $0.samples > 0 }.min {
            $0.warmMedian < $1.warmMedian
        }
        let variant = screenVariants.first { $0.name == best?.name } ?? fallback
        let measurements =
            selection.measurements
            + (try await RAWDisplaySustainedLoad.run(
                plan: .init(
                    file: file, variant: variant,
                    maximumRenders: options.sustainedMaximumRenders,
                    maximumSeconds: options.sustainedMaximumSeconds,
                    batteryStartPercent: batteryStartPercent),
                measuring: measuring, step: step))
        await step("Finished")
        return LabReport(
            spike: RAWDisplayProbe.descriptor.id,
            context: [
                "phase": "sustained-load", "folderName": folder.lastPathComponent,
                "rawFiles": String(pairs.count),
                "file": RAWDisplayFiles.relativePath(file, in: folder),
                "variant": variant.name,
                "variantRule": "lowest median of warm screen-size renders in the selection pass",
                "selectionRepeats": String(samples),
                "screenLongEdge": String(options.screenLongEdge),
                "maximumRenders": String(options.sustainedMaximumRenders),
                "maximumSeconds": String(Int(options.sustainedMaximumSeconds)),
                "batteryStartPercent": batteryStartPercent.map { String($0) } ?? "unknown",
                "batterySource": "Lab app reads UIDevice batteryLevel before and after",
                "memory": "5 ms process RSS samples; lower bound",
            ],
            measurements: measurements,
            notes: [
                "The sustained step renders one screen-size variant back to back, with no preview request between renders.",
                "The duration bound is checked before each render, so the final render can run past it.",
                "Thermal state is ProcessInfo.thermalState; the battery level at the end is appended by the Lab app layer.",
                "Each render is the same synchronous CIRAWFilter path as the main suite; no queued or cancelled work is included.",
                "Results are only meaningful on the physical device, charger unplugged, at room temperature.",
            ])
    }

    // MARK: - Variant phases

    static func variantMeasurements(
        pairs: [RAWDisplayPair], folder: URL, variants: [RAWDisplayVariant], warmRepeats: Int,
        measuring: any RAWDisplayMeasuring, step: (String) async -> Void
    ) async throws -> (measurements: [LabMeasurement], summaries: [DisplayVariantSummary]) {
        var measurements: [LabMeasurement] = []
        var coldDone: Set<String> = []
        var coldMilliseconds: [String: Double] = [:]
        var samples: [String: [Double]] = [:]
        var failures: [String: Int] = [:]
        var outputLongEdge: [String: Int] = [:]
        for pair in pairs {
            try Task.checkCancellation()
            let relative = RAWDisplayFiles.relativePath(pair.raw, in: folder)
            var perFile: [String: [Double]] = [:]
            for variant in variants {
                if !coldDone.contains(variant.name) {
                    coldDone.insert(variant.name)
                    await step("\(variant.name) cold: \(relative)")
                    let cold = try measuring.renderRAW(url: pair.raw, variant: variant)
                    measurements += cold.measurements(
                        file: relative, variantName: variant.name,
                        role: variant.role.rawValue, phase: .cold, request: requestTags(variant))
                    if cold.error != nil {
                        failures[variant.name, default: 0] += 1
                    } else {
                        coldMilliseconds[variant.name] = cold.milliseconds
                        outputLongEdge[variant.name] = max(cold.width, cold.height)
                    }
                }
                for repeatIndex in 0..<max(0, warmRepeats) {
                    try Task.checkCancellation()
                    await step(
                        "\(variant.name) warm \(repeatIndex + 1)/\(warmRepeats): \(relative)")
                    let timing = try measuring.renderRAW(url: pair.raw, variant: variant)
                    measurements += timing.measurements(
                        file: relative, variantName: variant.name,
                        role: variant.role.rawValue, phase: .warm, request: requestTags(variant))
                    if timing.error != nil {
                        failures[variant.name, default: 0] += 1
                    } else {
                        perFile[variant.name, default: []].append(timing.milliseconds)
                        samples[variant.name, default: []].append(timing.milliseconds)
                        outputLongEdge[variant.name] = max(timing.width, timing.height)
                    }
                }
            }
            for variant in variants {
                guard let fileSamples = perFile[variant.name], !fileSamples.isEmpty else {
                    continue
                }
                let tags = summaryTags(variant: variant)
                    .merging(["file": relative]) { _, new in new }
                measurements += [
                    LabMeasurement(
                        name: "render-file-warm-median", value: median(fileSamples), unit: "ms",
                        tags: tags),
                    LabMeasurement(
                        name: "render-file-warm-p90",
                        value: nearestRank(fileSamples, fraction: 0.9), unit: "ms", tags: tags),
                ]
            }
        }
        let summaries = variants.map { variant in
            let warm = samples[variant.name] ?? []
            return DisplayVariantSummary(
                name: variant.name, role: variant.role.rawValue,
                scaleMethod: variant.scaleMethod,
                requestedLongEdge: variant.requestedLongEdge, draft: variant.draft,
                context: variant.context.rawValue,
                outputLongEdge: outputLongEdge[variant.name] ?? 0,
                warmMedian: warm.isEmpty ? 0 : median(warm),
                warmP90: warm.isEmpty ? 0 : nearestRank(warm, fraction: 0.9),
                samples: warm.count, failures: failures[variant.name] ?? 0,
                coldMilliseconds: coldMilliseconds[variant.name])
        }
        return (measurements + summaries.flatMap(summaryMeasurements), summaries)
    }

    static func cameraPreviewMeasurements(
        pairs: [RAWDisplayPair], folder: URL, variants: [CameraPreviewVariant],
        warmRepeats: Int, measuring: any RAWDisplayMeasuring, step: (String) async -> Void
    ) async throws -> (measurements: [LabMeasurement], summaries: [DisplayVariantSummary]) {
        var measurements: [LabMeasurement] = []
        var coldDone: Set<String> = []
        var coldMilliseconds: [String: Double] = [:]
        var samples: [String: [Double]] = [:]
        var failures: [String: Int] = [:]
        var outputLongEdge: [String: Int] = [:]
        for pair in pairs {
            try Task.checkCancellation()
            guard let camera = pair.cameraPreview else { continue }
            let relative = RAWDisplayFiles.relativePath(camera, in: folder)
            for variant in variants {
                if !coldDone.contains(variant.name) {
                    coldDone.insert(variant.name)
                    await step("\(variant.name) cold: \(relative)")
                    let cold = try measuring.renderCameraPreview(url: camera, variant: variant)
                    measurements += cold.measurements(
                        file: relative, variantName: variant.name, role: "camera",
                        phase: .cold, request: cameraRequestTags(variant))
                    if cold.error != nil {
                        failures[variant.name, default: 0] += 1
                    } else {
                        coldMilliseconds[variant.name] = cold.milliseconds
                        outputLongEdge[variant.name] = max(cold.width, cold.height)
                    }
                }
                for repeatIndex in 0..<max(0, warmRepeats) {
                    try Task.checkCancellation()
                    await step(
                        "\(variant.name) warm \(repeatIndex + 1)/\(warmRepeats): \(relative)")
                    let timing = try measuring.renderCameraPreview(url: camera, variant: variant)
                    measurements += timing.measurements(
                        file: relative, variantName: variant.name, role: "camera",
                        phase: .warm, request: cameraRequestTags(variant))
                    if timing.error != nil {
                        failures[variant.name, default: 0] += 1
                    } else {
                        samples[variant.name, default: []].append(timing.milliseconds)
                        outputLongEdge[variant.name] = max(timing.width, timing.height)
                    }
                }
            }
        }
        let summaries = variants.map { variant in
            let warm = samples[variant.name] ?? []
            return DisplayVariantSummary(
                name: variant.name, role: "camera", scaleMethod: variant.scaleMethod,
                requestedLongEdge: variant.requestedLongEdge, draft: nil, context: nil,
                outputLongEdge: outputLongEdge[variant.name] ?? 0,
                warmMedian: warm.isEmpty ? 0 : median(warm),
                warmP90: warm.isEmpty ? 0 : nearestRank(warm, fraction: 0.9),
                samples: warm.count, failures: failures[variant.name] ?? 0,
                coldMilliseconds: coldMilliseconds[variant.name])
        }
        return (measurements + summaries.flatMap(summaryMeasurements), summaries)
    }

    // MARK: - Colour

    static func colourMeasurements(
        file: URL, cameraPreview: URL?, folder: URL, variants: [RAWDisplayVariant],
        measuring: any RAWDisplayMeasuring
    ) throws -> [LabMeasurement] {
        var measurements: [LabMeasurement] = []
        let relative = RAWDisplayFiles.relativePath(file, in: folder)
        let nativeVariant =
            variants.first { $0.role == .native }
            ?? RAWDisplayVariant(
                name: "raw-native-fresh-context", scale: .native, draft: false, context: .fresh,
                role: .native)
        do {
            let native = try measuring.rawImage(url: file, variant: nativeVariant)
            for variant in variants where variant.role != .native {
                do {
                    let reduced = try measuring.rawImage(url: file, variant: variant)
                    guard
                        let reference = RAWDisplayColour.scaled(
                            native, toWidth: reduced.width, height: reduced.height),
                        let difference = RAWDisplayColour.compare(reference, reduced)
                    else {
                        measurements.append(
                            colourFailure(
                                file: relative, method: variant.name, status: "cannotCompare"))
                        continue
                    }
                    measurements += difference.measurements(
                        tags: [
                            "file": relative, "method": variant.name,
                            "compare": "raw-reduced-vs-raw-native",
                            "reference": "raw-native-rendered-then-lanczos-scaled",
                            "scaleMethod": variant.scaleMethod,
                            "requestedLongEdge": String(variant.requestedLongEdge),
                            "draft": String(variant.draft),
                            "outputLongEdge": String(max(reduced.width, reduced.height)),
                        ])
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    measurements.append(
                        colourFailure(
                            file: relative, method: variant.name,
                            status: String(describing: error)))
                }
            }
            if let cameraPreview {
                do {
                    let preview = try measuring.embeddedPreviewImage(
                        url: cameraPreview, maxPixel: 2_000)
                    guard
                        let reference = RAWDisplayColour.scaled(
                            native, toWidth: preview.width, height: preview.height),
                        let difference = RAWDisplayColour.compare(reference, preview)
                    else {
                        measurements.append(
                            colourFailure(
                                file: relative, method: "camera-embedded-preview",
                                status: "cannotCompare"))
                        return measurements
                    }
                    measurements += difference.measurements(
                        tags: [
                            "file": relative, "method": "camera-embedded-preview",
                            "compare": "camera-preview-vs-raw-native",
                            "reference": "raw-native-rendered-then-lanczos-scaled",
                            "cameraPreview": RAWDisplayFiles.relativePath(
                                cameraPreview, in: folder),
                            "previewLongEdge": String(max(preview.width, preview.height)),
                        ])
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    measurements.append(
                        colourFailure(
                            file: relative, method: "camera-embedded-preview",
                            status: String(describing: error)))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            measurements.append(
                colourFailure(
                    file: relative, method: nativeVariant.name,
                    status: String(describing: error)))
        }
        return measurements
    }

    static func cameraPreviewColourMeasurements(
        pair: RAWDisplayPair, folder: URL, variants: [CameraPreviewVariant],
        measuring: any RAWDisplayMeasuring
    ) throws -> [LabMeasurement] {
        guard let camera = pair.cameraPreview else { return [] }
        let fullVariant =
            variants.first { $0.kind == .fullDecode }
            ?? CameraPreviewVariant(name: "camera-full-decode", kind: .fullDecode)
        let relative = RAWDisplayFiles.relativePath(camera, in: folder)
        do {
            let full = try measuring.cameraPreviewImage(url: camera, variant: fullVariant)
            let preview = try measuring.embeddedPreviewImage(url: camera, maxPixel: 2_000)
            guard
                let reference = RAWDisplayColour.scaled(
                    full, toWidth: preview.width, height: preview.height),
                let difference = RAWDisplayColour.compare(reference, preview)
            else {
                return [
                    colourFailure(
                        file: relative, method: "camera-full-decode", status: "cannotCompare")
                ]
            }
            return difference.measurements(
                tags: [
                    "file": relative, "method": "camera-full-decode",
                    "compare": "camera-full-vs-camera-preview",
                    "reference": "camera-full-decode-then-lanczos-scaled",
                    "previewLongEdge": String(max(preview.width, preview.height)),
                ])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return [
                colourFailure(
                    file: relative, method: "camera-full-decode",
                    status: String(describing: error))
            ]
        }
    }

    // MARK: - Report helpers

    static func bestVariant(
        in summaries: [DisplayVariantSummary], role: RAWDisplayVariant.Role
    ) -> DisplayVariantSummary? {
        summaries.filter { $0.role == role.rawValue && $0.samples > 0 }.min {
            $0.warmMedian < $1.warmMedian
        }
    }

    private static func plannedRenders(files: Int, variants: Int, samples: Int) -> Int {
        guard files > 0, variants > 0 else { return 0 }
        return variants * (1 + samples) + (files - 1) * variants * samples
    }

    private static func requestTags(_ variant: RAWDisplayVariant) -> [String: String] {
        [
            "scaleMethod": variant.scaleMethod,
            "requestedLongEdge": String(variant.requestedLongEdge),
            "draft": String(variant.draft),
            "context": variant.context.rawValue,
        ]
    }

    private static func cameraRequestTags(_ variant: CameraPreviewVariant) -> [String: String] {
        var tags: [String: String] = [
            "scaleMethod": variant.scaleMethod,
            "requestedLongEdge": String(variant.requestedLongEdge),
        ]
        if case .subsample(let factor) = variant.kind {
            tags["subsampleFactor"] = String(factor)
        }
        return tags
    }

    private static func summaryTags(variant: RAWDisplayVariant) -> [String: String] {
        requestTags(variant).merging(["variant": variant.name, "role": variant.role.rawValue]) {
            _, new in new
        }
    }

    static func summaryMeasurements(_ summary: DisplayVariantSummary) -> [LabMeasurement] {
        var tags: [String: String] = [
            "variant": summary.name, "role": summary.role,
            "scaleMethod": summary.scaleMethod,
            "requestedLongEdge": String(summary.requestedLongEdge),
            "outputLongEdge": String(summary.outputLongEdge),
            "samples": String(summary.samples), "failures": String(summary.failures),
        ]
        if let draft = summary.draft { tags["draft"] = String(draft) }
        if let context = summary.context { tags["context"] = context }
        var measurements: [LabMeasurement] = []
        if summary.samples > 0 {
            measurements += [
                LabMeasurement(
                    name: "render-summary-median", value: summary.warmMedian, unit: "ms",
                    tags: tags),
                LabMeasurement(
                    name: "render-summary-p90", value: summary.warmP90, unit: "ms", tags: tags),
            ]
        }
        if let cold = summary.coldMilliseconds {
            measurements.append(
                LabMeasurement(name: "render-summary-cold", value: cold, unit: "ms", tags: tags))
        }
        return measurements
    }

    private static func colourFailure(
        file: String, method: String, status: String
    ) -> LabMeasurement {
        LabMeasurement(
            name: "colour-failure", value: 1, unit: "count",
            tags: ["file": file, "method": method, "status": status])
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Nearest-rank percentile; p90 of 3 repeats is the largest of the three.
    static func nearestRank(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func context(
        folder: URL, pairs: [RAWDisplayPair], detailed: [RAWDisplayPair],
        cameraPairs: [RAWDisplayPair], colourPairs: [RAWDisplayPair],
        variants: [RAWDisplayVariant], cameraVariants: [CameraPreviewVariant],
        options: RAWDisplayOptions, bestScreen: DisplayVariantSummary?,
        bestGrid: DisplayVariantSummary?
    ) -> [String: String] {
        [
            "folderName": folder.lastPathComponent,
            "rawFiles": String(pairs.count),
            "rawFilesWithCameraPreview": String(pairs.filter { $0.cameraPreview != nil }.count),
            "detailedRawFiles": String(detailed.count),
            "cameraPreviewPairs": String(cameraPairs.count),
            "colourFiles": String(colourPairs.count),
            "warmRepeats": String(options.warmRepeats),
            "screenLongEdge": String(options.screenLongEdge),
            "gridLongEdge": String(options.gridLongEdge),
            "screenLongEdgeSource":
                "passed in by the Lab app (screen nativeBounds long edge, px)",
            "variantOrder": variants.map(\.name).joined(separator: ","),
            "cameraVariantOrder": cameraVariants.map(\.name).joined(separator: ","),
            "bestScreenVariant": bestScreen?.name ?? "none",
            "bestGridVariant": bestGrid?.name ?? "none",
            "variantRule": "lowest median of warm render times with samples",
            "scaleMethod":
                "CIRAWFilter.scaleFactor set before outputImage; no render-then-downscale",
            "memory": "5 ms process RSS samples; lower bound",
            "percentile": "nearest-rank; p90 of 3 repeats is the largest of the three",
            "colourMetric": "CIEDE2000",
            "colourSampling": "same-sized sRGB bitmaps, lattice of at most 4096 pixels",
            "colourReference": "larger image reduced after render with CILanczosScaleTransform",
            "order": "sorted path; variants serial per file; cold is first use in this run",
        ]
    }

    private static func notes(options: RAWDisplayOptions) -> [String] {
        [
            "Times end at a materialized CPU bitmap, not on-screen presentation or UI scrolling.",
            "scaleFactor and isDraftModeEnabled are decode-time requests set before outputImage; the report records output size and time, not which decoder stage applied them.",
            "Screen and grid variants use CIRAWFilter.scaleFactor. They do not render at native size and downscale, which is what S2's 2000 px row measured.",
            "Cold means the first render of that variant in this run, in a process that may already have rendered other variants of the same file; it is not a cold process, framework cache or card read.",
            "Warm median and p90 come from \(options.warmRepeats) repeats per file; nearest-rank p90 of 3 is the largest of the three.",
            "Camera HEIF variants are ImageIO decodes of the HIF, not CIRAWFilter controls; full decode is the 100% source for camera-preview mode.",
            "Colour numbers compare same-sized sRGB bitmaps with CIEDE2000; the larger reference is Lanczos-reduced after render, so they measure colour plus resampling, not sharpness.",
            "Resident memory is process-wide 5 ms sampling: a lower bound that includes framework caches and other work, not an isolated allocation.",
            "Detailed RAW renders use the first \(options.detailedFiles) RAWs; camera HEIF variants use \(options.cameraPreviewPairs) pairs; swipes use \(options.swipePhotos) photos; nothing reads a whole folder into memory.",
            "The grid folder projection is arithmetic on one measured render time; the concurrency-2 row assumes perfect division and was not measured concurrently.",
            "Run on the physical device, charger unplugged, at room temperature; simulator and Mac numbers are not device numbers.",
        ]
    }
}
