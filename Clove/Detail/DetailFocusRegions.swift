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
        accessibilityName(language: .english)
    }

    func accessibilityName(language: ResolvedAppLanguage) -> String {
        switch self {
        case .autofocus: AppLocalization.string("Autofocus region", language: language)
        case .face: AppLocalization.string("Face region", language: language)
        case .eye: AppLocalization.string("Eye region", language: language)
        }
    }
}

/// One advisory focus marker on the displayed photo. Located regions are inspectable unless
/// an explicit unavailability reason or degenerate geometry prevents it; no score or focus
/// percentage reaches the interface.
struct DetailFocusRegion: Hashable, Identifiable, Sendable {
    /// Proximity margin in normalized image coordinates used to detect local AF collisions with
    /// analysis markers without using 44 pt touch padding.
    static let localOverlapMargin: Double = 0.015

    let id: String
    let kind: DetailFocusRegionKind
    let groupIndex: Int?
    let region: NormalizedRegion
    let unavailableReason: String?

    var isActionable: Bool { unavailableReason == nil }

    var centre: UnitPoint {
        UnitPoint(x: region.centerX, y: region.centerY)
    }

    init(id: String, evidence: RegionSharpnessEvidence) {
        self.id = id
        kind = DetailFocusRegionKind(evidence.kind)
        groupIndex = evidence.groupIndex
        region = evidence.region
        unavailableReason =
            evidence.unavailableBecause?.rawValue
            ?? evidence.region.normalizedUnavailability?.rawValue
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

    /// Compact normalized footprint of the visible marker rather than enlarged eye measurement
    /// ROIs or expanded 44 pt touch targets.
    var normalizedMarkerRect: CGRect {
        switch kind {
        case .autofocus, .face:
            return CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
        case .eye:
            let side = min(max(min(region.width, region.height), 0.025), 0.04)
            return CGRect(
                x: region.centerX - side / 2,
                y: region.centerY - side / 2,
                width: side,
                height: side)
        }
    }

    /// Deterministic local collision/containment check between a camera AF marker and an analysis
    /// marker in normalized image space.
    func collidesLocally(with analysisMarker: DetailFocusRegion) -> Bool {
        let afRect = normalizedMarkerRect.insetBy(
            dx: -Self.localOverlapMargin, dy: -Self.localOverlapMargin)
        return afRect.intersects(analysisMarker.normalizedMarkerRect)
    }

    var unavailableAccessibilityDescription: String? {
        unavailableAccessibilityDescription(language: .english)
    }

    func unavailableAccessibilityDescription(language: ResolvedAppLanguage) -> String? {
        guard let unavailableReason else { return nil }
        switch unavailableReason {
        case RegionScoreUnavailable.regionTooSmall.rawValue:
            return AppLocalization.string("Unavailable: region too small", language: language)
        case RegionScoreUnavailable.regionOutsideImage.rawValue:
            return AppLocalization.string("Unavailable: outside the image", language: language)
        case RegionScoreUnavailable.pixelsUnavailable.rawValue:
            return AppLocalization.string("Unavailable: pixels unavailable", language: language)
        case RegionScoreUnavailable.staleSource.rawValue:
            return AppLocalization.string("Unavailable: photo changed", language: language)
        default:
            return AppLocalization.string("Unavailable", language: language)
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

    /// All retained evidence mapped to presentation values before per-person and overlap filtering.
    var retainedRegions: [DetailFocusRegion] {
        var result: [DetailFocusRegion] = []
        if let autofocus { result.append(contentsOf: Self.regions(from: autofocus, path: "af")) }
        if let faces { result.append(contentsOf: Self.regions(from: faces, path: "face")) }
        return result
    }

    /// Selected camera-style overlay presentation:
    /// 1. Keep camera AF markers from metadata (never fabricated).
    /// 2. Per person (`groupIndex`), keep at most one deterministically chosen usable eye and omit
    ///    that person's face frame; fall back to that person's face frame when no usable eye exists.
    /// 3. Suppress only analysis markers that locally collide with camera AF in normalized marker
    ///    geometry, leaving separated AF and unrelated subjects visible.
    var regions: [DetailFocusRegion] {
        let afRegions = autofocus.map { Self.regions(from: $0, path: "af") } ?? []
        let faceRegions = faces.map { Self.regions(from: $0, path: "face") } ?? []
        let selectedAnalysis = Self.selectPerPerson(from: faceRegions)
        let filteredAnalysis = Self.suppressLocalOverlaps(
            analysis: selectedAnalysis, against: afRegions)
        return afRegions + filteredAnalysis
    }

    /// Presentation filtered by the session visibility toggle and active focused inspection.
    func regions(visible: Bool, inspectedRegionID: String?) -> [DetailFocusRegion] {
        guard visible else { return [] }
        let presented = regions
        if let inspectedRegionID,
            let inspected = presented.first(where: { $0.id == inspectedRegionID })
        {
            return [inspected]
        }
        return presented
    }

    /// Selects the most relevant actionable focus region for a double-tap at `anchor`, or `nil`
    /// when no actionable regions are presented (so double-tap zooms to the tap point).
    ///
    /// Order: active inspected region, then camera AF, then the presented per-person eye/face
    /// regions. Multiple candidates in the winning tier resolve deterministically to the region
    /// nearest `anchor`, breaking ties by presentation order.
    func preferredDoubleTapRegion(
        at anchor: UnitPoint,
        visible: Bool,
        inspectedRegionID: String?
    ) -> DetailFocusRegion? {
        let candidates = regions(visible: visible, inspectedRegionID: nil).filter(\.isActionable)
        guard !candidates.isEmpty else { return nil }
        if let inspectedRegionID,
            let inspected = candidates.first(where: { $0.id == inspectedRegionID })
        {
            return inspected
        }
        let autofocusRegions = candidates.filter { $0.kind == .autofocus }
        let pool = autofocusRegions.isEmpty ? candidates : autofocusRegions
        return pool.enumerated().min { lhs, rhs in
            let lhsDistance = Self.squaredDistance(from: anchor, to: lhs.element.centre)
            let rhsDistance = Self.squaredDistance(from: anchor, to: rhs.element.centre)
            if abs(lhsDistance - rhsDistance) > 1e-9 {
                return lhsDistance < rhsDistance
            }
            return lhs.offset < rhs.offset
        }?.element
    }

    private static func squaredDistance(from first: UnitPoint, to second: UnitPoint) -> Double {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }

    var resultIndicators: DetailFocusResultIndicators {
        guard !analysisUnavailable else {
            return DetailFocusResultIndicators(face: nil, missingAutofocusMetadata: false)
        }
        let face: DetailFocusFaceIndicator? =
            switch faces {
            case .regions(let items)
            where items.contains(where: { $0.kind == .face || $0.kind == .eye }):
                .detected
            case .unavailable(.noFacesDetected):
                .noFacesDetected
            default:
                nil
            }
        let missingAutofocusMetadata: Bool =
            switch autofocus {
            case .unavailable(.noAutofocusMetadata):
                true
            default:
                false
            }
        return DetailFocusResultIndicators(
            face: face,
            missingAutofocusMetadata: missingAutofocusMetadata)
    }

    func resultIndicators(visible: Bool) -> DetailFocusResultIndicators {
        guard visible else {
            return DetailFocusResultIndicators(face: nil, missingAutofocusMetadata: false)
        }
        return resultIndicators
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

    private static func selectPerPerson(from items: [DetailFocusRegion]) -> [DetailFocusRegion] {
        var grouped: [Int: [DetailFocusRegion]] = [:]
        var ungrouped: [DetailFocusRegion] = []
        for item in items {
            if let groupIndex = item.groupIndex {
                grouped[groupIndex, default: []].append(item)
            } else {
                ungrouped.append(item)
            }
        }
        var selected: [DetailFocusRegion] = []
        for groupIndex in grouped.keys.sorted() {
            let members = grouped[groupIndex] ?? []
            let usableEyes = members.filter { $0.kind == .eye && $0.isActionable }
            if let chosenEye = usableEyes.min(by: eyeSelectionPrecedes) {
                selected.append(chosenEye)
                continue
            }
            let groupFaces = members.filter { $0.kind == .face }
            if let chosenFace = groupFaces.first(where: \.isActionable) ?? groupFaces.first {
                selected.append(chosenFace)
            } else if let fallbackEye = members.first(where: { $0.kind == .eye }) {
                selected.append(fallbackEye)
            }
        }
        selected.append(contentsOf: ungrouped)
        return selected
    }

    /// Stable geometric tie-break among usable eyes for the same person: independent of sharpness
    /// score and invariant across render scales and zoom.
    private static func eyeSelectionPrecedes(_ lhs: DetailFocusRegion, _ rhs: DetailFocusRegion)
        -> Bool
    {
        let leftKey = (
            lhs.region.centerX, lhs.region.centerY, lhs.region.width, lhs.region.height, lhs.id
        )
        let rightKey = (
            rhs.region.centerX, rhs.region.centerY, rhs.region.width, rhs.region.height, rhs.id
        )
        return leftKey < rightKey
    }

    private static func suppressLocalOverlaps(
        analysis: [DetailFocusRegion], against autofocusRegions: [DetailFocusRegion]
    ) -> [DetailFocusRegion] {
        guard !autofocusRegions.isEmpty else { return analysis }
        return analysis.filter { marker in
            let blockingAF =
                marker.isActionable
                ? autofocusRegions.filter(\.isActionable) : autofocusRegions
            return !blockingAF.contains { af in af.collidesLocally(with: marker) }
        }
    }
}

enum DetailFocusFaceIndicator: Equatable, Sendable {
    case detected
    case noFacesDetected

    var systemImageName: String {
        switch self {
        case .detected: "person.fill.viewfinder"
        case .noFacesDetected: "person.slash"
        }
    }

    func accessibilityLabel(language: ResolvedAppLanguage) -> String {
        switch self {
        case .detected:
            AppLocalization.string("Face detected", language: language)
        case .noFacesDetected:
            AppLocalization.string("No faces detected", language: language)
        }
    }
}

struct DetailFocusResultIndicators: Equatable, Sendable {
    let face: DetailFocusFaceIndicator?
    let missingAutofocusMetadata: Bool

    var isEmpty: Bool {
        face == nil && !missingAutofocusMetadata
    }

    func missingAutofocusAccessibilityLabel(language: ResolvedAppLanguage) -> String {
        AppLocalization.string("No autofocus metadata", language: language)
    }

    /// Returns whether the upper-leading indicator badge sits over photo pixels at the current
    /// zoom and fit geometry, so a subtle scrim appears only where icons cover photo pixels.
    static func coversPhotoPixels(
        indicators: DetailFocusResultIndicators,
        scale: CGFloat,
        imagePixels: CGSize?,
        viewSize: CGSize,
        origin: CGPoint = CGPoint(x: 12, y: 8)
    ) -> Bool {
        guard !indicators.isEmpty else { return false }
        if scale > DetailFitScale.tolerance { return true }
        guard let imagePixels, viewSize.width > 0, viewSize.height > 0 else { return false }
        let fitted = DetailZoom.fittedSize(imagePixels: imagePixels, viewSize: viewSize)
        let fittedRect = CGRect(
            x: (viewSize.width - fitted.width) / 2,
            y: (viewSize.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height)
        let badgeWidth: CGFloat =
            (indicators.face != nil && indicators.missingAutofocusMetadata) ? 52 : 30
        let badgeRect = CGRect(origin: origin, size: CGSize(width: badgeWidth, height: 24))
        return fittedRect.intersects(badgeRect)
    }
}

struct SlashedViewfinderGlyph: View {
    var body: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 16, weight: .medium))
            .overlay {
                Canvas { context, size in
                    let inset = min(size.width, size.height) * 0.14
                    var path = Path()
                    path.move(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
                    context.blendMode = .destinationOut
                    context.stroke(
                        path,
                        with: .color(.black),
                        style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                    context.blendMode = .normal
                    context.stroke(
                        path,
                        with: .foreground,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            .compositingGroup()
    }
}

struct DetailFocusResultIndicatorsView: View {
    let indicators: DetailFocusResultIndicators
    let usesPhotoBacking: Bool
    let language: ResolvedAppLanguage

    var body: some View {
        HStack(spacing: 6) {
            if let face = indicators.face {
                Image(systemName: face.systemImageName)
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(face.accessibilityLabel(language: language))
                    .accessibilityIdentifier("clove.detail.focusIndicator.face")
            }
            if indicators.missingAutofocusMetadata {
                SlashedViewfinderGlyph()
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(
                        indicators.missingAutofocusAccessibilityLabel(language: language)
                    )
                    .accessibilityIdentifier("clove.detail.focusIndicator.autofocus")
            }
        }
        .foregroundStyle(
            usesPhotoBacking
                ? AnyShapeStyle(Color.clove.focus.outline)
                : AnyShapeStyle(Color.clove.text.primary)
        )
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            if usesPhotoBacking {
                Capsule()
                    .fill(Color.clove.focus.edge)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.focusIndicators")
        .reportHeaderControlFrame("clove.detail.focusIndicators")
    }
}
