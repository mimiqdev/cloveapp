import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import SwiftUI

/// The folder-bound analysis surface detail uses. Production joins the folder's scheduler;
/// the generated library supplies deterministic regions without files or a decode.
@MainActor
protocol DetailRegionSharpnessSource: AnyObject {
    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis?

    func closeRegionAnalysis() async
}

extension DetailRegionSharpnessSource {
    func closeRegionAnalysis() async {}
}

/// The overlay kinds are view values rather than another analysis-domain concept.
enum DetailFocusRegionKind: String, Hashable, Sendable {
    case autofocus
    case face
    case eye

    init(_ kind: SharpnessRegionKind) {
        switch kind {
        case .cameraAutofocus: self = .autofocus
        case .face: self = .face
        case .eye: self = .eye
        }
    }

    var accessibilityName: String {
        switch self {
        case .autofocus: "Autofocus region"
        case .face: "Face region"
        case .eye: "Eye region"
        }
    }
}

/// One advisory rectangle on the displayed photo. A score only decides whether the region can
/// be inspected; no score or focus percentage reaches the interface.
struct DetailFocusRegion: Hashable, Identifiable, Sendable {
    let id: String
    let kind: DetailFocusRegionKind
    let region: NormalizedRegion
    let unavailableReason: String?

    var isActionable: Bool { unavailableReason == nil }

    var centre: UnitPoint {
        UnitPoint(x: region.centerX, y: region.centerY)
    }

    init(id: String, evidence: RegionSharpnessEvidence) {
        self.id = id
        kind = DetailFocusRegionKind(evidence.kind)
        region = evidence.region
        unavailableReason =
            evidence.unavailableBecause?.rawValue ?? (evidence.score == nil ? "unknown" : nil)
    }

    /// Maps normalized displayed-image coordinates through the same aspect-fit rectangle the
    /// preview uses. The returned rectangle is in the fitted image view's coordinate space.
    func rect(in fittedImage: CGRect) -> CGRect {
        CGRect(
            x: fittedImage.minX + region.x * fittedImage.width,
            y: fittedImage.minY + region.y * fittedImage.height,
            width: region.width * fittedImage.width,
            height: region.height * fittedImage.height)
    }

    var unavailableAccessibilityDescription: String? {
        guard let unavailableReason else { return nil }
        switch unavailableReason {
        case RegionScoreUnavailable.regionTooSmall.rawValue:
            return "Unavailable: region too small"
        case RegionScoreUnavailable.regionOutsideImage.rawValue:
            return "Unavailable: outside the image"
        case RegionScoreUnavailable.pixelsUnavailable.rawValue:
            return "Unavailable: pixels unavailable"
        case RegionScoreUnavailable.staleSource.rawValue:
            return "Unavailable: photo changed"
        default:
            return "Unavailable"
        }
    }
}

/// Result-to-presentation transitions for one photo. The photo identity rejects an early-AF or
/// final answer that arrives after navigation; the source's scheduler supplies the stronger
/// folder-session and revision checks.
struct DetailFocusRegionState {
    private(set) var photo: PhotoIdentity?
    private var autofocus: RegionSharpnessPathResult?
    private var faces: RegionSharpnessPathResult?
    private var isAnalyzing = false
    private var analysisUnavailable = false

    var regions: [DetailFocusRegion] {
        var result: [DetailFocusRegion] = []
        if let autofocus { result.append(contentsOf: Self.regions(from: autofocus, path: "af")) }
        if let faces { result.append(contentsOf: Self.regions(from: faces, path: "face")) }
        return result
    }

    var status: String? {
        if analysisUnavailable { return "Analysis unavailable" }
        var messages: [String] = []
        if let autofocus, case .unavailable(let reason) = autofocus {
            if case .noAutofocusMetadata = reason { messages.append("No AF metadata") }
        }
        if let faces, case .unavailable(let reason) = faces {
            switch reason {
            case .noFacesDetected:
                messages.append("No faces")
            case .faceDetectionFailed, .previewFailed:
                messages.append("Face analysis unavailable")
            case .noAutofocusMetadata:
                break
            }
        }
        if isAnalyzing {
            messages.append(autofocus == nil ? "Analyzing focus regions…" : "Analyzing faces…")
        }
        if regions.contains(where: { $0.unavailableReason != nil }) {
            messages.append(
                regions.contains {
                    $0.unavailableReason == RegionScoreUnavailable.regionTooSmall.rawValue
                }
                    ? "Tiny focus region unavailable" : "Focus region unavailable")
        }
        return messages.isEmpty ? nil : messages.joined(separator: " · ")
    }

    mutating func begin(for photo: PhotoIdentity) {
        self.photo = photo
        autofocus = nil
        faces = nil
        isAnalyzing = true
        analysisUnavailable = false
    }

    mutating func receiveAutofocus(
        _ result: RegionSharpnessPathResult, for photo: PhotoIdentity
    ) {
        guard self.photo == photo, isAnalyzing else { return }
        autofocus = result
    }

    mutating func finish(_ analysis: RegionSharpnessAnalysis?, for photo: PhotoIdentity) {
        guard self.photo == photo else { return }
        isAnalyzing = false
        guard let analysis else {
            autofocus = nil
            faces = nil
            analysisUnavailable = true
            return
        }
        autofocus = analysis.autofocus
        faces = analysis.faces
    }

    private static func regions(
        from result: RegionSharpnessPathResult, path: String
    ) -> [DetailFocusRegion] {
        guard case .regions(let evidence) = result else { return [] }
        return evidence.enumerated().map { index, evidence in
            let group = evidence.groupIndex.map { "-\($0)" } ?? ""
            return DetailFocusRegion(
                id: "clove.detail.region.\(path).\(index)\(group)", evidence: evidence)
        }
    }
}
