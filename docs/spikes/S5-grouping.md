# S5 — Is the data needed for grouping available?

## Question

Is the data needed for grouping available? Measure subsecond capture time,
camera model and serial number, Vision feature computation on previews, and
trial time-gap/similarity thresholds; propose fallbacks for missing data.

Part 1 of #16. Physical-device timing and real-burst calibration are **pending**.
This is verification code for C9/C10/I3/I4, not production grouping or a G1 decision.

## What was tested

- Mac mini `Mac14,12`, macOS 27.0, Xcode 27.2 (27B52), Swift 6 mode.
  macOS numbers were taken on a **shared, loaded host**, with two other spike
  workers. One serial observation per file/size; filesystem and framework caches
  were not flushed. These are observations, not performance targets.
- The standard `formats` set from `/Volumes/T7/Projects/.clove-fixtures/sets/formats`:
  nine downloaded images plus the generated Sony HEIC, ten primary files total.
  See [fixtures](../fixtures.md) for cameras, licenses and source provenance.
  No public real burst dataset was added. The sweep uses synthetic fixture repeats.
- macOS report: `.build/s5/macos.json`, created `2026-11-08T17:25:06Z`.
  The full [macOS JSON is preserved on #16](https://github.com/mimiqdev/cloveapp/issues/16#issuecomment-6724765238)
  as a fenced report, outside git. Reproduce with:

  ```sh
  export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
  mkdir -p .build/s5
  CLOVE_S5_REPORT="$PWD/.build/s5/macos.json" mise run test-spikes
  ```

- Simulator: fresh iPhone 17 Pro (`iPhone18,1`), iOS 27.0, on the same shared
  host. Report `.build/s5/simulator.json`, created `2026-11-08T17:43:41Z`;
  the full [simulator JSON is preserved on #16](https://github.com/mimiqdev/cloveapp/issues/16#issuecomment-6724861254).
  The dedicated runner uses optimized Swift and the same S5 module:

  ```sh
  bash Packages/CloveSpikes/Tests/SpikeS5GroupingTests/measure-simulator.sh
  ```

  It creates/deletes its own simulator, copies fixtures into that app's sandbox,
  and saves `.build/s5/simulator.json` inside this checkout. It never writes to
  the cache. The runner adopts the required UIScene lifecycle through SwiftUI.
  Earlier standalone probe launches failed before measurements; no numbers from
  those attempts are used.
- Physical iPhone 17 Pro Max, iPad Pro and Duo: **pending**. No TestFlight upload
  is part of this work.
- `mise run verify` passed: fixture/release tooling tests, all Swift package
  tests (including 10 S5 tests), both simulator builds, and the UI smoke test.
  Validation-only release was attempted but stopped before archive/signing:
  UTC build `26110817` already exists in App Store Connect. Re-run in a later
  UTC hour (18:00 UTC or later on the measurement date); no upload was requested.

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
physical-device speed or feasibility; physical-device confirmation remains
pending. The macOS Vision path succeeded without a substitute algorithm.

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

### Threshold sweep

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

These fixture variants expose enough metadata and previews to run a grouping
trial, with material gaps in subsecond precision and serial identity. Vision at
grid size is practical to measure, but device speed and real-burst thresholds
remain inconclusive until part 2. Model-only identity cannot guarantee separation
of two unidentified bodies of the same model.

## Recommendation and options for G1

Recommend continuing the PRD's time-first, feature-refinement approach. Start the
device trial with **2 s, Vision revision 2 at 400 pixels, distance ≤ 0.5**, and
compare **0.75** and detail-size features against the returned labels. The screen
uses the conservative 0.5 value to make possible wrong splits visible. These are
trial parameters, not calibrated product defaults or a G1 decision.

Options for the product owner at G1:

- Vision at grid size: reuses smaller previews; measure initialization and
  end-to-end cost on devices before setting a throughput target. Calibrate using
  real scenes with crop/exposure/subject changes, not exact copies.
- Vision at detail size: more extraction work; the Sony conversion comparison
  suggests scale can help, but one pair cannot justify the extra cost generally.
- dHash: low compute cost and useful for duplicates/coarse rejection; coarse
  visual structure can merge different subjects or split cropped repeats.
- Time-only provisional groups followed by conservative feature refinement:
  fits C9's planned two-stage output. Unknown-serial/model items can either use
  documented lossy fallbacks or be excluded for stricter body separation.

No numeric performance or grouping-accuracy target is proposed before device
data. G1 remains open; no decision record is added.

## Open questions

- Real burst labeling: are 0.5 vs 0.75 and 400 vs 2000 appropriate for the owner's
  subjects, cameras and compression modes? Need reviewed device boundaries.
- Unknown serial/model policy: prefer fewer groups or accept model-only mixing?
  Need same-model two-body samples and a G1 decision.
- Physical-device feature latency, thermal effects and memory at 300–600 files:
  pending; the serial run is bounded to 600 files and retains review thumbnails.
- Offset availability and maker serial mappings beyond these ten samples need
  wider camera coverage. Generated HEIC is not an iPhone-camera HEIC sample.

### Device checklist (part 2)

1. On iPhone 17 Pro Max, connect an SD reader or USB-C SSD containing **at least
   300 photos with several bursts**, ideally from **two camera bodies**. Keep
   original subfolders and RAW+JPEG names. Prefer 300–600 primary photos; the
   screen measures only the first 600 sorted paths. Repeat on iPad Pro and Duo
   where available; the JSON records the actual device/OS version.
2. In Clove Lab, open **S5 · Grouping data**, tap **Choose folder**, choose the
   shooting folder, then **Compute metadata and groups**. Keep the app open.
   Allow about **2–10 minutes**; the counter should reach the selected total,
   then a group count and excluded-time count appear. Cancel drains the current
   image. No original or XMP is edited.
3. Expand proposed groups to check membership. Under **Label boundaries**, look
   at each preview pair around several bursts and composition changes. **Start
   new group** means these photos belong to different bursts/compositions.
   Tap **Confirm suggestion: split/same group** when correct, or change the
   toggle to correct a wrong split/merge. Label both kinds of error and correct
   joins/splits; allow **5–15 minutes**, or save a partial review. Reviewed count
   increases only after an explicit confirmation/change. Missing previews stay
   visible as unavailable; do not guess their labels.
4. Tap **Save report with labels**. The status shows
   `clove-lab-S5-<UTC timestamp>.json`. Use the footer's **Export** to **attach the
   JSON file to issue #16**. Copies are in the tested folder and Files › On My
   iPhone/iPad › Clove Lab. If a card write fails, check the Documents copy and
   send the visible error with the JSON. This JSON includes all timings, paths,
   group memberships, proposals and the reviewed boundary labels.
