# S2 — Are previews fast enough?

## Question

Are previews fast enough? Measure embedded preview extraction time, size, and
memory per format, and `CIRAWFilter` full decoding, to recommend a thumbnail and
detail image strategy, cache design, and performance targets for G1. This is
part 2 of [#13](https://github.com/mimiqdev/cloveapp/issues/13), following
[part 1 / PR #20](https://github.com/mimiqdev/cloveapp/pull/20) and
[HIF support / PR #28](https://github.com/mimiqdev/cloveapp/pull/28). It finishes
with the available iPhone device evidence. The product owner deferred the
remaining device checks on 2026-11-09 to
[#29](https://github.com/mimiqdev/cloveapp/issues/29); they do not block this
report. G1's choice remains with the product owner.

## What was tested

- **macOS 27.0, Mac14,12 (Mac mini), Xcode 27.2 (27B52)**, Swift 6 debug
  compilation. These macOS numbers were taken on a **shared, loaded host with
  two other spike workers**. They are not physical-device numbers.
- **iOS 27.0 simulator (24A434), iPhone 17 Pro Max / iPhone18,2**, on that Mac.
  A standalone arm64 simulator executable called the same `PreviewSuite.run`
  used by Clove Lab, with debug compilation. It used its own newly created
  simulator, deleted after collection. It read the Mac's T7 fixture directory
  directly, not an SD card through Files. This is functional simulator evidence,
  not iPhone performance evidence.
- The ten files in the `formats` set from `docs/fixtures.md`, under
  `/Volumes/T7/Projects/.clove-fixtures/sets/formats`: Apple iPhone 12 Pro ProRAW
  DNG, Canon EOS 6D JPEG, Canon EOS R6 CR3, Fujifilm X-S10 RAF, Nikon D500 NEF,
  Olympus E-M1MarkII ORF, Panasonic GH4 RW2, Pentax K-5 II s DNG, Sony ILCE-7S
  ARW, and the locally generated Sony HEIC. The `card-basic` fixture set also
  exercises recursive enumeration and exclusion of hidden files and `_Rejected`.
- JSON artifacts: `clove-lab-S2-20261108T164735Z.json`
  ([macOS payload](https://github.com/mimiqdev/cloveapp/issues/13#issuecomment-6724339307))
  and `clove-lab-S2-20261108T165128Z.json`
  ([simulator payload](https://github.com/mimiqdev/cloveapp/issues/13#issuecomment-6724339747)).
  Complete gzip/base64 payloads, SHA-256 checksums and retrieval instructions
  are preserved on issue #13 because `gh` cannot attach local files to issues;
  JSON is kept out of git. Local copies
  and build/check logs are in this checkout's ignored `.build/previews/` directory.
- **Physical iPhone 17 Pro Max (`iPhone19,4`), iOS 27.2**, Clove Lab 0.1.0,
  local storage through the folder picker, in two owner-returned runs:
  - **Run 1, build 26110818:** one Sony A1 II ARW (`MMQ05184.ARW`) measured.
    A companion HIF was present but skipped by the pre-PR-28 extension filter;
    this is missing coverage, not a decoding failure.
  - **Run 2, build 26110903:** ten Sony A1 II ARW+HIF burst pairs found (20
    files); throughput covers all 20. Detailed variants and cache measurements
    cover only the first 12 sorted files: six pairs, `MMQ02678`–`MMQ02683`,
    with `.ARW` and `.HIF` extensions. The S4 folder from the same session is
    outside S2's measurements. Native rendered output is 5760×8640 after
    orientation (8640×5760 camera dimensions).
  - Original reports were read in place without modification. The citations
    below identify the exact private artifacts; raw JSON and owner folder
    paths are not published. Only measurements and safe file/model names are
    quoted. SHA-256 was computed with `shasum -a 256`:

    | Run | Report file name | SHA-256 |
    | --- | --- | --- |
    | 1 | `clove-lab-S2-20261109T022003Z.json` | `357d1c22f066342c4ccb0da32d763e689f7e7b61c19a4db6e1609539aa8c436b` |
    | 2 | `clove-lab-S2-20261109T033803Z.json` | `3aa36dee06a999ef13244fadb68e82672ff5f5faf05791f8d3d110ade931cc5e` |

- A generated 2400×1600 JPEG with **no embedded thumbnail**, EXIF orientation 6,
  is created in a per-run temporary directory. It supplies the missing-preview
  and rotation control without changing a fixture. The test checks there is no
  nested JPEG thumbnail and that orientation swaps the output dimensions.

Each request opens a fresh ImageIO source with source caching disabled. There
is one observation per file/method/size, with methods serial in a fixed order;
filesystem caches and framework initialization are **not** reset. Timing begins
before opening/properties and ends after a CPU bitmap provider is materialized.
It includes measurement overhead (including source metadata inspection); it
measures neither display presentation nor UI scrolling. Repeated/warm methods
can be faster than the first method. No percentile or cold-card claim follows
from this sample.

`embeddedOnly` is a diagnostic with **both thumbnail creation flags explicitly
false**, at 400, 2000, and 20000 px. `ifAbsent` and `always` set the corresponding
creation flag true and the other false, at 400 and 2000 px. Transform is enabled
except for an extra untransformed 400 px comparison. The 20000 px diagnostic
shows the largest preview ImageIO exposes via this API for these inputs; it is
not a parser for every embedded preview or proof of how ImageIO obtained it.

RAW measurements construct `CIRAWFilter`, obtain `outputImage`, and actually
render through a fresh `CIContext` to RGBA8 sRGB, either native size or scaled to
2000 px. This does **not** measure a draft RAW decode: scaling the output can
still incur full demosaicing. The suite also calls this API on JPEG/HEIC as
controls; their success does not imply those files contain RAW sensor data.

Decoded memory is `bytesPerRow × height`. A sampler records absolute **process
resident memory every 5 ms**, with the baseline exported separately. This is a
lower bound on peak RSS, includes framework caches and other work in the
process, and is not a per-request allocation count or a physical-device memory
ceiling. Decode buffers can be missed between samples. The probe temporarily
retains the provider bytes to ensure materialization, which can add memory.

The Lab suite caps detailed methods and cache measurements at the first **12**
files in sorted relative-path order and concurrency measurements at **240**.
Run `formats` separately before a camera folder so every format is represented.
Reports identify each file by relative path, including subfolders. Full RAW is
on by default and can be turned off explicitly; `context.fullRAW` records it.
Typical suite time should be allowed **2–10 minutes** on hardware, depending on
RAW size/card speed; this remains a planning allowance for deferred card runs.
The returned JSON does not measure end-to-end suite or export duration.
The measured ten-file suite took about 9 s inside the warm macOS test process.
The simulator's individually timed operations totalled about 57 s, under the
shared host load; setup and report export add time.

Reproduce the macOS JSON without running benchmarks in every verification:

```sh
mkdir -p .build/previews
CLOVE_PREVIEWS_REPORT="$PWD/.build/previews/macOS.json" \
  mise exec -- swift test --package-path Packages/CloveLabKit \
  --filter PreviewTests.collectReport
```

The simulator collector can be reproduced from the checkout root with the
following commands. It creates and deletes its own simulator and reads the host
fixture directory directly. All generated files stay under the checkout.

<details>
<summary>Standalone simulator collector</summary>

```sh
set -eu
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
previews_out="$PWD/.build/previews-simulator"
mkdir -p "$previews_out"
previews_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -sdk "$previews_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name LabSupport \
  Packages/CloveLabKit/Sources/LabSupport/*.swift \
  -emit-module-path "$previews_out/LabSupport.swiftmodule" \
  -o "$previews_out/LabSupport.o"
xcrun --sdk iphonesimulator swiftc -sdk "$previews_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name PreviewProbe -I "$previews_out" \
  Packages/CloveLabKit/Sources/PreviewProbe/*.swift \
  -emit-module-path "$previews_out/PreviewProbe.swiftmodule" \
  -o "$previews_out/PreviewProbe.o"
cat > "$previews_out/Runner.swift" <<'SWIFT'
import Foundation
import PreviewProbe

@main struct Runner {
    static func main() async throws {
        let arguments = CommandLine.arguments
        var report = try await PreviewSuite.run(folder: URL(fileURLWithPath: arguments[1]))
        report.context["execution"] = "standalone arm64 iOS Simulator runner; debug compiler settings"
        report.notes.append("iOS simulator on shared, loaded Mac host. Not physical-device measurements.")
        try report.write(to: URL(fileURLWithPath: arguments[2]))
    }
}
SWIFT
xcrun --sdk iphonesimulator swiftc -sdk "$previews_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -I "$previews_out" "$previews_out/Runner.swift" \
  "$previews_out/LabSupport.o" "$previews_out/PreviewProbe.o" -o "$previews_out/runner"
previews_device="$(xcrun simctl create "Clove previews measurement $$" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
trap 'xcrun simctl delete "$previews_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$previews_device"
xcrun simctl bootstatus "$previews_device" -b
xcrun simctl spawn "$previews_device" "$previews_out/runner" \
  "${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/sets/formats" \
  "$previews_out/simulator.json"
```

</details>

Normal `mise run verify` runs functional fixture tests, orientation/fallback and
cache invalidation controls, a bounded task-group test, cancellation checks, and
one native-resolution ProRAW render. Fixture tests skip when their sets are
missing; they assert results and explicit errors, never speed thresholds.

## Data

### macOS: ImageIO per format

Single observations, milliseconds to materialized CPU pixels; transformed.
`I` = `IfAbsent`, `A` = `Always`. Sizes are actual outputs, not requested sizes.
Memory is the decoded **I400 / I2000** bitmap, in MiB (2²⁰ bytes). A dash is a
failed request, with the failure discussed below.

| Format / camera | Exposed preview at 20000 cap | I400 ms / size | A400 ms | I2000 ms / size | A2000 ms / size | Decoded MiB I400 / I2000 |
| --- | --- | --- | --- | --- | --- | --- |
| ProRAW / iPhone 12 Pro | 3024×4032 | 28.8 / 300×400 | 29.4 | 91.3 / 1500×2000 | 94.2 / 1500×2000 | 0.46 / 11.44 |
| JPEG / EOS 6D | 256×171 | 3.1 / 256×171 | 36.0 | 2.4 / 256×171 | 57.9 / 2000×1333 | 0.17 / 0.17 |
| CR3 / EOS R6 | 5472×3648 | 25.0 / 400×267 | 239.1 | 50.6 / 2000×1333 | 51.8 / 2000×1333 | 0.41 / 10.17 |
| RAF / X-S10 | 4416×2944 | 19.8 / 400×267 | 176.5 | 37.6 / 2000×1333 | 285.3 / 2000×1333 | 0.41 / 10.17 |
| NEF / D500 | 5568×3712 | 26.1 / 400×267 | 78.0 | 53.9 / 2000×1333 | 57.5 / 2000×1333 | 0.41 / 10.17 |
| ORF / E-M1MarkII | 3200×2400 | 39.6 / 400×300 | 231.5 | 76.3 / 2000×1500 | 276.9 / 2000×1500 | 0.46 / 11.44 |
| RW2 / GH4 | 1920×1440 | 11.7 / 400×300 | 95.7 | 13.2 / 1920×1440 | 164.3 / 2000×1500 | 0.46 / 10.55 |
| DNG / K-5 II s | 4928×3264 | 20.0 / 400×265 | 20.2 | 43.7 / 2000×1325 | 42.5 / 2000×1325 | 0.40 / 10.11 |
| ARW / ILCE-7S | 1616×1080 | 12.8 / 400×267 | 49.7 | 14.7 / 1616×1080 | 110.9 / 2000×1335 | 0.41 / 6.66 |
| HEIC / generated | none returned | — | 94.1 | — | 57.4 / 2000×1336 | — / — |

The 20000-cap diagnostic itself took, in table order: 79.0, 2.8, 59.5, 44.0,
57.6, 50.9, 17.3, 47.2, 17.0, and 1.5 ms (HEIC failure). It materializes a large
bitmap and is **only a spike diagnostic**, not a proposed grid operation.
A400 generally returned 400 px on the long edge (JPEG included); exact sizes,
source dimensions/orientation, and memory for every variant are in the JSON.
ARW A2000 used about 20.37 MiB despite its dimensions, versus 6.66 MiB for I2000:
measure row bytes rather than assuming every ImageIO bitmap is four bytes/pixel.

Important format behavior:

- `IfAbsent` returns a small existing JPEG thumbnail even when asked for 2000 px.
  It is not a minimum-quality guarantee. The ARW and RW2 previews also remain
  below 2000 px; do not mistake upscaling for focus detail.
- Both HEIC `embeddedOnly` and `IfAbsent` return `noThumbnail` at both sizes on
  this macOS and simulator. `Always` works. Treat an unsuccessful `IfAbsent` as
  a recoverable path and explicitly try `Always` before showing unavailable.
- The RAF API output is 4416×2944 despite the fixture notes describing tiny
  embedded previews. Record the system observation without assuming which
  internal preview/decoding route produced it. A container-level investigation
  would be needed to establish provenance.

### Missing-preview and orientation controls

Transformed 400 px output, no-thumbnail JPEG control:

| Platform | Both flags false | IfAbsent | Always | Orientation behavior |
| --- | --- | --- | --- | --- |
| macOS | `noThumbnail`, 0.24 ms | 3.19 ms, 267×400 | 3.42 ms, 267×400 | Without transform 400×267; with transform 267×400 |
| iOS 27 simulator | `noThumbnail`, 0.28 ms | 11.75 ms, 267×400 | 4.78 ms, 267×400 | Without transform 400×267; with transform 267×400 |

This confirms fallback from the full JPEG when there is no embedded thumbnail,
and that EXIF orientation must be applied. It does not prove how fallback works
for a RAW with no usable embedded preview: every RAW fixture returned pixels in
the diagnostic. That specific real-camera sample remains part of device work.
An invalid `.dng` test also verifies an explicit RAW failure; the filter may
initialize and produce an output graph yet fail at rendering (`cannotRender`),
so a non-nil filter alone is insufficient evidence of support. A nil filter is
reported as `rawUnsupported`; nil output is `rawNoOutput`.

### macOS: CIRAWFilter render and memory

Time includes filter initialization and CPU image materialization. Screen output
is around 2000 px; full output uses native dimensions. Absolute sampled peak RSS
is **process-wide**, including earlier operations in this serial suite.

| Format | Screen ms | Full ms / dimensions | Full decoded MiB | Sampled RSS MiB screen / full |
| --- | --- | --- | --- | --- |
| ProRAW | 175.5 | 176.4 / 3024×4032 | 46.51 | 422.8 / 504.8 |
| JPEG control | 57.4 | 84.2 / 5472×3648 | 76.15 | 459.4 / 652.8 |
| CR3 | 323.9 | 358.0 / 5472×3648 | 76.15 | 954.7 / 1107.9 |
| RAF | 322.3 | 368.4 / 6240×4160 | 99.02 | 888.3 / 937.0 |
| NEF | 208.1 | 260.3 / 5568×3712 | 78.84 | 695.6 / 778.0 |
| ORF | 337.5 | 334.3 / 5184×3888 | 76.89 | 763.2 / 954.7 |
| RW2 | 263.8 | 228.0 / 4608×3456 | 60.75 | 836.0 / 839.3 |
| DNG | 307.1 | 307.8 / 4928×3264 | 61.36 | 900.6 / 932.6 |
| ARW | 101.4 | 104.9 / 2768×1848 | 19.51 | 685.0 / 698.0 |
| HEIC control | 24.0 | 28.4 / 2768×1848 | 19.51 | 683.8 / 684.2 |

All eight RAW samples rendered on this OS. This is sample-specific support,
not a compatibility guarantee for every compression mode or camera with the
same extension. Rendering to 2000 px did not reliably save time versus native
size. The process peak exceeded 1 GiB in this instrumented macOS process; it
cannot justify an iOS memory ceiling or parallel full RAW decoding.

### Simulator: functional comparison, not physical-device numbers

iOS 27.0 simulator on the loaded Mac; milliseconds. Full RAW sizes match the
macOS native dimensions above. These values include first-use setup and host
contention, especially the first ProRAW request.

| Format | I400 | I2000 | A2000 | RAW screen | RAW full | RAW full sampled RSS MiB |
| --- | --- | --- | --- | --- | --- | --- |
| ProRAW | 2083.7 | 686.0 | 1064.5 | 5671.6 | 1402.2 | 475.4 |
| JPEG control | 7.5 | 5.2 | 160.7 | 271.0 | 296.7 | 463.0 |
| CR3 | 53.7 | 129.2 | 119.1 | 2388.3 | 1077.0 | 339.6 |
| RAF | 59.6 | 103.0 | 106.5 | 2454.4 | 1492.1 | 420.2 |
| NEF | 47.7 | 102.6 | 93.7 | 522.7 | 590.5 | 417.6 |
| ORF | 64.2 | 123.3 | 116.8 | 672.4 | 512.1 | 428.8 |
| RW2 | 17.8 | 24.7 | 23.6 | 709.5 | 721.2 | 343.4 |
| DNG | 35.3 | 72.2 | 78.4 | 425.3 | 475.3 | 307.8 |
| ARW | 26.6 | 28.9 | 32.0 | 136.0 | 129.1 | 144.3 |
| HEIC control | fails | fails | 356.3 | 147.7 | 166.1 | 132.3 |

The simulator's `Always` path sometimes differs from macOS: ARW A2000 remains
1616×1080, and RW2 A2000 remains 1920×1440. Neither flag promises a full-resolution
RAW decode on all platforms. Validate native RAW separately for 100% inspection.

### Concurrency and cancellation

Ten `formats` inputs, bounded task groups, 400 px `IfAbsent`, no application
cache. Each pass succeeded on 9/10 files; the HEIC failure is counted explicitly
and is excluded from successful-image throughput. These short mixed-format
passes are not a substitute for a 200+ RAW SD-card run. Pass order was 1, 2, 4,
8, so later passes may benefit from warm caches.

| Concurrency | macOS elapsed ms / successful images per s | Simulator elapsed ms / successful images per s |
| --- | --- | --- |
| 1 | 184.0 / 48.9 | 584.7 / 15.4 |
| 2 | 97.0 / 92.8 | 268.4 / 33.5 |
| 4 | 61.1 / 147.3 | 177.4 / 50.7 |
| 8 | 42.3 / 212.9 | 155.7 / 57.8 |

A task signaled immediately before entering the native render call, then the
awaiting task cancelled it. Both grid and RAW outputs were discarded after
cancellation. Draining the ProRAW request took **25.0 ms grid / 142.2 ms RAW**
on macOS and **130.5 ms grid / 409.0 ms RAW** in the simulator. There is a
scheduling race at this boundary; the report records completed-before-cancel
if that happens. This is a cooperative cancellation experiment, not an actual
scrolling UI benchmark. Tests also cancel a request before it starts and assert
it cannot deliver pixels. Native synchronous calls continue to completion;
bound admission and drop obsolete results instead of assuming `Task.cancel()`
interrupts ImageIO or Core Image.

### Cache experiment and 2000-photo estimates

Nine successful 400 px inputs (HEIC `IfAbsent` fails). `NSCache<NSString, CGImage>`
uses decoded row bytes as cost. Disk uses orientation-applied JPEG at quality
0.8, then reads and materializes it. Each run uses a separate temporary cache,
removed afterward; these are warmed filesystem reads, not cold SD latency.

| Measurement | macOS | Simulator |
| --- | --- | --- |
| NSCache warmed lookup, mean | 0.00082 ms | 0.00140 ms |
| JPEG encode + write, mean | 0.92 ms | 1.53 ms |
| Disk JPEG read + decode, mean | 0.80 ms | 2.32 ms |
| Disk JPEG size, mean / range | 33110 B / 16672–51684 B | 32953 B / 15031–52184 B |
| Decoded bitmap size, mean | 416434 B | 416434 B |

For **2000 photos**, extrapolating this small sample gives about **63 MiB disk**
(macOS JPEG mean × 2000) versus **794 MiB decoded RAM**. The sampled disk-size
range extrapolates to about 32–99 MiB. A 400×400 four-byte bitmap for every photo
would take 1.19 GiB. A 2000×1333 four-byte detail bitmap costs about 10.2 MiB;
2000 such images would take about 20 GiB. Some ImageIO outputs use more bytes,
as the ARW example shows. These estimates exclude indexing/filesystem overhead,
full RAW working sets, and runtime caches. The fixture sample does not establish
JPEG cache size for every real camera scene.

The experiment keys SHA-256 of standardized full path, fresh file size and
modification timestamp, method, requested size, transform, and rendering-version
identifier. Tests cover stable keys and invalidation on modification time,
size, path and method; metadata cache values are cleared before reading. I1
should additionally namespace by source location/bookmark identity and pipeline
version, account for Files-provider timestamp precision, and use atomic cache
writes plus eviction. This spike's direct JPEG write goes only to a unique
temporary directory; it is not a production disk cache.

### Physical device: local A1 II previews and native renders

All rows below are **measured** on iPhone 17 Pro Max / iOS 27.2, with run
provenance explicit. Times are milliseconds to materialized CPU pixels, not
presentation. Run 1 is one observation per variant; run 2 uses the ordinary
median (mean of the middle two of six observations), with min–max where shown.
No p95, repeated-trial, or cold-I/O result follows from these small samples.
`E` = `embeddedOnly`, `I` = `IfAbsent`, `A` = `Always`. All outputs here apply
orientation. Decoded MiB is bitmap row bytes × height / 2²⁰.

| Status | Format / request | Time ms (run 2: median; range) | Actual output | Decoded MiB |
| --- | --- | --- | --- | --- |
| Measured, run 1 | ARW E400, first variant | 122.6 | 267×400 | 0.409 |
| Measured, run 1 | ARW I400 / A400 | 8.7 / 8.7 | 267×400 | 0.409 |
| Measured, run 1 | ARW E2000 / I2000 / A2000 | 12.2 / 11.8 / 12.2 | 1080×1616 | 6.66 |
| Measured, run 1 | ARW RAW 2000 / native | 717.4 / 502.7 | 1334×2000 / 5760×8640 | 10.19 / 189.84 |
| Measured, run 2 | ARW E400 | 14.4; 13.4–36.5 | 267×400 | 0.409 |
| Measured, run 2 | ARW I400 | 8.3; 7.9–12.6 | 267×400 | 0.409 |
| Measured, run 2 | ARW A400 | 8.8; 8.4–11.6 | 267×400 | 0.409 |
| Measured, run 2 | ARW E2000 / I2000 / A2000 | 12.2 / 12.4 / 12.7 | 1080×1616 | 6.66 |
| Measured, run 2 | ARW RAW 2000 | 592.8; 578.9–676.2 | 1334×2000 | 10.19 |
| Measured, run 2 | ARW RAW native | 529.1; 518.0–544.4 | 5760×8640 | 189.84 |
| Measured, run 2 | HIF E400 | 16.0; 14.6–19.6 | 267×400 | 0.513 |
| Measured, run 2 | HIF I400 | 10.5; 10.1–10.9 | 267×400 | 0.513 |
| Measured, run 2 | HIF A400 | 53.2; 51.3–116.6 | 266×400 | 0.406 |
| Measured, run 2 | HIF E2000 / I2000 | 7.2 / 6.4 | 1080×1616 | 6.66 |
| Measured, run 2 | HIF A2000 | 55.6; 52.2–57.7 | 1334×2000 | 10.18 |
| Measured, run 2 | HIF CIRAWFilter control 2000 | 1773.9; 1617.2–1937.4 | 1334×2000 | 10.19 |
| Measured, run 2 | HIF CIRAWFilter control native | 1755.6; 1678.7–1852.5 | 5760×8640 | 189.84 |
| Measured, runs 1 / 2 | ARW E20000 diagnostic | 12.1 / 12.3 | 1080×1616 | 6.66 |
| Measured, run 2 | HIF E20000 diagnostic | 8.2 | 1080×1616 | 6.66 |
| Measured, run 1 | ARW EXIF 6, I400 without / with transform | 8.0 / 8.7 | 400×267 / 267×400 | 0.407 / 0.409 |
| Measured, run 2 | ARW / HIF EXIF 8, I400 without transform | 8.3 / 12.9 | 400×267 (both) | 0.407 / 0.509 |
| Measured, runs 1 / 2 | Synthetic no-thumbnail JPEG, E400 | `noThumbnail` in both runs | No pixels, expected | 0 |
| Measured, runs 1 / 2 | Synthetic JPEG I400 with transform | 3.6 / 3.7 | 267×400; untransformed 400×267 | 0.409 |

Every detailed camera variant succeeded (10/10 in run 1, 120/120 in run 2).
The synthetic control's two expected `noThumbnail` results per run are the only
method failures. Orientation dimensions are correct for the measured EXIF 6/8
samples; this does not establish visual color fidelity or every mirrored case.

Both A1 II formats expose only **1616 px on the long side** through the
embedded-only diagnostic, even at a 20000 px cap. A 2000 px `IfAbsent` request
is a cap, not a guarantee of 2000 px detail. ARW source-property rows themselves
report 1616×1080, so I2 must obtain native sensor dimensions from the RAW route
rather than treating those ImageIO properties as native resolution. The native
render demonstrates 8640×5760 before orientation. Neither `Always` on ARW nor
upscaling the embedded image supplies more focus detail on this device.

The first run's 122.6 ms E400 call precedes the 8.7 ms I/A400 calls. Fixed order
and unflushed system caches prevent attributing that gap entirely to the flag.
Run 2 likewise measures one variant per file, not six repeated cold trials.

**HIF is rendered camera HEIF, not RAW.** Its `raw` tag denotes the suite's
CIRAWFilter control. The approximately 1.8 s result must not be attributed to
every HIF decoding route: ImageIO A2000 produced 2000 px in 55.6 ms. That is a
separate generated-preview route; it does not establish native 100% quality or
its memory at native size. For routine grid/loupe previews, retain the fast
embedded path and never route HIF through a full-resolution decode. For an
ARW+HIF pair, ARW supplies actual detail beyond the embedded 1616 px limit.

### Physical device: sampled process memory

Absolute sampled RSS includes prior operations, frameworks and app state, with
a 5 ms sampling interval. It is a lower bound on the peak, not an isolated
allocation budget. Run 2 renders ARW then HIF repeatedly and leaves a high
baseline; subtracting the baseline is not a reliable working-set estimate.

| Status | Method | Sampled peak RSS MiB (median / maximum) |
| --- | --- | --- |
| Measured, run 1 | ARW RAW 2000 | 413.1 / 413.1 |
| Measured, run 1 | ARW RAW native | 632.0 / 632.0 |
| Measured, run 2 | ARW RAW 2000 | 1047.7 / 1145.9 |
| Measured, run 2 | ARW RAW native | 863.6 / 991.9 |
| Measured, run 2 | HIF CIRAWFilter control 2000 | 932.0 / 1097.3 |
| Measured, run 2 | HIF CIRAWFilter control native | 1304.3 / 1438.7 |

The last row is **1.27 GiB median / 1.40 GiB maximum** (about 1.37 / 1.51 GB
in decimal units). This is evidence against full HIF rendering for previews,
not a safe process ceiling. A native A1 II bitmap alone is 189.84 MiB. The
reports contain no memory-pressure notifications, post-run recovery trace,
GPU allocation inventory or sustained-load test. Successful report export
shows completion of these runs, not safety under repeated navigation.

### Physical device: grid throughput and cancellation

Run 2 uses all **20 files, ten ARW+HIF pairs**, as independent thumbnail jobs,
with I400, no app cache, and pass order 1, 2, 4, 8. Every pass succeeded 20/20.
This is neither 20 unique photos nor a pair-aware production pipeline.

| Status | Concurrency | Elapsed ms | Successful file thumbnails/s |
| --- | --- | --- | --- |
| Measured, run 2 | 1 | 232.3 | 86.1 |
| Measured, run 2 | 2 | 110.1 | 181.6 |
| Measured, run 2 | 4 | 69.5 | 287.6 |
| Measured, run 2 | 8 | 56.6 | 353.6 |

Four workers give 1.58× the two-worker throughput; eight give another 1.23×.
These very short passes cannot establish sustained thermal/memory behavior,
pair-aware throughput or cold-card latency. Run 1 had only one file: its
102–124/s results cannot measure concurrency scaling.

| Status | Automatic cancellation probe | Drain ms | Result |
| --- | --- | --- | --- |
| Measured, run 1 | ARW I400 | 6.7 | Cancelled result discarded |
| Measured, run 1 | ARW RAW **2000**, not native-size output | 455.3 | Cancelled result discarded |
| Measured, run 2 | ARW I400 | 6.9 | Cancelled result discarded |
| Measured, run 2 | ARW RAW **2000**, not native-size output | 544.3 | Cancelled result discarded |

The preliminary reading's “full-RAW cancellation” describes demosaicing work;
these probes request 2000 px output. They do not measure cancelling native-size
output, HIF rendering, or the manual Cancel button's UI response. They confirm
that an in-flight RAW can occupy its worker for roughly half a second after
cancellation. Keep that slot occupied until native work drains; discard stale
pixels and cancel queued requests before entry.

### Physical device: thumbnail cache

I400 inputs, NSCache warmed lookup and temporary JPEG quality-0.8 disk entries.
Run 1 samples one ARW; run 2 samples six pairs (12 files). Reads are warm local
filesystem reads including decode; cache directories are removed by the suite.

| Status | Measurement | Median (range where useful) |
| --- | --- | --- |
| Measured, run 1 | Memory lookup / JPEG encode-write / read-decode | 0.000375 / 7.10 / 3.63 ms |
| Measured, run 1 | Disk entry / decoded bitmap | 19507 / 428800 B |
| Measured, run 2 | Memory lookup; hits | 0.000458 ms; 12/12 |
| Measured, run 2 | JPEG encode + write | 0.96 ms (0.90–6.96) |
| Measured, run 2 | Disk read + decode | 1.74 ms (1.34–2.07) |
| Measured, run 2 | Disk entry | 40150 B (38746–41617); mean 40199 B |
| Measured, run 2 | Decoded bitmap | ARW 428800 B; HIF 537600 B; mean 483200 B |

Extrapolating run 2's mean to **2000 cached photo thumbnails** gives **76.7 MiB
disk / 921.6 MiB decoded RAM**. With ARW chosen for paired grid thumbnails,
2000 × 428800 B is **817.9 MiB** decoded; disk size remains scene-dependent.
This is a storage estimate, not a 2000-photo device measurement. Cache one grid
variant per logical pair, not both files. A 64 MiB decoded grid budget holds
about 156 measured ARW thumbnails or 124 HIF thumbnails before overhead; a
256 MiB disk budget has room for roughly 6677 entries at the mixed-sample mean.
File/index overhead and eviction need headroom. These local cache results
support the two-tier design; they do not settle timestamp/provider identity or
card I/O behavior.

## Conclusion

The local iPhone evidence supports embedded previews for camera browsing and
on-demand ARW rendering for focus inspection. On the owner's A1 II, both ARW
and HIF expose 1616 px embedded detail; ARW I400 takes 8.3 ms, HIF's first loupe
preview takes about 7 ms, and native ARW rendering takes 529.1 ms (run-2 medians).
Neither an undersized preview nor an upscaled one satisfies native focus detail.
Avoid full HIF decoding for previews. Cancellation discards obsolete results
but does not promptly interrupt native RAW work. The two-tier cache is supported
by local device data. Sustained throughput, card I/O, iPad behavior and a safe
total process memory ceiling remain deferred, with their implications below.

## Recommendation and options for G1

**Recommend an embedded-first system pipeline, one on-demand RAW worker, and a
bounded two-tier thumbnail cache.** This is a proposal for the product owner's
G1 decision, not a production implementation or decision record.

1. **Grid (I1):** request an orientation-applied roughly 400 px preview and
   record the returned size. For the owner's **ARW+HIF pairs, use ARW I400**:
   it is slightly faster (8.3 versus HIF I400's 10.5 ms), uses less decoded
   memory (0.409 versus 0.513 MiB), and needs only one grid cache entry per
   logical photo. Avoid HIF `Always` during scrolling (53.2 ms at 400 px).
   For HIF-only photos, use `embeddedOnly` to enforce the no-full-decode preview
   policy. Cache quality/failure state by source revision, prioritize usable
   pixels, and show an explicit unavailable state if none can be obtained.
   For ordinary JPEG or other tested raster inputs, `IfAbsent` then a bounded
   `Always` fallback handles absent/tiny previews. Do not apply that fallback
   indiscriminately to HIF or repeatedly start expensive RAW work for a cell.
2. **First loupe/detail preview (I2):** for **ARW+HIF, prefer HIF's embedded
   preview**, requested at about 2000 px via `embeddedOnly` (7.2 ms measured;
   I2000 was 6.4 ms). It supplies camera-rendered pixels quickly, at the same
   1080×1616 size and 6.66 MiB as ARW's approximately 12 ms preview. If the HIF
   is missing/unreadable, use ARW's embedded preview. Keep the source identity,
   actual dimensions and orientation in the cache/result so switching sources
   cannot display another photo or confuse the quality level. A single-file
   ARW path remains a reasonable alternative if card I/O or color consistency
   outweighs the local few-ms saving; that comparison is deferred.
3. **Sharper loupe and 100% (I2):** the pair's 1616 px embedded image is only
   an immediate placeholder when the display/zoom needs more pixels. Render
   **the ARW**, not the HIF, through `CIRAWFilter` on demand once demand exceeds
   embedded resolution, including double-tap to native 100%. Preserve zoom
   position/orientation during replacement and show loading/failure state.
   A 2000 px RAW output is not a cheap draft decode (592.8 ms versus native
   529.1 ms here); do not promise proportional savings from output scaling.
   Native rendering is needed for sensor-pixel inspection; do not trigger it
   for every fit-view navigation. Never fully decode HIF for routine previews:
   its CIRAWFilter control costs about 1.8 s and a large working set. HIF-only
   native 100% quality/memory is unverified; retain explicit preview-quality
   state and validate a bounded raster zoom route in I2 before claiming it.
4. **Scheduling:** start I1 evaluation with **four bounded grid workers** on
   the measured iPhone/local camera input (287.6/s versus 181.6/s at two), with
   a two-worker fallback for pressure/contention. Eight's extra 23% in a 57 ms
   pass is insufficient to select it as the sustained default. Admit at most
   **one RAW render**, prioritize current/visible items over prefetch, and
   pause speculative work under pressure. Cancel queued work before native
   entry and discard stale in-flight results. Keep the RAW worker occupied
   until cancellation drains (455–544 ms measured for 2000 px), then render
   the latest request; never accumulate obsolete RAW work.
5. **Cache:** use a cost-limited **64 MiB NSCache for grid** and an app-private
   **256 MiB LRU disk JPEG cache**, initially quality 0.8 as tested. Run 2
   estimates 76.7 MiB disk for 2000 mixed camera thumbnails, versus 921.6 MiB
   decoded RAM; memory-only storage is unsuitable. Store one grid variant per
   pair. Include the chosen physical file/companion revision, location identity,
   path, size, modification time, transform, target size, rendering method and
   pipeline version in keys. Changing the fallback source must invalidate the
   relevant variant. Use atomic writes/eviction in I1; do not reuse the spike's
   temporary direct-write experiment as a production cache. Keep **32 MiB**
   separately for a few embedded/detail bitmaps (about four at 6.66 MiB with
   headroom), release on memory warning, and retain **at most one** native RAW
   result (189.84 MiB for this A1 II) outside that small-preview budget. Release
   the old native image before allocating the next. Cache limits are advisory;
   the decoder/framework working set and UI require a separate pressure-tested
   total budget. The sampled RSS does not justify setting that ceiling at G1.

Alternatives for G1:

| Option | Benefit | Cost / evidence |
| --- | --- | --- |
| Always generate every thumbnail | Simple quality policy; works for the generated HEIC fixture | A1 II HIF A400 is about 5× I400; unnecessary work while scrolling |
| Embedded/system-preview only | Low work for camera browsing | A1 II stops at 1616 px; insufficient for native focus inspection; tiny JPEG previews persist |
| ARW for both paired grid and first loupe | One file/source path, consistent preview selection | Loupe about 12 ms versus HIF 7 ms locally; may win on a card; compare visual color too |
| Generate HIF A2000 as an intermediate | 2000 px in 55.6 ms on this sample | Extra decode/cache variant, not native focus detail; not needed for the recommended ARW-pair route |
| Memory-only cache | No disk eviction/indexing | About 922 MiB for 2000 run-2 thumbnails; frequent regeneration after eviction/relaunch |
| Disk cache only | Small persistent thumbnail storage | Read/decode on each display (1.74 ms warm median); still needs bounded decoded images |
| Full RAW for every grid cell | Native source rendering | About 0.5–0.7 s per A1 II ARW and large working set; conflicts with smooth browsing priority |

**Proposed on-device evaluation targets, not approved launch promises:** retain
the conservative part-1 targets below for I1/I2, now informed by the A1 II local
measurements. Evaluate camera inputs on iPhone 17 Pro Max and iPad Pro; card
and iPad performance remain unmeasured. These p95 targets require repeated trials
and a broader file sample. Six observations per format do not establish p95.

| Proposed target | Available local iPhone evidence | Validation still needed |
| --- | --- | --- |
| Warm disk grid read/decode p95 ≤ 20 ms | Run 2: 1.74 ms median, 2.07 ms maximum | Repeated cache hits, eviction/relaunch and iPad |
| Uncached app-level embedded grid p95 ≤ 150 ms | ARW I400 8.3 ms; HIF I400 10.5 ms medians; first run E400 122.6 ms | Cold source/framework/card access; separate first-use from warm |
| First detail preview p95 ≤ 300 ms | Run 2: embedded 6–13 ms, actual 1616 px | End-to-end presentation, external media, iPad |
| On-demand RAW focus image p95 ≤ 2 s, including queue/drain wait | ARW native 529.1 ms median; obsolete RAW drain 544.3 ms in a separate probe | Repeated rapid navigation, native-size cancellation, iPad, card |
| ≥ 30 successful 400 px thumbnails/s on a 240-file camera run | 20-file local pass: 287.6/s at four workers | 240 distinct files, pair-aware work, sustained load and reader/SSD |
| Stable memory over repeated navigation; queued cancellations do no decode and stale results never display | Automatic probes discarded cancelled outputs; functional tests cover pre-entry cancellation | Pressure/recovery and UI checks; set a total memory ceiling before fixing M3/Q3 targets |

The latency targets refer to separate stages and are not additive UI promises.
ImageIO timings include metadata probes; they exclude display. There is no
native-call interruption deadline: keep navigation responsive while the worker
drains. Revisit numeric budgets before M3/Q3 targets are fixed using #29's
checks; a reader may dominate I/O and favor fewer workers or one preview source.
The embedded-first/on-demand-RAW architecture is supported already, without
waiting for those checks. Do not equate 96 MiB of small-image caches with total
process memory.

No decision record is created by this spike. I4 can reuse the source-opening
and properties probes, but metadata extraction policy remains its own task.

## Open questions

- Which total process memory ceiling is safe during repeated 50 MP RAW focus
  inspection? Measure pressure and recovery, including the old displayed image
  and GPU/private allocations; the JSON's process-wide RSS peaks cannot set it.
- Are HIF and ARW embedded-preview colors visually consistent, and does switching
  to system RAW alter appearance enough to distract from focus inspection?
  Confirm with the owner; timing/dimension tests do not establish visual fidelity.
- What bounded raster route can support native focus inspection of standalone
  camera HIF without the expensive CIRAWFilter control? The measured ImageIO
  A2000 path is an option for intermediate detail, not proof of native quality.
- Do coarse Files-provider timestamps require a content signature beyond source
  identity/path/size/mtime? Resolve during I1 cache invalidation testing.
- System support remains camera/compression/OS-specific. Both device runs cover
  only A1 II ARW/HIF; other formats have macOS/simulator evidence, not physical
  iPhone compatibility or speed guarantees.

## Deferred device checks

The product owner deferred further checks on 2026-11-09; track them in
[#29](https://github.com/mimiqdev/cloveapp/issues/29). Finish S2 with the evidence
above. These checks are not urgent or prerequisites for closing #13; perform
them before M3/Q3 performance targets are fixed, or earlier if G1 depends on a
particular answer. Each row explicitly identifies its unmeasured status.

| Status | Check | What it would answer | Could it change the G1 recommendation? |
| --- | --- | --- | --- |
| Deferred, #29 | A1 II camera folder on an exFAT card through a reader | Cold reads, provider overhead, errors and latency versus local storage | Yes: numeric targets, worker count and ARW-only versus split ARW/HIF sourcing; embedded-first still avoids needless decode |
| Deferred, #29 | 240 distinct camera files, repeated grid passes and rapid focus navigation | Sustained concurrency 1/2/4/8, thermal behavior, memory growth/recovery and manual cancellation responsiveness | Yes: four-worker default, prefetch/cache budgets and total memory ceiling; one bounded RAW worker remains the starting point |
| Deferred, #29 | Same camera folder on external SSD, compared with card/local | Whether reader/media I/O or decode dominates, including opening a second companion file | Yes: I/O scheduling, source choice and targets; no evidence yet for a different decoder architecture |
| Deferred, #29 (all spikes) | iPad Pro, record hardware/iPadOS, repeat formats/camera suites | Large-display embedded quality, decoder support, speed and pressure | Yes: when to upgrade beyond 1616 px, concurrency and memory/latency budgets; do not transfer iPhone numbers to iPad |
| Deferred, follow-up with #29 | Physical-device `formats` set; real missing-preview/unsupported camera samples; visual rotated/color checks | Non-A1 II support, explicit failures and visual accuracy beyond synthetic orientation dimensions | Could change per-format fallback/source policy; current evidence still supports system APIs and explicit unavailable states |
| Deferred, follow-up with #29 | Native-size ARW cancellation and repeated full-render pressure diagnostics | Whether native output drains differently and whether process memory stabilizes | Could tighten admission, retention and memory targets; not evidence that cancellation interrupts a native call |
| Deferred / known gap, #29 | iPhone HEIC | Behavior of phone-specific HEIF beyond camera HIF | No blocker for this camera-focused recommendation; reconsider with photo-library support |

The generated HEIC fixture's `IfAbsent` failure remains a known gap with a
working macOS/simulator `Always` control; it is not an iPhone-HEIC device result.
The S4 iPhone-HEIC failure mentioned in #29 concerns metadata ownership, not an
S2 preview measurement. No iPhone-HEIC fix is part of this report. Camera files,
especially the owner's A1 II ARW+HIF, are the main target.

### Device checklist (deferred follow-up; also referenced in the PR)

1. After the supervisor publishes the merged Lab build, install **Clove Lab**
   from TestFlight on **iPhone 17 Pro Max**. Record the installed iOS version;
   the report records the app build and hardware identifier automatically.
2. Prepare an SD card with two **separate** folders: a copy of the complete
   **`formats`** fixture set (all ten files including HEIC and both DNGs), and
   **at least 240 distinct camera files** (preferably distinct A1 II photos with
   ARW+HIF companions), ideally including rotated photos. Use a copy of your media for this measurement. Do not mix
   the formats folder into the camera folder. The suite samples at most 240
   files for throughput and the first 12 for detailed variants; pairs consume
   two file slots. If available, also prepare a RAW with no usable embedded
   preview and an unsupported compression
   sample in a separate small folder. Reports are the only writes to the
   selected folders; images are read without modification.
3. Connect the SD card reader, unlock the phone, and confirm the folders appear
   in Files. Open **Clove Lab → S2 · Previews** (the run screen
   is titled **S2 · Preview speed**). Tap **Choose folder**, select `formats`,
   and confirm its name appears under the picker.
4. Leave **Include full-resolution RAW** on and tap **Run preview suite**.
   Allow **2–10 minutes**, keep the app in the foreground, and wait for the
   progress count and **Finished: clove-lab-S2-<timestamp>.json**. The screen
   should remain responsive; individual unsupported methods are recorded in
   the JSON without stopping the whole run. If it terminates or takes over ten
   minutes, record the last visible filename/progress and report that on #29;
   do not keep repeating a failing run.
5. Go **Back** to the **Clove Lab** list, scroll below S7, and tap **Export**
   in the shared footer to save/share that S2 JSON. It also appears in the
   selected folder and in **Files → On My iPhone → Clove Lab**.
   If export reports a card-write error, look in the Documents location for
   the copy already saved there and include the error text.
6. Open **S2** again. Choose the **240+ file camera folder**, keep full RAW on
   (only the first 12 files get detailed renders), and run again. Expect stages for
   **Grid concurrency 1, 2, 4, 8**, then cache measurements and a final report.
   Save that second JSON. Note the camera model, file count, card/reader model,
   whether the device was charging/hot, and approximate elapsed time in #29.
7. Open **S2**, choose the camera folder and start one more run, tap **Cancel**
   while a file is being measured, and wait.
   Expect **Cancelled. Current decode drained; no new report exported.** The
   prior exported report remains available. Record whether the interface stayed
   responsive and how long cancellation took. If the run already finished,
   repeat once and cancel earlier. The automatic grid/RAW cancellation probes
   are included in each completed report as well.
8. If you have the optional missing-preview/unsupported samples, choose that
   small folder and run/export it too. A method failure should be in the report,
   never a permanently stuck progress indicator.
9. Repeat steps 1–8 on **iPad Pro**, recording its model and installed iPadOS
   version; Documents appears under **On My iPad → Clove Lab**. Reconnect the
   same card/reader for comparable input. If convenient, repeat on an external
   SSD to distinguish decoding from card latency, identifying the media in #29.
10. **Attach each `clove-lab-S2-<timestamp>.json` file to issue #29**, identifying
    device, media and run. Include cancellations/errors and any termination
    observations. Reports can contain private folder paths: send the original
    privately to the supervisor for redaction before any public attachment.
    These follow-up results refine I1/I2 and M3/Q3 targets; they do not hold
    part 2 or #13 open.
