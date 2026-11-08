# S4 — Can metadata be changed without re-encoding?

## Question

Can metadata be changed without re-encoding?

Part 1 of #15: collect macOS and iOS simulator evidence and prepare the Clove Lab
confirmation. Physical-device results are **pending**. G1 remains open.

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
- Fourteen attempts: native copy and a decoded re-encoding comparison for each
  file, a native-copy seeded preservation control for each file, and two
  JPEG-only XMP packet replacement comparisons (original and seeded).
- Baseline writes use rating `3`, label `Green`, and Reject `True`. Seeded writes
  replace rating `1`/`Red` with rating `-1`/`Purple` and Reject `False`. The latter
  exercises the optional rating-minus-one convention and clearing Reject;
  rating and Reject remain independent. The experimental Reject namespace is
  `urn:clove:spike:s4:1.0/`, not a production namespace decision.

JSON reports stay out of git. Local artifacts in this checkout:
`.build/s4/clove-lab-S4-macos.json`,
`.build/s4/clove-lab-S4-simulator.json` (timing samples), plus
`.build/s4/clove-lab-S4-macos-verification.json`,
`.build/s4/clove-lab-S4-simulator-verification.json` and
`.build/s4/simulator.xcresult` (final checks including interruption/thumbnail tests).
They use `LabReport` schema 1: scalar results in `measurements`; each JSON object
string in `notes` retains the complete before/after hashes, source properties,
recursive XMP tags (including qualifiers), changed paths, errors, and failure
integrity checks. Device reports will be attached to #15 in part 2.

Part 1 checks: `mise install` and `mise run verify` pass; the final simulator run
passes all 9 S4 tests. The required validation-only release command was attempted,
but stopped before archive/signing/validation because UTC build `26110817` is
already visible in TestFlight. The script refuses to reuse an hourly build
number. The supervisor must rerun it in a later available UTC hour (earliest
2026-11-08 18:00 UTC); S4 does not bypass that guard or upload a build.

The repository calls the JPEG a camera JPEG. Its actual embedded packet contains
`Image::ExifTool 10.27`, Adobe Camera Raw settings, and an XMP history entry saying
it was converted from `image/x-canon-cr2` to `image/jpeg`. This is useful
other-app metadata coverage, but does not establish an untouched out-of-camera
JPEG. Shared fixture-provenance correction is tracked separately in
[#23](https://github.com/mimiqdev/cloveapp/issues/23).

## Data

### Per-format result

The macOS and simulator native-copy results agree. "Lossless" in this table means
compressed image bytes and decoded pixels were both unchanged; preservation of
other information is a separate check.

| Format / fixture | Lossless embedded write possible in tested paths? | Method | What else changed / preservation | Evidence |
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

- Native JPEG copy changes latitude from `69.16956833333333` to
  `69.16956999999999` degrees (about 0.19 m north/south). Its XMP coordinate changes
  from `69,10.1741N` to `69,10.1742N`. It also reduces equivalent fractions such as
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
- JPEG and HEIC seeded controls add an independent unknown namespace with scalar,
  nested resource, ordered array, caption/keywords and `xml:lang` qualifier; all
  source-exposed values survive. The JPEG seed also lands GPS. The HEIC seed's
  requested GPS does **not** land, and the HEIC fixture has no GPS or maker note;
  HEIC GPS/maker-note preservation is therefore **unproven**, not a pass on
  absent information. Arbitrary camera HEIC auxiliary/gain-map variants need
  broader coverage before a production allowlist.
- Raw maker-note bytes are hashed from TIFF/EXIF rather than inferred from
  decoded properties. The ProRAW source has a 1,268-byte maker note. No maker
  note is found in the other three fixtures. No successful DNG write exists;
  source-integrity evidence is the whole-file digest on rejection.
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

### Physical-device confirmation — pending

1. Prepare a flat folder named **S4 fixtures** with copies of the four files
   listed above (about 54 MB). Put it in Files or on the USB-C SSD/card used for
   the combined session; connect that reader/drive if needed. Install the
   supervisor's Clove Lab TestFlight build.
2. Open **Clove Lab → S4 → Choose folder**, pick **S4 fixtures**, then press
   **Run metadata check**. Allow about **1 minute** (up to 2 on a busy device).
   Expect **14 checks**: unchanged image bytes/pixels for native JPEG and HEIC,
   the JPEG native-metadata warning, preserved JPEG packet comparison, and DNG
   unavailable. Re-encoding comparison differences or encoder failure are
   expected. Selected image files stay unchanged.
3. Use **Export S4 JSON** and **attach the JSON file to issue #15**. The screen
   names `clove-lab-S4-<UTC timestamp>.json`; copies are in the picked folder and
   **Files → On My iPhone/iPad → Clove Lab**, also shareable through the footer's
   Export button. Send the JSON even if an unexpected check fails. Repeat on
   **iPhone 17 Pro Max and iPad Pro** with their installed iOS/iPadOS versions;
   the JSON records the exact model and OS automatically.

## Conclusion

On macOS 27.0 and the iOS 27.0 simulator, JPEG and generated HEIC accept embedded
rating, label and Reject without changing compressed images or decoded pixels.
The native JPEG path nevertheless changes unrelated numeric metadata; the
bounded JPEG packet comparison avoids that change. Neither tested DNG variant
has an ImageIO destination. Hardware confirmation remains pending, and none of
these results establishes universal camera-format or storage-provider coverage.

## Recommendation and options for G1

Recommended per-format state under PRD rule 6, subject to part 2 and G1:

| Format | Default | Proposed eligibility for the optional setting | Reason / remaining condition |
| --- | --- | --- | --- |
| JPEG | Off | Eligible only after adopting a preservation-safe XMP packet writer and validating its supported packet forms; otherwise keep disabled | Native copy passes the no-re-encoding rule but changes GPS/EXIF. The bounded comparison supports one standard packet and rejects duplicate/extended XMP. Production hardening belongs to C7, informed by S3 |
| HEIC | Off | Provisionally eligible with native copy, after hardware and richer camera-HEIC preservation coverage | Generated fixture passes both byte and pixel checks and seeded unknown-XMP preservation. Camera GPS, maker notes and auxiliary variants remain unproven |
| Camera DNG | Off | Disabled for the tested ImageIO implementation | No destination; show the PRD's embedded-write-unavailable explanation and retain sidecars |
| ProRAW DNG | Off | Disabled for the tested ImageIO implementation | Same result, independently tested on a ProRAW file |

Options for G1 (the product owner chooses):

1. **Recommended:** retain sidecars by default, use a preservation-safe JPEG
   packet approach for supported files, and native HEIC copying after device
   confirmation and additional preservation coverage. Keep DNG disabled with a
   clear explanation. Preserve unsupported cases as explicit failures; never
   substitute re-encoding. This needs JPEG container/extended-XMP hardening in
   C7 and the XMP preservation approach selected at S3/G1.
2. Use native copying for JPEG too, accepting its measured numeric normalization.
   This is less implementation work, but the GPS/unknown-value changes require
   an explicit G1 assessment against PRD rule 9. The spike does not grant that
   acceptance.
3. Keep all embedded options disabled until larger preservation coverage exists.
   This reduces initial writer complexity but leaves standalone-file Lightroom
   interoperability unresolved because Lightroom ignores these sidecars.
4. Investigate a bounded TIFF/DNG packet editor or a separately approved library.
   A custom writer might append an XMP packet and repair IFD links without
   touching raw payloads, but safe DNG/ProRAW, auxiliary-data and unknown-tag
   support is substantial new work. It was not implemented here. ImageIO's lack
   of a destination is not proof that every possible DNG writer is impossible.

No product default, production writer, PRD text or decision record was changed.
No performance target is proposed from this shared-host sample.

## Open questions

- **Pending part 2:** do the iPhone 17 Pro Max and iPad Pro JSON results confirm
  these capabilities and preservation warnings on their installed OS versions?
- **G1:** choose the JPEG preservation approach and HEIC allowlist scope after
  S3 and device confirmation. HEIC GPS/maker-note/camera-auxiliary samples would
  settle the current preservation gap; the generated HEIC cannot do so.
- **C7:** supported JPEG extended/duplicate/malformed XMP policies, production
  Reject namespace, provider coordination, durable writes and storage-specific
  behavior remain implementation work informed by the combined spikes.
- [#23](https://github.com/mimiqdev/cloveapp/issues/23) tracks the shared fixture
  documentation correction for the JPEG's existing processing history.
