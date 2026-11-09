# S6 — How long does scanning take?

## Question

How long does a recursive scan of about 2,000 files take through a card reader,
which way of listing files and prefetching their attributes is fastest, and
should results appear while the scan runs?

Part 2 of [#17](https://github.com/mimiqdev/cloveapp/issues/17) finishes the report
with macOS evidence and a recommendation for G1. **There is no physical-device
S6 report in either owner run.** The owner deferred every device check on
2026-11-09 to [#29](https://github.com/mimiqdev/cloveapp/issues/29); they are not
urgent and do not hold #17 open. G1 remains the product owner's decision.
Camera files, especially Sony A1 II ARW+HIF and ARW+JPEG, are the main target.
iPhone HEIC is out of focus until photo library support.

## What was tested

- **Mac mini `Mac14,12` (M2 Pro), macOS 27.0 (26A428), Xcode 27.2 (27B52),
  Swift 6.4.2, debug build.** Generated trees live in a UUID-named temporary
  directory on the internal APFS SSD (`Macintosh HD`), outside the repository
  and fixtures cache. The checkout and build products live on the T7; these
  timings are not T7 or external-reader measurements.
- **Historical part-1 macOS aggregate:** three processes × three passes, nine
  observations per cell, on a heavily loaded shared host (load average 270–860
  on 10 cores). Its medians are retained below as historical observations.
- **Part-2 macOS run, 2026-11-09T06:57:15Z:** one process × three passes, with
  no other worker running. Host load was still nonzero: `uptime` immediately
  before/after reported 1-minute averages 11.08/9.60 and 5-minute averages
  23.70/22.97. Collection took **6.618 s**, excluding compilation. New numbers
  are medians of three observations with min–max ranges, not p95 or targets.
  They are never pooled with the historical nine-observation aggregate.
- **Historical iPhone 17 Pro simulator (`iPhone18,1`), iOS 27.0 (24A434):**
  a standalone arm64 executable called the same `ScanBenchmark.run` as Lab on
  the Mac's APFS, using a fresh simulator that was deleted afterwards. The
  heavily loaded host produced 10–100× timing spreads. This is functional/schema
  evidence only. No new simulator timing run was needed for part 2; acceptance
  builds and smoke testing are recorded in the PR.
- **Generated `Clove-Scan` tree:** 2,000 accepted photo files in six DCIM
  subfolders, 518 RAW+JPEG pairs (CR3, NEF, ARW, RAF, ORF, RW2, DNG cycling),
  1,482 logical photos, 150 rejected JPEGs, 20 hidden entries (18 AppleDouble
  files, `.DS_Store`, `.Trashes/`), plus unsupported MOV, text and XMP files.
  About 25.9 GB logical, about 2 MB allocated when sparse. The benchmark tree
  is historical RAW+JPEG content; its counts/timings do not measure real A1 II
  photos or a 2,000-file HIF population.
- **Deviation retained from part 1:** names and attributes are generated rather
  than copying real fixture pixels. Each file starts with a 1 KiB placeholder;
  APFS sparse extension gives plausible photo sizes without tens of GB of disk
  use. The device generator uses small placeholders. Listing does not read
  pixels, EXIF or XMP contents. Real camera/provider behavior still needs #29.
  Shared fixture sets were present; no rebuild or writes into `files/` occurred.
- **Three methods:** `FileManager.enumerator`, recursive
  `FileManager.contentsOfDirectory`, Foundation-free `opendir`/`readdir` with
  directory-entry types or `lstat` fallback. Twelve key sets isolate each of
  name, regular-file type, directory flag, size, modification date and content
  type, then add them in a ladder. All methods use the same candidate filters.
- **Cache limitations:** no page-cache flush. Generation itself touches the
  tree, and key sets run in fixed order; method order rotates each pass. Pass 1
  is the first suite pass, **not a controlled cold scan**. Later passes are
  warm. Neither macOS nor simulator observations predict a cold card/provider.
- **Pairing regression checks:** temporary `DCIM/100MSDCF` and `101MSDCF` trees
  across all three methods, with names-only and the recommended five keys.
  Added coverage checks all four `.ARW`/`.arw` × `.HIF`/`.hif` combinations,
  differently cased stems, RAW+JPEG, root and nested `_Rejected`, hidden
  AppleDouble files, XMP exclusion, `_Rejected2` remaining visible, and no
  cross-folder pairing. Existing tests already covered uppercase ARW+HIF,
  mixed-case HIF and the proposed JPEG preference in a triple. **No pairing
  implementation change was necessary.** These are filename tests, not camera
  preview, metadata or desktop interoperability evidence.

Reports stay outside git:

| Evidence | Artifact and provenance |
| --- | --- |
| Historical macOS aggregate | Part-1 report's nine-observation tables; only one of its three JSON processes was archived on #17. The other six observations are not independently reconstructible from that archive; the inherited aggregate is labeled accordingly |
| Archived historical macOS process | `macOS.json`, SHA-256 `aedf799446f38f800ae6a251f0cdc727cbd1063380ad2d9ad18716abe23a3dd8`, gzip/base64 in the [#17 evidence comment](https://github.com/mimiqdev/cloveapp/issues/17) |
| Historical simulator | `clove-lab-S6-20261108T173917Z.json`, SHA-256 `6d3f8e16a8c968b1ef61658501a56e2f5b73100899ddcf40f992403deb35a4e2`, archived in the same issue comment |
| Part-2 macOS run | `.build/scan/macOS-current.json`, `createdAt` 2026-11-09T06:57:15Z, SHA-256 `cb8bff2d05c81d10e7377de707cedb13eebfca8ec4e4348c6d3fd70e9ba100ab`; gzip/base64 preserved in the part-2 PR |

Reproduce one short macOS collection (about 7–10 s after compilation):

```sh
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
mkdir -p .build/scan
CLOVE_SCAN_REPORT="$PWD/.build/scan/macOS-current.json" \
  mise exec -- swift test --package-path Packages/CloveLabKit \
  --filter ScanBenchmarkTests.collectReport
```

Record host load alongside the JSON. The collector note now asks for that context
instead of claiming every future run has other workers running. `mise run
verify` runs functional scan tests without enabling this timing collector or
asserting timing thresholds.

## Data

### Listing time per method and key set

**Part-2 macOS run** above, 2,000 photo candidates on internal APFS. Milliseconds,
median of three passes (min–max); `_Rejected` is skipped during traversal.
`type` means `.isRegularFileKey`, not UTI.

| Keys | `FileManager.enumerator` | `contentsOfDirectory` | POSIX `readdir` |
| --- | ---: | ---: | ---: |
| `names` | 14.4 (14.3–16.0) | 11.1 (9.9–11.5) | 21.6 (20.7–23.6) |
| `name` | 17.5 (17.3–17.9) | 13.2 (12.4–13.5) | 37.0 (36.9–41.8) |
| `type` | 17.1 (17.0–17.7) | 13.0 (12.3–13.2) | 39.2 (36.4–40.6) |
| `isDirectory` | 17.4 (17.0–17.4) | 12.6 (12.5–12.8) | 40.6 (36.3–41.8) |
| `size` | 17.4 (17.1–17.9) | 12.8 (12.3–12.8) | 39.6 (36.5–40.2) |
| `modified` | 17.3 (17.2–17.6) | 13.1 (12.8–13.3) | 39.2 (38.8–42.5) |
| `contentType` | 55.0 (53.4–62.2) | 49.3 (48.4–49.6) | 102.2 (100.5–110.6) |
| `name+type` | 18.8 (18.5–25.5) | 13.7 (13.6–13.8) | 38.3 (38.0–39.6) |
| `name+type+size` | 19.7 (19.4–22.2) | 14.7 (14.6–14.9) | 39.3 (38.9–39.6) |
| `name+type+size+modified` | 20.8 (20.7–23.0) | 16.2 (16.0–16.3) | 41.0 (40.6–42.0) |
| `name+type+size+modified+isDirectory` | 22.0 (21.9–23.5) | 17.4 (17.3–17.5) | 42.2 (41.8–48.5) |
| `all` | 61.1 (59.6–62.5) | 55.1 (54.4–55.2) | 107.4 (107.0–117.0) |

**Historical part-1 aggregate**, nine observations, same tree shape/internal
APFS, heavily loaded shared host. Milliseconds, inherited medians (min–max).

| Keys | `FileManager.enumerator` | `contentsOfDirectory` | POSIX `readdir` |
| --- | ---: | ---: | ---: |
| `names` | 17.2 (15–50) | 13.9 (12–18) | 29.2 (24–46) |
| `name` | 20.0 (19–54) | 15.2 (14–22) | 63.5 (42–97) |
| `type` | 19.3 (18–91) | 15.3 (14–25) | 66.4 (42–86) |
| `isDirectory` | 20.2 (19–58) | 16.7 (14–27) | 67.6 (41–109) |
| `size` | 20.5 (18–69) | 17.0 (14–30) | 60.0 (41–141) |
| `modified` | 20.3 (18–91) | 17.2 (14–37) | 60.5 (42–132) |
| `contentType` | 65.0 (58–189) | 60.0 (53–124) | 151.6 (110–503) |
| `name+type` | 21.7 (21–65) | 18.7 (15–32) | 59.3 (43–186) |
| `name+type+size` | 22.9 (21–82) | 19.8 (16–41) | 69.1 (44–139) |
| `name+type+size+modified` | 24.4 (22–88) | 21.7 (17–46) | 66.2 (45–126) |
| `name+type+size+modified+isDirectory` | 25.8 (23–95) | 21.7 (18–43) | 63.1 (48–154) |
| `all` | 71.2 (63–272) | 64.1 (59–153) | 150.1 (116–438) |

In the new run, adding the five keys costs 7.6 ms over names for the enumerator;
adding `contentType` to those five costs another **39.1 ms**, making listing
**2.8×** as long. The single-key rows are comparisons against `names`, not
independent additive prices: Foundation caches, fixed key order and type lookup
can interact. Ladder increments other than content type are about 1–1.3 ms
here. An extension identifies a scan candidate; ImageIO later establishes actual
preview/metadata support. A UTI lookup is no substitute for that validation.

`contentsOfDirectory` is **4.6 ms (21%) faster** than the enumerator with five
keys in this run, with nonoverlapping observed ranges. It is a real local
advantage in this sample, not evidence of a card advantage. The enumerator
recommendation trades those few milliseconds for built-in recursion and
`skipDescendants`. POSIX is about 1.9× the enumerator with five keys and 1.8×
with all keys, with more recursion/filter/error-handling work.

### First 100 accepted files

**Part-2 macOS run**, milliseconds, median of three passes (min–max). These
are traversal-order file candidates before pairing, metadata reads, previews,
XMP reads or screen rendering; 100 files need not mean 100 logical photos.

| Keys | `FileManager.enumerator` | `contentsOfDirectory` | POSIX `readdir` |
| --- | ---: | ---: | ---: |
| `names` | 0.9 (0.9–1.2) | 1.3 (0.9–1.3) | 1.5 (1.3–1.6) |
| `name` | 1.0 (1.0–1.1) | 1.2 (1.1–1.2) | 2.1 (2.1–2.4) |
| `type` | 1.0 (1.0–1.0) | 1.1 (1.0–1.2) | 2.1 (2.0–2.3) |
| `isDirectory` | 1.0 (1.0–1.0) | 1.1 (1.1–1.2) | 2.2 (2.0–2.3) |
| `size` | 1.0 (1.0–1.0) | 1.1 (1.1–1.1) | 2.2 (2.0–2.3) |
| `modified` | 1.0 (1.0–1.1) | 1.1 (1.1–1.1) | 2.1 (2.1–2.6) |
| `contentType` | 3.4 (3.4–5.4) | 7.2 (7.2–7.4) | 5.7 (5.4–6.1) |
| `name+type` | 1.2 (1.1–1.2) | 1.2 (1.1–1.2) | 2.2 (2.1–2.3) |
| `name+type+size` | 1.2 (1.1–1.3) | 1.2 (1.2–1.3) | 2.2 (2.1–2.2) |
| `name+type+size+modified` | 1.2 (1.2–1.6) | 1.3 (1.2–1.5) | 2.2 (2.1–2.3) |
| `name+type+size+modified+isDirectory` | 1.2 (1.2–1.4) | 1.3 (1.3–1.3) | 2.3 (2.3–2.6) |
| `all` | 3.9 (3.6–4.0) | 7.4 (7.3–7.5) | 5.8 (5.6–6.5) |

### Pairing, rejects, prefetch and streaming

**Part-2 macOS run**, milliseconds, median of three passes (min–max). Streaming
uses **all six keys**, batches of 64 files, and pairing within each batch.
It has not measured the proposed five-key streaming path or a rendered grid.

| Stage | enumerator | contentsOfDirectory | readdir |
| --- | ---: | ---: | ---: |
| Sort by relative path | 9.0 (8.8–9.1) | 9.0 (8.9–9.0) | 8.6 (8.6–8.8) |
| Pair by same-directory stem | 13.3 (13.0–13.3) | 13.2 (13.0–13.3) | 13.1 (13.0–14.0) |
| List all keys, walk rejects | 59.3 (58.7–60.3) | 54.1 (53.8–57.3) | 116.2 (112.6–120.5) |
| Filter walked rejects by path | 3.3 (3.3–3.6) | 3.3 (3.2–3.3) | 3.3 (3.3–3.4) |
| Names plus lazy six-key reads | 95.5 (92.5–100.4) | 91.4 (89.9–102.1) | 107.8 (107.1–114.3) |
| Stream first batch produced | 3.3 (3.1–3.7) | 7.9 (7.8–8.2) | 4.5 (4.5–5.1) |
| Stream first batch received | 3.3 (3.1–3.7) | 7.9 (7.8–8.2) | 4.5 (4.5–5.1) |
| Stream 100th accepted file | 4.8 (4.2–4.8) | 8.2 (8.1–8.5) | 6.2 (6.1–7.1) |
| Stream last batch received | 82.3 (75.7–83.7) | 73.6 (70.2–75.4) | 122.0 (121.6–132.3) |

All methods found **2,000 candidates, 518 pairs and 1,482 photos**, with zero
reported errors and zero POSIX stat fallbacks on APFS. Foundation omits
AppleDouble files even without `.skipsHiddenFiles`; POSIX sees them. C2 still
needs explicit hidden/`._` filtering rather than depending on that API behavior.

Prefetch beats names plus subsequent six-key resource reads: **61.1 vs 95.5 ms**
for the enumerator and **55.1 vs 91.4 ms** for recursive listing. The lazy total
adds the separately measured names scan to fresh URL resource reads; it is not
an instrumented syscall count or a cold-cache comparison. Pairing costs about
13 ms; it does no disk reads. Reject-pruning has no stable speed benefit in the
new Foundation sample: walk-and-filter totals are 62.6/57.4 ms versus
61.1/55.1 ms skip medians (sums of stage medians, not end-to-end observations).
Prune during traversal for correctness and to avoid unnecessary rejected-file
work, rather than promising a measured large saving.

Historical part 1 reported 14–16 ms pairing, 9.8–10.7 ms sorting, 4–9 ms first
stream batch and 82.9–161.0 ms last batch, all medians of nine observations.
Those remain separate from the new run. Early stream delivery is reproducible;
its user-visible benefit on a card remains unmeasured. The current consumer
only records times: it performs no UI updates, preview work or backpressure.
Pairing independently within batches can split a pair, and cannot enforce
JPEG preference until the directory is complete. The probe is not a production
streaming implementation.

### Simulator run

The historical simulator report is valid functional/schema evidence, but not
usable device timing. All-key listing ranged 323–1,798 ms for the enumerator,
255–5,575 ms for recursive listing and 1,032–10,726 ms for POSIX; individual
content-type scans reached 16 seconds under load. No simulator number is used
to set a phone/card target.

### Device findings

Every physical-device row is deferred. Owner run 1 (Clove Lab 26110818) and
run 2 (26110903) contain **no S6 execution**, including on local storage.
Their ARW/HIF results in other probes add no scan-speed evidence.

| Check | Status / evidence | Finding and limit |
| --- | --- | --- |
| iPhone 17 Pro Max, local storage | **Deferred — #29** | No S6 report in either owner run; no phone baseline |
| exFAT SD card through intended reader | **Deferred — #29** | No listing/key-set/first-100, pairing, rejects or streaming times |
| Real A1 II `DCIM/<NNN>MSDCF` ARW+HIF / ARW+JPEG | **Deferred — #29** | New macOS filename regressions pass; no physical camera-folder scan or preview count confirmation |
| External USB-C SSD | **Deferred — #29** | No SSD listing/provider or streaming comparison |
| Locked/read-only card | **Deferred — #29** | No physical read-only scan, generation refusal or export-failure evidence |
| Cancel/disconnect while scanning | **Deferred — #29** | No provider cancellation/partial-result or disconnect observation |
| iPad Pro, local/card/SSD | **Deferred — #29** | No iPadOS behavior or timing result |
| Other supported hardware, including Duo when available | **Deferred — #29** | No cross-device scan result |

## Conclusion

On macOS internal APFS, the new three-pass run lists 2,000 candidates in
**22.0 ms with the enumerator's five keys**, or **17.4 ms with recursive
listing**. `contentType` adds about 38–39 ms to either method; POSIX is slower.
Pairing adds about 13 ms and a path sort about 9 ms. All-key batches reach the
consumer after 3–8 ms, well before the walk ends, demonstrating a useful
incremental delivery mechanism without proving time to visible photos.

Recommend the enumerator, five prefetched keys and streamed results, with
pair-safe publication and capture-time ordering handled by the production
pipeline. This is a reasoned G1 baseline with explicit revision criteria below;
there is **no measured card-reader factor, phone latency or approved numeric
launch promise**. Finishing #17 does not finish #29 or establish external-media
readiness.

## Recommendation and options for G1

**Recommended baseline (A):**

1. One `FileManager.enumerator(at:includingPropertiesForKeys:options:)` pass
   with `[.nameKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey,
   .contentModificationDateKey]`, `.skipsHiddenFiles`, explicit `._` exclusion,
   and the configured rejects-folder name (`_Rejected` by default). Call
   `skipDescendants()` at that directory at any depth. Use case-insensitive
   image-extension/stem matching within the same directory, retaining actual
   on-disk spellings and paths. Do not normalize different directory identities
   into one pairing bucket. Production C2 must validate regular files, refuse
   unsafe traversal outside the selected root, and report read errors per entry.
   The probe's error counters are not production diagnostics.
2. Accept RAW/JPEG/HEIF candidates (including `.HIF`/`.hif`) by extension; avoid
   `.contentTypeKey` on every file. Supply size and modification time for cache
   invalidation. Decode/metadata failures remain explicit unsupported or
   unreadable states; candidate acceptance is not proof of preview support.
3. **Stream through `AsyncStream` in batches of 64 initially**, on a worker away
   from the main thread. Keep same-directory stem state across batches and
   reconcile at directory completion, with stable logical photo IDs. Publish
   only resolved pairs/standalones or explicit provisional items that can merge
   without duplicate cells, marks or counts. Waiting for directory completion
   is a valid correctness-first fallback. The first resolved-photo latency must
   be measured separately from the probe's first raw file batch. Add bounded
   buffering/backpressure and propagate cancellation through the producer.
4. Feed XMP/metadata/preview work incrementally with bounded concurrency. Read
   sidecar marks before displaying them. Default order is capture time with
   subseconds (P0-03), obtained from I4, not filesystem dates. Path sorting in
   this benchmark is deterministic bookkeeping, not the proposed default UI
   order. Keep the viewed item stable as metadata/grouping refines. G1 must
   settle whether provisional filename-order cells may appear while capture
   times are pending; the stream API does not require exposing that order.

**Proposed evaluation budgets:** first resolved-photo batch delivered to the
consumer within **0.5 s**, and complete **discovery/pairing within 3 s** for
2,000 files. These exclude EXIF, XMP parsing, preview decoding/rendering and
feature computation; measure first visible grid separately in I1/U3. They are
engineering candidates for G1, not promises extrapolated by multiplying Mac
speed. Confirm or revise with #29 before M3/Q3 targets are fixed.

### Options and quantitative revision criteria

These thresholds are proposed decision criteria, not measured device outcomes.
Compare the same tree, key set, filters, correct counts and cache conditions in
three passes per method on the intended exFAT card/reader, then repeat the
comparison once to check stability. Do not compare a warm alternative against
a first-touch baseline or combine different storage results.

| Option | Available macOS evidence / cost | What device result would change the recommendation? |
| --- | --- | --- |
| A: enumerator, five keys, stream | New run: 22.0 ms listing, 13.3 ms pair, 9.0 ms path sort; one recursive API and pruning | Default while deferred; revisit if it misses the proposed 0.5 s / 3 s budgets |
| B: recursive `contentsOfDirectory`, same keys | 17.4 ms listing, 4.6 ms / 21% saved locally; manual recursion and per-directory arrays | Prefer B if repeat comparisons save **both ≥20% and ≥100 ms** of median full listing, without worse first-resolved-batch time, missing entries or error handling. A few local milliseconds do not meet the absolute threshold |
| C: POSIX, same keys | 42.2 ms listing; own recursion, filtering and resource lookup | Reconsider only with **both ≥30% and ≥250 ms** median listing savings over A on target storage, plus identical supported-file/error behavior. Current evidence goes the other way |
| D: add `contentType` | Enumerator 61.1 vs 22.0 ms, +39.1 ms / 178%; redundant for extension candidacy | Consider eager UTI only for a concrete correctness requirement **and ≤5% and ≤50 ms** added median listing cost on target devices. Cheap UTI alone is no reason to add it; otherwise resolve only ambiguous entries lazily |
| E: reduce eager size/modified keys | Names-only 14.4 vs 22.0 ms, saves 7.6 ms but omits cache revision data | If those keys cost **both ≥20% and ≥100 ms** on card, evaluate deferring them to bounded preview/metadata admission. Fetch revision data before cache reuse; do not replace prefetch with unbounded per-file reads |
| F: publish only after complete discovery | Removes partial-cell/merge/sort UI work; the probe saves no measured UI cost | Disable visible partial publication if real end-to-end trials on **all target storage** finish within **250 ms** and streaming improves first visible resolved photos by **<100 ms**. Keep streaming if it saves ≥100 ms or complete discovery exceeds 0.5 s; address pairing/order correctness before enabling partial interaction |

For a change of lister or key set, also require identical behavior on real Sony
folders, errors and cancellation; a fast incomplete walk is a failed scan. If
none meets the budgets, keep progressive delivery and revise scheduling/budgets
with G1 rather than claim a faster API will solve preview or metadata costs.

### What the scanner hands to the other lanes

These are production handoff requirements, not additions to the scan probe or
edits to the other reports.

- **[S3 XMP](S3-xmp.md) / C3 / C4:** hand over one logical photo with its RAW
  primary, optional rendered companion, directory identity, actual URLs and
  spellings, and sidecar-discovery candidates. `MMQ05184.ARW` + `MMQ05184.HIF`
  share **`MMQ05184.xmp`**; RAW+JPEG uses the same replacement-extension rule.
  XMP is excluded from photo counts but must still be discoverable during the
  same directory walk (or a directory-level sidecar index). Find unique
  same-directory same-stem `.xmp`/`.XMP` case variants and reuse actual spelling.
  Surface competing packets, appended-extension names such as `NAME.ARW.xmp`,
  or multiple RAWs per stem as ambiguity; never silently create a second packet
  or choose a writer destination. Read marks before showing persisted state;
  serialize writes to the one shared packet and independently confirm read-back.
  The current `ScanLister` discards XMP entries and `ScannedPhoto` has no sidecar
  field; C2/C3 must implement this contract under domain names in CloveCore.
- **[S4 metadata](S4-metadata.md):** preserve the distinction between a RAW pair
  and a standalone rendered file. Neither ARW nor its paired HIF/JPEG receives
  embedded writes, even if the standalone option is on. Pass all members to the
  later move plan together with the shared sidecar. A standalone HIF is still
  discoverable, but its native embedded writer is ineligible under S4's measured
  thumbnail loss. A pair descriptor does not establish desktop interoperability.
- **[S1 access](S1-access.md) / C11:** start from the resolved, identity-validated
  folder session, not a stored path or volume label. Hold balanced security
  scope for the entire producer and admitted downstream file work; use provider
  coordination as required. Validate access with an actual read before scanning,
  refresh stale bookmarks only after successful read/identity validation, and
  cancel/drain work before releasing scope. Retain exact failure phase and
  NSError chains; a partial scan is not a complete zero-photo result. Supply
  logical photo count and completion/partial status to Recents; only successful
  opens update the count/last-opened time. Never transfer pending work to a
  same-label replacement card. Positive writable/capacity hints authorize no
  later write, and read-only media may still be browsed.
- **[S5 grouping](S5-grouping.md) / I4 / C8 / C9:** hand over each logical photo
  once, with stable identity, RAW as metadata/preview source for a pair,
  source size/mtime and relative path for deterministic ties. I4 supplies
  capture time/subseconds, offset availability, model and body identity with
  explicit missing values; filesystem mtime is cache data, never capture time.
  Missing capture time sorts last and excludes grouping. Missing A1 II serial
  remains S5's G1 body-attribution question; pairing cannot infer a body ID.
  Refinement must preserve the viewed photo and never write marks. S5 currently
  excludes both rendered companions in a RAW+JPEG+HIF triple, whereas the scan
  probe proposes a standalone HIF; reconcile that difference at G1 before C2/C9
  integration rather than independently rediscovering/filtering pair members.

## Open questions

1. **G1 triple-file rule:** when RAW+JPEG+HIF share a directory/stem, the
   current probe proposes **RAW+JPEG plus standalone HIF**. Its tests document
   that proposal, not an approved policy. Should G1 adopt it, use one logical
   photo with more members, or another rule? A standalone same-stem HIF and the
   RAW+JPEG pair would compete for the same canonical `.xmp`; G1/C3 must settle
   mark ownership/discovery before writing either. S5 currently excludes both
   companions for grouping. Do not silently decide either conflict here.
2. **G1 streaming order:** may resolved filename-order items appear until
   capture-time metadata arrives, with stable viewed-photo anchoring? Otherwise
   stream into the metadata pipeline and publish only when order is usable.
   Pair completion at directory boundaries can delay first visible photos.
3. **#29 card/provider factor:** do the proposed budgets and switching criteria
   hold for real Sony folders, cold/first-touch conditions and intended reader?
   Five-key streaming and real rendering need end-to-end measurements beyond
   the current all-key consumer timer.
4. **Scale and ambiguity:** is 2,000 files representative, or should evaluation
   cover 5,000+? Test rather than assume linear provider cost. Multiple RAWs,
   case-distinct duplicate stems and competing sidecars need explicit C1/C2/C3
   identity/error policy; this probe's deterministic selection is not approval.

## Deferred device checks

All checks below are **deferred** by the owner to
[#29](https://github.com/mimiqdev/cloveapp/issues/29). None is measured by the
owner's two sessions. Complete the dependent runs before M3/Q3 performance
targets are fixed, or earlier if G1 needs a firm answer.

| Deferred check | What it would answer | Could it change the G1 recommendation? |
| --- | --- | --- |
| iPhone 17 Pro Max local S6 baseline | Phone Foundation/API behavior and latency independent of external reader | Yes: delivery/scheduling budget; cannot establish card speed. Apply the same method/key criteria before preferring another API |
| exFAT SD card and intended reader, full method/key matrix | First-100 and complete listing, per-key/provider cost, prefetch benefit, pairing and reject-pruning | **Yes:** switch lister or reduce eager keys at the quantitative thresholds above; fix or revise the 0.5 s / 3 s budgets |
| Streamed results on that card, real consumer/grid follow-up | First resolved and visible photos, pair splits, queue growth, final capture order and viewed-photo stability | **Yes:** change batch size/buffering/publication; omit partial UI under option F's <250 ms / <100 ms conditions. A fast raw batch alone is insufficient |
| Real A1 II `DCIM/<NNN>MSDCF` with ARW+HIF and ARW+JPEG | Correct counts, cases, `_Rejected` exclusion, pairing and actual preview/metadata availability | Could change format/provider handling; any count error blocks adopting that lister. Triple-file behavior remains a G1 policy question, not a speed result |
| Same tree and real camera folder on USB-C SSD | Reader/card cost versus external SSD/provider cost | Could change per-storage budgets or scheduling. Prefer one correct API unless repeat comparisons meet the switching thresholds |
| Locked/read-only card, then reopen unlocked | Browse-only scan, generation/export errors, original-file safety | Could change access/recovery/export handling, not justify touching rejected files or importing originals. Skip generation and use an existing camera folder |
| Cancel/disconnect mid-scan; reconnect/reopen | Provider blocking, cancellation, partial counts, exact errors and scope lifetime | Could require cancellation/coordination/recovery changes even with unchanged lister. S1 owns disconnect classification; no timeout guarantee is inferred |
| iPad Pro repeat; Duo when available, device/OS recorded | Cross-device API, latency, resource pressure and provider parity | Could change device budgets or admission limits; no phone-to-iPad transfer of numbers. Revisit method/key/streaming choices by the same criteria |

No iPhone HEIC scan benchmark is required for this camera-focused conclusion;
phone-photo work remains deferred with photo library support. Fixture provenance
work in #23 is outside this part 2.

### Device checklist (deferred follow-up)

No new physical-device run or TestFlight upload is required for this PR. When
#29 is scheduled, use the supervisor's merged Clove Lab build. Allow **5–15
minutes** for generation and the synthetic suite on each storage/device; this
is an unverified operator estimate, not a measured scan time. If a step exceeds
15 minutes, note the device/card/reader and report the last progress line.

1. On **iPhone 17 Pro Max**, connect the intended reader with a writable exFAT
   test card. Record reader/card model, filesystem, free space, installed OS
   and Lab build. Pick the card root in **Clove Lab → S6 · Scan speed → Choose
   folder**. The selected folder name appears. Use a test volume without an
   existing `Clove-Scan` folder.
2. Tap **Generate test tree**. Expect **Test tree ready: 2000 photo files**,
   **518 pairs**, **1482 grid items**, **150 rejects**, and one `Clove-Scan`
   folder containing six DCIM subfolders. Generated files are placeholders,
   not previewable camera images. Do not generate on a locked card.
3. Tap **Run scan suite**. Keep the app open. Expect progress through **144
   steps** (three passes × three methods × twelve listing sets plus four
   stages per method), then **Finished: clove-lab-S6-<UTC timestamp>.json**.
   Cache clearing is unavailable: label first suite pass and warm passes,
   not cold/warm measurements. A second suite checks repeatability, not cold
   cache. The report records producer/consumer batches, not visible cells.
4. Use the footer's **Export**, or Files → **On My iPhone → Clove Lab**, to
   retain the JSON. The picked-folder copy should also exist; if export needs
   attention, preserve the Documents copy and send the exact visible error.
   Tap **Delete test tree**; expect **Test tree deleted** and confirm only the
   generated `Clove-Scan` folder is gone.
5. With no generated tree present, select an existing Sony camera-folder copy
   containing `DCIM/100MSDCF`, another numbered folder, ARW+HIF and ARW+JPEG
   pairs and an `_Rejected` subtree. Run the suite and export. Compare accepted
   file/pair/photo counts with the known layout; excluded files must not enter
   the count. Record case variants and triples present, without sending photos
   or private paths. This probe does not display a photo grid; actual visible
   latency/order requires the later C2/I1/U3 integration measurement.
6. Repeat the synthetic tree on the **USB-C SSD**, then on **iPad Pro** with
   the same card/reader and SSD; repeat on Duo when available. A local-folder
   run is the optional phone baseline. Record actual device/OS and storage per
   report rather than comparing unlabeled results.
7. For a **locked card**, use the existing folder with **Run scan suite** only;
   report read and export outcomes. No generation or deletion is needed.
   Optional cancellation/disconnect checks use a disposable read-only test
   session with no pending writes. Send the observed progress/error and reopen
   behavior even when no JSON is produced; no partial-report export is promised.
8. Note each on-screen **`clove-lab-S6-<UTC timestamp>.json`** filename and
   **attach the JSON file to [issue #29](https://github.com/mimiqdev/cloveapp/issues/29)**,
   referencing #17. The current Lab screen still directs reports to #17;
   use #29 for these deferred runs. Include device/OS/build, storage/reader,
   expected counts, skipped checks and mismatches. JSON context is small, but
   review any report/comments for private paths before sharing.
