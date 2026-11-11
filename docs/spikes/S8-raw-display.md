# S8 — What does showing a RAW's own colours cost on the iPhone?

## Question

What does showing a RAW's own colours cost on the iPhone, and how do decode-time
scaling, draft mode, a reused `CIContext`, colour agreement, contention, sustained
load and caching change that cost? The answer informs the owner's new setting with
two modes, RAW first and camera preview first, and its default.

This is **part 1 of [#122](https://github.com/mimiqdev/cloveapp/issues/122)**: the
probe, the Clove Lab screen and this report. The owner's device run fills the
device tables in part 2, which sets out both modes' costs. **This report makes no
product recommendation and states no device number.** It also changes no product
code: `Clove`, `CloveCore` and `CloveImaging` are untouched.

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
  device screen, not a measured screen size.
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

The camera HEIF full and subsample decodes apply EXIF orientation after decoding,
because `CGImageSourceCreateImageAtIndex` leaves orientation to the caller and a
100% source must be displayed the same way as the embedded preview. The thumbnail
route already applies it through `CreateThumbnailWithTransform`. Output sizes for
f and g are therefore display-oriented (edges swapped for orientations 5–8), and a
rotated file's f/g time includes the orientation redraw. The RAW routes are
unaffected because `CIRAWFilter` applies orientation itself.

The probe records the requested long edge, the actual output size and the time to
a **materialized CPU bitmap** (`image.dataProvider?.data`). It does not inspect
which internal decoder stage honours `scaleFactor` or draft mode, and it does not
measure GPU-only completion or on-screen presentation.

### Cold and warm

Each variant's first render in the run is `cold`; every later render is `warm`.
Warm repeats are three per variant per file. Cold is *not* a cold process, cold
framework cache or cold card read: by the time a later variant has its cold render,
the same process has already rendered other variants of the same file. The report
tags every row with its phase, and `render-summary-cold` keeps the cold value
separate.

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

Walks up to 20 photos per dwell (0, 300 and 800 ms). Arrival is the instant the
reader lands on a photo. From there it requests the embedded preview at 2000 px,
waits the dwell, then requests the fastest screen-size RAW variant measured earlier
in the run in a background task and moves on. One render is in flight at a time, as
in production. A render that has not finished **before the next arrival** is
superseded: it is cancelled, drained, and its drain is timed. At the end of the walk
the last render is awaited, because the reader stays on that photo.

Two times are recorded for a render that succeeds: `swipe-render-ready` from
requesting the render to its completion, and `swipe-arrival-to-ready` from arrival
to completion, which therefore also contains the preview request and the dwell.
Neither is an on-screen presentation measurement; completion of the bitmap is the
proxy for "showing". A render that finishes before the next arrival but returns no
pixels is recorded as `swipe-render-failed`, not ready. `swipe-renders-started`,
`-ready`, `-wasted` and `-failed` classify every started render exactly once.

Preview time is tagged with `renderRunning`, sampled at arrival: a photo whose
previous render is still running is the contention case. If the camera HEIF preview
has no usable pixels, the preview request falls back to the RAW's own embedded
preview and the tag says so.

### Sustained load

A separate button and report. The faster screen-size variant is selected with a
short warm pass, then rendered back to back until **300 renders or 5 minutes**,
whichever comes first. The duration bound is checked before each render, so the
last render can run past it. Each render's time, every `ProcessInfo.thermalState`
change with its elapsed seconds, and the start/end thermal state are recorded.
Battery level is read by the **Lab app layer** (`UIDevice.batteryLevel`); the
probe module stays UIKit-free, and the view appends `battery-end` plus both
battery states to the report. A level the system does not report is recorded as
-1.

### Cache cost

For the screen-size variant: encode to HEIC and JPEG at quality **0.9** into a
temporary folder, record encode time, file bytes and decode time, then hold six
decoded renders at once and record their summed bitmap bytes and the sampled
process RSS. The temporary folder is removed after the run.

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
  and every retained bitmap; discovery itself reads paths only.

### Memory

`render-sampled-peak-resident` and `cache-held-resident` sample absolute **process
RSS every 5 ms**. They are lower bounds that include framework caches and other
work in the process, and a decode buffer can be missed between samples. The report
also records the RSS immediately before each render, so the Mac tables below show
both the peak and the median baseline. The difference is not an isolated
allocation count.

## Data

### macOS: RAW variants, not device numbers

One fixture ARW, 2768×1848, one warm repeat set of 3. Times in milliseconds to a
materialized bitmap. Memory is MiB (2²⁰ bytes); peak and baseline are medians of
the warm renders, and the baseline grows across this serial run, so read the
**delta** as a lower bound on working memory, not as a per-variant budget.

| Variant | Long edge asked | Actual output | Cold ms | Warm median ms | Warm p90 ms | Decoded MiB | Peak RSS MiB / baseline |
| --- | --- | --- | --- | --- | --- | --- | --- |
| a native, fresh context | native | 2768×1848 | 275.9 | 95.0 | 99.3 | 19.51 | 163.0 / 120.4 |
| b native, reused context | native | 2768×1848 | 93.0 | 82.1 | 87.9 | 19.51 | 212.1 / 195.8 |
| c screen `scaleFactor` | 2000 | 2000×1336 | 80.7 | 74.6 | 75.6 | 10.19 | 307.7 / 281.2 |
| d screen `scaleFactor`, draft | 2000 | 2000×1336 | 75.7 | 74.4 | 75.2 | 10.19 | 362.7 / 346.3 |
| e grid `scaleFactor` | 400 | 400×268 | 68.8 | 69.7 | 70.0 | 0.41 | 428.7 / 412.3 |
| e grid `scaleFactor`, draft | 400 | 400×268 | 69.8 | 68.1 | 69.3 | 0.41 | 494.2 / 477.9 |

Every row succeeded. The requested long edge arrived within 2 px on this fixture.
On this host `scaleFactor` saved about **7.5 ms** at screen size and **12.4 ms**
(draft off) or **14.0 ms** (draft on) at grid size against the native reused-context
render; against the fresh-context native render the saving was about **20–27 ms**.
Draft mode did not separate from non-draft at either size. The first cold
fresh-context native render paid about **181 ms** over its warm median. Those are
Mac numbers from a loaded host and must not be read as iPhone ratios.

### macOS: camera HEIF variants, not device numbers

Same fixture session; the HEIC is the generated fixture, not a camera HIF.

| Variant | Actual output | Cold ms | Warm median ms | Warm p90 ms | Decoded MiB | Peak RSS MiB / baseline |
| --- | --- | --- | --- | --- | --- | --- |
| f full decode | 2768×1848 | 143.2 | 82.4 | 83.6 | 19.51 | 585.9 / 570.6 |
| g subsample factor 2 | 1384×924 | 41.2 | 40.1 | 41.4 | 4.88 | 563.7 / 561.9 |
| g screen thumbnail, always | 2000×1336 | 50.0 | 49.3 | 50.7 | 10.19 | 586.3 / 584.5 |

The full decode produced exactly the container's pixel size and the subsample
factor halved both edges, so both requests are honoured on this platform. This
fixture carries no rotation; the orientation handling is covered by a generated
orientation-6 JPEG test instead. Again, macOS numbers from a loaded host; the A1 II
HIF is 8640×5760 and the device run is what matters.

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

One photo per walk, so no render was ever superseded and the preview never ran
while a render was in flight. These rows exercise the path and its counters, not
contention.

| Dwell | Preview median ms (source, 1616 px) | Render ready ms | Arrival → ready ms | Started / ready / wasted / failed |
| --- | --- | --- | --- | --- |
| 0 ms | 16.9, RAW fallback, no render running | 82.7 | 100.6 | 1 / 1 / 0 / 0 |
| 300 ms | 15.7, RAW fallback, no render running | 119.0 | 437.4 | 1 / 1 / 0 / 0 |
| 800 ms | 15.3, RAW fallback, no render running | 119.3 | 967.9 | 1 / 1 / 0 / 0 |

The HEIC fixture has no embedded preview on macOS, so these preview requests used
the RAW's own 1616 px preview. With one photo per walk, the preview never had a
render running, nothing was superseded, and the arrival-to-ready rows are simply
the preview request plus the dwell plus the render plus process noise. They are not
evidence that a longer dwell slows the render, and they say nothing about
contention.

### macOS: cache cost, not device numbers

One screen-size render (2000×1336, 10.19 MiB decoded), encoded at quality 0.9.

| Measurement | HEIC | JPEG |
| --- | --- | --- |
| Encode ms | 40.9 | 14.2 |
| File bytes | 708,390 | 854,362 |
| Decode ms | 17.0 | 7.3 |
| Decoded bytes | 10,688,000 | 10,688,000 |

The six-held-image sample has one image on this run: 10,688,000 B summed bitmap
bytes, 216,121,344 B (206.1 MiB) sampled process RSS, 74.1 ms of renders. The device
run with six files is what answers the six-image question.

### macOS: grid projection, not device numbers

Best 400 px variant in this run: `raw-grid-scale-draft`, warm median **68.1 ms**
per photo.

| Projection | 2000 photos |
| --- | --- |
| Concurrency 1, arithmetic | 136.1 s |
| Concurrency 2, arithmetic, perfect division | 68.1 s |

The device run's numbers replace this projection; it is not a concurrent
measurement and not a promise that two decoders halve the time.

### macOS: sustained-load path check, not device numbers

10-render bound, one file, selected variant `raw-screen-scale-draft` (76.4 ms
selection median against 82.9 ms for draft off). Total 744.4 ms; individual renders
71.4–76.5 ms; thermal state `nominal` at start and end, no transitions; no battery
reading on macOS. This only shows that the second button's code path runs. Heat,
thermal transitions and battery drain need the device.

### Device: pending the owner's run

Nothing below is measured yet. Each row is filled from the two S8 JSON reports on
issue [#122](https://github.com/mimiqdev/cloveapp/issues/122), on the A1 II ARW+HIF
pairs, iPhone 17 Pro Max and iPad Pro.

| Status | RAW variant | Cold ms | Warm median / p90 ms | Output | Decoded MiB | Peak RSS MiB |
| --- | --- | --- | --- | --- | --- | --- |
| Pending | a native, fresh context | Pending | Pending | Pending | Pending | Pending |
| Pending | b native, reused context | Pending | Pending | Pending | Pending | Pending |
| Pending | c screen `scaleFactor` | Pending | Pending | Pending | Pending | Pending |
| Pending | d screen draft | Pending | Pending | Pending | Pending | Pending |
| Pending | e grid `scaleFactor` | Pending | Pending | Pending | Pending | Pending |
| Pending | e grid draft | Pending | Pending | Pending | Pending | Pending |

| Status | Camera HEIF variant | Cold ms | Warm median / p90 ms | Output | Decoded MiB | Peak RSS MiB |
| --- | --- | --- | --- | --- | --- | --- |
| Pending | f full decode (100% source) | Pending | Pending | Pending | Pending | Pending |
| Pending | g subsample factor 2 | Pending | Pending | Pending | Pending | Pending |
| Pending | g screen thumbnail, always | Pending | Pending | Pending | Pending | Pending |

| Status | Colour comparison | Mean ΔE00 | p95 | Max | Compared pixels |
| --- | --- | --- | --- | --- | --- |
| Pending | c screen vs native | Pending | Pending | Pending | Pending |
| Pending | d screen draft vs native | Pending | Pending | Pending | Pending |
| Pending | e grid vs native | Pending | Pending | Pending | Pending |
| Pending | e grid draft vs native | Pending | Pending | Pending | Pending |
| Pending | HIF embedded preview vs RAW native | Pending | Pending | Pending | Pending |
| Pending | full HIF decode vs HIF preview | Pending | Pending | Pending | Pending |

| Status | Dwell | Preview ms, render running / idle | Render ready ms | Arrival → ready ms | Started / ready / wasted / failed |
| --- | --- | --- | --- | --- | --- |
| Pending | 0 ms | Pending | Pending | Pending | Pending |
| Pending | 300 ms | Pending | Pending | Pending | Pending |
| Pending | 800 ms | Pending | Pending | Pending | Pending |

| Status | Sustained load | Value |
| --- | --- | --- |
| Pending | Renders completed / duration | Pending |
| Pending | Thermal transitions with elapsed seconds | Pending |
| Pending | Battery start → end, charging state | Pending |
| Pending | Screen-size cache: HEIC encode / bytes / decode | Pending |
| Pending | Screen-size cache: JPEG encode / bytes / decode | Pending |
| Pending | Six decoded screen renders held: bytes / RSS | Pending |
| Pending | Grid per-photo and 2000-photo projection, concurrency 1 / 2 | Pending |
| Pending | Suite duration (10-minute budget check) | Pending |

## Open questions

- Does the iPhone honour `scaleFactor` and draft mode by the same margin the Mac
  shows? The Mac's 17–25 ms saving against a 67–92 ms render is not a device
  ratio; the device table decides whether a screen-size RAW render is materially
  cheaper than a native one.
- Does draft mode change colour or detail visibly? This probe measures colour
  difference only, and on the Mac fixture draft and non-draft were identical;
  visual quality needs the owner's eye on the device.
- How does a RAW render affect the next photo's preview in practice? The Mac walk
  had one photo and never contended; the 20-photo device walk is what measures
  preview latency while a render is running, wasted renders and drain after
  supersede.
- Is the full HIF decode a usable 100% source at 8640×5760? S2 measured about 1.8 s
  and 1.3 GB peak through `CIRAWFilter` on the previous build; this probe repeats
  it through ImageIO on the device build. A 100% source that is correct but slow
  may still be acceptable as a cold-path image, but the memory ceiling under
  repeated navigation is unmeasured.
- Is the full HIF decode's colour equal to the embedded preview's on the owner's
  camera? The Mac fixture has no embedded preview; the device comparison is the
  first real measurement of that claim.
- What does the grid cost in a real concurrent pipeline? The projection here is
  arithmetic from one 400 px render at a time. Concurrency 2 and four workers need
  the same treatment S2 gave embedded thumbnails before a grid decision exists.
- How long does the whole display suite take on the device, and does the sustained
  step change thermal state within five minutes? The `run-duration` and
  `thermal-change` rows answer both for the owner's folder.
- Does an iPad screen long edge change the colour and time results materially? The
  probe accepts the screen edge from the app, so the same build answers it; no iPad
  run exists yet.

## Device checklist

Part 1 writes the checklist; part 2 and the owner's run fill the device tables.

1. After the supervisor publishes the merged Lab build, install **Clove Lab** from
   TestFlight on **iPhone 17 Pro Max**. Note the installed iOS version; the report
   records the hardware identifier, iOS version and app build itself.
2. Copy **12 or more A1 II ARW + HIF pairs** (each `.ARW` with its same-name `.HIF`)
   to local storage, not a card or reader. Unplug the charger and let the phone sit
   at room temperature.
3. Open **Clove Lab → S8 · RAW display**. Choose the folder and confirm its name
   appears under the picker. Check **Screen long edge** matches the phone's panel;
   adjust it only if it is wrong.
4. Tap **Run display suite**. Expect a progress count that moves through RAW
   variants, camera HEIF variants, colour, swipes, cache and the grid projection,
   then **Finished: clove-lab-S8-<timestamp>.json**. The app must stay responsive
   and **Cancel** must be available. Allow about 10 minutes; if the run takes much
   longer, record the last progress message instead of repeating it.
5. Tap **Run sustained load (up to 5 min)**. Expect up to 300 renders or five
   minutes of progress, then a second **Finished: clove-lab-S8-<timestamp>.json**.
   Keep the app in the foreground; note whether the phone becomes warm.
6. Use **Export** in the footer for each report, or find both in Files › On My
   iPhone › Clove Lab. They are also written into the tested folder. Attach both
   JSON files to issue [#122](https://github.com/mimiqdev/cloveapp/issues/122) and
   identify the device, iOS version and folder. Do not attach screenshots of the
   folder path.
7. Repeat steps 1–6 on **iPad Pro**, recording its model and installed iPadOS
   version. The screen long edge is read from that device, so c–e and g change
   size.
8. If a run stops early or a variant row fails in the JSON, keep the report and
   say which step stopped; a failure is recorded as a `status` tag rather than
   stopping the whole run.
