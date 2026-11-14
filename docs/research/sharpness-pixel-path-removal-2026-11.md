# Sharpness Pixel-Path Removal Feasibility Memo (#274)

- **Date:** 2026-11-14
- **Baseline revision:** `05293a1` (`main`)
- **Related issue:** [#274](https://github.com/mimiqdev/cloveapp/issues/274)
- **Triggering product decision:** A sharpness score's only current consumer is `DetailFocusRegion.isActionable`; the owner has decided to defer sharpness scoring until a future AI-analysis feature. Region localization stays as-is (camera AF metadata without decode + Vision face/eye on the `800 px` preview), and 100% inspection already decodes full size on demand.

## Executive Conclusion

**Removing `pixelAcquisition` and `regionScoring` from presentation focus analysis is immediately feasible with zero UI regression and no hidden dependency from the 100% zoom path.**

- **Eliminates the `#274` bottleneck directly:** Drops 100% of analysis-triggered full-sensor `CIRAWFilter` `nativeRAW` / `fullRaster` decodes (`382–484 ms` measured on 20–26 MP RAWs; `~750–1,100+ ms` projected on 50 MP Sony ARW), freeing `DetailPipeline`'s sole `.render` worker exclusively for interactive `screenRAW`, `+1` `prefetchScreen`, and on-demand 100% zoom.
- **No A/B/C concurrency harness work needed:** Because presentation analysis no longer reads `.render`-lane pixels, two-lane concurrency vs. half-resolution analysis decode no longer applies until the future AI-analysis feature.
- **Fixes two side bugs for free:** Eliminates `DetailCache.state.native` single-slot eviction caused by background `.group`/`.nearby` `analysisImage` calls, and stops unwanted `nativeRAW` decodes under `.cameraPreviewFirst` caused by `DetailRegionSharpnessReading`'s hardcoded `.rawFirst` `DetailRequest`.

---

## 1. What Stops Running, UI Regression Check & `#239` Cache Schema

### 1.1 Execution Diff in `RegionSharpnessAnalyzer`

| Stage | Current behavior | After removal | Citations |
| :--- | :--- | :--- | :--- |
| `.metadataRead` | ImageIO properties + `AutofocusMetadataReader` / `CloveFocusMetadata` (`1–3 ms`, no decode) | **Stays.** Delivers `onAutofocus` immediately after `.metadataRead` for both `.success` and `.failure`, removing `#261`'s split zero-region branch | [`RegionSharpnessAnalyzer.swift:153-209`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L153-L209) |
| `.faceDetection` | `DetailPipeline.analysisPreview` (`effort: .previewOnly, priority: .analysis, usePreviewHeader: true`) on `.preview` lane (`previewWorkers = 2`), downsampled to `800 px` + `VisionFaceRegionDetector` | **Stays.** Zero `.render`-lane work; opportunistically warms compressed preview cache for swipes | [`DetailRegionSharpnessReading.swift:36-40`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/DetailRegionSharpnessReading.swift#L36-L40), [`DetailPipeline.swift:180-188`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailPipeline.swift#L180-L188), [`DetailPipeline.swift:591-595`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailPipeline.swift#L591-L595) |
| `.pixelAcquisition` | `DetailRegionSharpnessReading.highResolution` → `DetailPipeline.analysisImage` (`effort: .best`, `.render` lane full `nativeRAW` / `fullRaster`) | **Stops.** `DetailPipeline.analysisImage` is never called during browsing | [`RegionSharpnessAnalyzer.swift:275-294`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L275-L294), [`DetailPipeline.swift:192-200`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailPipeline.swift#L192-L200) |
| `.regionScoring` | `RegionSharpnessScorer.score` Sobel Tenengrad pass (`CGContext` up to `512×512`) | **Stops.** Geometric validation runs inline without pixel buffers | [`RegionSharpnessAnalyzer.swift:337-359`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L337-L359), [`RegionSharpnessScorer.swift:21-53`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessScorer.swift#L21-L53) |

### 1.2 Zero UI Regression Check (`DetailFocusRegions` & `RegionScoreUnavailable`)

1. **Critical catch — `score == nil` fallback in `DetailFocusRegion.init`:**
   [`DetailFocusRegion.init`](../../Clove/Detail/DetailFocusRegions.swift#L71-L78) currently maps:
   ```swift
   unavailableReason =
       evidence.unavailableBecause?.rawValue ?? (evidence.score == nil ? "unknown" : nil)
   ```
   Simply omitting scoring (`score: nil, unavailableBecause: nil`) would fall into `"unknown"` and render **every** AF, face, and eye marker `isActionable == false`:
   - `focusRegionTapped` becomes a no-op ([`DetailMarkingView.swift:1151-1155`](../../Clove/Detail/DetailMarkingView.swift#L1151-L1155));
   - `preferredDoubleTapRegion` filters out every region ([`DetailFocusRegions.swift:187-188`](../../Clove/Detail/DetailFocusRegions.swift#L187-L188));
   - `selectPerPerson` loses `usableEyes` preference ([`DetailFocusRegions.swift:294`](../../Clove/Detail/DetailFocusRegions.swift#L294));
   - `status` appends `"Focus region unavailable"` ([`DetailFocusRegions.swift:232-238`](../../Clove/Detail/DetailFocusRegions.swift#L232-L238)).

   **Required fix:** Change line 76–77 to `unavailableReason = evidence.unavailableBecause?.rawValue`. No numeric score or focus percentage is displayed anywhere in UI ([`DetailFocusRegions.swift:52-53`](../../Clove/Detail/DetailFocusRegions.swift#L52-L53)), and `eyeSelectionPrecedes` already breaks ties purely by normalized geometry ([`DetailFocusRegions.swift:310-322`](../../Clove/Detail/DetailFocusRegions.swift#L310-L322)).

2. **Preserving `RegionScoreUnavailable` semantics purely geometrically:**
   - **`.regionOutsideImage`:** Currently checked via [`NormalizedRegion.pixelRect(in:)`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessTypes.swift#L47-L55). Without decoded pixels, check directly in normalized `[0, 1] × [0, 1]` space: a region is `.regionOutsideImage` when `width <= 0 || height <= 0` or its intersection with `CGRect(x: 0, y: 0, width: 1, height: 1)` has non-positive width or height.
   - **`.regionTooSmall`:** Previously required `rect.width >= 3 && rect.height >= 3` against full-res pixel dimensions ([`RegionSharpnessAnalyzer.swift:445-450`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L445-L450)). Replace with a normalized edge threshold `region.width >= minimumNormalizedEdge && region.height >= minimumNormalizedEdge`. Choosing `0.003` (`0.3%` of frame width/height ≈ `26 px` on a 50 MP 8,640 px sensor, `16–18 px` on 20–24 MP, `8 px` on 5 MP) keeps real AF spots (`0.02–0.12`) and eyes (`0.03–0.05`) actionable while marking degenerate boxes (`0.001–0.002` in existing tests) `.regionTooSmall`, preserving `"Tiny focus region unavailable"` and `"Unavailable: region too small"` ([`DetailFocusRegions.swift:117-118, 234-237`](../../Clove/Detail/DetailFocusRegions.swift#L117-L118)). Note [`SampleDetailImages.swift:251-257`](../../Clove/Detail/SampleDetailImages.swift#L251-L257) (`MMQ02679.ARW`, `0.01 × 0.01`) hardcodes `unavailableBecause: .regionTooSmall` directly for UI test `testDetailFocusRegionsCentreNativeZoom`, so UI tests remain unaffected.
   - **`.pixelsUnavailable` / `.staleSource`:** Presentation analysis will no longer emit these (preview failures remain `.unavailable(.previewFailed(...))` on the `.faces` path). Keep enum cases/accessibility switch arms in [`DetailFocusRegions.swift:121-124`](../../Clove/Detail/DetailFocusRegions.swift#L121-L124) if older records can still decode, or prune them with a `payloadVersion` bump.

### 1.3 `#239` Disk Cache Schema Compatibility

[`RegionSharpnessPayload`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessCache.swift#L61-L68) and [`RegionSharpnessEvidence`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessTypes.swift#L129-L151) already type every removed output as optional:
- `RegionSharpnessEvidence.score: RegionSharpnessScore?`
- `RegionSharpnessEvidence.unavailableBecause: RegionScoreUnavailable?`
- `RegionSharpnessAnalysis.acquisitionFailure: RegionImageFailure?`
- `RegionSharpnessTimings.pixelAcquisition` / `.regionScoring: ContinuousClock.Duration?`

Storing coordinate-only records (`score: nil`, `unavailableBecause: nil` or geometric `.regionTooSmall`/`.regionOutsideImage`, `acquisitionFailure: nil`) is **already wire-compatible** with `#239`'s JSON schema.

**Recommendation:** Bump `RegionSharpnessScheduler.parametersVersion` (`1 → 2` at [`RegionSharpnessScheduler.swift:176`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessScheduler.swift#L176)) — or `RegionSharpnessCache.Configuration.payloadVersion` (`1 → 2` at [`RegionSharpnessCache.swift:83`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessCache.swift#L83)). Because [`RegionSharpnessCache.isPersistable`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessCache.swift#L233-L239) persists prior `.cannotOpen`/`.noUsablePreview` `acquisitionFailure` records whose regions carry `unavailableBecause: .pixelsUnavailable`, old disk entries on test devices would otherwise resurface `"Focus region unavailable"`. Bumping `parametersVersion` immediately invalidates those entries and provides a clean `2 → 3` invalidation key later when full-res AI scoring is added.

---

## 2. Audit of Everything `pixelAcquisition` Currently Gates

| Surface | Does `pixelAcquisition` gate it? | Impact of removal | Citations |
| :--- | :--- | :--- | :--- |
| **100% zoom / region tap inspection** | **No.** `focusRegionTapped` → `inspectFullResolution(at:)` → `upgrade(need: .fullResolution)` → `DetailPipeline.image(for:)` (`effort: .best, priority: .visible`) decodes `fullRaster` / `nativeRAW` on demand. | **Improves zoom.** `analysisImage` writes to `DetailCache.state.native` (capacity = **1 photo** globally), and `DetailPipeline.perform` calls `cache.releaseNative()` before every `.best` render (`lines 611, 657, 686`). Background `.group`/`.nearby` `analysisImage` runs currently *evict* the active photo's held 100% image; removing `analysisImage` eliminates that eviction. Also avoids unused `.rawFirst` decodes under `.cameraPreviewFirst`. | [`DetailMarkingView.swift:1151-1208`](../../Clove/Detail/DetailMarkingView.swift#L1151-L1208), [`DetailPipeline.swift:168-176, 610-675`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailPipeline.swift#L610-L675), [`DetailCache.swift:97`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailCache.swift#L97), [`DetailRegionSharpnessReading.swift:54-59`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/DetailRegionSharpnessReading.swift#L54-L59) |
| **`DetailCache.nativeSizes` (`100%` target scale)** | **No.** `analysisImage` writes `nativeSize` at `line 674`, but `screen()` (`usePreviewHeader: false`) and `preview()` (`usePreviewHeader: true`) already populate `nativeSizes` independently via `DetailNativeSizeReading`, and 100% zoom updates it on decode. | Zero regression on zoom scale computation. | [`DetailPipeline.swift:587-595, 674, 782-809`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailPipeline.swift#L782-L809) |
| **Interactive acquisition pause seam** | **Yes (only consumer).** `DetailMarkingView.loadPreview` brackets arrival with `beginInteractiveRender()` / `endInteractiveRender(_:)` to pause `.pixelAcquisition` in `RegionSharpnessScheduler`. | Safe to delete completely (`DetailFocusRegions`, `PipelineDetailImages`, `DetailMarkingView`, `RegionSharpnessScheduler.interactivePauseTokens` / `interactiveWaiters`). | [`DetailMarkingView.swift:737-742`](../../Clove/Detail/DetailMarkingView.swift#L737-L742), [`DetailFocusRegions.swift:18-25`](../../Clove/Detail/DetailFocusRegions.swift#L18-L25), [`PipelineDetailImages.swift:375-382`](../../Clove/Detail/PipelineDetailImages.swift#L375-L382), [`RegionSharpnessScheduler.swift:129-157, 468-486, 517-526`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessScheduler.swift#L129-L157) |
| **`DetailPipeline` `.render`-lane `.analysis` rules** | **Yes (only consumer).** `analysisImage`, `beginNavigation(_:keepingAnalysisFor:)`, `navigate`, and `queueLimit` victim selection carry special `.analysis` logic solely for `analysisImage` (`analysisPreview` runs on `.preview`, not `.render`). | `.render` simplifies to `.visible` + `.prefetch` only (`analysisPreview` keeps `.preview`-lane priority `.analysis`). | [`DetailPipeline.swift:118, 131-137, 192-200, 338, 349`](../../Packages/CloveImaging/Sources/CloveImaging/Detail/DetailPipeline.swift#L118-L140) |
| **`RegionSharpnessScheduler` stage budgets & `#261` control flow** | **Yes.** `acquisitionWorkers = 1`, `scoringWorkers = 2`, `SharpnessAnalysisStage.pixelAcquisition`/`.regionScoring`, and `#261`'s `autofocus == .failure` zero-region split before `acquirePixels`. | Simplifies `analyzeGated` back to a single `.metadataRead` → immediate `onAutofocus` → `.faceDetection` → geometric validation flow. | [`SharpnessAnalysisStage.swift:13-17`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/SharpnessAnalysisStage.swift#L13-L17), [`RegionSharpnessScheduler.swift:173-189`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessScheduler.swift#L173-L189), [`RegionSharpnessAnalyzer.swift:161-261`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L161-L261) |
| **`OSSignposter` & `CloveLabKit`** | **`CloveLabKit` has no dependency.** `BrowsingPerformanceProbe` never invokes `RegionSharpness*` or `analysisImage`. Only `SharpnessPixelAcquisition` / `SharpnessRegionScoring` signposts and `docs/browsing-performance.md` reference them. | Remove dead signpost intervals and doc names alongside code cleanup. | [`RegionSharpnessAnalyzer.swift:282, 344`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L282), [`browsing-performance.md:122-125`](../browsing-performance.md#L122-L125) |

---

## 3. Removal Plan: Implementation-Issue Outlines & Test Matrix

### 3.1 Proposed Implementation Issues

1. **`[UI / Focus] Decouple DetailFocusRegion actionability from sharpness score`**
   Remove the `evidence.score == nil` `"unknown"` fallback in [`DetailFocusRegion.init`](../../Clove/Detail/DetailFocusRegions.swift#L76-L77) so located AF, face, and eye regions remain tappable and double-tap-selectable without scores, and add normalized bounds/size validation helpers.
2. **`[Perf R2 / Focus] Skip pixel acquisition and scoring in presentation region analysis`**
   Remove `.pixelAcquisition` and `.regionScoring` from [`RegionSharpnessAnalyzer.analyzeGated`](../../Packages/CloveImaging/Sources/CloveImaging/Sharpness/RegionSharpnessAnalyzer.swift#L142-L261), fire `onAutofocus` immediately after `.metadataRead` for both `.success` and `.failure`, validate `.regionTooSmall`/`.regionOutsideImage` in normalized coordinates, and bump `RegionSharpnessScheduler.parametersVersion` (`1 → 2`) to invalidate persisted `.pixelsUnavailable` `#239` entries.
3. **`[Cleanup / Imaging] Remove DetailPipeline.analysisImage and interactive acquisition pause seam`**
   Delete `DetailPipeline.analysisImage`, `.render`-lane `.analysis` queue special cases, `DetailRegionSharpnessReading.highResolution`, and `beginInteractiveRender` / `beginInteractiveAcquisitionPause` across `DetailMarkingView`, `PipelineDetailImages`, `DetailFocusRegions`, `RegionSharpnessScheduler`, and `SharpnessAnalysisStage`.
4. **`[Cleanup / Docs] Retire RegionSharpnessScorer from presentation and update signpost docs`**
   Delete `RegionSharpnessScorer` (recoverable from git when future AI analysis lands) and remove `SharpnessPixelAcquisition` / `SharpnessRegionScoring` from [`docs/browsing-performance.md`](../browsing-performance.md#L124).

### 3.2 Test Disposition Matrix

| Test file / case | Action | Rationale |
| :--- | :--- | :--- |
| **`CloveImagingTests/Sharpness/RegionSharpnessScorerTests.swift`** | **Split: Keep geometric / Delete scorer** | Delete Tenengrad kernel tests (`texturedRegionScoresHigherThanFlatRegion`…`scoringIsDeterministic`, lines `64–140`) with `RegionSharpnessScorer`; keep `NormalizedRegion` orientation/geometry tests (`identityAndHalfTurns`…`displayPointMatchesEveryExifOrientation`, lines `141–220`, moved to `RegionSharpnessTypesTests`). |
| **`RegionSharpnessAnalyzerTests.swift`** | **Update / Prune** | Delete `bothPathsScoreThroughTheSharedScorer`, `oneAcquisitionServesEveryRegion`, `missingAutofocusWithDetectedFacesDetectsBeforeAcquiringPixels`, `failedAcquisitionIsExplicitAndRegionsSayWhy`, `staleAcquisitionMapsToStaleSourcePerRegion`; update `afResultIsDeliveredBeforeFaceDetectionCompletes`, `sonyRegionThroughTheMetadataFallbackIsLocatedAndScored` (located, no score), `tinyDetectedFacesReportTooSmallRatherThanAScore` (normalized size threshold), `timingsRecordEveryStageRan` (no `pixelAcquisition`/`regionScoring`); keep `unavailableAFIsDeliveredEarlyToo`, `missingAutofocusMetadataReportsEvidenceNotAnEmptyRegion`, `failedPreviewFailsOnlyTheFacePath`, `detectionFailureCarriesVisionMessage`. |
| **`DetailRegionSharpnessReadingTests.swift`** | **Update** | Remove `.highResolution(_:)` assertions (lines `34–42`, `66–70`); keep `.preview(_:)` and `.properties(of:)` coverage for raster, `DetailFixtures` formats, and unreadable files. |
| **`RegionSharpnessSchedulerTests.swift`** | **Update / Prune** | Delete `interactivePauseHoldsPixelAcquisitionWithoutBlockingEarlyAFOrDiskHits` and `zeroRegionPhotoSkipsPixelAcquisitionAndStillPersistsDiskRecord` (plus `staleAcquisitionIsNotStored` if `acquisitionFailure` is retired); update `GatedSharpnessReader` and remaining 23 scheduler/priority/cancel/pause/invalidate tests to gate `.preview` / `.properties` instead of `.highResolution`. |
| **`RegionSharpnessCacheTests.swift`** | **Update / Keep** | Update `staleSourceAndContentionNeverPersisted` & `schedulerDoesNotPersistStaleSourceAndRerunsOnReopen` to simulate stale `.previewFailed(.staleSource)` (instead of `highResolutionResult`); keep all 8 disk persistence, LRU, corrupt-file, and `parametersVersion` bump tests. |
| **`AutofocusMetadataReaderTests`**, **`FocusMetaBridgeTests`**, **`RealSonyBridgeTests`**, **`SharpnessFixtureTests`**, **`RegionSharpnessResultStoreTests`** | **Keep** | Pure metadata / Vision preview / in-memory store tests; unaffected by pixel-scoring removal. |
| **`DetailSchedulingTests.swift`** | **Update / Keep** | Delete `beginNavigationCancelsNonMatchingQueuedAnalysisJobs` & `queuedPrefetchBeatsQueuedAnalysisOnRenderLane` (lines `294–341`, tested `analysisImage` on `.render`), or replace with `analysisPreview` `.preview`-lane priority assertions; keep all other `DetailPipeline` tests. |
| **`CloveTests/PipelineFocusRegionTests.swift`** | **Update / Prune** | Update synchronization seams (`fullRasterPaths` → `previewPaths` or face-detection gate) in `openingTheCurrentPhotoDoesNotCancelItsAnalysis`, `navigationCancelsAnalysisForThePhotoLeftBehind`, `changingCurrentPhotoCancelsObsoleteSchedulerWork`, `cancelledViewerNeverReceivesAF...`, `openingAfterNearbyAnalysisDeliversEarlyAFAndCachedRevisits` (assert located region rather than `score != nil`); delete `queuedManualRenderingWinsOverAnalysis`, `laterManualRenderingDoesNotCancelQueuedCurrentAnalysis`, and the pause-count assertions in `detailViewSkipsFocusAnalysisWhenOverlayIsOffAndHoldsPauseDuringFitAndPrefetch` (keep overlay-off skip check). |
| **`CloveTests/DetailFocusRegionTests.swift`** | **Keep + Add 1 case** | Keep all 14 existing tests (helper uses synthetic scores today, unaffected when fallback is removed); add a unit test asserting `DetailFocusRegion(id:evidence:)` with `score: nil, unavailableBecause: nil` is `isActionable == true`. |
| **`CloveTests/LibraryCacheLifetimeTests.swift`**, **`MainActorPerformanceTests.swift`**, **`DetailDisplayPresentationTests.swift`** | **Keep** | None rely on sharpness scores or `pixelAcquisition` (`DetailDisplayPresentationTests:715` builds mock `RegionSharpnessEvidence`). |
| **`CloveUITests/CloveFlowTests.swift` (`testDetailFocusRegionsCentreNativeZoom`)** | **Keep** | Uses `SampleDetailImages` deterministic metadata + hardcoded `.regionTooSmall` (`MMQ02679.ARW`); full 100% region tap and double-tap assertions stay valid. |
