import Foundation

/// One bounded stage of a sharpness analysis. A scheduler admits each stage separately, so
/// heavy work keeps its own budget and priorities are reconsidered between a photo's stages
/// (#216).
public enum SharpnessAnalysisStage: String, CaseIterable, Hashable, Sendable {
    /// The primary file's ImageIO property read that locates camera-AF regions. Bounded on
    /// its own so a folder-wide background submit does not fan out one read per photo at
    /// once (#216's bounded budgets).
    case metadataRead
    /// One Vision face and eye localization over the photo's preview.
    case faceDetection
    /// The single high-resolution pixel acquisition every region of the photo shares.
    case pixelAcquisition
    /// One batch of local sharpness scoring over located regions.
    case regionScoring
}

/// Per-stage admission for ``RegionSharpnessAnalyzer``. The analyzer calls ``enter(_:)``
/// before a bounded stage's work and ``exit(_:)`` after it, so a scheduler can bound how
/// much work runs at once, reconsider priorities whenever a slot frees, and refuse admission
/// for work that became obsolete (#216).
///
/// ``enter(_:)`` throws `CancellationError` when the stage must not run; the analysis stops
/// at that boundary instead of returning a result a caller could publish.
public protocol RegionSharpnessStageGate: Sendable {
    func enter(_ stage: SharpnessAnalysisStage) async throws
    func exit(_ stage: SharpnessAnalysisStage) async
}

/// The gate the ungated entry point uses: admission always succeeds, so an analysis without
/// a scheduler behaves exactly as it did before stages could be bounded (#215's behavior).
struct UngatedSharpnessStage: RegionSharpnessStageGate {
    func enter(_ stage: SharpnessAnalysisStage) async throws {}

    func exit(_ stage: SharpnessAnalysisStage) async {}
}
