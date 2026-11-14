# Browsing performance measurement

Clove Lab's **Q3 · Browsing performance** screen measures the production
`CloveCore` and `CloveImaging` pipelines on 2,000 logical photos. It does not
change production behavior or decide whether a target passes.

## Generate the standard folder

Run the pinned fixture tasks on the Mac:

```sh
mise run fixtures-sets
mise run test-fixtures
```

`fixtures/sets.json` builds
`${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/sets/browsing-2000`
with 4,000 image files:

| Photo set | Count |
| --- | ---: |
| ARW+JPEG | 1,200 |
| ARW+HIF | 600 |
| ARW+JPEG+HIF | 100 |
| Standalone DNG | 50 |
| Standalone JPEG | 25 |
| Standalone HEIC | 25 |
| **Total logical photos** | **2,000** |

The generator repeats pinned sources under unique paths. Hard links avoid
extra data on a supporting Mac filesystem. Other filesystems use copies. A
copy without links needs about 20 GiB. Repeated files share capture metadata
and pixels, so this set measures load, not burst-grouping accuracy.

The hidden `.clove-fixture.json` records the set name, definition SHA-256,
source SHA-256 values, recipe definitions, generated-companion SHA-256 values,
and declared file count. The report checks the declared count against the
production scan. No fixture binary enters git.

## Run the owner checklist on the iPhone

Use an iPhone 17 Pro Max with local storage. Do not use a camera folder or the
only copy of any photo. CFexpress and other external media stay non-blocking
under [#29](https://github.com/mimiqdev/cloveapp/issues/29).

1. Copy the generated `browsing-2000` folder to a disposable folder in Files
   under **On My iPhone**. Keep about 20 GiB free for this copy.
2. Install the TestFlight build that contains this flow. Connect the phone to
   power and keep Clove Lab open.
3. Open **Q3 · Browsing performance**. Choose the copied `browsing-2000`
   folder, adjust the screen long edge if targeting a specific device (defaults
   to the current screen's `nativeBounds` long edge; presets cover `2,752 px`
   iPad Pro 13" and `2,868 px` iPhone 17 Pro Max), optionally choose a
   multi-format RAW folder (`sets/formats`), then tap **Run browsing
   measurements**.
4. Wait for the six-stage progress display to finish. The photos, companions,
   and XMP stay unchanged. The run writes only its JSON report beside them.
5. Confirm that the status names a `clove-lab-Q3-<timestamp>.json` file. The
   same report appears under **Files › On My iPhone › Clove Lab**.
6. Use **Export** in the footer and attach the JSON file to
   [#219](https://github.com/mimiqdev/cloveapp/issues/219). Include the
   TestFlight build number and iOS version if they are not clear in the report.

Regenerate the Mac fixture set to delete old reports and recreate the same
defined folder. The identity records any generated-companion differences. Do
not run the measurement in the Mac cache while another task is rebuilding that
set.

## Read the JSON report

The normal `LabReport` schema carries the app, device, fixture, and source
identities. Tagged measurements add these facts:

- `statistic` is `p50` or `p95`. Percentiles use nearest rank over successful
  samples. `sampleCount` and the separate `<stage>-sample-count` entry give the
  number of observations.
- `cache` is `cold`, `disk`, or `warm`. Cold means fresh Lab-owned caches and
  first touch in that run. The flow cannot flush OS caches or simulate a
  reboot. Disk passes disable the memory tier over the cold run's disk files.
  Warm detail uses memory. Warm grouping includes group-cache loading,
  candidate revision reads, feature-cache lookups, and refinement. Cache hits
  avoid image recomputation.
- `<stage>-failure-count` and `<stage>-failure-reason` record unsuccessful
  observations. `metric-unavailable` explains a metric that the flow cannot
  produce. The 25 standalone HEIC files currently return `noUsablePreview` in
  the Mac run and remain in the attempted counts.
- Thumbnail latency includes queueing behind at most 32 in-flight requests.
  Throughput counts successful materialized previews over the whole pass.
- `detail-first-preview` (`displayPixels` tag) measures `DetailPipeline.preview`
  at the configured display edge (default `2,868 px` to match native screen
  arrival). `detail-screen` (`screenPixels` tag) warms `preview` first and
  measures `DetailPipeline.screen` (`screenRAW` quality) across up to 24 RAW
  sets.
- `detail-format-preview`, `detail-format-screen`, and `detail-format-native`
  (`format`, `megapixels`, and `displayPixels`/`screenPixels` tags) benchmark
  RAW formats from `sets/formats` (or the selected format folder) across
  repeated fresh pipelines (1 warmup + 5 measured passes by default), pairing
  5.1 MP `sony-ilce-7s.ARW` with 20+ MP full-frame/APS-C RAWs. `detail-20mp-*`
  and `raw-focus-20mp*` aggregate the `>= 19.9 MP` RAWs (`canon-eos-r6.CR3`,
  `nikon-d500.NEF`, `olympus-e-m1markii.ORF`, `fujifilm-x-s10.RAF`).
- `feature-read-and-compute` times one-at-a-time production feature requests,
  including preview reading, Vision, dHash, and cache publication.
  `grouping-feature-completion` includes folder-wide queueing.
- `raw-focus-cancel-drain` waits for native render admission, cancels it, and
  measures `DetailPipeline.close()`. `raw-focus-including-cancel` adds that
  drain to a second native RAW render in a fresh pipeline. Only observed
  admission and cancellation enter those distributions. RAW-focus samples must
  have `.nativeRAW` quality. Embedded fallbacks with `.rawRenderFailed` count as
  failures, including warm-cache attempts. Warm detail and native checks verify
  bitmap dimensions (`width`, `height`, `bytesPerRow`) without calling
  `CGImage.dataProvider?.data` (`CGDataProviderCopyData`).
- `memory-peak` is process RSS sampled every 5 ms. It is a cumulative lower
  bound, not per-stage allocation attribution.
- `grid-scroll-presentation` is unavailable. Lab drives the production
  thumbnail pipeline without Clove's `UICollectionView`, so decode latency is
  not an on-screen frame-rate result.
- Physical-device `xctrace` traces share `OSSignposter` intervals under
  subsystem `com.mimiqdev.clove` across categories `GridCell`
  (`GridCellConfigure`, `GridCellPixelLoad`), `DetailArrival`
  (`DetailArrivalToPreview`, `DetailArrivalToScreen`, `DetailScreenRender`),
  `DetailPipeline` (`DetailRenderLane`, `DetailScreenRAW`, `DetailNativeRAW`,
  `DetailFullRaster`), `Sharpness` (`SharpnessAnalysis`,
  `SharpnessMetadataRead`, `SharpnessFaceDetection`), and
  `FolderGrouping` (`FolderGroupingPass`).

The Lab caches use a temporary directory that the run deletes. Export uses the
existing tested-folder, Documents, and share-sheet flow.

For a full Mac runner report, generate the fixture sets (`browsing-2000` and
`formats`) and run:

```sh
CLOVE_BROWSING_PERFORMANCE_REPORT="$PWD/.build/browsing-performance-mac.json" \
CLOVE_SOURCE_REVISION="$(git rev-parse HEAD)" \
CLOVE_DETAIL_SCREEN_PIXELS=2868 \
swift test -c release --package-path Packages/CloveLabKit --filter collectFullMacReport
```

Omit `-c release` for a debug-runner comparison, or set
`CLOVE_DETAIL_SCREEN_PIXELS=2752` for iPad Pro 13" native screen edge. The
runner writes Mac-only evidence. It does not represent an iPhone or iPad result.

## G1 comparison and current Mac evidence

These values come from three consecutive full runs on a `Mac14,12` (Apple M2
Pro, 10 cores, 16 GiB RAM) running `macOS 27.0` (`26A428`) and `Xcode 27.2`
(`27B52`), using source `e9f0a7c5f265f0e2817d85abe1c985b700e65ae6` over
`browsing-2000` plus `sets/formats` (1 warmup + 5 measured passes per format).
Run durations and host 1m/5m/15m load averages (`uptime`):

- **Release (`2,868 px`, iPhone 17 Pro Max edge):** `83.38 s`, load
  `3.76 / 3.29 / 6.22` at start.
- **Release (`2,752 px`, iPad Pro 13" edge):** `82.93 s`, load
  `2.88 / 3.20 / 5.85` at start.
- **Debug (`2,868 px`, iPhone 17 Pro Max edge):** `85.40 s`, load
  `1.91 / 2.99 / 6.48` at start.

Times are in milliseconds except throughput and memory. Every iPhone and iPad
value remains pending physical-device runs. These are measurements, not pass
claims.

| G1 stage | Starting iPhone target | Mac-only Release `2,868 px` (p50 / p95) | Mac-only Debug `2,868 px` (p50 / p95) | Samples | Device |
| --- | --- | --- | --- | --- | --- |
| First photos delivered | ≤ 500 ms | Cold 6.570 / 6.570 ms; warm 2.377 / 2.514 ms | Cold 7.550 / 7.550 ms; warm 3.214 / 3.383 ms | 1 cold, 4 warm | Pending |
| Full scan and pairing | ≤ 3,000 ms | Cold 85.350 / 85.350 ms; warm 77.161 / 78.513 ms | Cold 107.456 / 107.456 ms; warm 99.648 / 102.390 ms | 1 cold, 4 warm | Pending |
| Capture-time read | Measure | Cold serial 2.631 / 2.725 ms | Cold serial 2.660 / 2.781 ms | 240 | Pending |
| Uncached grid thumbnail | p95 ≤ 150 ms | Cold 91.735 / 95.186 ms | Cold 92.608 / 97.563 ms | 1,975 (25 fail) | Pending |
| Disk-cached grid thumbnail | p95 ≤ 20 ms | Disk 13.318 / 13.537 ms | Disk 13.332 / 13.591 ms | 1,975 (25 fail) | Pending |
| Thumbnail throughput | ≥ 30 photos/s | Cold 332.319/s; disk 2,397.449/s | Cold 328.935/s; disk 2,394.845/s | 1,975 each | Pending |
| First detail preview (`5.1 MP` set mix) | p95 ≤ 300 ms | Cold 152.110 / 156.048 ms; warm 14.025 / 15.656 ms | Cold 151.900 / 154.599 ms; warm 14.121 / 15.741 ms | 14 (10 fail) | Pending |
| Screen RAW (`detail-screen`, `5.1 MP` ARW) | Measure | Cold 269.785 / 281.135 ms; warm 13.288 / 14.070 ms | Cold 270.971 / 275.924 ms; warm 13.498 / 14.903 ms | 24 | Pending |
| Full RAW + cancel (`5.1 MP` ARW) | p95 ≤ 2,000 ms | Cold 370.429 / 380.503 ms; drain 279.565 / 287.427 ms; combined 653.188 / 659.441 ms; warm 0.062 / 0.091 ms | Cold 368.993 / 372.863 ms; drain 276.639 / 284.328 ms; combined 648.570 / 653.322 ms; warm 0.088 / 0.147 ms | 6 | Pending |
| 20+ MP preview (`detail-20mp-preview`) | Measure | Cold 133.327 / 164.629 ms; warm 7.220 / 7.830 ms | Cold 146.655 / 169.150 ms; warm 7.375 / 8.004 ms | 20 (4 RAWs × 5) | Pending |
| 20+ MP screen RAW (`detail-20mp-screen`) | Measure | Cold 252.450 / 306.762 ms; warm 14.100 / 16.785 ms (`2,752 px`: 248.605 / 300.043 ms; warm 12.278 / 13.920 ms) | Cold 254.131 / 303.912 ms; warm 14.101 / 15.995 ms | 20 (4 RAWs × 5) | Pending |
| 20+ MP native RAW (`detail-20mp-native`) | Measure | Cold 336.175 / 358.552 ms; warm 0.075 / 0.117 ms | Cold 337.435 / 378.257 ms; warm 0.084 / 0.139 ms | 20 (4 RAWs × 5) | Pending |
| 20+ MP full RAW + cancel (`raw-focus-20mp`) | Measure | Cold 397.611 / 432.002 ms; drain 362.415 / 375.072 ms; combined 772.683 / 794.417 ms; warm 0.075 / 0.132 ms | Cold 436.824 / 507.825 ms; drain 364.323 / 379.113 ms; combined 801.147 / 886.938 ms; warm 0.072 / 0.083 ms | 2 | Pending |
| Feature per photo | Measure | Cold preview+features+cache 20.293 / 42.199 ms | Cold preview+features+cache 20.547 / 42.488 ms | 215 (25 fail) | Pending |
| Grouping total | No numeric G1 target | Cold 20,308.417 ms (refine 7.780 ms); warm 431.868 ms | Cold 20,754.429 ms (refine 180.377 ms); warm 753.483 ms | 1 each | Pending |
| Peak process RSS | No numeric G1 target | 1,753,939,968 bytes (1,672.7 MiB; thumbnails peak 176.3 MiB) | 1,714,946,048 bytes (1,635.5 MiB; thumbnails peak 176.2 MiB) | 5 ms samples | Pending |
| Grid scrolling | Q3 names the stage | Unavailable in the package-only Lab flow | Unavailable in the package-only Lab flow | 0 | Pending |

### Multi-format RAW detail comparison (`sets/formats`, Release)

Measured across 1 warmup + 5 measured passes on fresh `DetailPipeline`
instances per fixture (`0` failures). `screenRAW` columns compare iPhone 17 Pro
Max (`2,868 px`) and iPad Pro 13" (`2,752 px`) native screen long edges:

| Fixture (`megapixels`) | Preview cold / warm (p50 / p95; warm p50) | `screenRAW` @ `2,868 px` (cold p50 / p95; warm p50) | `screenRAW` @ `2,752 px` (cold p50 / p95; warm p50) | `nativeRAW` cold / warm (cold p50 / p95; warm p50) |
| --- | --- | --- | --- | --- |
| `sony-ilce-7s.ARW` (5.1 MP) | 65.501 / 69.693 ms; warm 4.865 ms | 110.453 / 111.921 ms; warm 11.922 ms | 108.421 / 114.827 ms; warm 11.892 ms | 105.154 / 109.610 ms; warm 0.061 ms |
| `canon-eos-r6.CR3` (20.0 MP) | 130.313 / 133.327 ms; warm 7.061 ms | 271.962 / 275.236 ms; warm 13.975 ms | 275.123 / 276.733 ms; warm 12.056 ms | 342.191 / 342.723 ms; warm 0.056 ms |
| `olympus-e-m1markii.ORF` (20.2 MP) | 163.830 / 165.640 ms; warm 7.759 ms | 305.980 / 309.746 ms; warm 15.747 ms | 299.858 / 300.929 ms; warm 13.905 ms | 356.830 / 363.171 ms; warm 0.085 ms |
| `nikon-d500.NEF` (20.7 MP) | 154.109 / 156.311 ms; warm 7.195 ms | 179.287 / 181.736 ms; warm 14.100 ms | 185.713 / 188.633 ms; warm 12.296 ms | 245.907 / 253.879 ms; warm 0.111 ms |
| `fujifilm-x-s10.RAF` (26.0 MP) | 102.954 / 105.112 ms; warm 7.322 ms | 249.072 / 252.450 ms; warm 13.950 ms | 242.121 / 248.605 ms; warm 12.080 ms | 329.674 / 336.175 ms; warm 0.106 ms |
| `apple-iphone-12-pro.DNG` (12.2 MP) | 145.303 / 146.076 ms; warm 9.043 ms | 168.516 / 174.103 ms; warm 15.798 ms | 168.048 / 170.454 ms; warm 13.575 ms | 177.642 / 178.429 ms; warm 0.070 ms |
| `panasonic-dmc-gh4.RW2` (15.9 MP) | 86.623 / 88.831 ms; warm 7.758 ms | 190.206 / 190.975 ms; warm 16.906 ms | 183.465 / 184.172 ms; warm 14.471 ms | 220.117 / 223.393 ms; warm 0.101 ms |
| `pentax-k-5-ii-s.DNG` (16.1 MP) | 87.277 / 90.466 ms; warm 6.761 ms | 271.558 / 272.348 ms; warm 14.649 ms | 270.625 / 275.865 ms; warm 13.154 ms | 305.828 / 308.820 ms; warm 0.086 ms |

The `browsing-2000` scan covers 4,000 image files paired into 2,000 photos. The
thumbnail and grouping passes each record 25 standalone HEIC failures with
`noUsablePreview`. The 24 first-detail attempts record 10 failures and 14
successes for the same reason; `detail-screen` filters to 24 RAW sets (`ARW`)
and records 0 failures. Removing `CGImage.dataProvider?.data` from warm probe
checks drops warm `raw-focus` from ~50 ms to `0.062 / 0.091 ms` (and warm
`detail-20mp-native` to `0.075 / 0.117 ms`), while exercising 20–26 MP RAWs
raises peak process RSS from `681.9 MiB` (`5.1 MP` ARW only) to `1,672.7 MiB`.
The cold grouping run computes features for 1,975 photos and produces three
groups. Its duration is not a burst-accuracy result.

### Phase 2 detail-swipe smoothness (`task/perf-phase2-detail-swipes`, Release)

Measured on `Mac17,3` (Apple Silicon MacBook Air, 10 cores, 24 GiB RAM) running
`macOS 27.0.1` (`26A434`) across `286a114` (baseline) vs `65909b4` (O1 + O2)
with `CLOVE_DETAIL_SCREEN_PIXELS=2868` (`collectFullMacReport`, Release):

| Q3 detail metric (`2,868 px`) | Baseline `286a114` (p50 / p95) | Phase 2 `65909b4` (p50 / p95) | Change |
| --- | --- | --- | --- |
| `detail-20mp-preview` cold | `88.542 / 109.806 ms` | `42.983 / 56.342 ms` | `-51.5% / -48.7%` |
| `detail-20mp-preview` warm | `4.890 / 5.529 ms` | `0.045 / 0.058 ms` | `-99.1% / -98.9%` |
| `detail-20mp-screen` cold | `211.495 / 242.204 ms` | `190.347 / 223.481 ms` | `-10.0% / -7.7%` |
| `detail-20mp-screen` warm | `9.113 / 10.075 ms` | `0.040 / 0.054 ms` | `-99.6% / -99.5%` |
| `detail-first-preview` (`browsing-2000` mix) cold | `119.203 / 120.179 ms` | `93.732 / 99.773 ms` | `-21.4% / -17.0%` |
| `detail-format-preview` cold (`sony-ilce-7s.ARW`) | `44.618 / 46.892 ms` | `12.594 / 12.775 ms` | `-71.8% / -72.8%` |
| `detail-format-preview` cold (`canon-eos-r6.CR3`) | `87.297 / 88.542 ms` | `42.707 / 44.670 ms` | `-51.1% / -49.5%` |
| `detail-format-preview` cold (`nikon-d500.NEF`) | `103.008 / 108.171 ms` | `44.607 / 46.291 ms` | `-56.7% / -57.2%` |
| `detail-format-preview` cold (`olympus-e-m1markii.ORF`) | `109.675 / 110.056 ms` | `55.963 / 56.834 ms` | `-49.0% / -48.4%` |
| `detail-format-preview` cold (`fujifilm-x-s10.RAF`) | `69.537 / 70.501 ms` | `34.377 / 34.674 ms` | `-50.6% / -50.8%` |
| `detail-format-preview` cold (`panasonic-dmc-gh4.RW2`) | `48.659 / 50.739 ms` | `12.366 / 13.754 ms` | `-74.6% / -72.9%` |
| `memory-peak` (`detail` / `overall`) | `1,220.8 MiB` | `1,148.5 MiB` | `-5.9%` |

Table 3.4 contention simulation on `Mac17,3` (`2,752 px`, Release, `DetailPipeline`
+ `RegionSharpnessScheduler` `.current` + `.nearby` + `.folder`):

| Workload (`screenPixels = 2752`) | Swipes `n` | Arrival → `preview` (p50 / p95) | Arrival → `screenRAW` (p50 / p95; mean) | `+1 screenRAW` Hits | `nativeRAW` Renders |
| --- | ---: | --- | --- | ---: | ---: |
| `20 MP canon-eos-r6.CR3` — `400 ms` cadence (O1+O2 gated sharpness) | 12 | `0.2 / 5.1 ms` | `0.3 / 239.0 ms` (`27.6 ms`) | `10 / 12` (`83%`) | `0` |
| `20 MP canon-eos-r6.CR3` — `800 ms` cadence (O1+O2 gated sharpness) | 12 | `0.3 / 8.6 ms` | `0.4 / 8.7 ms` (`1.1 ms`) | `12 / 12` (`100%`) | `0` |
| `26 MP fujifilm-x-s10.RAF` (with AF) — `400 ms` cadence (O1+O2 gated sharpness) | 12 | `2.0 / 10.6 ms` | `8.7 / 72.4 ms` (`11.0 ms`) | `11 / 12` (`92%`) | `24` |
| `26 MP fujifilm-x-s10.RAF` (with AF) — `800 ms` cadence (O1+O2 gated sharpness) | 12 | `0.3 / 9.6 ms` | `0.4 / 9.7 ms` (`3.2 ms`) | `12 / 12` (`100%`) | `21` |
| `5.1 MP sony-ilce-7s.ARW+JPG` — `800 ms` cadence (O1+O2 sharpness ON) | 16 | `0.3 / 12.0 ms` | `0.4 / 12.0 ms` (`1.2 ms`) | `16 / 16` (`100%`) | `0` |

Physical-device `xctrace` Animation Hitches verification on the owner's iPad Pro
remains pending TestFlight verification for [#253](https://github.com/mimiqdev/cloveapp/issues/253).

