import Foundation
import LabSupport

/// The sustained-load step: the best screen-size RAW variant, back to back, bounded
/// by the brief's five minutes or 300 renders.
public struct RAWDisplaySustainedPlan: Sendable {
    public var file: URL
    public var variant: RAWDisplayVariant
    public var maximumRenders: Int
    public var maximumSeconds: Double
    /// Battery level in percent, read in the Lab app layer so this module stays UIKit-free.
    public var batteryStartPercent: Double?

    public init(
        file: URL, variant: RAWDisplayVariant, maximumRenders: Int = 300,
        maximumSeconds: Double = 300, batteryStartPercent: Double? = nil
    ) {
        self.file = file
        self.variant = variant
        self.maximumRenders = maximumRenders
        self.maximumSeconds = maximumSeconds
        self.batteryStartPercent = batteryStartPercent
    }
}

/// Runs the sustained load and reports each render, thermal transitions and the
/// battery level at the start.
public enum RAWDisplaySustainedLoad {
    /// Renders until the render or duration bound is reached, whichever comes first.
    /// The duration bound is checked before each render, so one render can run past it.
    public static func run(
        plan: RAWDisplaySustainedPlan, measuring: any RAWDisplayMeasuring,
        step: (String) async -> Void = { _ in }
    ) async throws -> [LabMeasurement] {
        let start = ContinuousClock.now
        var measurements: [LabMeasurement] = []
        let baseTags: [String: String] = [
            "variant": plan.variant.name, "file": plan.file.lastPathComponent,
            "scaleMethod": plan.variant.scaleMethod,
            "requestedLongEdge": String(plan.variant.requestedLongEdge),
            "bounds": "\(plan.maximumRenders) renders or \(Int(plan.maximumSeconds)) s",
        ]
        if let battery = plan.batteryStartPercent {
            measurements.append(
                LabMeasurement(
                    name: "battery-start", value: battery, unit: "percent",
                    tags: baseTags.merging(["source": "UIDevice batteryLevel"]) { _, new in new }))
        }
        var thermal = ProcessInfo.processInfo.thermalState
        measurements.append(
            LabMeasurement(
                name: "thermal-start", value: 0, unit: "s",
                tags: baseTags.merging(["state": thermalName(thermal)]) { _, new in new }))
        var renders = 0
        while renders < plan.maximumRenders,
            displayMilliseconds(since: start) / 1_000 < plan.maximumSeconds
        {
            try Task.checkCancellation()
            await step("Sustained render \(renders + 1)")
            let timing = try measuring.renderRAW(url: plan.file, variant: plan.variant)
            renders += 1
            measurements.append(
                LabMeasurement(
                    name: "sustained-render", value: timing.milliseconds, unit: "ms",
                    tags: [
                        "index": String(renders), "thermal": thermalName(thermal),
                        "status": timing.error ?? "ok",
                        "outputLongEdge": String(max(timing.width, timing.height)),
                    ]))
            let state = ProcessInfo.processInfo.thermalState
            if state != thermal {
                measurements.append(
                    LabMeasurement(
                        name: "thermal-change",
                        value: displayMilliseconds(since: start) / 1_000, unit: "s",
                        tags: [
                            "from": thermalName(thermal), "to": thermalName(state),
                            "render": String(renders),
                        ]))
                thermal = state
            }
        }
        measurements += [
            LabMeasurement(
                name: "sustained-renders", value: Double(renders), unit: "count", tags: baseTags),
            LabMeasurement(
                name: "sustained-duration", value: displayMilliseconds(since: start), unit: "ms",
                tags: baseTags),
            LabMeasurement(
                name: "thermal-end", value: displayMilliseconds(since: start) / 1_000, unit: "s",
                tags: baseTags.merging(["state": thermalName(thermal)]) { _, new in new }),
        ]
        return measurements
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
