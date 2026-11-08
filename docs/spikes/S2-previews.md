# S2 — Are previews fast enough?

## Question

Are previews fast enough? Measure embedded preview extraction time, size, and
memory per format, and `CIRAWFilter` full decoding, to recommend a thumbnail and
detail image strategy, cache design, and performance targets for G1. This is
part 1 of [#13](https://github.com/mimiqdev/cloveapp/issues/13); device conclusions
remain open for part 2.

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
  and build/check logs are in this checkout's ignored `.build/s2/` directory.
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
RAW size/card speed; this is a planning allowance pending device measurement.
The measured ten-file suite took about 9 s inside the warm macOS test process.
The simulator's individually timed operations totalled about 57 s, under the
shared host load; setup and report export add time.

Reproduce the macOS JSON without running benchmarks in every verification:

```sh
mkdir -p .build/s2
CLOVE_S2_REPORT="$PWD/.build/s2/macOS.json" \
  mise exec -- swift test --package-path Packages/CloveSpikes \
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
s2_out="$PWD/.build/s2-simulator"
mkdir -p "$s2_out"
s2_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -sdk "$s2_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name SpikeSupport \
  Packages/CloveSpikes/Sources/SpikeSupport/*.swift \
  -emit-module-path "$s2_out/SpikeSupport.swiftmodule" \
  -o "$s2_out/SpikeSupport.o"
xcrun --sdk iphonesimulator swiftc -sdk "$s2_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -whole-module-optimization -emit-object -emit-module \
  -module-name SpikeS2Previews -I "$s2_out" \
  Packages/CloveSpikes/Sources/SpikeS2Previews/*.swift \
  -emit-module-path "$s2_out/SpikeS2Previews.swiftmodule" \
  -o "$s2_out/SpikeS2Previews.o"
cat > "$s2_out/Runner.swift" <<'SWIFT'
import Foundation
import SpikeS2Previews

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
xcrun --sdk iphonesimulator swiftc -sdk "$s2_sdk" \
  -target arm64-apple-ios18.0-simulator -swift-version 6 \
  -parse-as-library -I "$s2_out" "$s2_out/Runner.swift" \
  "$s2_out/SpikeSupport.o" "$s2_out/SpikeS2Previews.o" -o "$s2_out/runner"
s2_device="$(xcrun simctl create "Clove S2 measurement $$" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
trap 'xcrun simctl delete "$s2_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$s2_device"
xcrun simctl bootstatus "$s2_device" -b
xcrun simctl spawn "$s2_device" "$s2_out/runner" \
  "${CLOVE_FIXTURES_DIR:-/Volumes/T7/Projects/.clove-fixtures}/sets/formats" \
  "$s2_out/simulator.json"
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

### Physical-device results — pending part 2

| Device / OS | Formats: time, output dimensions, memory | 200+ RAW: concurrency 1/2/4/8 | Cancellation / export |
| --- | --- | --- | --- |
| iPhone 17 Pro Max / record installed iOS version | **pending** | **pending** | **pending** |
| iPad Pro / record model and installed iPadOS version | **pending** | **pending** | **pending** |

## Conclusion

The macOS sample supports using a small system preview before full RAW, but
`IfAbsent` alone is insufficient: it can return an undersized preview or fail
on a readable HEIC. Both OS environments rendered every sampled RAW through
Core Image, and the reusable Lab suite is ready to collect physical-device
results. Preview throughput, thermal behavior, SD-card latency and a safe iOS
memory budget remain inconclusive until part 2.

## Recommendation and options for G1

**Recommend a two-stage system pipeline and a bounded two-tier thumbnail cache**,
subject to the device results and the product owner's G1 decision:

1. **Grid (I1):** request an orientation-applied roughly 400 px preview with
   `IfAbsent`, inspect returned dimensions, and show usable pixels promptly.
   On absence/failure, try `Always` at low concurrency. An undersized preview
   can appear immediately while a better JPEG/HEIC thumbnail is prepared.
   For RAW, avoid repeatedly invoking expensive fallback for cells that are no
   longer visible; cache failure/quality state by source revision. If neither
   path works, show an explicit cannot-preview state, consistent with P0-03.
2. **Detail and 100% (I2):** display the available approximately 2000 px preview
   first, retaining its actual pixel dimensions and source orientation. Small
   JPEG previews need `Always`; small RAW previews need a separately validated
   full RAW route for focus inspection. On zoom to 100%, render full RAW through
   `CIRAWFilter` on demand, one request at a time, with visible loading/failure
   state. Do not call a 1616 px embedded preview native sensor resolution.
3. **Scheduling:** start with two grid workers and one full RAW worker; prioritize
   current/visible photos over prefetch. Device data may justify four grid
   workers. Eight improved this tiny Mac sample but is not yet a device default.
   Cancel queued work before native entry; discard cancelled/stale in-flight
   results when the synchronous call finishes. Avoid admitting another RAW
   merely because an obsolete one has received a cancellation request.
4. **Cache:** use a cost-limited NSCache (provisional **64 MiB grid**, around 150
   sampled thumbnails), plus an app-private disk JPEG cache with a provisional
   **256 MiB LRU budget**. Cache previews rather than originals, keyed by source
   identity/path/size/modification time and rendering variant. Keep only two or
   three detail images (provisional **32 MiB** separate budget), release on memory
   warning, and retain at most one native RAW result. Full-decode temporary
   memory needs a separate measured budget; NSCache limits are advisory.

Alternatives for G1:

| Option | Benefit | Cost / evidence |
| --- | --- | --- |
| Always generate every thumbnail | Simpler quality policy; fixes the HEIC case | Often much slower on macOS RAW; simulator differs; more work during fast scrolling |
| Embedded/system-preview only | Lowest work for many RAW files | JPEG can stay 256 px, small ARW/RW2 previews limit focus checks, HEIC can fail |
| Memory-only cache | No disk eviction/indexing | About 794 MiB for 2000 sampled thumbnails; frequent regeneration after eviction/relaunch |
| Disk cache only | Small persistent thumbnail storage | A decode on every display; warmed lookup is slower than NSCache; still needs bounded decoded images |
| Full RAW for every grid cell | Consistent native source rendering | Larger working set and latency; conflicts with the PRD priority for smooth browsing |

**Proposed evaluation targets, not approved launch promises:** on the iPhone 17
Pro Max and iPad Pro with the prepared SD card, aim for warm disk-cache grid
p95 ≤ 20 ms per thumbnail, uncached embedded/system-preview grid p95 ≤ 150 ms,
first detail preview p95 ≤ 300 ms, and on-demand full RAW p95 ≤ 2 s for the
fixture-sized cameras. Aim for at least 30 successful 400 px thumbnails/s at the
chosen device concurrency on 200+ RAW files, with no progressive memory growth
across repeated runs. Pending requests should stop before decode; obsolete
results must never replace the current photo. There is no proposed native-call
interruption deadline. Confirm or revise these targets with repeated device
runs; this single-observation suite does not establish p95. G1 should set the
process memory ceiling only after device peak/pressure data, not equate 96 MiB
of image caches with total process memory.

No decision record is created by this spike. I4 can reuse the source-opening
and properties probes, but metadata extraction policy remains its own task.

## Open questions

- Repeat the suite on both physical devices with an SD reader and real camera
  files, including a RAW known to have no usable embedded preview and an
  unsupported camera/compression sample if available. Do both fallback routes
  fail explicitly where expected? Support for an extension alone is not enough.
- What concurrency remains stable over 200+ unique RAW files, repeated runs,
  warming and thermal load? The ten-file Mac/simulator passes do not settle it.
- What is the physical-device peak/pressure during native RAW render, and does
  the process return to a stable baseline? Sampling RSS misses brief peaks and
  does not measure GPU/private framework allocations comprehensively. Use
  Instruments/device diagnostics if the JSON or a termination indicates pressure.
- Do preview colors and orientation look correct for real rotated camera images?
  The synthetic orientation test covers rotation dimensions, not visual color
  fidelity or all mirrored EXIF orientations.
- Files providers and cards can have coarse timestamps; determine whether I1
  needs an additional content signature when path/size/mtime do not change.

### Device checklist (also copied into the PR)

1. After the supervisor publishes the merged Lab build, install **Clove Lab**
   from TestFlight on **iPhone 17 Pro Max**. Record the installed iOS version;
   the report records the app build and hardware identifier automatically.
2. Prepare an SD card with two **separate** folders: a copy of the complete
   **`formats`** fixture set (all ten files including HEIC and both DNGs), and
   **at least 200 distinct RAW files from a real camera**, ideally including
   rotated photos. Use a copy of your media for this measurement. Do not mix
   the formats folder into the 200-file camera folder. If available, also
   prepare a RAW with no usable embedded preview and an unsupported compression
   sample in a separate small folder. Reports are the only writes to the
   selected folders; images are read without modification.
3. Connect the SD card reader, unlock the phone, and confirm the folders appear
   in Files. Open **Clove Lab → S2 · Are previews fast enough?** (the run screen
   is titled **S2 · Preview speed**). Tap **Choose folder**, select `formats`,
   and confirm its name appears under the picker.
4. Leave **Include full-resolution RAW** on and tap **Run preview suite**.
   Allow **2–10 minutes**, keep the app in the foreground, and wait for the
   progress count and **Finished: clove-lab-S2-<timestamp>.json**. The screen
   should remain responsive; individual unsupported methods are recorded in
   the JSON without stopping the whole run. If it terminates or takes over ten
   minutes, record the last visible filename/progress and report that on #13;
   do not keep repeating a failing run.
5. Go **Back** to the **Clove Lab** list, scroll below S7, and tap **Export**
   in the shared footer to save/share that S2 JSON. It also appears in the
   selected folder and in **Files → On My iPhone → Clove Lab**.
   If export reports a card-write error, look in the Documents location for
   the copy already saved there and include the error text.
6. Open **S2** again. Choose the **200+ RAW camera folder**, keep full RAW on (only the first 12
   files get detailed renders), and run again. Expect progress stages for
   **Grid concurrency 1, 2, 4, 8**, then cache measurements and a final report.
   Save that second JSON. Note the camera model, file count, card/reader model,
   whether the device was charging/hot, and approximate elapsed time in #13.
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
   SSD to distinguish decoding from card latency, identifying the media in #13.
10. **Attach each `clove-lab-S2-<timestamp>.json` file to issue #13**, identifying
    device, folder and run. Include cancellations/errors and any termination
    observations. The later part-2 worker uses these reports to fill the pending
    device table and revisit the G1 recommendations.
