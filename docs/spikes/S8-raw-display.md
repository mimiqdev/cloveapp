# S8 — What does showing a RAW's own colours cost on the iPhone?

## Question

What does showing a RAW's own colours cost on the iPhone, and how do decode-time
scaling, draft mode, a reused `CIContext`, colour agreement, contention, sustained
load and caching change that cost? The answer informs the owner's new setting with
two modes, RAW first and camera preview first, and its default.

Part 1 of [#122](https://github.com/mimiqdev/cloveapp/issues/122) added the probe
and Clove Lab screen. Part 2, delivered with
[#132](https://github.com/mimiqdev/cloveapp/issues/132), records the iPhone device
summaries below and the decided product policy. The private reports were read in
place by a script outside the checkout. Only aggregate measurements are published.

Owner decision behind the task (2026-11-11): RAW is the truth when it is present,
and neither mode may mix sources by zoom level or history. The camera-preview mode
therefore needs a 100% source, which is why this probe measures a full HIF decode
and two reduced HIF decodes next to the RAW variants.

## What was tested

- Xcode **27.2**, iOS SDK **27.2**; Swift 6 language mode, debug compilation.
- macOS **27.0**, **Mac14,12 (Mac mini)**. The Mac run below is a **shared, loaded
  host with another spike worker**. It is **not a device measurement** and no
  iPhone performance claim follows from it.
- The `formats` fixture set from [docs/fixtures.md](../fixtures.md): the Sony
  ILCE-7S ARW (**2768×1848** output) and the locally generated Sony HEIC
  (**2768×1848**), copied into a unique temporary folder under the same stem so
  the probe's same-folder pairing applies. The HEIC is a stand-in camera-preview
  companion, not a real A1 II HIF. The fixture cache's `files/` folder was only
  read.
- Mac run: one `swift test` invocation of the same `RAWDisplaySuite.run` and
  `RAWDisplaySuite.runSustained` functions the Lab screen calls, with
  `CLOVE_RAW_DISPLAY_REPORT` set. Every count is clamped to the files present, so
  the Mac run used 1 RAW, 1 camera-preview pair, 1 colour file and 1 cache file and
  a 10-render sustained bound. Screen long edge was **2000 px**, a stand-in for a
  device screen, not a measured screen size. The display run took **5.0 s** on the
  loaded Mac; the device estimate below is derived from that.
- Report rows never contain the folder or file names: a RAW is `raw-01.<EXT>` and
  its camera preview shares the number (`raw-01.HIF`). The two JSON files are the
  only artifacts the owner shares.
- JSON artifacts stay out of git, in the gitignored `.build/rawdisplay/` folder:
  `macOS.json` and `macOS-sustained.json`. On device the same runs write
  `clove-lab-S8-<timestamp>.json` into the tested folder and into Files › Clove
  Lab.
- Clove Lab lists the topic as **S8 · RAW display** and gives the display suite and
  the sustained-load step their own buttons, each producing its own report. The
  screen was opened on a throwaway iOS 27.0 simulator (iPhone 17 Pro) and showed
  the picker, a screen long edge of 2,622 px, disabled run buttons before a folder
  was chosen, and the status/export sections. The simulator was deleted afterwards.

### What the probe is, and is not

`CloveLabKit/Sources/RAWDisplayProbe` measures; it does not change Clove's preview
pipeline. The suite is synchronous decode work inside a detached task on the Lab
screen, so the screen stays responsive and Cancel is available between renders. A
native decode cannot be interrupted: cancel discards the result and the slot stays
occupied until the call returns.

## Method

### Render variants

| Variant | Render | Output size | Context | Draft |
| --- | --- | --- | --- | --- |
| a `raw-native-fresh-context` | `CIRAWFilter` | native | new `CIContext` per render (today's detail pipeline) | off |
| b `raw-native-reused-context` | `CIRAWFilter` | native | one `CIContext` kept by the renderer | off |
| c `raw-screen-scale` | `CIRAWFilter` | `scaleFactor` for the screen long edge | reused | off |
| d `raw-screen-scale-draft` | `CIRAWFilter` | same as c | reused | on |
| e `raw-grid-scale` / `raw-grid-scale-draft` | `CIRAWFilter` | `scaleFactor` for 400 px | reused | off / on |
| f `camera-full-decode` | `CGImageSourceCreateImageAtIndex` | native | — | — |
| g `camera-subsample-2` | same, `kCGImageSourceSubsampleFactor` 2 | half the native edge | — | — |
| g `camera-screen-thumbnail` | `CreateThumbnailFromImageAlways` at the screen edge | screen long edge | — | — |

`scaleFactor` and `isDraftModeEnabled` are set after the filter opens and before
`outputImage` is requested. Both are therefore decode-time requests, **not** a
downscale of an already rendered bitmap. S2's "2000 px" RAW row rendered at native
size and then transformed the output, which is why its 592.8 ms sat next to the
529.1 ms native number; S2 said so in its method. Every c–e row in this probe is a
different route and must not be compared with S2's 2000 px row.

Orientation is a display transform in production, so it is excluded from the timed
section. All three camera routes time an unoriented decode: `CreateThumbnailWithTransform`
is false, and `CGImageSourceCreateImageAtIndex` leaves orientation to the caller.
Output sizes are still reported display-oriented: the edges are swapped for
orientations 5–8, which costs no pixel work. Every render row — RAW, camera, swipe
and sustained — carries its source orientation as a tag, and the colour comparison
applies the orientation once before comparing. The RAW routes are unaffected
because `CIRAWFilter` applies orientation itself.

The probe records the requested long edge, the actual output size and the time to
a **materialized CPU bitmap** (`image.dataProvider?.data`). It does not inspect
which internal decoder stage honours `scaleFactor` or draft mode, and it does not
measure GPU-only completion or on-screen presentation.

### Startup, cold and warm

One extra render of variant a runs before the cold pass and is reported on its own
`phase: startup` row. It absorbs the process's first Core Image and RAW setup, so
variant a's cold number is comparable with the other variants instead of carrying a
one-off cost. On the Mac it took 151.4 ms; after it, a's cold render was 99.6 ms
against a 93.4 ms warm median, i.e. within run-to-run noise.

Each variant's first measured render after the startup row is `cold`; every later
render is `warm`. Warm repeats are three per variant per file. Cold is *not* a cold
process, cold framework cache or cold card read: by the time a later variant has its
cold render, the same process has already rendered other variants of the same file.
The report tags every row with its phase, and `render-summary-cold` keeps the cold
value separate.

Warm median and p90 use all warm samples for the variant. The percentile is
nearest-rank, so **p90 of 3 repeats is the largest of the three**.

### Colour agreement

Every comparison draws both images into same-sized sRGB bitmaps and samples a
lattice of at most **4096 pixels**. The metric is **CIEDE2000** (kL = kC = kH = 1),
checked against Sharma, Wu and Dalal's published reference pairs, and returns 0 for
identical images. A larger reference is reduced with `CILanczosScaleTransform`
*after its render* and then drawn to the reduced variant's exact size, so a
comparison includes the resampling step and says nothing about sharpness.

Three comparisons are reported:

- every reduced RAW variant against the native render at the same size;
- the camera HEIF's embedded preview against that native render (the colour jump a
  reader sees when the RAW render replaces the placeholder);
- the full camera HEIF decode against the camera HEIF's embedded preview, which
  should be close to 0.

### Swipe simulation

Walks up to 20 photos per dwell (0, 300 and 800 ms). **The dwell is the whole time
spent on the photo**, so the leaving deadline is fixed at arrival. For each photo
the walk records arrival, requests the embedded preview at 2000 px, starts the
fastest screen-size RAW variant measured earlier in the run right away, waits only
until the deadline, then leaves. A render is `ready` when it finished before the
deadline, with pixels; one that returns no pixels is `failed`; one that is still
running at the deadline is `wasted` and keeps running, because Core Image cannot
cancel mid-render. The next photo's render is queued behind it, so only one decoder
is busy at a time, as in production; the next photo's preview is the contended case.
Cancellation stops every queued render through the same registry, so a cancelled
walk admits no further decode.

Two times are recorded for a ready render: `swipe-render-ready` from requesting the
render to its completion, and `swipe-arrival-to-ready` from arrival to completion.
The second contains the preview, the render request and the render, plus the small
orchestration gaps between them, so it is slightly more than the sum of the two
reported pieces. Neither is an on-screen presentation measurement; completion of
the bitmap is the proxy for "showing". `swipe-renders-started`, `-ready`, `-wasted`
and `-failed` classify every started render exactly once, and progress counts
photos, not dwells.

Preview time is the **total wall time** of the request, so a failed camera HEIF
attempt that falls back to the RAW's own embedded preview includes both attempts;
`previewAttempt` keeps the first attempt's own time. `renderRunning`, sampled at
arrival, marks a photo whose previous render is still running.

### Sustained load

A separate button and report. The faster screen-size variant is selected with a
short warm pass, then rendered back to back until **300 renders or 5 minutes**,
whichever comes first. The duration bound is checked before each render, so the
last render can run past it. Each render's time, every `ProcessInfo.thermalState`
change with its elapsed seconds, and the start/end thermal state are recorded.
Battery level is read by the **Lab app layer** (`UIDevice.batteryLevel`); the
probe module stays UIKit-free, and the view appends `battery-end` plus both
battery states to the report. `batteryLevel` moves in **5% steps**, so compare the
ends only at that resolution. A level the system does not report is recorded as
-1.

### Cache cost

For the screen-size variant: encode to HEIC and JPEG at quality **0.9** into a
temporary folder, record encode time, file bytes and decode time, then hold six
decoded renders at once. `cache-held-resident` is RSS after all six are held minus
RSS before the loop; `cache-held-resident-absolute` and `cache-held-render-peak`
are separate columns. The temporary folder is removed after the run.

### Grid estimate

The fastest 400 px variant's per-photo warm median is projected to a **2000-photo**
folder at concurrency 1 and 2. This is arithmetic on one measured render time, not
a concurrent measurement; the concurrency-2 row assumes perfect division.

### Bounds

- Detailed RAW variants: first **12** RAWs.
- Camera HEIF variants and their colour comparison: first **6** RAW + HEIF pairs.
  The supervisor's 2026-11-11 scope update for this task (a coordinator instruction,
  not issue text) allows 6 pairs instead of 12 when the HIF variants would push the
  run over about ten minutes; this probe takes that option and says so here. The
  full-HIF decode is the slowest step.
- Colour: **every** detailed RAW (up to 12) for the reduced-variant comparisons.
- Swipes: first **20** photos, three dwells.
- Cache: **6** files.
- Sustained: 300 renders or 5 minutes, on its own button.
- Every loop checks cancellation between steps and is bounded by the counts above.
  File discovery has the preview probe's rules — it skips hidden files and
  `_Rejected`, keeps RAW and camera HEIF paths, checks cancellation during the
  walk, and sorts — then samples the first N. Those counts bound every image decode
  and every retained bitmap; discovery itself reads paths only. The swipe progress
  counts photos; each draw is one step.

**Time estimate.** The Mac display run took 5.0 s with one RAW and one pair. The
per-file RAW variant work dominates: about 2.0 s per RAW on this host, so 12 RAWs
would be about 24 s on the Mac. Scaling that by S2's roughly 5.5× Mac-to-device
native render ratio gives about 2.5 minutes of RAW variants, plus the fixed HIF,
colour, swipe and cache phases. The device run is therefore expected to take
**about 5 minutes**, and `run-duration` records the actual number. The sustained
step is a separate 5-minute bound.

### Memory

Every timed render and its `dataProvider` copy runs inside a per-render
`autoreleasepool`, including the cache, sustained and swipe loops.

`render-sampled-peak-resident` samples absolute **process RSS every 5 ms**; it is a
lower bound that includes framework caches and other work, and a decode buffer can
be missed between samples. The report also records the RSS immediately before each
render. With per-render `autoreleasepool` wrapping, the warm baseline no longer grows
**inside a variant**: within each RAW variant it moved by at most 0.3 MiB. Across
variants the warm RAW baseline medians run from 89.2 to 120.8 MiB (individual warm
baselines start at 89.0 MiB), and the camera baseline medians from 167.5 to 193.9 MiB; the earlier build climbed from about 120 MiB to 585 MiB
over the same RAW variants. The camera repeats rise by up to about 13 MiB. The cause
of the remaining between-variant and camera growth is not isolated by this probe;
it is consistent with framework caches but not proven to be only that. The
sustained step records timings and thermal state, not per-render RSS, so it makes no
memory-stability claim. The difference between peak and baseline is still not an
isolated allocation count.

## Data

### macOS: RAW variants, not device numbers

One fixture ARW, 2768×1848, one warm repeat set of 3, after the startup row
(**151.4 ms**, `phase: startup`). Times in milliseconds to a materialized bitmap.
Memory is MiB (2²⁰ bytes); peak and baseline are medians of the warm renders. The
baseline no longer grows inside a variant, so the peak is a useful working-memory
bound rather than an artifact of earlier variants.

| Variant | Long edge asked | Actual output | Cold ms | Warm median ms | Warm p90 ms | Decoded MiB | Peak RSS MiB / baseline |
| --- | --- | --- | --- | --- | --- | --- | --- |
| a native, fresh context | native | 2768×1848 | 99.6 | 93.4 | 98.2 | 19.51 | 133.9 / 89.2 |
| b native, reused context | native | 2768×1848 | 85.3 | 85.1 | 88.4 | 19.51 | 118.7 / 99.5 |
| c screen `scaleFactor` | 2000 | 2000×1336 | 81.3 | 74.0 | 74.8 | 10.19 | 135.2 / 119.9 |
| d screen `scaleFactor`, draft | 2000 | 2000×1336 | 71.0 | 74.2 | 76.4 | 10.19 | 135.2 / 120.0 |
| e grid `scaleFactor` | 400 | 400×268 | 68.8 | 66.5 | 68.1 | 0.41 | 136.0 / 120.7 |
| e grid `scaleFactor`, draft | 400 | 400×268 | 66.3 | 69.2 | 69.5 | 0.41 | 136.0 / 120.8 |

Every row succeeded. The requested long edge arrived within 2 px on this fixture.
On this host `scaleFactor` saved about **11 ms** at screen size and **16–19 ms**
at grid size against the native reused-context render, or about **19–27 ms**
against the fresh-context one. Draft mode did not separate from non-draft at either
size. After the startup row, variant a's cold render is within noise of its warm
median; the earlier 181 ms cold penalty was process setup and is now attributed to
the startup row instead. Individual deltas varied by a few milliseconds between
repeat runs on this shared host, so treat them as approximate. Those are Mac numbers from a loaded host and must not be
read as iPhone ratios.

Baseline flatness across the same run, first → last of the three warm renders:

| Variant | Baseline MiB first → last |
| --- | --- |
| a native, fresh context | 89.0 → 89.3 |
| b native, reused context | 99.4 → 99.5 |
| c screen `scaleFactor` | 119.9 → 119.9 |
| d screen draft | 120.0 → 120.0 |
| e grid `scaleFactor` | 120.6 → 120.7 |
| e grid draft | 120.8 → 120.8 |
| f full decode | 167.5 → 180.2 |
| g subsample factor 2 | 168.3 → 171.5 |
| g screen thumbnail | 188.1 → 193.9 |

The earlier build's baseline climbed from about 120 to 585 MiB over the same
variants; per-render `autoreleasepool` wrapping removed that growth. The camera
rows still show a small rise (up to about 13 MiB), consistent with framework caches
but not isolated by this probe
rather than retained render bitmaps. These are process-wide RSS baselines, not
isolated allocations.

### macOS: camera HEIF variants, not device numbers

Same fixture session; the HEIC is the generated fixture, not a camera HIF.

| Variant | Actual output | Orientation | Cold ms | Warm median ms | Warm p90 ms | Decoded MiB | Peak RSS MiB / baseline |
| --- | --- | --- | --- | --- | --- | --- | --- |
| f full decode | 2768×1848 | 1 | 143.8 | 87.9 | 91.6 | 19.51 | 197.5 / 180.2 |
| g subsample factor 2 | 1384×924 | 1 | 40.6 | 40.4 | 42.1 | 4.88 | 173.3 / 171.4 |
| g screen thumbnail, always | 2000×1336 | 1 | 49.0 | 48.8 | 49.3 | 10.19 | 195.6 / 193.9 |

The full decode produced exactly the container's pixel size and the subsample
factor halved both edges, so both requests are honoured on this platform. This
fixture carries no rotation, so its orientation tag is 1; the orientation handling
is covered by a generated orientation-6 JPEG test that checks the swapped output
size and the tag. The f and g rows are timed decodes without the display-orientation
redraw. Again, macOS numbers from a loaded host; the A1 II HIF is 8640×5760 and the
device run is what matters.

### macOS: colour agreement, not device numbers

| Comparison | Method | Mean ΔE00 | p95 | Max | Compared pixels | Samples |
| --- | --- | --- | --- | --- | --- | --- |
| reduced RAW vs native | c screen `scaleFactor` | 1.66 | 6.30 | 18.03 | 2000×1336 | 4004 |
| reduced RAW vs native | d screen draft | 1.66 | 6.30 | 18.03 | 2000×1336 | 4004 |
| reduced RAW vs native | e grid `scaleFactor` | 4.01 | 10.78 | 74.48 | 400×268 | 3015 |
| reduced RAW vs native | e grid draft | 4.01 | 10.78 | 74.48 | 400×268 | 3015 |
| camera preview vs RAW native | embedded HEIC preview | — | — | — | — | — |
| full camera HEIF vs its preview | full decode | — | — | — | — | — |

Draft and non-draft produced identical differences on this file, as expected for
the same colour pipeline. The grid row's larger spread is consistent with the same
small differences being magnified at 400 px and with resampling; this probe does
not separate those causes. The two camera rows have no number because the generated
HEIC fixture exposes **no embedded preview on macOS** (`noThumbnail`, matching S2's
HEIC `embeddedOnly` result). That is fixture behaviour, not a probe failure; the
A1 II HIF returned a 1616 px embedded preview in S2's device run, so the device
table should have both rows.

### macOS: swipe simulation, not device numbers

One photo per walk, so the preview never had a previous render running and the
walk cannot show contention. The rows show the classification model.

| Dwell | Preview median ms (source, 1616 px) | Render ready ms | Arrival → ready ms | Started / ready / wasted / failed |
| --- | --- | --- | --- | --- |
| 0 ms | 17.6, RAW fallback, no render running | — | — | 1 / 0 / 1 / 0 |
| 300 ms | 16.1, RAW fallback, no render running | 79.6 | 98.4 | 1 / 1 / 0 / 0 |
| 800 ms | 36.7, RAW fallback, no render running | 95.0 | 140.1 | 1 / 1 / 0 / 0 |

The HEIC fixture has no embedded preview on macOS, so these preview requests used
the RAW's own 1616 px preview. With a 0 ms dwell the render (about 67–100 ms on
this host) had not finished before the reader left, so it counts as wasted; the
300 and 800 ms rows finish inside the dwell and count as ready, with
arrival-to-ready covering the preview, the render and the small orchestration gaps
between them. A 20-photo device walk is what
measures contention, because only then does one photo's render run into the next
photo's preview.

### macOS: cache cost, not device numbers

One screen-size render (2000×1336, 10.19 MiB decoded), encoded at quality 0.9.

| Measurement | HEIC | JPEG |
| --- | --- | --- |
| Encode ms | 40.6 | 13.9 |
| File bytes | 708,390 | 854,362 |
| Decode ms | 16.1 | 6.9 |
| Decoded bytes | 10,688,000 | 10,688,000 |

The six-held-image sample has one image on this run: 10,688,000 B summed bitmap
bytes, **10,862,592 B (10.4 MiB) RSS growth** over the pre-loop baseline,
225,771,520 B absolute (215.3 MiB), 231,063,552 B peak during the renders
(220.4 MiB), and 120.3 ms of renders. The device run with six files is what answers
the six-image question; the delta and the peak are separate columns.

### macOS: grid projection, not device numbers

Best 400 px variant in this run: `raw-grid-scale`, warm median **66.5 ms** per
photo.

| Projection | 2000 photos |
| --- | --- |
| Concurrency 1, arithmetic | 133.1 s |
| Concurrency 2, arithmetic, perfect division | 66.5 s |

The device run's numbers replace this projection; it is not a concurrent
measurement and not a promise that two decoders halve the time.

### macOS: sustained-load path check, not device numbers

10-render bound, one file, selected variant `raw-screen-scale-draft` (71.9 ms
selection warm median against 72.2 ms for draft off; the startup row is excluded
from selection). Total 806.5 ms; individual renders 71.3–79.8 ms; thermal state
`nominal` at start and end, no transitions; no battery reading on macOS. This only shows that the second button's code path runs. Heat,
thermal transitions and battery drain need the device.

### Device: iPhone results

Measured on iPhone 17 Pro Max with local A1 II ARW+HIF pairs. The display suite
covered 12 RAWs, six full-HIF pairs, three warm repeats per file, and a 2670 px
screen edge. RAW warm statistics aggregate 36 renders per variant, camera
statistics 18. Cold is one observation per variant after startup. All render
variants succeeded. Times end at materialized CPU pixels, not presentation.
Peak RSS is the median of warm absolute process samples, including earlier work.

The iPad run is **Not run** for every table below. No iPhone result is an iPad
measurement. The run keeps the screen awake through
`UIApplication.shared.isIdleTimerDisabled`.

| Status | RAW variant | Cold ms | Warm median / p90 ms | Output | Decoded MiB | Peak RSS MiB |
| --- | --- | --- | --- | --- | --- | --- |
| Measured | a native, fresh context | 530.8 | 521.9 / 683.3 | 5760×8640 | 189.84 | 615.8 |
| Measured | b native, reused context | 491.3 | 503.5 / 754.8 | 5760×8640 | 189.84 | 627.2 |
| Measured | c screen `scaleFactor` | 281.0 | 287.7 / 370.7 | 1780×2670 | 18.13 | 528.8 |
| Measured | d screen draft | 270.4 | 287.1 / 351.0 | 1780×2670 | 18.13 | 528.4 |
| Measured | e grid `scaleFactor` | 259.6 | 266.2 / 297.8 | 267×400 | 0.41 | 315.2 |
| Measured | e grid draft | 252.8 | 263.3 / 298.5 | 267×400 | 0.41 | 315.0 |

| Status | Camera HEIF variant | Cold ms | Warm median / p90 ms | Output | Decoded MiB | Peak RSS MiB |
| --- | --- | --- | --- | --- | --- | --- |
| Measured | f full decode (100% source) | 97.7 | 106.6 / 118.7 | 5760×8640 | 189.84 | 795.5 |
| Measured | g subsample factor 2 | 68.7 | 63.9 / 70.1 | 2880×4320 | 47.46 | 507.5 |
| Measured | g screen thumbnail, always | 122.4 | 64.0 / 66.1 | 1780×2670 | 18.13 | 481.8 |

| Status | Colour comparison | Mean ΔE00 | p95 | Max | Compared pixels |
| --- | --- | --- | --- | --- | --- |
| Measured | c screen vs native | 0.83 | 2.53 | 17.51 | 1780×2670 |
| Measured | d screen draft vs native | 0.83 | 2.53 | 17.51 | 1780×2670 |
| Measured | e grid vs native | 2.00 | 7.19 | 31.36 | 267×400 |
| Measured | e grid draft vs native | 2.00 | 7.19 | 31.36 | 267×400 |
| Measured | HIF embedded preview vs RAW native | 9.04 | 17.53 | 31.50 | 1080×1616 |
| Measured | full HIF decode vs HIF preview | 1.27 | 3.84 | 16.21 | 1080×1616 |

Colour columns are medians of per-file mean, p95 and maximum, across 12 RAWs
or six full-HIF pairs. The maximum column is a median of maxima, not a global
maximum. Resampling contributes to these differences. The screen and native RAW
colours agree much more closely than the camera preview and RAW; full HIF versus
its preview is close but not zero. Draft and non-draft results agree.

| Status | Dwell | Preview ms, render running / idle | Render ready ms | Arrival → ready ms | Started / ready / wasted / failed |
| --- | --- | --- | --- | --- | --- |
| Measured | 0 ms | 8.23 / 10.19 | — | — | 12 / 0 / 12 / 0 |
| Measured | 300 ms | 8.26 / 7.49 | 278.7 | 288.4 | 12 / 6 / 6 / 0 |
| Measured | 800 ms | Not observed / 18.52 | 331.7 | 363.1 | 12 / 12 / 0 / 0 |

Each walk used the 12 available photos, below the 20-photo cap. Preview medians
cover running/idle counts of 11/1, 5/7 and 0/12 respectively. These small groups
cannot establish a contention penalty. Half the renders missed a 300 ms dwell;
all finished within 800 ms. Fast travel needs queued cancellation and stale-result
discard.

| Status | Sustained load | Value |
| --- | --- | --- |
| Measured | Renders completed / duration | 300 / 86.6 s; median 285.6 ms, range 265.0–316.7 ms |
| Measured | Thermal transitions with elapsed seconds | nominal → fair at 41.9 s; fair at end |
| Measured | Battery start → end, charging state | 80% → 80%, unplugged |
| Measured | Screen-size cache: HEIC encode / bytes / decode | 48.7 ms / 699,352 B / 30.0 ms medians, six files |
| Measured | Screen-size cache: JPEG encode / bytes / decode | 22.7 ms / 1,092,680 B / 11.1 ms medians, six files |
| Measured | Six decoded screen renders held: bytes / RSS | 114,062,400 B (108.8 MiB) bitmaps; 166.5 MiB RSS growth; 1129.8 MiB absolute; 1245.6 MiB sampled peak |
| Measured | Grid per-photo and 2000-photo projection, concurrency 1 / 2 | 263.3 ms; 526.5 s / 263.3 s, arithmetic only |
| Measured | Suite duration (5-minute estimate check) | 199.5 s, about 3.3 minutes |

The sustained run stopped at its **300-render bound after about 87 seconds**, not
five minutes. The battery read showed no change over that interval at its coarse
resolution. It does not establish five-minute thermal behaviour or battery drain.
Holding six images cost about 27.7 MiB RSS per image, compared with 18.13 MiB of
bitmap bytes each. RSS includes decoder/framework state and cannot define a safe
process ceiling.

### Decided display policy

The owner's decision in #132 is **RAW first by default**, with **Camera preview
first** as the other consistent mode. Neither mode changes colour sources because
of zoom level or navigation history. The camera preview fills the wait for RAW.

RAW first pays about 288 ms for a new screen-size render, compared with about
503 ms for native RAW. It keeps at most three screen renders for the current photo
and neighbours, and renders one ahead in the direction of travel after the current
render is shown. Native RAW is requested only beyond the screen render or for
100%. The render lane remains single, draft stays off, and no disk cache is added.

Camera preview first keeps the cheap embedded fit route. Its camera 100% route
uses full ImageIO HIF decoding, about 107 ms and 795 MiB median sampled peak RSS,
or full JPEG. This is a different route from S2's 1.8 s CIRAWFilter HIF control.
Only one full decode is held, released on leaving the photo. A RAW set without a
usable camera full image uses RAW first for that whole photo. JPEG-only and
HIF-only behaviour is unchanged. The grid stays on embedded previews.

The supervisor's revised device default is memory only: below 5 GiB reported
physical memory gives Camera preview first; otherwise RAW first. Exactly 5 GiB
gives RAW. The 5 GiB boundary replaces issue #132's 6 GiB boundary because nominal
6 GB iPhones report about 5.5–5.8 GiB, while 4 GB phones report about 3.7 GiB.
The owner prefers no extra state, so the product collects no render-time samples,
stores no measurement, and applies no speed rule. An explicit Settings choice
wins. Reset clears that choice and returns to the memory-only device default;
the UI offers only RAW and Camera preview.

## Remaining questions

- Does the brief camera-to-RAW colour shift bother the owner during normal
  navigation? The colour metric measures a difference, not preference. Visual
  focus detail and the screen-to-native replacement still need the owner's eye.
- Does repeated navigation with one full HIF decode stay within a safe device
  memory ceiling? The suite completed, but sampled process peaks do not establish
  pressure recovery or a launch memory budget.
- What does RAW grid generation cost in a concurrent pipeline? The 8.8-minute
  serial estimate for 2000 photos is arithmetic. Concurrent work remains unmeasured
  and the grid is outside #132.
- What happens after five minutes of sustained load? This run ended at the count
  bound after 87 seconds, with fair thermal state and an unchanged battery read.
- Does iPad screen size change colour, latency or memory materially? All iPad
  measurements remain Not run.

## Device checklist

Part 1 writes the checklist; part 2 and the owner's run fill the device tables.

1. After the supervisor publishes the merged Lab build, install **Clove Lab** from
   TestFlight on **iPhone 17 Pro Max**. Note the installed iOS version; the report
   records the hardware identifier, iOS version and app build itself. Set
   **Auto-Lock to Never** for the run; the app also keeps the screen awake while a
   run is active.
2. Copy **12 or more A1 II ARW + HIF pairs** (each `.ARW` with its same-name `.HIF`)
   to local storage, not a card or reader. Unplug the charger and let the phone sit
   at room temperature.
3. Open **Clove Lab → S8 · RAW display**, choose the local-storage location (the
   report records no names), and check **Screen long edge** matches the phone's
   panel. Adjust it only if it is wrong.
4. Tap **Run display suite**. Expect a progress count that moves through RAW
   variants, camera HEIF variants, colour, swipes, cache and the grid projection,
   then **Finished: clove-lab-S8-<timestamp>.json**. The app must stay responsive
   and **Cancel** must be available. Allow **about 5 minutes** (see the estimate
   below); if the run takes much longer, record the last progress message instead
   of repeating it.
5. Tap **Run sustained load (up to 5 min)**. Expect up to 300 renders or five
   minutes of progress, then a second **Finished: clove-lab-S8-<timestamp>.json**.
   Keep the app in the foreground; note whether the phone becomes warm.
6. Use **Export** in the footer for each report, or find both in Files › On My
   iPhone › Clove Lab. They are also written into the tested folder. Share both
   reports privately with the supervisor, identifying the device and iOS version.
   Do not attach the JSON to the public issue or repository. Only summary numbers
   belong in this report. Battery levels are recorded in 5% steps.
7. Repeat steps 1–6 on **iPad Pro**, recording its model and installed iPadOS
   version. The screen long edge is read from that device, so c–e and g change
   size.
8. If a run stops early or a variant row fails in the JSON, keep the report and
   say which step stopped; a failure is recorded as a `status` tag rather than
   stopping the whole run.
