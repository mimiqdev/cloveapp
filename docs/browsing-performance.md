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
   folder, then tap **Run browsing measurements**.
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
- `feature-read-and-compute` times one-at-a-time production feature requests,
  including preview reading, Vision, dHash, and cache publication.
  `grouping-feature-completion` includes folder-wide queueing.
- `raw-focus-cancel-drain` waits for native render admission, cancels it, and
  measures `DetailPipeline.close()`. `raw-focus-including-cancel` adds that
  drain to a second native RAW render in a fresh pipeline. Only observed
  admission and cancellation enter those distributions.
- `memory-peak` is process RSS sampled every 5 ms. It is a cumulative lower
  bound, not per-stage allocation attribution.
- `grid-scroll-presentation` is unavailable. Lab drives the production
  thumbnail pipeline without Clove's `UICollectionView`, so decode latency is
  not an on-screen frame-rate result.

The Lab caches use a temporary directory that the run deletes. Export uses the
existing tested-folder, Documents, and share-sheet flow.

For a full Mac debug-runner report, generate the fixture set and run:

```sh
CLOVE_BROWSING_PERFORMANCE_REPORT="$PWD/.build/browsing-performance-mac.json" \
CLOVE_SOURCE_REVISION="$(git rev-parse HEAD)" \
swift test --package-path Packages/CloveLabKit --filter collectFullMacReport
```

The runner writes Mac-only evidence. It does not represent an iPhone or a
release build.

## G1 comparison and current Mac evidence

These values come from one full run on a Mac14,12 with 10 cores and macOS 27.0,
using source `c7ca916f2ffd8e30e5d5a0fbce3d4525b0d4054f`. The run took 43.0
seconds on a shared host with load averages 3.21, 2.50, and 2.43. Times are in
milliseconds except throughput and memory. Every iPhone value remains pending
the owner checklist. These are measurements, not pass claims.

| G1 stage | Starting iPhone target | Mac-only p50 / p95 or value | Samples | iPhone |
| --- | --- | --- | --- | --- |
| First photos delivered | ≤ 500 ms | Cold 7.697 / 7.697 ms | 1 | Pending |
| Full scan and pairing | ≤ 3,000 ms | Cold 110.387 / 110.387 ms; warm 99.476 / 101.659 ms | 1 cold, 4 warm | Pending |
| Capture-time read | Measure | Cold serial 2.667 / 2.964 ms | 240 | Pending |
| Uncached grid thumbnail | p95 ≤ 150 ms | Cold 94.224 / 97.802 ms | 1,975 | Pending |
| Disk-cached grid thumbnail | p95 ≤ 20 ms | Disk 13.419 / 13.641 ms | 1,975 | Pending |
| Thumbnail throughput | ≥ 30 photos/s | Cold 323.435/s; disk 2,379.732/s | 1,975 each | Pending |
| First detail preview | p95 ≤ 300 ms | Cold 40.284 / 134.973 ms; warm 3.737 / 8.659 ms | 14 each | Pending |
| Full RAW including cancelled-render wait | p95 ≤ 2,000 ms | Drain 277.279 / 382.027 ms; combined 647.234 / 743.392 ms | 6 | Pending |
| Feature per photo | Measure | Preview+features+cache 20.724 / 42.294 ms | 215 | Pending |
| Grouping total | No numeric G1 target | Cold 21,099.486 ms; warm 750.713 ms | 1 each | Pending |
| Peak process RSS | No numeric G1 target | 712,933,376 bytes (679.9 MiB) | 5 ms samples | Pending |
| Grid scrolling | Q3 names the stage | Unavailable in the package-only Lab flow | 0 | Pending |

The scan covers 4,000 image files paired into 2,000 photos. The thumbnail and
grouping passes each record 25 standalone HEIC failures with `noUsablePreview`.
The 24 first-detail attempts record 10 failures and 14 successes for the same
reason. The cold grouping run computes features for 1,975 photos and produces
three groups. Its duration is not a burst-accuracy result.
