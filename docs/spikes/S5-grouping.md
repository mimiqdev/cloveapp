# S5 — Is the data needed for grouping available?

## Question

Is the data needed for grouping available? Measure subsecond capture time,
camera model and serial number, Vision feature computation on previews, and
trial time-gap/similarity thresholds; propose fallbacks for missing data.

Part 2 of [#16](https://github.com/mimiqdev/cloveapp/issues/16), following
[part 1 / PR #24](https://github.com/mimiqdev/cloveapp/pull/24) and
[HIF support / PR #28](https://github.com/mimiqdev/cloveapp/pull/28). This finishes
with the available device data. The owner deferred further checks on 2026-11-09
to [#29](https://github.com/mimiqdev/cloveapp/issues/29). This is verification
code for C9/C10/I3/I4; G1's decision remains with the product owner.

Camera files, especially the owner's Sony A1 II ARW+HIF pairs, are the main target.
RAW+JPEG or RAW+HEIF uses RAW only for grouping; when RAW, JPEG and HEIF share a
stem in one folder, both companions are excluded. Standalone `.HIF`/`.hif` files
use the raster-preview path. Unit coverage checks pairing and a standalone HIF
preview; device run 2 confirms pair filtering, not standalone HIF grouping.

## What was tested

- Mac mini `Mac14,12`, macOS 27.0, Xcode 27.2 (27B52), Swift 6 mode.
  macOS numbers were taken on a **shared, loaded host**, with two other spike
  workers. One serial observation per file/size; filesystem and framework caches
  were not flushed. These are observations, not performance targets.
- The standard `formats` set from `/Volumes/T7/Projects/.clove-fixtures/sets/formats`:
  nine downloaded images plus the generated Sony HEIC, ten primary files total.
  See [fixtures](../fixtures.md) for cameras, licenses and source provenance.
  No public real burst dataset was added. The sweep uses synthetic fixture repeats.
- macOS report: `.build/grouping/macos.json`, created `2026-11-08T17:25:06Z`.
  The full [macOS JSON is preserved on #16](https://github.com/mimiqdev/cloveapp/issues/16#issuecomment-6724765238)
  as a fenced report, outside git. Reproduce with:

  ```sh
  export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
  mkdir -p .build/grouping
  CLOVE_GROUPING_REPORT="$PWD/.build/grouping/macos.json" mise run test-lab
  ```

- Simulator: fresh iPhone 17 Pro (`iPhone18,1`), iOS 27.0, on the same shared
  host. Report `.build/grouping/simulator.json`, created `2026-11-08T17:43:41Z`;
  the full [simulator JSON is preserved on #16](https://github.com/mimiqdev/cloveapp/issues/16#issuecomment-6724861254).
  The dedicated runner uses optimized Swift and the same S5 module:

  ```sh
  bash Packages/CloveLabKit/Tests/GroupingProbeTests/measure-simulator.sh
  ```

  It creates/deletes its own simulator, copies fixtures into that app's sandbox,
  and saves `.build/grouping/simulator.json` inside this checkout. It never writes to
  the cache. The runner adopts the required UIScene lifecycle through SwiftUI.
  Earlier standalone probe launches failed before measurements; no numbers from
  those attempts are used.
- **Physical iPhone 17 Pro Max (`iPhone19,4`), iOS 27.2**, Clove Lab 0.1.0,
  local storage through the folder picker, in two owner-returned runs:
  - **Run 1, build 26110818:** one Sony A1 II (`ILCE-1M2`) ARW,
    `MMQ05184.ARW`. Its HIF companion was skipped before PR #28; there are no
    adjacent boundaries and no groups, as expected for one photo.
  - **Run 2, build 26110903:** ten A1 II ARW+HIF pairs from one burst,
    `MMQ02678`–`MMQ02687`. S5 reports ten primary files found/tested, all ARWs;
    it excludes the ten HIF companions as intended. The S4 folder is outside
    this S5 analysis. No card, SSD, iPad or Duo measurement is inferred.
  - Originals were read in place without modification. Raw JSON is kept out
    of git and private paths, capture timestamps, GPS and serial values are
    omitted here. File names and SHA-256 identify the exact artifacts:

    | Run | Report file name | SHA-256 (`shasum -a 256`) |
    | --- | --- | --- |
    | 1 | `clove-lab-S5-20261109T022505Z.json` | `b71815cd5244bf14d21f8e9d8dc85b7527599ed56e7923232fd297fbcf07f446` |
    | 2 | `clove-lab-S5-20261109T033915Z.json` | `d44750e0bfaa0dad9d1ca95a31b75f0d044618c6547a447b52bd83abc39b2f86` |

- iPad Pro, Duo, external media and the 300+ photo multi-burst folder are
  **deferred** to #29. No release, signing or TestFlight upload is part of part 2.
- Part 1's `mise run verify` passed, including ten S5 tests and the UI smoke
  test. Part 2 changes only the S5 report and boundary controls; the existing
  optional-Bool label model and JSON schema are unchanged. `false` means keep
  together, `true` means new group, and `nil` means unreviewed. The existing
  label/export/sweep test covers those states. Check output is in the part-2 PR.

## Data

### Metadata availability

macOS `formats`, one file per camera/compression variant; availability describes
these samples, not every file of the format. Paths are the literal ImageIO keys.
All ten expose capture time at `{Exif}.DateTimeOriginal` and model at `{TIFF}.Model`.
No sample exposes `OffsetTimeOriginal`; timezone cannot be recovered reliably.

| Fixture / format | Subseconds at `{Exif}.SubsecTimeOriginal` | Body serial path | Metadata read, ms |
| --- | --- | --- | ---: |
| iPhone 12 Pro / ProRAW DNG | `700` | missing | 130.70 |
| Canon EOS 6D / JPEG | `00` (present, coarse in this file) | `{Exif}.BodySerialNumber` | 4.01 |
| Canon EOS R6 / CR3 | `06` | `{Exif}.BodySerialNumber` | 4.93 |
| Fujifilm X-S10 / RAF | missing | `{Exif}.BodySerialNumber` | 3.72 |
| Nikon D500 / NEF | `89` | `{ExifAux}.SerialNumber` | 5.22 |
| Olympus E-M1MarkII / ORF | missing | `{ExifAux}.SerialNumber` | 9.51 |
| Panasonic DMC-GH4 / RW2 | `842` | `{ExifAux}.SerialNumber` | 3.03 |
| Pentax K-5 II s / camera DNG | missing | `{ExifAux}.SerialNumber` | 3.76 |
| Sony ILCE-7S / ARW | missing | missing | 7.51 |
| Sony ILCE-7S / generated HEIC | missing | missing | 1.91 |

The timer includes opening the ImageIO source, copying properties, enumerating
XMP tags, choosing paths and parsing time. It does not decode an image. The first
ProRAW observation includes framework initialization; do not infer that all
ProRAW metadata takes 131 ms.

The reader records relevant property paths/values and selected paths per file
in the JSON (`metadata` measurement tags). Serial selection prefers EXIF body
serial, then ExifAux, XMP `exifEX:BodySerialNumber` / `aux:SerialNumber`, then
known maker dictionary serial keys. Maker paths are implemented and unit tested;
none is needed ahead of EXIF/ExifAux in this set. ExifAux and XMP `aux` expose the
same serial on Nikon/Olympus/Panasonic/Pentax. Lens serials are never body IDs.
Whitespace on Olympus/Pentax model/serial fields is trimmed. TIFF `DateTime`
(modification time) is deliberately not a capture-time fallback.

### Features on embedded previews

macOS times in ms; extraction and feature computation are timed separately.
Grid/detail requests cap the long edge at 400/2000 pixels. Actual returned sizes
are in JSON and may be smaller. RAW uses both thumbnail creation flags false;
there is no full RAW decode fallback. JPEG/HEIC use raster thumbnails. ImageIO
does not provide a definitive embedded-preview provenance guarantee.

| Fixture | Extract 400 | Vision 400 | Extract 2000 | Vision 2000 | dHash 400 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ProRAW DNG | 43.42 | 53.88 | 91.29 | 11.71 | 0.60 |
| JPEG | 34.10 | 8.83 | 52.68 | 11.31 | 0.41 |
| CR3 | 23.37 | 8.22 | 50.41 | 10.39 | 0.30 |
| RAF | 16.68 | 8.14 | 36.01 | 11.22 | 0.28 |
| NEF | 22.52 | 8.25 | 58.48 | 9.92 | 0.29 |
| ORF | 31.07 | 6.64 | 73.65 | 8.08 | 0.30 |
| RW2 | 8.37 | 5.33 | 12.15 | 8.91 | 0.30 |
| Pentax DNG | 18.68 | 7.11 | 46.68 | 9.04 | 0.27 |
| ARW | 10.83 | 6.91 | 12.76 | 9.02 | 0.28 |
| Generated HEIC | 149.70 | 6.55 | 58.12 | 7.39 | 1.20 |

20/20 Vision requests and 10/10 hashes succeeded. Vision explicitly uses
`VNGenerateImageFeaturePrintRequest` revision 2 with `scaleFit`. Hashing draws a
9×8 grayscale image, then compares horizontal neighbors into a 64-bit dHash.
It is much cheaper after extraction but is sensitive to crop/rotation and cannot
resolve focus/expression. Extraction dominates many of the steady-state samples.
The first Vision request is reported separately by its place in the table;
there is no controlled cold-start comparison.

| Pair population | n | Vision 400 min / median / max | Vision 2000 min / median / max | dHash differing bits min / median / max |
| --- | ---: | --- | --- | --- |
| Different scenes, adjacent fixture paths | 8 | 0.939 / 1.060 / 1.123 | 1.012 / 1.102 / 1.203 | 20 / 32 / 40 |
| Same Sony source, ARW vs generated HEIC | 1 | 0.689 | 0.256 | 3 |
| Exact same feature compared to itself (synthetic) | 9 | 0 / 0 / 0 | not swept | 0 by construction |

### Simulator observations

Metadata availability and selected property paths match the macOS table for all
ten samples. All 20 preview reads and all ten dHashes completed. **All 20 Vision
requests failed** with `NSOSStatusErrorDomain -1: Failed to create espresso
context.` There are no valid simulator Vision times/distances or synthetic
Vision sweep labels. This is a recorded runtime failure, not evidence of
physical-device speed or feasibility; physical-device runs below now confirm Vision succeeds on the measured iPhone.
The macOS Vision path also succeeded without a substitute algorithm.

Simulator timings in ms, one serial observation per variant; optimized runner,
shared loaded host, fresh sandbox with no cache flush. These values should not
be compared as phone-versus-Mac throughput. Framework initialization, simulator
services and host load produce large outliers.

| Fixture | Metadata | Preview 400 | Preview 2000 | dHash 400 |
| --- | ---: | ---: | ---: | ---: |
| ProRAW DNG | 118.25 | 109.28 | 288.99 | 3.14 |
| JPEG | 8.03 | 97.67 | 194.74 | 0.74 |
| CR3 | 3915.84 | 72.67 | 152.02 | 0.29 |
| RAF | 7.90 | 55.41 | 97.19 | 0.30 |
| NEF | 10.03 | 46.25 | 92.95 | 0.30 |
| ORF | 15.37 | 57.13 | 154.56 | 0.32 |
| RW2 | 28.45 | 21.47 | 31.79 | 0.39 |
| Pentax DNG | 8.44 | 38.75 | 68.58 | 0.30 |
| ARW | 1442.52 | 30.31 | 42.97 | 0.29 |
| Generated HEIC | 60.36 | 4988.64 | 2611.19 | 1091.52 |

The Sony conversion pair in the macOS table is excluded from the different-scene
population and from synthetic scene transitions. Its 400-pixel distance exceeds the screen's
conservative 0.5 trial threshold, showing why the synthetic sweep cannot choose
a production default. Preview scale/conversion changes feature distance.

### Physical-device findings

All timings below are milliseconds, one serial observation per file/size;
run-2 medians use the mean of the middle two of ten observations. No cache
flush, controlled cold-start comparison, p95 or sustained throughput is measured.
Preview extraction and feature computation are separate timers. Both sizes
apply orientation; 2000 is a requested cap, not the actual embedded resolution.

| Status | Finding | Result |
| --- | --- | --- |
| Measured, runs 1 / 2 | Metadata availability, 1 / 10 ARWs | All have `{Exif}.DateTimeOriginal`, `{Exif}.SubsecTimeOriginal` and `{TIFF}.Model` = `ILCE-1M2`; no body serial selected and no `OffsetTimeOriginal` |
| Measured, run 1 | Metadata read; preview 400 / 2000 | 9.35; 18.35 / 21.34 ms |
| Measured, run 1 | Vision 400 / 2000; dHash 400 | 64.53 / 14.07; 0.349 ms; first-use costs included, 2/2 Vision calls succeed |
| Measured, run 1 | Groups / reviewed boundaries | 0 / 0; one ARW cannot establish grouping behavior |
| Measured, run 2 | Metadata read, median (range) | 2.66 (2.31–11.90) ms |
| Measured, run 2 | Preview 400, median (range) | 7.47 (7.21–17.54) ms; actual 267×400 |
| Measured, run 2 | Preview 2000, median (range) | 11.07 (10.84–19.62) ms; actual 1080×1616 |
| Measured, run 2 | Vision 400, median (range) | 3.25 (3.15–161.37) ms; maximum is first call |
| Measured, run 2 | Vision 2000, median (range) | 4.37 (3.77–14.05) ms; maximum is first call |
| Measured, run 2 | dHash 400, median (range) | 0.225 (0.211–0.897) ms |
| Measured, run 2 | Feature success and proposed groups | 20/20 Vision calls and 10/10 hashes; one ten-photo group at 2 s / Vision 0.5 |
| Measured, run 2 | Nine adjacent time gaps | Approximately 0.200–0.201 s |
| Measured, run 2 | Nine Vision 400 distances, min / median / max | 0.231 / 0.291 / 0.420 |
| Measured, run 2 | Nine Vision 2000 distances, min / median / max | 0.205 / 0.272 / 0.330 |
| Measured, run 2 | Nine dHash distances, min / median / max | 2 / 7 / 12 bits |
| Measured, run 2; owner-corrected labels | Nine reviewed boundaries | All confirmed keep-together; correction and sweep below |
| Deferred, #29 | 300+ photos, multiple bursts / scene changes, ideally two bodies | Needed for threshold calibration and false-merge evidence |
| Deferred, #29 | Card/SSD, sustained load, iPad Pro / Duo | No media, thermal, memory or cross-device performance claim |
| Deferred / known gap, #29 | iPhone HEIC and standalone camera HIF grouping | No standalone device feature/metadata result; paired HIF was excluded |

The preliminary dHash reading of 2–5 covers only the first four boundaries.
The complete sequence is **2, 5, 3, 5, 12, 9, 7, 11, 9**; five exceed 5 bits.
Vision's 400 px minimum is 0.231, while 0.205 is the 2000-cap minimum. The two
`body-adjacent-distance` populations are distinct; `path-adjacent-distance`
repeats these pairs in this folder and must not double the sample count.

The A1 II serial is missing in every measured ARW. The model fallback groups
this single-body folder, but **two unidentified A1 II bodies would share a
bucket and could mix** when times and scenes overlap. Neither filename order
nor visual similarity establishes body identity. This fallback cannot satisfy
the PRD's unconditional two-body separation guarantee; C9/I4 and G1 must settle
the unknown-body policy before claiming that acceptance condition. There is no
evidence that body separation is infeasible when an actual body ID is available.

[S2's merged report](S2-previews.md) supplies complementary preview costs:
run-2 ARW I400 median 8.3 ms, HIF I400 10.5 ms, and both expose only 1616 px
embedded detail. Native ARW render is 529.1 ms median; HIF's CIRAWFilter control
is about 1.8 s. S5 therefore recommends reusing a 400 px embedded grid preview
for grouping rather than requesting full RAW or decoding both companions. S5's
7.47 ms extraction is a separate measurement path, not a faster S2 benchmark.
S5 raster previews currently use `Always`; S2's embedded-first HIF policy is
for I1/I3 integration, not a reason to change another spike here.

### Threshold sweep (synthetic, part 1)

The synthetic sample has nine unique source scenes (the generated HEIC duplicate
is omitted): nine same-scene repeat boundaries at 0.2 s (join), nine same-scene
pause boundaries at 3 s (split), and eight transitions to a different source at
0.8 s (split). These are **26 constructed labels**, not observed bursts; capture
times/body IDs are conceptual trial inputs and exact-repeat distances are zero.
The sweep uses the same boundary predicate as the pure grouping function.

Each cell below is **wrong splits / wrong merges**, among 26 labels. A time gap
must be strictly less than the threshold; feature distance is inclusive.

| Gap threshold, s | Distance 0.1 | 0.25 | 0.5 | 0.75 | 1.0 | 1.5 |
| ---: | --- | --- | --- | --- | --- | --- |
| 0.5 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 1 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 1 | 0 / 8 |
| 2 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 1 | 0 / 8 |
| 3 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 1 | 0 / 8 |
| 5 | 0 / 9 | 0 / 9 | 0 / 9 | 0 / 9 | 0 / 10 | 0 / 17 |

This only checks mechanical threshold behavior; the zero-error region is broad
because exact copies are easy. It provides no evidence for real-burst accuracy,
recall, or a best threshold. Device reports repeat the 30-cell sweep using only
human-reviewed boundaries, and retain individual gap/distance/label values for
later analysis. Unreviewed suggestions are never ground truth. Device JSON also
retains both preview-size distances and dHash distances for body-adjacent pairs,
so part 2 can compare alternatives without another feature pass.

### Corrected labeled sweep (device run 2)

**Owner correction, 2026-11-09:** all nine boundaries in the returned JSON store
`expectedSplit = true`, while all proposals are `proposedSplit = false`. The
owner meant to confirm keeping the burst together. Treat all nine as
**confirmed no-split (`expectedSplit = false`) in this analysis only**. The
original JSON and its checksum are unchanged. Its precomputed reviewed sweep
therefore does not represent the owner's intent: at 2 s / 0.5 it reports zero
wrong splits and nine wrong merges. Recomputing with the correction gives
**zero wrong splits and zero wrong merges** on those nine joins.

For each boundary, split when gap ≥ time threshold or Vision distance > distance
threshold (missing/nonfinite data also splits). Count a wrong split when that
predicate is true for a corrected keep-together label, and a wrong merge when
it is false for a true split label. The latter population has **n = 0** here.
All nine gaps are below every swept time threshold.

Each cell is **wrong splits / wrong merges**, using the nine corrected labels
and recorded 400 px distances, with the same predicate as `Grouping.sweep`:

| Gap threshold, s | Vision 0.1 | 0.25 | 0.5 | 0.75 | 1.0 | 1.5 |
| ---: | --- | --- | --- | --- | --- | --- |
| 0.5 | 9 / 0 | 8 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 1 | 9 / 0 | 8 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 2 | 9 / 0 | 8 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 3 | 9 / 0 | 8 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 5 | 9 / 0 | 8 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

Recomputing from the 2000-cap distances gives 9 / 0 at 0.1, 5 / 0 at 0.25,
and 0 / 0 at ≥ 0.5 for every time threshold. Detail features do not improve
this burst's result at 0.5. With a time gap of 2 s and dHash instead of Vision,
inclusive cutoffs of 5 / 8 / 12 / 16 bits give respectively **5 / 4 / 0 / 0
wrong splits**, all with zero wrong merges because there are no split labels.
A 12-bit cutoff merely fits this burst; it is not calibrated against negatives.

**One ten-frame burst supports no accuracy claim.** Nine correlated joins
cannot select a time threshold, estimate false merges, favor 0.5 over 0.75, or
establish performance on other subjects. The real multi-burst labeled 300+
photo folder is deferred to #29. Run 1 has no boundaries; zero-count sweeps
there carry no accuracy information. Synthetic fixture sweeps remain separate
and are not added to the human-labeled population.

The Lab now shows **Suggestion** and **Saved label** separately, with explicit
**Keep together** / **New group here** buttons and **Clear label**. There is no
implicit toggle state or separate confirm action to confuse with a split.
Labels still use the existing optional Bool and unchanged export schema.

### Fallback trials and rules

| Missing data | Trial behavior / option | What breaks |
| --- | --- | --- |
| Subseconds | Sort by available capture seconds, then numeric relative filename (`IMG_2` before `IMG_10`); retain coarse seconds for gap tests | Cannot recover within-second timing; sequence rollover, renamed files and folder names can reverse capture order; unrelated compositions in one second need feature splitting |
| Subseconds, filesystem/file order alternative | Considered, not selected; deterministic filename order is tested instead | Enumeration order varies between volumes/rescans and does not establish capture order |
| Serial | Use trimmed model only, separated from the same model with a known serial | Two unknown-serial bodies of the same model can mix; this sample cannot resolve that ambiguity |
| Model and serial | Unknown-identity bucket within the selected folder | Different unidentified bodies can mix; a conservative production option is to exclude these items |
| Offset | Use camera wall time in a fixed UTC surrogate; apply explicit offsets when available | Camera clock changes remain ambiguous; mixed offset/no-offset records from one body can appear discontinuous |
| Capture time missing or invalid | Exclude from grouping, even when filename/file timestamps are available | Missed bursts; filename order cannot justify inventing capture times under the PRD |
| Feature/preview unavailable | Break the boundary; keep the error in JSON and show no-preview state | More singletons/wrong splits; time-only provisional grouping remains an alternative |

The pure function separates bodies before sorting, uses adjacent time gaps and
injected feature distances, and returns only groups of at least two. Tests cover
body/model separation, numeric ties, missing times/features, exact threshold
edges, minimum size, metadata path priorities, fractional time/offset parsing,
and explicit labels. No marks or XMP are changed. Stable IDs, two-stage UI,
pausing and persistent feature caching remain C9/I3 work.

## Conclusion

Vision revision 2 works on the measured physical iPhone despite the simulator's
espresso failure. On ten local A1 II ARWs it takes 3.25 ms median after a 400 px
preview read of 7.47 ms median, with a 161.37 ms first-call Vision outlier. The
2 s / 0.5 trial keeps the one burst together, matching all nine owner-corrected
labels. This supports the pipeline's feasibility on that device and input,
with no accuracy or sustained-speed claim. Missing A1 II body serials remain a
material identity gap; model-only grouping cannot guarantee two-body separation.

## Recommendation and options for G1

**Recommend the PRD's time-first, Vision refinement rule, starting with a 2 s
gap and Vision revision 2 distance ≤ 0.5 on orientation-applied 400 px embedded
previews.** These are initial evaluation parameters for C9/I3, not calibrated
launch defaults or an approved G1 decision.

1. Treat RAW+HIF/RAW+JPEG as one logical photo and use its RAW embedded preview
   once. Separate by model plus body serial when available, exclude missing or
   invalid capture times, then sort by capture time with subseconds and numeric
   filename for ties. Never invent capture times from filenames or filesystem
   timestamps. Publish time-only runs first; adjacent gaps **strictly < 2 s**
   join, with groups of at least two.
2. Refine those runs in the background using Vision revision 2 / `scaleFit` at
   400 px. Keep a boundary joined when distance **≤ 0.5**; otherwise split.
   Cache features by source revision, actual preview pipeline/size and Vision
   revision, pause under interaction/pressure, and preserve stable group IDs
   and the viewed photo during refinement. Missing preview/features produce an
   explicit unavailable state and conservatively split the final result. Those
   scheduling/cache/UI behaviors remain C9/I3 integration work.
3. **dHash fallback, only when Vision is unavailable but a preview is usable:**
   evaluate a **≤ 12 differing-bit** cutoff with the same < 2 s gap. This keeps
   the measured burst intact, unlike ≤ 5 (five wrong splits). It is a provisional
   degraded-mode candidate, not an equivalent replacement for Vision. Default
   to a split if neither feature is usable. Keep fallback results identifiable
   for evaluation; the current Lab still splits when Vision fails. Do not add a
   hard dHash rejection prefilter to the normal Vision path yet: 12 is only the
   maximum observed on one burst and larger true-join distances are untested.
4. **Unknown-body policy:** recommend excluding unknown-serial photos from
   cross-body automatic grouping unless the source is reliably identified as
   one body. This is conservative and would leave the owner's A1 II photos
   ungrouped in an unverified mixed folder. The Lab's model-only alternative
   remains useful for single-body trials but can merge two A1 II bodies.
   G1 must choose a reliable body/source attribution approach or approve a
   documented limitation through the product process. Do not silently weaken
   the PRD's no-mixed-bodies acceptance condition. No source-attribution UI or
   PRD change is implemented by this spike.

Options for the product owner at G1:

| Option | Benefit | Cost / evidence |
| --- | --- | --- |
| Recommended: Vision 400 / 0.5, time-first | Reuses grid previews; all nine corrected joins retained | First-use spike; false merges untested; needs #29 calibration |
| Vision 400 / 0.75 | Could tolerate more appearance change | Same result here; no negative samples to justify widening |
| Vision 2000-cap / 0.5 | Smaller distances on this burst | No better result at 0.5; extraction median 11.07 vs 7.47 ms, Vision 4.37 vs 3.25 ms; actual preview only 1616 px |
| dHash ≤ 12 fallback | 0.225 ms median feature compute; no Vision dependency | Uncalibrated false merges, crop/rotation sensitivity; cannot judge focus/expression |
| Time-only final groups | Avoids feature cost/failure | Cannot split a subject change inside a run; retain as provisional output only |
| Model-only unknown-serial identity | Groups the owner's single A1 II burst | Two A1 II bodies may mix; conflicts with unconditional PRD body separation |
| Exclude unknown serials until reliable attribution | Avoids automatic mixing of unidentified bodies | Misses useful A1 II bursts; G1 policy remains open |

No numeric p95, sustained throughput or accuracy target follows from these
runs. Both preview and feature costs should be measured end to end with #29's
camera folder before M3/Q3 targets are fixed. G1 remains open; no decision
record is added.

## Open questions

- Which thresholds distinguish joins from composition changes across multiple
  bursts? Need corrected controls and labels for both joins and splits in #29;
  a perfect count on this burst cannot estimate accuracy.
- Can I4 recover a stable A1 II body ID through another system-exposed property,
  or can a source be reliably attributed to one body? If neither works, G1 must
  resolve the PRD conflict and the cost of excluding unknown-serial A1 II files.
- Does dHash ≤ 12 preserve enough real joins without merging unrelated scenes?
  Keep it an optional fallback candidate until labeled negatives exist.
- How do first-use latency, thermal behavior, retained review thumbnails and
  feature caches behave at 300–600 photos? No S5 device memory measurement exists.
- How often are offsets/subseconds and maker serials available beyond these
  samples? Clock changes, coarse time, filename rollover and renamed files can
  still produce misleading adjacency. Standalone HIF needs camera evidence;
  generated HEIC is not an iPhone-camera HEIC sample.

## Deferred device checks

The owner deferred these checks on 2026-11-09 to
[#29](https://github.com/mimiqdev/cloveapp/issues/29). They are not urgent and do
not hold part 2 or #16 open. Run before M3/Q3 targets are fixed, or earlier if a
G1 choice needs the answer.

| Status | Check | What it would answer | Could it change the G1 recommendation? |
| --- | --- | --- | --- |
| Deferred, #29 | 300+ camera photos with multiple bursts, pauses and subject changes; label joins and splits | Real positive/negative boundary distributions, 0.5–5 s gap and Vision/dHash calibration, accumulated adjacency chaining | Yes: time/distance defaults, dHash eligibility, possibly the refinement rule; no current accuracy claim |
| Deferred, #29 | Two bodies, ideally two A1 II bodies, in that folder | Unknown-serial mixing, recoverable identity and order/clock ambiguity | Yes: body attribution or exclusion policy; model-only cannot meet the guarantee |
| Deferred, #29 follow-up | Same camera folder on exFAT card/reader and external SSD | I/O/provider cost versus local storage; sustained feature admission and cancellation | Could change scheduling, caching and speed targets; no current evidence against embedded-first Vision |
| Deferred, #29 | iPad Pro, repeat camera folder and record hardware/iPadOS; Duo where available | Vision availability, latency, preview scale and pressure on other hardware | Could change device budgets or fallback use; iPhone timings do not transfer |
| Deferred, #29 follow-up | Standalone A1 II HIF and wider camera formats, missing previews/subseconds/offsets | Metadata/preview availability outside paired RAW; failure behavior and image transformations | Could change per-format source/fallback policy; pair filtering already measured |
| Deferred / known gap, #29 | iPhone HEIC | Phone-specific metadata/features beyond camera HIF | No blocker for camera-focused G1; revisit with photo-library support |

The iPhone-HEIC ownership failure recorded by S4/#29 is not an S5 result. S5
has no returned phone-HEIC observation; no fix or phone-photo support claim is
part of this work. The remaining multi-burst evidence and body policy are open
for G1, while S5's measurements and initial recommendation are complete.

### Device checklist (deferred follow-up)

1. After the supervisor publishes the merged Lab build, install it on iPhone
   17 Pro Max and record the iOS version. Connect an SD reader or USB-C SSD containing **at least
   300 photos with several bursts**, ideally from **two camera bodies**. Keep
   original subfolders and RAW+HIF/RAW+JPEG names. Prefer 300–600 primary photos; the
   screen measures only the first 600 sorted paths. Repeat on iPad Pro and Duo
   where available; the JSON records the actual device/OS version.
2. In Clove Lab, open **S5 · Grouping**, tap **Choose folder**, choose the
   shooting folder, then **Compute metadata and groups**. Keep the app open.
   Allow about **2–10 minutes**; the counter should reach the selected total,
   then a group count and excluded-time count appear. Cancel drains the current
   image. No original or XMP is edited.
3. Expand proposed groups to check membership. Under **Label boundaries**, look
   at each preview pair around several bursts and composition changes. Read
   **Suggestion**, then tap **Keep together** if both belong in one group, or
   **New group here** if the right photo starts another group. Do this even
   when the suggestion is correct. Check **Saved label** matches your intent;
   **Clear label** restores **Not reviewed**. Label correct joins and splits as
   well as wrong merges/splits; allow **5–15 minutes**, or save a partial review.
   Reviewed count increases only after choosing an action. Missing previews
   stay visible as unavailable; do not guess their labels.
4. Tap **Save report with labels**. The status shows
   `clove-lab-S5-<UTC timestamp>.json`. Use the footer's **Export** to send the
   original privately to the supervisor, who can redact and attach it to
   **issue #29**. Copies are in the tested folder and Files › On My iPhone/iPad
   › Clove Lab. If a card write fails, check the Documents copy and send the
   visible error with the JSON. Reports include private paths, capture metadata,
   group memberships, camera identifiers and the reviewed boundary labels.
