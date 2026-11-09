# S6 — How long does scanning take?

## Question

How long does a recursive scan of about 2,000 files take through a card reader,
which way of listing files and prefetching their attributes is fastest, and
should results appear while the scan runs?

This is part 1 of [#17](https://github.com/mimiqdev/cloveapp/issues/17): the
tree generator, three scanners, the pairing function, macOS and simulator
measurements, and a draft recommendation. The card-reader numbers, and with them
the finished recommendation for G1, belong to part 2.

2026-11-09 — HIF support: `.HIF`/`.hif` camera HEIF files are now accepted.
S6 pairs a same-name RAW+HEIF in the same folder, including Sony `.ARW`+`.HIF`.
**Proposal for G1:** if JPEG and HEIF both share the RAW's stem, keep RAW+JPEG
and leave HEIF as a separate standalone item. Pairing tests cover that rule,
case-insensitive matching and folder boundaries across all three listers.
A device rerun with a Sony HIF is pending; the historical measurements below
and the unfinished part 2 are unchanged.

## What was tested

- **Mac mini `Mac14,12` (M2 Pro), macOS 27.0 (26A428), Xcode 27.2 (27B52),
  Swift 6.4.2, debug build.** The host is shared and was heavily loaded while
  measuring: load average 270–860 on 10 cores, with the other spike workers and
  their simulators running. The macOS table is therefore the **median of nine
  observations** (three processes × three passes) with the min–max range; single
  values in the raw data are 3–4× the median when the scheduler interferes.
  These are **not** physical-device numbers.
- **iPhone 17 Pro simulator (`iPhone18,1`), iOS 27.0 (24A434)**, created for the
  run and deleted afterwards. A standalone arm64 simulator executable calls the
  same `ScanBenchmark.run` as Clove Lab and builds its tree in the simulator's
  own temporary container on the Mac's APFS. The run completed and produced a
  valid report, but the timings spread by one to two orders of magnitude under
  the same host load (for example `contentType` on `contentsOfDirectory`: 190 ms
  to 15,951 ms). The simulator data is **functional evidence only** and is not
  used for any conclusion.
- **Generated tree** (`ScanTree`), 2,000 photo files in six `DCIM/1xx…` folders:
  518 RAW+JPG pairs (CR3, NEF, ARW, RAF, ORF, RW2, DNG cycling), 1,482 grid
  items, a `_Rejected` folder with 150 JPEGs, 20 hidden entries (18 AppleDouble
  `._` files, `.DS_Store`, `.Trashes/`), and `.MOV`, `.txt`, and `.XMP` files the
  app does not open. The tree is written below a temporary directory in one
  `Clove-S6-Scan` folder. With sparse sizes the tree is ~25.9 GB logical,
  ~2 MB on disk.
- **Deviation from the issue's wording:** the tree does not copy fixture
  photographs. 2,000 real 20 MB RAWs need about 40 GB, and a listing reads names
  and metadata, not pixels. The generator writes a 1 KiB placeholder per file
  and, on APFS only, extends it to a plausible photo size with a sparse write, so
  `.fileSizeKey` and `.contentModificationDateKey` see card-like numbers without
  the disk use. The device tree uses the small placeholders because a camera card
  has no sparse files.
- **Three listing methods:** `FileManager.enumerator`, recursive
  `FileManager.contentsOfDirectory`, and Foundation-free `opendir`/`readdir`
  with the entry type or one `lstat` for directory detection.
- **Twelve key sets:** `names` (no prefetch), each of `name`, `type`,
  `isDirectory`, `size`, `modified`, `contentType` on its own, then the ladder
  `name+type`, `+size`, `+modified`, `+isDirectory`, and `all` (six keys).
- **Cache:** neither macOS nor iOS offers an unprivileged way to drop the page
  cache (`purge` needs admin rights, iOS has nothing). Every process generated a
  fresh tree before measuring, so pass 1 is the first touch in that process and
  passes 2–3 are warm. No claim about a cold card is made here.
- **Measured per scan:** traversal time, time to the 100th accepted file in
  traversal order, sort by path, pairing, the rejects folder skipped during the
  walk versus walked and filtered afterwards, prefetched keys versus one stat per
  file, and streamed batches of 64 files over `AsyncStream` with timestamps in
  both the producer and the consumer.
- **Reports:** `clove-lab-S6-…json` from the simulator runner and three
  `macOS*.json` files from the test collector, untracked under `.build/s6/` in
  the worker checkout. The macOS and simulator payloads are preserved gzip/base64
  with checksums in a comment on issue #17.

Reproduce the macOS report (about 10 s, writes outside the tracked tree):

```sh
mkdir -p .build/s6
CLOVE_S6_REPORT="$PWD/.build/s6/macOS.json" \
  mise exec -- swift test --package-path Packages/CloveSpikes \
  --filter ScanBenchmarkTests.collectReport
```

The simulator collector compiles `SpikeSupport`, `SpikeS6Scan`, and
`S6LocalRunner.swift` for `arm64-apple-ios18.0-simulator` with
`-D CLOVE_S6_LOCAL_RUNNER`, creates its own simulator, runs
`xcrun simctl spawn <device> <runner> <output-directory>`, and deletes the
device. `mise run verify` runs the functional tests (tree shape, three methods
agreeing on one file set, filters, pairing, batches, cancellation, report
round-trip) but no timing thresholds.

## Data

### Listing time per method and key set

macOS, freshly generated tree on the internal APFS SSD; milliseconds, **median
of nine observations** with the min–max range in brackets. The rejects folder is
skipped during the walk.

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

The same data per file: 32–36 µs for the two FileManager methods with all six
keys, 75 µs for `readdir`. Every key except `contentType` costs 2–3 ms in total
for 2,000 files; `contentType` costs about 45 ms with the enumerator and 42 ms
with `contentsOfDirectory`, and it alone raises a 26 ms scan to 71 ms.

### Other stages

macOS, milliseconds, median of nine observations (range in brackets). The scan
column repeats the `all`-key row for comparison.

| Stage | enumerator | contentsOfDirectory | readdir |
| --- | ---: | ---: | ---: |
| list `all` keys, skip rejects | 71.2 (63–272) | 64.1 (59–153) | 150.1 (116–438) |
| list `all` keys, walk rejects then filter | 72.7 (65–191) | 67.1 (60–176) | 179.4 (121–420) |
| list names, then stat each file for six keys | 136.3 (104–244) | 127.5 (97–261) | 160.0 (117–410) |
| sort by relative path | 10.7 (9–38) | 9.8 (9–22) | 9.8 (9–18) |
| pair RAW+JPG by base name | 14.2 (13–47) | 13.6 (13–31) | 16.0 (13–29) |
| filter rejects out by path | 3.7 (3–8) | 3.6 (3–8) | 3.6 (3–7) |
| stream first batch (64 files) | 4.0 (3–5) | 9.0 (9–19) | 5.9 (5–7) |
| stream last batch | 86.2 (80–107) | 82.9 (76–134) | 161.0 (134–323) |

First observation notes that matter for C2:

- **`contentType` is the expensive key.** Reading the UTI per file costs 30–75 µs
  per file on this Mac and dominates the scan. It is also redundant: the scan
  candidate list already comes from the extension, and capture time, camera, and
  preview failures come from ImageIO (S5, S2).
- **Prefetching beats one stat per file:** 71 ms versus 136 ms for the
  enumerator, 64 versus 128 for `contentsOfDirectory`. Prefetching is also what
  makes `contentsOfDirectory` competitive; `readdir` gains nothing because each
  value is a separate `stat`.
- **`readdir` is 2.1× the enumerator** with all keys and needs hand-written
  recursion, hidden and `._` filters, type detection, and error handling.
- **FileManager never returns AppleDouble `._` files**, even with
  `.skipsHiddenFiles` removed: the enumerator and `contentsOfDirectory` skip them
  internally. `readdir` does return them (20 hidden entries seen). The explicit
  `._` check still belongs in C2, because the rule is about the file set, not
  about one API's behavior.
- **Counts agree across methods:** 2,000 photo files, 8 directories, 2,004 file
  entries seen by the FileManager methods (2,024 by `readdir`, which also counts
  the 20 hidden entries), 3 unsupported files, 1 rejects folder, 0 stat
  fallbacks on APFS, 0 errors.
- **Pairing is cheap:** 14–16 ms for 2,000 files, about 20 % of a 71 ms
  enumerator scan, and 518 pairs were found identically by all three methods
  (1,482 grid items).
- **Skipping the rejects folder during the walk** saves little on the internal
  SSD (1.5 ms for 150 files) but is simpler and never touches rejected files'
  metadata. On `readdir` the walk-and-filter variant costs 29 ms more.
- **Streaming arrives early:** the first 64-file batch is produced in 4–9 ms and
  the first 100 accepted files in 4–9 ms, while the complete scan takes
  64–150 ms. The consumer received the first batch within about 0.2 ms of the
  producer emitting it, so the delivery mechanism is not the cost.

### Simulator run

The iPhone 17 Pro simulator produced a valid `LabReport` from the same suite, so
the Lab path, the JSON schema, and the generated tree work with the iOS SDK. Its
timings are not usable: under the host load, `all`-key listing took 323–1,798 ms
with the enumerator, 255–5,575 ms with `contentsOfDirectory`, and
1,032–10,726 ms with `readdir`, and individual `contentType` scans reached 16 s.
The shape of the result matches macOS (`contentType` dominates, `readdir` is
slowest, streaming arrives early), but no number from the simulator is quoted as
iOS performance.

## Conclusion

On the internal SSD, one recursive listing of 2,000 photo files with the five
metadata keys C2 needs takes about **22–26 ms**, and about **64–71 ms** if
`contentType` is included. POSIX `readdir` is roughly twice that. Prefetching
keys during the walk is about twice as fast as listing names and statting each
file afterwards, pairing adds 14–16 ms, sorting 10 ms, and a streamed first batch
arrives after 4–9 ms.

The two FileManager methods are within measurement noise of each other here; the
enumerator is recommended for a single call and `skipDescendants`, not for a
measured speed advantage. Dropping `contentType` from the prefetch set is the
single largest saving. Showing results during the scan is justified: the first
batch is ready after roughly a tenth of the total scan time. The card-reader
factor is unknown, so the absolute targets stay open until part 2.

## Recommendation and options for G1

**Recommended scan strategy (A):**

1. One `FileManager.enumerator(at:includingPropertiesForKeys:options:)` pass over
   the opened folder with `[.nameKey, .isRegularFileKey, .isDirectoryKey,
   .fileSizeKey, .contentModificationDateKey]`, `.skipsHiddenFiles`, and an
   error handler that counts unreadable entries and continues.
2. When a directory's name equals the configured rejects folder
   (`_Rejected` by default), call `skipDescendants()` and do not touch its files.
3. Accept candidates by extension (RAW, JPEG, HEIC/HEIF/HIF); count unsupported files
   for the visible state instead of asking the system for a UTI.
4. Emit batches of 64–128 entries through `AsyncStream`. Pair a RAW with a
   same-name JPEG or HEIF in the same folder, preferring JPEG when both exist
   and leaving HEIF standalone (proposal for G1). Carry a RAW over to the next
   batch when its companion has not arrived yet, or pair once at the end
   (the historical RAW+JPEG run took 14 ms for 2,000 files).
5. Sort by capture time (C8) when the scan completes, or stream in path order and
   re-sort without moving the cell the user is looking at.
6. Keep the POSIX walk for the verification tool, not for the product.

**Proposed performance targets to confirm on device:** first 64-cell batch under
0.5 s, complete 2,000-file scan under 3 s. The same work takes 4–9 ms and
64–150 ms on this internal SSD, so a card reader about 20× slower would still
meet both. These are proposals for G1, not measured card numbers.

**Options and what each costs:**

| Option | Change | Measured cost | Trade-off |
| --- | --- | --- | --- |
| A (recommended) | enumerator, five keys, streamed batches | 26 ms listing, 14 ms pairing, 10 ms sort (2,000 files, internal SSD) | Lowest measured cost; extension list must stay current |
| B | add `.contentTypeKey` | 71 ms listing, about 2.7× A | A system UTI per file; duplicate of the extension list |
| C | recursive `contentsOfDirectory` | 21.7 ms with the same keys, within noise of A | Manual recursion; no measured advantage |
| D | POSIX `opendir`/`readdir` | 63 ms with the same keys, about 2.4× A | Own recursion, filters, and type detection; only method that sees `._` files |
| E | scan fully, then show the grid | saves the batch and split-pair handling | Blank grid for 64–150 ms here, likely 1–3 s on a card |

## Open questions

1. **Card-reader factor.** How much slower is the same tree through the product
   owner's card and reader? This settles the proposed first-batch and full-scan
   targets.
2. **`contentType` on iOS.** Is the UTI lookup as expensive on a device as on the
   Mac? The simulator's numbers cannot answer this.
3. **Streaming versus sorting.** May the grid show path-ordered cells before the
   capture-time sort (P0-03), as long as the visible photo does not move? The
   PRD settles the no-jump rule for grouping, not for the first scan.
4. **Folder size.** Is 2,000 files a typical card folder, or should the target
   cover 5,000 or more? The suite is linear in file count, so a larger target is
   a matter of the time budget.
5. **Read-only cards.** The generated tree needs a writable card. On a locked
   card the suite can still run on an existing folder, with the file count recorded
   in the report.

## Device checklist

1. Connect the SD card reader, insert a writable card, and open Clove Lab ›
   S6. Allow 5–15 minutes for the whole checklist.
2. Tap **Choose folder** and pick the card's root folder, for example
   `EOS_DIGITAL`. The screen shows the folder name.
3. Tap **Generate test tree**. Expect a progress line counting to about 2,150
   files and then "Test tree ready: 2000 photo files". The card now has one
   `Clove-S6-Scan` folder with `DCIM/100CANON` … `105PANASONIC`.
4. Tap **Run scan suite**. Expect about 135 scans in three passes, the status
   line naming the method and key set, and then
   "Finished: clove-lab-S6-<timestamp>.json". If the run takes much longer than
   15 minutes, cancel and note the card and reader model.
5. Note the report file name on screen, then tap **Delete test tree** and confirm
   the card has no `Clove-S6-Scan` folder left.
6. Send the JSON back: attach the file to
   [#17](https://github.com/mimiqdev/cloveapp/issues/17), or use **Export** in
   the footer. Copies are also in Files › On My iPhone › Clove Lab.
7. Repeat on iPhone 17 Pro Max and iPad Pro if available, iOS 27.x, with the same
   card and reader. Record the card model, reader model, and card free space in
   the issue comment.
