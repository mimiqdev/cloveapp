# S4 — Can metadata be changed without re-encoding?

## Question

Can metadata be changed without re-encoding?

Part 2 of [#15](https://github.com/mimiqdev/cloveapp/issues/15), following
[PR #25](https://github.com/mimiqdev/cloveapp/pull/25) and the HEIF comparison / JPEG
seed changes in [PR #28](https://github.com/mimiqdev/cloveapp/pull/28). Device
runs 1 and 2 complete the available confirmation. On 2026-11-09 the product owner
deferred the remaining checks to [#29](https://github.com/mimiqdev/cloveapp/issues/29).
G1 remains open; this report recommends policy without changing the PRD or writer.
The main target is camera files, particularly Sony A1 II ARW+HIF pairs.

`.HIF`/`.hif` camera HEIF files are accepted by the file filter and HEIF
payload/MakerNote readers. The current comparison follows `pitm` → primary/grid
→ ordered `dimg` references and locates auxiliary/derived images by reference
type and owner, including tone maps, gain maps, alpha/depth and thumbnails. A
canonical reference-topology digest detects changed ordering/ownership even for
shared items. Source item IDs remain diagnostic fields; `heif-renumbered-only`
records ID changes separately from `compressed-content-changed`. Disconnected,
ambiguous or unsupported image graphs fail closed. Synthetic tests cover
renumbering, moved storage/table order, changed tile order/ownership and changed
coded bytes. The device HIF result below adds camera evidence; no new fixture
is pinned.

## What was tested

- Mac mini `Mac14,12`, macOS 27.0, Xcode 27.2 (`27B52`). Timings were taken on a
  **shared, loaded host** with other spike workers. One pass per case; these are
  observations, not throughput targets or device performance predictions.
- A fresh iPhone 17 Pro simulator (`iPhone18,1`), iOS 27.0 (`24A434`), created and
  deleted for S4. The package's S4 tests run with `xcodebuild test -scheme
  CloveSpikes -only-testing:SpikeS4MetadataTests`; they exercise the same plain
  functions as the Lab screen.
- The `formats` set in `/Volumes/T7/Projects/.clove-fixtures/sets/formats`, filtered
  to `canon-eos-6d.JPG`, `sony-ilce-7s.HEIC`, `pentax-k-5-ii-s.DNG`, and
  `apple-iphone-12-pro.DNG`. HEIC is the generated `sips` recipe described in
  `fixtures/generated.json`, not an iPhone camera HEIC. Every attempt starts from
  a private temporary copy. Tests hash the picked fixtures before and after;
  neither the sets nor the cache's `files/` folder is written.
- Fourteen attempts per four-file host/simulator pass: native copy and a decoded
  re-encoding comparison for each file, a seeded preservation control for each
  file, and two JPEG-only XMP packet replacement comparisons (original and seeded).
- Two physical-device reports from iPhone 17 Pro Max (`iPhone19,4`), iOS 27.2,
  local storage: Clove Lab 26110818 and 26110903. Their filenames, SHA-256 hashes,
  camera files and per-write findings are in Physical-device confirmation below.
- Baseline writes use rating `3`, label `Green`, and Reject `True`. Seeded writes
  replace rating `1`/`Red` with rating `-1`/`Purple` and Reject `False`. The latter
  exercises the optional rating-minus-one convention and clearing Reject;
  rating and Reject remain independent. The experimental Reject namespace is
  `urn:clove:spike:s4:1.0/`, not a production namespace decision.

JSON reports stay out of git. Part 1 recorded these ignored local artifacts
(they are not copied into the part-2 checkout):
`.build/s4/clove-lab-S4-macos.json`,
`.build/s4/clove-lab-S4-simulator.json` (timing samples), plus
`.build/s4/clove-lab-S4-macos-verification.json`,
`.build/s4/clove-lab-S4-simulator-verification.json` and
`.build/s4/simulator.xcresult` (final checks including interruption/thumbnail tests).
They use `LabReport` schema 1: scalar results in `measurements`; each JSON object
string in `notes` retains the complete before/after hashes, source properties,
recursive XMP tags (including qualifiers), changed paths, errors, and failure
integrity checks. The device evidence is cited below by report filename and
SHA-256. The owner's JSON was read in place and is not committed; capture
timestamps, GPS values, serial numbers and personal folder paths are omitted.

Historical part-1 checks: `mise install` and `mise run verify` passed; the final
simulator run passed all 9 then-current S4 tests. Its validation-only release
attempt stopped at the existing-build-number guard before archive/signing.
Part-2 check output is recorded separately in the pull request.

The repository calls the JPEG a camera JPEG. Its actual embedded packet contains
`Image::ExifTool 10.27`, Adobe Camera Raw settings, and an XMP history entry saying
it was converted from `image/x-canon-cr2` to `image/jpeg`. This is useful
other-app metadata coverage, but does not establish an untouched out-of-camera
JPEG. Shared fixture-provenance correction is tracked separately in
[#23](https://github.com/mimiqdev/cloveapp/issues/23).

## Data

### Per-format result

The macOS and simulator native-copy results agree. This historical table answers
the narrower **no re-encoding** question: compressed image bytes and decoded
pixels were unchanged where marked yes. It does not establish preservation-safe
eligibility. The device findings and G1 table below require preservation too;
`lossless-candidate` additionally checks marks, existing metadata, MakerNotes,
image count and EXIF previews. A successful seeded control is not a substitute
for comparing against the camera original.

| Format / fixture | Write without re-encoding in tested paths? | Method | What else changed / preservation | Evidence |
| --- | --- | --- | --- | --- |
| JPEG / Canon EOS 6D | **Yes** | `CGImageDestinationCopyImageSource` + metadata + merge; JPEG APP1 XMP replacement comparison also works | Native copy rewrites EXIF rationals and slightly changes GPS latitude; packet replacement preserves every byte outside the standard XMP segment and all source-exposed existing metadata | 4,316,790 scan bytes identical; 5472×3648 RGBA digest identical; rating/label/Reject read back on both OSes |
| HEIC / generated Sony image | **Yes**, for this generated file | `CGImageDestinationCopyImageSource` + metadata + merge | New XMP grows the file; no existing property or recursive XMP value changed; seeded caption, keywords, unknown namespace, nested structure, ordered array and language qualifier survive | 25 image items (primary grid plus 24 HEVC tiles), 1,805,397 bytes identical; 2768×1848 RGBA digest identical on both OSes |
| Camera DNG / Pentax K-5 II s | **No**, ImageIO paths unavailable | Both ImageIO destination paths reject `com.adobe.raw-image` | Original whole-file hash unchanged; there is no rewritten output to compare; seeded write unavailable too | 1 raw strip, 17,265,510 bytes; 2 other image payloads, 1,167,260 bytes; pre-write 4928×3264 raster decodes on both OSes |
| ProRAW DNG / iPhone 12 Pro | **No**, ImageIO paths unavailable | Same destination rejection | Original whole-file hash unchanged, including maker note, previews and auxiliary image; seeded write unavailable | 64 raw tiles plus 2 other image payloads, 29,131,484 bytes total; pre-write 4032×3024 raster decodes on both OSes |

The documented copy path writes the result itself: do **not** call
`CGImageDestinationFinalize` afterward. The destination type matches the source.
The metadata input contains only the three requested fields and
`kCGImageDestinationMergeMetadata = true`. A full source-metadata round-trip was
also tried during development; the minimal delta still shows the native JPEG
normalization, so a delta alone does not solve that problem.

### File sizes and atomic write times

These samples are from the original (unseeded) files. Time covers opening the
source, creating metadata, writing the sibling temporary file and renaming it,
but excludes input copying and the expensive verification snapshots. Failed
attempt times end at the rejection. Baseline macOS JSON was recorded at
2026-11-08T17:34:08Z; the simulator sample was recorded at
2026-11-08T17:33:56Z. Later acceptance runs confirm behavior and are not averaged
into these samples.

| File / method | Before, bytes | After, bytes | Delta, bytes | macOS, ms | Simulator, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| JPEG / native copy | 4,365,312 | 4,362,036 | −3,276 | 8.253 | 111.016 |
| JPEG / XMP packet replacement | 4,365,312 | 4,367,709 | +2,397 | 7.740 | 88.362 |
| HEIC / native copy | 1,809,122 | 1,809,375 | +253 | 9.458 | 43.699 |
| Pentax DNG / native attempt | 18,537,244 | unchanged | 0 | 0.276 | 25.756 |
| ProRAW DNG / native attempt | 29,195,592 | unchanged | 0 | 0.366 | 9.431 |
| JPEG / decode + add image and metadata | 4,365,312 | 5,748,706 | +1,383,394 | 201.710 | 1,352.133 |
| HEIC / decode + add image and metadata | 1,809,122 | 1,806,967 on Mac; failed on simulator | −2,155 on Mac; 0 on simulator | 89.819 | 536.577 (failed) |

`CGImageDestinationAddImageAndMetadata` receives a decoded `CGImage`; it is an
explicit re-encoding control, not a fallback suitable for PRD rule 6. JPEG's
compressed scans **and** decoded pixel digest change on both OSes. HEIC's image
items and pixels change on macOS. The simulator HEIC encoder instead fails at
finalization; its original stays unchanged. Both DNG destination creations fail.
The spike does not claim that every use of `CGImageDestinationAddImageFromSource`
necessarily re-encodes: that API was not used as a separate comparison.

### Preservation and evidence boundaries

- Native JPEG copy changes the fixture's GPS latitude by about 0.19 m
  north/south, including its XMP coordinate representation. It also reduces
  equivalent fractions such as
  `96500/10000` → `193/20`, changes unknown lens-aperture `0/0` to `0/1`, and changes
  aperture/shutter floating values slightly. All 12 changed existing paths are
  retained in JSON. This is an actual preservation caveat, despite identical
  image data; it is not counted as a fully preserved candidate.
- The JPEG packet comparison copies all bytes other than one standard APP1 XMP
  segment exactly. Therefore existing EXIF, IPTC, ICC/profile data, any embedded
  EXIF thumbnail and maker-note bytes are untouched. The fixture's 15,028-byte
  EXIF JPEG thumbnail is also checked independently and is identical after both
  native copying and packet replacement. Existing source-exposed XMP
  (including Camera Raw edits/history) remains equal apart from the requested
  marks. Standard packet serialization changes whitespace/size. A standalone
  ImageIO XMP parse rejects this fixture's original packet; the image-source
  metadata reader supplies the comparison's fallback metadata. This fallback
  must not be generalized to arbitrary unreadable or unsupported XMP.
- **Seeded-control boundary:** the historical results above used a native write
  to create the seed. That write may already discard a camera MakerNote or
  normalize EXIF rationals before the measured "before" snapshot. A successful
  seeded result, including `lossless-candidate = 1`, does **not** show
  preservation against the camera original. Since 2026-11-09, JPEG seeds merge
  sentinels into existing XMP by packet splice; every original byte outside XMP
  is retained (unit checked). Native copy of this stronger seeded JPEG still
  exposes EXIF/GPS normalization and can reconcile the original IPTC caption
  over the seeded XMP caption on macOS. Packet splice preserves the seed.
  HEIF seeds still use native writes, with the same explicit limitation in the
  JSON notes and Lab screen. Camera-original rows must also be consulted.
- Historical native-seeded JPEG and generated HEIC controls add an independent
  unknown namespace with scalar, nested resource, ordered array, caption/keywords
  and `xml:lang` qualifier; all source-exposed values survive from those seeds.
  The stronger PR #28 JPEG seed exposes native caption reconciliation too. The
  JPEG seed also lands GPS. The HEIC seed's requested GPS does **not** land, and
  the HEIC fixture has no GPS or maker note;
  HEIC GPS/maker-note preservation is therefore **unproven**, not a pass on
  absent information. Arbitrary camera HEIC auxiliary/gain-map variants need
  broader coverage before a production allowlist.
- Raw maker-note bytes are hashed from TIFF/EXIF rather than inferred from
  decoded properties. The pinned ProRAW source has a 1,268-byte maker note. No
  maker note is found in the other three pinned fixtures. Device files below
  add Sony JPEG/HIF and a different ProRAW MakerNote. No successful DNG write
  exists; source-integrity evidence is the whole-file digest on rejection.
- JPEG evidence includes every SOS scan, stuffed bytes and restart markers;
  synthetic tests also mutate a later progressive scan. EXIF thumbnail ranges
  are checked independently. HEIC parses `iinf`/`pitm`/`iloc`, resolves every
  non-metadata image item's extents in `mdat` (or construction-method-1 `idat`),
  and excludes Exif/XMP items that share the same `mdat`. Comparing the whole
  `mdat` would incorrectly flag a metadata edit as an image change. DNG follows
  next-IFD and SubIFD links and hashes every strip/tile/JPEG preview, requiring an
  identified CFA or LinearRaw payload. BigTIFF and unsupported extent variants
  fail closed. Truncated/malformed containers never yield an empty "pass".
- Pixel verification uses ImageIO index 0 at its native decoded dimensions,
  rendered to deterministic sRGB 8-bit RGBA. It checks the system's default
  raster, not a second independent RAW renderer. The compressed-byte checks are
  the direct proof that image data was not re-encoded. No comparison relies on
  whole-file equality after a successful metadata write.
- All output goes through a sibling temporary file and a single POSIX `rename`.
  Tests inject failure after a partial candidate is written, verify that the
  original survives and no candidate remains, then verify successful replacement.
  Unsupported writes and encoder failures also retain the original whole-file
  hash. This proves local failure cleanup and atomic path replacement; it does
  not establish crash durability, Files-provider coordination, or exFAT-device
  behavior. S3's device/storage results remain relevant to the later writer.

### Physical-device confirmation

Both runs used **iPhone 17 Pro Max (`iPhone19,4`), iOS 27.2, local storage only**.
Run 1 used Clove Lab **26110818**, run 2 **26110903** (after PR #28).
These are single observations, not a throughput benchmark. The reports use
schema 1; the per-write JSON objects in `notes` supply the before/after evidence,
changed paths and errors behind the scalar `measurements`.

| Evidence ID | Report filename | SHA-256 (`shasum -a 256`) |
| --- | --- | --- |
| Run 1 | `clove-lab-S4-20261109T023845Z.json` | `158ed70b54d3b033d77a12b04effa3003c0735beb02a5151f63e12d57cb4ce3f` |
| Run 2 | `clove-lab-S4-20261109T032611Z.json` | `7e24d160320237b9befc35f5282d0720196e77acd12650933d907f6d464adec3` |

Run 1 contains `6789416231.jpg` (Sony ILCE-1M2 / A1 II), `IMG_3435.HEIC`
(iPhone) and `IMG_3404.DNG` (iPhone ProRAW): **11 attempts**. Run 2 contains the
same three files plus Sony A1 II `MMQ05184.HIF`: **14 attempts**. Its surrounding
device session also contained ten ARW+HIF pairs; S4 did not measure embedded ARW
writes or all ten HIFs. Run 1 predates HIF support and does not establish an HIF
write result.

#### Device findings

Here “preservation-safe” requires unchanged image payloads/pixels **and** no
unrelated information loss. “Candidate” is the JSON `lossless-candidate` scalar;
its value is meaningful only within that control and the comparator's coverage.
Every row identifies measured evidence or a deferred check.

| Status / evidence | File / control / method | Payloads and pixels | Preservation-safe embedded write? / other findings |
| --- | --- | --- | --- |
| **Measured — runs 1, 2** | A1 II JPEG, camera-original, native copy | 10,605,961 scan bytes and 8640×5760 pixels identical | **No**, candidate 0. Entire 38,340-byte MakerNote lost; EXIF rationals rewritten; 24 changed paths, of which 20 are unrelated existing-metadata paths |
| **Measured — run 1** | JPEG, native-seeded, native copy | Identical | Candidate 1 only against a seed whose MakerNote was already gone; no proof of camera-original preservation |
| **Measured — run 2** | JPEG, packet-splice seed, native copy | Identical | **No**, candidate 0. The stronger seed retains the original MakerNote before the measured write; native copying drops it and changes unrelated metadata, including seeded caption values |
| **Measured — runs 1, 2** | JPEG, camera-original and seeded, packet splice | Identical | **Yes on tested files**, candidate 1 in both controls. Only 4 mark paths change; all non-XMP bytes identical. Run 1's seed had already lost the MakerNote; run 2 preserves it in both controls |
| **Measured — runs 1, 2** | JPEG, camera-original, decode/re-encode control | Scan bytes and pixels changed | **No**; expected negative control |
| **Measured — run 2** | A1 II HIF, camera-original, native copy | Primary grid and nine tiles identical; 8640×5760 pixels identical; one thumbnail lost | **No**, candidate 0. Keeps 38,400-byte MakerNote and two HEVC thumbnails, drops an 8,192-byte JPEG thumbnail, changes reference topology and adds `photoshop:DateTimeOriginal`; −65,774 file bytes |
| **Measured — run 2** | HIF, native-seeded, native copy | Remaining payloads and pixels identical | Candidate 1 only against the native seed, which already lacks the JPEG thumbnail; not camera-original preservation |
| **Measured — run 2** | HIF, camera-original, decode/re-encode control | Tiles and pixels changed | **No**; MakerNote and thumbnails lost too; expected negative control |
| **Measured — run 1** | iPhone HEIC, native copy, original and native-seeded | Old ID-keyed comparison reports original payload mismatch; pixels identical; seeded candidate 1 | **Inconclusive**. Historical byte multiset evidence is consistent with item renumbering, but cannot prove reference ownership. Superseded by the explicit refusal below; no eligibility inferred |
| **Measured — run 1** | iPhone HEIC, decode/re-encode control | Payloads and pixels changed | **No**; expected negative control |
| **Measured — run 2** | iPhone HEIC, all three attempts | No completed snapshots/output comparison: `Ambiguous HEIF image ownership` | **Known gap**, out of focus until photo library support. Original-control attempts fail before the requested write and retain their private copy; seeded caveat below |
| **Measured — runs 1, 2** | ProRAW DNG, native, seeded and re-encode attempts | No successful output; whole-file failure-integrity check passes | **No ImageIO destination**: `ImageIO has no destination for com.adobe.raw-image`. Original 32,280,352-byte file unchanged |
| **Deferred — #29** | S4 exFAT card / reader | Unmeasured | Card access/export and actual on-card replacement remain distinct checks; see below |
| **Deferred — #29** | iPad Pro confirmation | Unmeasured | No iPad format, preservation or timing claim |
| **Deferred — #29** | iPhone HEIC ownership support | Unresolved by current comparator | Known gap to revisit with photo library support; not a camera-workflow blocker |

The four JPEG mark paths are `xmp:Rating`, `xmp:Label`, `clove:Reject` and the
ImageIO-exposed `properties.{IPTC}.StarRating`. Four paths represent three marks.
Native JPEG's 24 changed paths are not “24 rationals”: the list includes the
four mark paths, numeric XMP/EXIF representations, and removed camera properties.
Its MakerNote loss is checked separately as raw bytes. Packet splice preserves
that MakerNote, the EXIF JPEG preview and every byte outside standard APP1 XMP.
On run 2 it also retains seeded unknown-namespace scalars, nested structures,
ordered arrays, keywords and the caption/language qualifier.

For camera HIF, compare `notes` for the **camera-original** native write:
`HEIF/primary/grid/thmb/in/1/jpeg` (source item 13, 8,192 bytes) disappears.
The original has 13 image items: grid, nine tiles and three thumbnails; the
output has 12. The two retained HEVC thumbnails are 8,192 and 110,592 bytes.
The primary grid is 8 bytes and the nine coded tiles total 8,130,560 bytes;
all those bytes and the MakerNote hashes match. The canonical reference digest
changes too. Accordingly `compressed-content-changed = 1` and
`heif-renumbered-only = 0`: this is actual loss, not harmless item renumbering.
The removed thumbnail explains only 8,192 bytes of the 65,774-byte shrink;
the report does not attribute the remaining container/metadata size change to
one cause. `changedExistingMetadata` is empty but does not cover image items;
its emptiness cannot override the thumbnail loss. The seeded HIF “before”
already has the 12-item topology, explaining its candidate 1.

The iPhone HEIC diagnosis in [#29](https://github.com/mimiqdev/cloveapp/issues/29)
is ten byte-identical 156-byte `hvc1` items with identical references. Run 1's
payload hashes confirm the ten identical byte ranges; run 2's reference-based
reader refuses ambiguous ownership rather than guessing. This does not show a
changed image. There is one important failure-integrity boundary: the run-2
**seeded** attempt reports `failure-original-unchanged = 0`. Code inspection
shows native seed creation runs before the failing snapshot, so the private
working copy was already changed by the seed; the requested measured write did
not run. The two unseeded attempts report 1. Picked source files are only read
and copied by the harness. No comparator/HEIC fix is included in part 2.

The ProRAW snapshot identifies 48 raw tiles and one other strip/preview,
32,074,707 payload bytes, a 1,816-byte MakerNote, and a 5712×4284 decoded raster.
There is no “after” snapshot on destination rejection. Zero comparison scalars
on a failed attempt mean **no comparison**, not that rejected writes altered
pixels or raw data. No embedded ARW writer was tested; proprietary RAW remains
sidecar-only under PRD rule 2.

#### Device sizes and times

All rows below are **measured — run 2**, local private-copy writes. Time excludes
source copying, seed construction and verification; it is one sample per row.
Refusal time ends at destination rejection. The HEIC ownership refusal occurs
before a write clock is started, so it has no write timing.

| File / control / method | Before, bytes | After, bytes | Delta, bytes | Write / refusal, ms |
| --- | ---: | ---: | ---: | ---: |
| JPEG / original / native | 10,980,880 | 10,943,630 | −37,250 | 11.662 |
| JPEG / packet seed / native | 10,980,581 | 10,944,370 | −36,211 | 13.142 |
| JPEG / original / packet splice | 10,980,880 | 10,979,750 | −1,130 | 10.925 |
| JPEG / packet seed / packet splice | 10,980,581 | 10,980,679 | +98 | 10.464 |
| JPEG / original / re-encode | 10,980,880 | 7,980,471 | −3,000,409 | 240.425 |
| HIF / original / native | 8,413,184 | 8,347,410 | −65,774 | 6.263 |
| HIF / native seed / native | 8,348,076 | 8,348,174 | +98 | 10.094 |
| HIF / original / re-encode | 8,413,184 | 8,782,613 | +369,429 | 229.120 |
| ProRAW / original / native refusal | 32,280,352 | unchanged | 0 | 0.237 |
| ProRAW / original / re-encode refusal | 32,280,352 | unchanged | 0 | 2.034 |

These local timings do not predict SD-card throughput, coordination overhead,
or durable-write latency. The existing S4 runner copies picked inputs into
`FileManager.default.temporaryDirectory`; its sibling temp file and `rename`
operate there, even when the picked folder is on an external volume. This is
local atomic replacement evidence, not an exFAT replacement measurement.

## Conclusion

JPEG packet splicing is the only tested camera embedded-write path that retains
both image data and unrelated information. Native JPEG copy preserves scans and
pixels but drops Sony MakerNotes and changes EXIF; native camera HIF copy keeps
tiles, pixels and MakerNotes but discards a JPEG thumbnail. Neither is an
acceptable preservation-safe fallback. ImageIO cannot write the tested DNGs.
The generated HEIC success does not establish camera HIF eligibility. iPhone
HEIC remains an explicitly recorded ownership gap outside the current focus.

## Recommendation and options for G1

Recommend **sidecars by default**, a bounded JPEG embedded option after C7
hardening, and **no native camera-HIF or RAW embedded writes**. This respects
PRD rules 2, 6 and 9 without silently accepting information loss. The product
owner chooses at G1; no product setting or decision record is changed here.

| Format / item | Default destination | Recommended optional in-file state under rule 6 | Evidence / condition |
| --- | --- | --- | --- |
| Standalone JPEG | Same-stem `.xmp`; embedded setting off | Eligible only through a preservation-safe packet writer for supported XMP/container forms; otherwise disabled / explicit refusal | Packet splice passes camera-original and stronger seeded controls. Native copy is excluded because it loses MakerNotes and changes EXIF |
| Standalone camera HIF / HEIF | Same-stem `.xmp`; embedded setting off | **Disabled for current ImageIO path** | A1 II native copy loses an embedded JPEG thumbnail and topology; seeded/generated successes cannot justify an allowlist. A preservation-safe container editor would need new evidence |
| Proprietary RAW, including A1 II ARW | Same-stem `.xmp` | **No embedded writes** | PRD rule 2; ARW embedding was not tested and is not needed for the owner's primary workflow |
| Standalone camera DNG / ProRAW DNG | Same-stem `.xmp`; embedded setting off | **Disabled for tested ImageIO paths** | Camera DNG rejected on Mac/simulator; ProRAW also rejected on device. No destination, original unchanged |
| RAW+HIF or RAW+JPEG pair | **One shared same-stem `.xmp` beside the pair** | **Do not embed in either member** | Rule 6 applies to standalone files without paired RAW. Keeps one persisted set of marks for the pair |
| iPhone HEIC | Sidecar; embedded setting off | Disabled / known gap, revisit with photo library support | Run 2 refuses ambiguous ownership; not a blocker for camera files |

For example, `MMQ05184.ARW` + `MMQ05184.HIF` share `MMQ05184.xmp`; an
`IMG_0001.ARW` + `IMG_0001.JPG` pair shares `IMG_0001.xmp`. Rating, label and
Clove Reject go in that one sidecar. Neither original nor the rendered companion
is changed, even if the standalone embedded option is enabled. Follow
[S3's sidecar naming and preserving-editor findings](S3-xmp.md): replace the
extension, discover existing `.XMP` case variants before creating a new file,
preserve unknown content, and refuse ambiguous/malformed inputs. S3 shows that
ImageIO whole-packet serialization can lose history or qualifiers; S4's
ImageIO-based XMP serialization passing its own sentinels is not proof against
those S3 losses. C7 should combine JPEG container splicing with the validated
preserving XMP edit selected at G1, rather than ship the spike serializer as-is.
C4 must confirm completed writes/read-back before showing Saved and retain
requested marks on failures.

The shared sidecar is a pair-level persistence rule, not a promise that every
desktop app will display embedded-companion marks. S3's Lightroom, Capture One
and Photo Mechanic checks still need to confirm naming, pair preferences and
read/sync behavior. Lightroom's standalone-file sidecar limitation remains:
for standalone HIF or DNG, saving a sidecar does not establish Lightroom
interoperability. Show the PRD's “Embedded write unavailable” explanation and
keep that limitation visible at G1; do not re-encode or claim it is solved.
The owner's principal ARW+HIF workflow can still use the shared RAW sidecar.

Options for G1 (the product owner chooses):

1. **Recommended:** sidecars for RAW and pairs, hardened preserving packet edits
   for supported standalone JPEGs, and disabled HIF/DNG embedding with the PRD
   explanation. Costs C3/C4/C7 hardening and preserves the tested originals;
   leaves standalone HIF/DNG Lightroom interop unresolved.
2. Keep every embedded option disabled initially. Reduces C7 scope but also
   leaves standalone JPEG Lightroom interoperability unresolved; weigh this
   explicitly against P0-07 before choosing it.
3. Investigate a preserving HEIF container editor and/or TIFF/DNG packet editor,
   or evaluate a separately approved library. Requires preservation of item
   topology, thumbnails, auxiliary images, MakerNotes and unknown metadata,
   plus device evidence. Lack of an ImageIO destination does not prove that
   every possible DNG writer is impossible.
4. Accept native JPEG/HIF loss as a product tradeoff. This is **not recommended**:
   it discards camera information. It would require an explicit owner assessment
   of PRD rule 9, rather than calling unchanged primary pixels “lossless”.

No performance target is proposed from these single local observations.

## Open questions

- **G1:** approve JPEG packet editing and its supported forms, disabled camera
  HIF/DNG embedding, and the visible standalone Lightroom limitation. Choose
  S3's production Reject namespace and optional Rating −1 restoration policy.
- **C3/C7:** bound packet sizes/encodings and JPEG segment placement; define
  extended/duplicate/malformed-XMP policies; verify unknown XMP against S3's
  stronger corpus and independently read back marks. The spike rejects
  duplicate/extended packets and is not a production codec.
- **C4 / #29:** provider coordination, permissions/attributes, actual exFAT
  replacement, crash durability and storage failures need writer validation.
  Successful app-local renames do not settle them.
- A broader camera-HIF corpus and a preserving alternative would be needed to
  reconsider embedding. The owner's sample answers the current A1 II question,
  but does not make a universal HEIF or camera guarantee. Public fixture
  provenance work remains in #23 and is outside this part 2.
- Desktop shared-sidecar behavior remains S3's read-only cross-reference above;
  no desktop interoperability result is invented here.

## Deferred device checks

The owner deferred the following checks on 2026-11-09 in
[#29](https://github.com/mimiqdev/cloveapp/issues/29); they do not block closing
#15 with the available evidence. Run them before M3/Q3 performance targets are
fixed, or sooner if G1 needs their answers.

| Deferred check | What it would answer | Could it change the G1 recommendation? |
| --- | --- | --- |
| S4 folder on an exFAT SD card / reader | Whether picker access, reading/copying fixture inputs and report export work on that storage; a follow-up writer probe staging on the card is needed to measure actual replacement, cleanup and failure behavior | Could change the C4 staging/coordination and supported-storage policy. It cannot undo the observed native JPEG/HIF information loss or create an ImageIO DNG destination |
| iPad Pro, installed iPadOS version recorded | Whether format availability, preservation outcomes and local timings agree on another device/OS | Could narrow or expand a device/OS allowlist if behavior differs. Until measured it cannot justify enabling native HIF/JPEG copying; pair/RAW sidecars remain the recommendation |
| iPhone HEIC ownership support, with photo library work | Whether byte-identical items with identical references can be compared without guessing, then whether a write preserves every item and unrelated metadata | Could change future iPhone-HEIC eligibility. It does not change the camera JPEG/HIF/RAW recommendation and is not a camera-workflow blocker |
| S3 desktop checks and external-storage checks (dependency) | Whether desktop apps read the shared sidecar as intended and which replacement/coordination behavior works on physical storage | Could refine pair interoperability guidance and C4 implementation. A failure would need a G1 assessment; it would not justify embedding through the lossy native paths |

### Deferred device checklist

No new device run is required for this PR. When #29 is scheduled:

1. Put **copies** of `6789416231.jpg`, `MMQ05184.HIF` and `IMG_3404.DNG` in a
   small flat **S4 fixtures** folder on the exFAT card. Connect its reader and
   use the supervisor's Clove Lab build. Repeat on **iPhone 17 Pro Max** and
   **iPad Pro**, recording installed OS versions. iPhone HEIC is optional and
   remains a known gap, not a required pass.
2. Open **Clove Lab → S4 → Choose folder**, select **S4 fixtures**, then press
   **Run metadata check**. Allow about 1–2 minutes. These three files produce
   **11 attempts**: JPEG packet controls should preserve payloads/pixels and
   metadata; native JPEG/HIF should expose the documented losses; DNG should
   report no destination. Re-encoding differences are expected. Selected
   originals stay unchanged. Adding iPhone HEIC makes 14 attempts and may
   report ambiguous ownership.
3. Use **Export S4 JSON**. Expect `clove-lab-S4-<UTC timestamp>.json` in the
   picked folder and **Files → On My iPhone/iPad → Clove Lab**, also shareable
   through the footer's Export button. **Attach the JSON file to issue #29**,
   referencing #15, even if an unexpected result occurs. Include reader/card
   model and storage condition, without photos or private capture metadata.
4. Treat this as card input/export confirmation only. Before claiming exFAT
   write atomicity, use a separately instrumented same-directory staging /
   replacement probe on disposable card copies, coordinated with C4 and S3.
   The current S4 runner's private temporary directory is local storage.
