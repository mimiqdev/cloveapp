# S3 — How should XMP be read and written?

## Question

How should XMP be read and written? Compare ImageIO's XMP APIs, Adobe XMP
Toolkit, and custom XML parsing: read and write `xmp:Rating`, `xmp:Label`, and
the Clove-specific field; round-trip the T0.3 fixtures and check that unknown
namespaces and structures survive unchanged; do atomic write-to-temp-and-replace
on an exFAT SD card.

This is **part 1 of #14**. G1 remains open. Physical exFAT, write-protection,
full-card, and desktop-app results are **pending**.

## What was tested

- Mac mini, Apple M2 Pro (`Mac14,12`), macOS 27.0, Xcode 27.2 (27B52), macOS
  and iOS Simulator SDK 27.2. **macOS numbers were taken on a shared, loaded
  host with two other spike workers.** These small samples are observations,
  not performance targets.
- All ten committed `fixtures/xmp/*.xmp` packets, including the zero-byte and
  malformed packets. These are hand-written shapes, not exports independently
  obtained from the named desktop apps. Exact compiled copies live in
  `XMPFixtures.swift`; a parameterized test checks every byte against the originals.
- The cache's `xmp-interop` set (11 sidecars including the RAW+JPG pair), and
  `name-collision` (`DCIM/100CANON/IMG_0001.CR3`, `.JPG`, `.XMP`, plus the
  existing files under `_Rejected`). Tests read these sets without changing them.
  Both sets were already present; no fixture rebuild was needed. Nothing wrote
  to the cache's `files/` directory.
- ImageIO: `CGImageMetadataCreateFromXMPData`, mutable copy, namespace
  registration, `CGImageMetadataSetValueWithPath`, `CGImageMetadataCreateXMPData`.
- Adobe XMP Toolkit Core, public commit
  `7093513bd3caaad29da01db0f275d88a39d6bcc2`, built locally as an arm64 static
  library with Expat 2.5.0. Default parse options, `kXMP_UseCompactFormat`
  serialization. No SDK, Expat source, binary, or dependency declaration is committed.
- Custom approach: Foundation `XMLParser` for validation, namespace-aware
  inspection, and lexical ranges for changing only mark attributes/elements.
  It handles the tested UTF-8 packets, aliased prefixes, element and attribute
  marks, self-closing descriptions, CDATA, comments, quoted `>`, and XML escaping.
  It deliberately refuses DTDs, duplicate marks, structured/qualified marks, and
  writes involving multiple descriptions or a nonempty `rdf:about`. This is
  verification code, not C3's production codec.
- Every successful write sets **Rating 3, Label Green, Clove Reject True** and
  reads all three back, including with the independent XML inspector. Original
  ratings/labels are also read (including Orange, Pink, and Rating −1).
- APFS atomic tests use three writes for each method with and without
  `NSFileCoordinator`: 12 replacements per run. Each writes a unique same-directory
  temporary file, synchronizes/closes it, replaces an existing sidecar, reads
  back the exact bytes, inventories temporary files, and removes its scratch folder.
- iPhone 17 Pro Max simulator, iOS 27.0 (24A434): a standalone executable compiled
  from the same S3 and SpikeSupport sources runs the complete suite inside a new,
  disposable simulator. It uses a local temporary folder on APFS. This measures
  iOS API behavior, **not** a document provider, picker interaction, or SD-card I/O.
  The Clove Lab screen is separately built by `mise run verify`; it uses the
  shared folder picker, security-scoped access, `LabSession`, exporter, and footer.

Evidence files, kept out of git and reproduced as JSON in issue #14 comments:

| Report | UTC run time | Contents |
| --- | --- | --- |
| `clove-lab-S3-macos.json` | 2026-11-08 16:59:36 | Fixture comparison, disk read-back, new sidecars, APFS replacements |
| `clove-lab-S3-sdk.json` | See JSON `createdAt` | Separate local Adobe run, independently inspected outputs |
| `clove-lab-S3-simulator.json` | 2026-11-08 17:01:41 | Same two dependency-free approaches and replacements on iOS Simulator |

Local copies and trimmed command logs are under `.build/s3/`. Device reports
will use the shared exporter's `clove-lab-S3-<UTC timestamp>.json` name instead.

## Data

### Preservation comparison

“Data” below compares namespace-expanded property values, qualifiers, and
containers, ignoring property order, description attribute versus property-element
form, formatting, namespace-prefix spelling, and the serializer's `x:xmptk` marker.
Sequence order remains significant. “Form” also compares unknown attribute/element
representation and property order, but not insignificant whitespace or prefix spelling.
This inspector is a conservative fixture comparator, not a general RDF equivalence
engine; SDK nested-structure rewrites also affect its comparison. The concrete
losses below were checked directly in the serialized XML.

The custom-editor tests additionally require each unknown description attribute
and complete unknown child subtree to remain an exact original substring. This
covers all nested `rdf:Seq`, `rdf:Bag`, `rdf:Alt`, IPTC, develop settings, and
`acme:` content, including whitespace and attribute/element form.

ImageIO, macOS 27.0 (simulator 27.0 has the same functional results):

| Fixture | Read / write / reread marks | Unknown data | Unknown form | Whitespace / ordering / envelope |
| --- | --- | --- | --- | --- |
| `capture-one.xmp` | Pass | Preserved | Changed | Reindented, reordered, attributes become elements; packet wrapper omitted |
| `custom-namespace-nested.xmp` | Pass | **Lost `rdf:datatype` on OpaqueBlob** | Changed | Nested structures/arrays remain, reordered and reindented; wrapper omitted |
| `empty-description.xmp` | **Parse refused** | No output | No output | Does not repair the empty description |
| `empty.xmp` | Pass; replaces empty input | No prior data | n/a | Creates valid XML/XMP, without standard packet wrapper |
| `label-orange.xmp` | Pass; initially Orange | Preserved | Changed | Attributes become elements; wrapper omitted |
| `label-pink.xmp` | Pass; initially Pink | Preserved | Changed | Attributes become elements; wrapper omitted |
| `lightroom-full.xmp` | Pass | **Both History entries lost; empty Seq remains** | Changed | Develop values, tone curves, keyword Bag remain; wrapper omitted |
| `malformed.xmp` | **Accepts and repairs**; marks reread | Cannot compare invalid original | Changed | Synthesizes missing closing tags; wrapper omitted |
| `photo-mechanic.xmp` | Pass | Preserved, including both caption languages | Changed | IPTC attributes become elements; arrays remain; wrapper omitted |
| `rating-minus-one.xmp` | Pass; initially −1 / empty label | Preserved | Changed | Attributes become elements; wrapper omitted |

Adobe SDK, macOS 27.0, local comparison only:

| Fixture | Read / write / reread marks | Unknown data | Unknown form | Whitespace / ordering / envelope |
| --- | --- | --- | --- | --- |
| `capture-one.xmp` | Pass | Preserved | Changed | New toolkit marker and packet padding; description attributes remain |
| `custom-namespace-nested.xmp` | Pass | **Lost OpaqueBlob datatype** | Changed | Resource/Description and attribute/element rewrites; nested values and arrays remain |
| `empty-description.xmp` | Pass | Preserved | Changed envelope | Rebuilds description; adds wrapper padding |
| `empty.xmp` | Pass; replaces empty input | No prior data | n/a | Creates packet wrapper and padded XMP |
| `label-orange.xmp` | Pass; initially Orange | Preserved | Changed envelope | New toolkit marker and padding |
| `label-pink.xmp` | Pass; initially Pink | Preserved | Changed envelope | New toolkit marker and padding |
| `lightroom-full.xmp` | Pass | **Both History entries lost** | Changed | Empty History Seq remains; develop and tone-curve data survive |
| `malformed.xmp` | **Accepts and repairs**; marks reread | Cannot compare invalid original | Changed | Completes truncated XML; emits a new packet wrapper |
| `photo-mechanic.xmp` | Pass | **Norwegian caption replaced by x-default English text** | Changed | `rdf:Alt` remains but its `xml:lang="no"` value changes |
| `rating-minus-one.xmp` | Pass; initially −1 / empty label | Preserved | Changed envelope | New toolkit marker and padding |

These SDK observations apply to this revision and these options. They do not
establish behavior for every Adobe SDK release or every serialization option.

Custom preserving edit, macOS 27.0 and iOS 27.0 simulator:

| Fixture | Read / write / reread marks | Unknown data / form / bytes | Formatting changes |
| --- | --- | --- | --- |
| `capture-one.xmp` | Pass | Preserved | Only owned marks changed |
| `custom-namespace-nested.xmp` | Pass | Preserved, including datatype and every nested byte | Only owned marks changed |
| `empty-description.xmp` | Pass | No unknown properties to change | Expands the self-closing description; adds marks |
| `empty.xmp` | Pass; replaces empty input | No prior data | Creates a new standard wrapped packet |
| `label-orange.xmp` | Pass; initially Orange | Preserved | Only owned marks changed |
| `label-pink.xmp` | Pass; initially Pink | Preserved | Only owned marks changed |
| `lightroom-full.xmp` | Pass | Preserved, including both History entries | Only owned marks changed |
| `malformed.xmp` | **Refuses before editing** | Original untouched | No output; no silent repair |
| `photo-mechanic.xmp` | Pass | Preserved, including language alternatives | Only owned marks changed |
| `rating-minus-one.xmp` | Pass; initially −1 / empty label | Preserved | Only owned marks changed |

Owned marks are replaced with locally namespace-declared property elements; all
other original source ranges are retained. A new custom sidecar includes the
`xpacket begin` BOM, standard `W5M0MpCehiHzreSzNTczkc9d` identifier, `x:xmpmeta`,
`rdf:RDF`, `rdf:Description rdf:about=""`, and `xpacket end="w"`. Both independent
XML parsing and mark read-back pass. The raw ImageIO API emits valid XMP without
that packet wrapper, so adopting it would need an explicit wrapping step.

### Atomic replacement

APFS macOS, three samples per row; elapsed milliseconds include temporary write,
file synchronization/close, and replacement, excluding subsequent read-back:

| Method | NSFileCoordinator | Confirmed | Median ms | Min–max ms | Temp remains |
| --- | --- | --- | --- | --- | --- |
| `FileManager.replaceItemAt` | No | 3/3 | 0.863 | 0.700–4.509 | 0/3 |
| `FileManager.replaceItemAt` | Yes | 3/3 | 1.603 | 1.365–5.746 | 0/3 |
| POSIX `rename` | No | 3/3 | 0.348 | 0.329–0.397 | 0/3 |
| POSIX `rename` | Yes | 3/3 | 1.259 | 1.151–1.285 | 0/3 |

APFS iPhone 17 Pro Max simulator, iOS 27.0, shared loaded host:

| Method | NSFileCoordinator | Confirmed | Median ms | Min–max ms | Temp remains |
| --- | --- | --- | --- | --- | --- |
| `FileManager.replaceItemAt` | No | 3/3 | 0.922 | 0.845–1.405 | 0/3 |
| `FileManager.replaceItemAt` | Yes | 3/3 | 15.009 | 5.240–5977.936 | 0/3 |
| POSIX `rename` | No | 3/3 | 0.570 | 0.517–0.827 | 0/3 |
| POSIX `rename` | Yes | 3/3 | 13.951 | 11.565–16.137 | 0/3 |

Coordination was not needed for success on these local APFS folders. Its large
simulator startup outlier is not an SD-card prediction. It coordinates other
presenters/providers; it does not itself prove filesystem atomicity. Device
runs include both modes to see whether that distinction matters for the card.
`replaceItemAt` can preserve destination metadata; `rename` installs the staging
file's inode and metadata. C4 must account for permissions/attributes if adopted.

The suite records exact destination bytes after replacement, staging-file
existence before overall scratch cleanup, and any domain/code error with whether
the original remained unchanged. It also creates a sidecar where none existed.
Failure tests cover a missing parent, a non-file destination, and an existing
scratch folder containing a sentinel that must never be removed. The writer
refuses non-regular destinations and attempts to remove its temporary file on
failure. The suite inventories residue and reports cleanup failure separately.

| Physical condition | Result | What settles it |
| --- | --- | --- |
| exFAT SD card, normal | **Pending** | Lab JSON with `context.fileSystem` reporting exFAT and all 12 replacement results |
| Write-protected card | **Pending** | Run on locked card; capture actual error and Documents report |
| Full/nearly-full card | **Pending, if feasible** | Disposable card with little free space; capture actual write/cleanup outcome |
| Disconnect/power loss during replace | Not established | A separate controlled fault experiment; successful rereads do not prove crash durability |

No volume was filled or remounted read-only on the shared host. S1 owns the full
error-to-product-message mapping. A protection/full-card run can fail before the
atomic loop (for example, creating scratch); that is still exported as evidence,
not counted as twelve successful replacements.

### Sidecar naming and public documentation

PRD rule 3 remains the rule: **replace the primary extension**. Thus
`IMG_0001.CR3` and its paired `IMG_0001.JPG` share `IMG_0001.xmp` in the same
folder. `IMG_0001.CR3.xmp` is an alternate spelling to investigate, not a second
sidecar Clove should silently start writing. Same stems in different folders
remain independent. Multiple RAW extensions with the same stem are an ambiguity
to expose during C2/C3; this spike does not invent a suffix policy.

The cache actually contains `IMG_0001.XMP`, not an appended-extension variant.
The test checks that real file by enumeration and compares the two candidate URL
rules; it does not claim the set provides an app-exported `.CR3.xmp` sample.
Production discovery should find case variants before creating a new `.xmp`,
especially on a case-sensitive volume. If multiple variants disagree, preserve
them and surface the ambiguity rather than overwrite one arbitrarily.

| App | Naming / documented read-write behavior | Evidence and remaining check |
| --- | --- | --- |
| Lightroom Classic | Expected `IMG_0001.xmp` beside proprietary RAW; explicit Save Metadata to File or automatic XMP writes; reading external changes is a separate catalog action | Adobe's [metadata basics](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/metadata-basics-actions.html) and [advanced metadata actions](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/advanced-metadata-actions.html) establish RAW sidecar storage and metadata synchronization. These pages do **not** establish whether appended-extension variants are read, or independently guarantee shared RAW+JPG behavior. Verify exact naming on desktop. |
| Capture One | `ImageName001.NEF` and `ImageName001.jpg` explicitly share `ImageName001.XMP`; Full Sync creates/updates and loads; Load is read-only synchronization | [Metadata in XMP sidecar files](https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files) explicitly gives the names and shared-sidecar example. Appended-extension acceptance remains unverified. |
| Photo Mechanic | Same base filename with `.xmp` replacing the image extension; RAW sidecars are the default read/write workflow | Camera Bits [Glossary, Sidecar (XMP)](https://docs.camerabits.com/support/solutions/articles/48001206190-glossary-of-terms) defines the name; [IPTC/XMP Preferences](https://docs.camerabits.com/support/solutions/articles/48001146198-iptc-xmp-preferences) documents sidecar creation/update and RAW metadata preferences. Appended-extension acceptance and pair behavior remain desktop checks. |

Documentation was fetched on 2026-11-08. Adobe also documents that Classic 15+
can create an additional `.ACR` companion for heavy edits ([Save metadata to
external sidecar files](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/create-xmp-acr-files.html)). S3 changes no ACR file. The desktop checklist should establish whether C6's future Move rejects plan needs to include that companion; that is an open product-scope question, not a change to this spike or the PRD.

### Reproducing the local Adobe comparison

Run from the checkout root. All downloads and outputs stay in ignored `.build/s3`.
CMake 4 requires the policy compatibility flag below. Only XMPCore is needed;
XMPFiles and its zlib dependency are not built. No SDK source patches are needed.

```sh
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
mkdir -p .build/s3
git clone https://github.com/adobe/XMP-Toolkit-SDK.git .build/s3/XMP-Toolkit-SDK
git -C .build/s3/XMP-Toolkit-SDK checkout 7093513bd3caaad29da01db0f275d88a39d6bcc2
curl -fL https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz -o .build/s3/expat-2.5.0.tar.gz
tar -xzf .build/s3/expat-2.5.0.tar.gz -C .build/s3
cp -R .build/s3/expat-2.5.0/lib .build/s3/XMP-Toolkit-SDK/third-party/expat/lib
cmake -S .build/s3/XMP-Toolkit-SDK/XMPCore/build -B .build/s3/sdk-core -G Xcode \
  -DCMAKE_CL_64=ON -DXMP_BUILD_STATIC=ON -DCMAKE_LIBCPP=ON \
  -DXMP_OSX_SDK=27.2 -DXMP_OSX_TARGET=15.0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build .build/s3/sdk-core --config Release --target XMPCoreStatic -- -jobs 2 CODE_SIGNING_ALLOWED=NO
```

Save the following as `.build/s3/sdk-roundtrip.cpp`:

```cpp
#define MAC_ENV 1
#define XMP_64 1
#define XMP_StaticBuild 1
#define TXMP_STRING_TYPE std::string
#include <string>
#include "XMP.hpp"
#include "XMP.incl_cpp"
#include <fstream>
#include <iostream>
#include <iterator>
#include <filesystem>
int main(int argc, char** argv) {
    if (argc != 3 || !SXMPMeta::Initialize()) return 2;
    SXMPMeta::RegisterNamespace("https://clove.photo/ns/1.0/", "clove", nullptr);
    std::filesystem::create_directories(argv[2]);
    for (const auto& entry : std::filesystem::directory_iterator(argv[1])) {
        if (entry.path().extension() != ".xmp") continue;
        std::ifstream input(entry.path(), std::ios::binary);
        std::string bytes((std::istreambuf_iterator<char>(input)), {});
        try {
            SXMPMeta meta;
            if (!bytes.empty()) meta.ParseFromBuffer(bytes.data(), bytes.size());
            std::string initialRating, initialLabel, initialReject;
            meta.GetProperty(kXMP_NS_XMP, "Rating", &initialRating, nullptr);
            meta.GetProperty(kXMP_NS_XMP, "Label", &initialLabel, nullptr);
            meta.GetProperty("https://clove.photo/ns/1.0/", "Reject", &initialReject, nullptr);
            meta.SetProperty_Int(kXMP_NS_XMP, "Rating", 3);
            meta.SetProperty(kXMP_NS_XMP, "Label", "Green");
            meta.SetProperty_Bool("https://clove.photo/ns/1.0/", "Reject", true);
            std::string output;
            meta.SerializeToBuffer(&output, kXMP_UseCompactFormat);
            SXMPMeta back(output.data(), output.size());
            XMP_Int32 rating = 0; bool reject = false; std::string label;
            back.GetProperty_Int(kXMP_NS_XMP, "Rating", &rating, nullptr);
            back.GetProperty(kXMP_NS_XMP, "Label", &label, nullptr);
            back.GetProperty_Bool("https://clove.photo/ns/1.0/", "Reject", &reject, nullptr);
            if (rating != 3 || label != "Green" || !reject) return 3;
            std::ofstream file(std::filesystem::path(argv[2]) / entry.path().filename(), std::ios::binary);
            file << output;
            std::cout << entry.path().filename() << " OK initial=" << initialRating
                      << "," << initialLabel << "," << initialReject << " bytes=" << output.size() << "\n";
        } catch (const XMP_Error& error) {
            std::cout << entry.path().filename() << " REFUSED " << error.GetID()
                      << " " << error.GetErrMsg() << "\n";
        }
    }
    SXMPMeta::Terminate();
}
```

```sh
clang++ -std=c++17 -arch arm64 -DMAC_ENV=1 -DXMP_64=1 -DXMP_StaticBuild=1 \
  -I .build/s3/XMP-Toolkit-SDK/public/include .build/s3/sdk-roundtrip.cpp \
  .build/s3/XMP-Toolkit-SDK/public/libraries/macintosh/universal/Release/libXMPCoreStatic.a \
  -framework CoreFoundation -framework Foundation -o .build/s3/sdk-roundtrip
.build/s3/sdk-roundtrip fixtures/xmp .build/s3/sdk-output
S3_REPORT_DIR="$PWD/.build/s3" S3_SDK_OUTPUT_DIR="$PWD/.build/s3/sdk-output" \
  mise exec -- swift test --package-path Packages/CloveSpikes --filter SpikeS3XMPTests
```

The opt-in SDK test independently reads all ten saved outputs; its log reports
semantic/form preservation, including the repaired malformed input. Ordinary
`mise run verify` never downloads, links, or requires the SDK. The macOS JSON is
written when `S3_REPORT_DIR` is set. The separate SDK JSON records the independently
verified mark/preservation booleans and output sizes; SDK throughput was not measured.

To reproduce the simulator data, compile the S3 and SpikeSupport Swift files for
`arm64-apple-ios18.0-simulator` using the installed simulator SDK (remove the
`import SpikeSupport` lines in temporary copies when combining into one executable).
Its `@main` calls `XMPSuite.run(in:)` on an empty temporary directory, writes the
returned `LabReport`, and removes the directory. Create a fresh iPhone 17 Pro Max
with `xcrun simctl create`, boot it, run the executable with `simctl spawn`, and
always shut down/delete that device. The run used `.build/s3/simulator-main.swift`
and `.build/s3/run-simulator.sh`; the attached JSON identifies this runner rather
than claiming a Clove Lab UI run.

## Conclusion

The preserving edit is the only tested approach that retains every unknown
fixture byte while refusing the malformed input. ImageIO and the default Adobe
SDK run both normalize XMP and lose specific unknown content, so a successful
rating read-back alone is insufficient. Both atomic methods succeed on APFS;
exFAT and provider behavior remain inconclusive until the device run.

## Recommendation and options for G1

Recommend a **validated preserving editor** for C3, with an independent read-back
check in C4. Extend and harden the spike's limited XML handling before using it
as the production codec: resource-qualified marks, multiple descriptions,
encoding/size limits, conflicting sidecars, and preservation diagnostics need
explicit policies and tests. Refuse ambiguous or malformed input and retain the
requested marks for retry; never silently repair another app's packet or mark a
failed/unconfirmed write Saved. No performance target is proposed from this host.

Alternatives remain open for the product owner's G1 decision:

1. **ImageIO with preservation safeguards.** No extra dependency and useful
   metadata APIs, but needs malformed/empty-description handling, packet wrapping,
   and a way to merge only owned changes back into the original. Whole-packet
   reserialization failed preservation here.
2. **Adobe SDK.** Broad XMP support, with C++ bridging, dependency/security/license
   maintenance, iOS builds, and more parse/serialization-policy investigation.
   This default run is not safe for the tested unknown content. A newer or
   differently configured SDK could be evaluated separately.
3. **Custom editor (recommended).** Best preservation evidence on this corpus;
   costs careful XML/namespace/range handling and explicit refusal of unsupported
   cases. It is not permission to ship this spike unchanged as the codec.

Proposed schema, **subject to G1 and confirmation of a permanent URI under our
control**: namespace URI `https://clove.photo/ns/1.0/`, preferred prefix `clove`,
property `clove:Reject`, XMP Boolean serialized as `True`/`False`. Prefix spelling
is not identity. Default Reject toggles only this property and preserves the star
rating. Labels use fixed English names, including Orange/Pink when enabled.

For the optional **Also write Rating −1** setting (off by default), propose
writing `xmp:Rating=-1` only when Reject is set, alongside `clove:Reject=True`.
To preserve the independent star rating across reopening/unreject, C3 needs a
separate persisted prior rating (for example `clove:RatingBeforeReject`, integer
0–5); confirm that additional property at G1. On clearing Reject, restore that
known rating and remove the auxiliary value. If an external −1 has no prior
rating, display external rejection without inventing a previous star value.
The spike returns raw Rating −1 separately from the Clove Boolean; production
mark interpretation and optional-mode state transitions are intentionally not
implemented here.

For C4, prefer same-directory staging plus `rename` as the simple candidate,
with read-back confirmation, pending exFAT results. Retain `replaceItemAt` as
an alternative if its attribute-preservation semantics matter. Decide whether
coordination is needed from the provider/device results, not these APFS timings.

## Open questions

- Physical exFAT success/timing, residue, protected/full-card errors, and whether
  coordination changes outcomes: collect the checklist JSON in part 2.
- Final namespace ownership and optional −1 restoration property: G1 decisions.
- Exact desktop naming, shared-pair handling, localized label sets, extended
  colors, Rating −1, and behavior with competing sidecars: desktop checks below.
- Lightroom 15+ `.ACR` companions: should the later Move rejects task preserve
  and move them too? Public documentation introduces this question; no PRD or
  shared code was changed.

### Device checklist (part 2)

Repeat on **iPhone 17 Pro Max, iPad Pro, and iPhone Duo**, recording the installed
OS version in each run (the JSON records it automatically). Use a supervisor-
uploaded Clove Lab TestFlight build containing S3.

1. Connect an **exFAT SD card** using the reader. In Files, create an empty
   `Clove-S3-Test` folder on the card. Keep personal photos outside this folder.
2. Open **Clove Lab → S3 · XMP → Choose folder**, select `Clove-S3-Test` on the
   SD card, then confirm the folder selection. The chosen folder name appears.
3. Tap **Run S3 suite** and wait for Finished. Expect **12/12 replacement checks
   confirmed**, file system **exfat/exFAT** (an unexpected value must be sent
   back), and **Scratch folder remains: false**. The suite copies its bundled
   inputs into `clove-lab-s3` and removes that folder. Expected codec comparison
   differences are in the JSON; they do not prevent the atomic checks.
4. In Files, verify `clove-lab-s3` is gone and an S3 JSON report is present in
   `Clove-S3-Test`. The same report should appear in **On My iPhone/iPad → Clove
   Lab**. The footer shows `clove-lab-S3-<UTC timestamp>.json` and offers Export.
5. If feasible, safely eject the card, lock its write-protection tab, reconnect,
   select the same folder again, and run. Expect a visible failure note rather
   than successful writes. A reader can ignore the tab: report what actually
   happens. If saving the card copy fails, tap **Export to Documents again** and
   use the footer's Export button for the Documents copy.
6. If a **disposable nearly-full card** is available, repeat there without
   deleting personal files. Success is possible if enough space remains; failure
   should include a reason and scratch-cleanup outcome. Do not fill the card
   from Clove Lab. State when this condition was skipped or could not be induced.
7. Attach **each S3 JSON file to [issue #14](https://github.com/mimiqdev/cloveapp/issues/14)**,
   using the on-screen filename. Include the reader/card details, lock/full-card
   conditions, and any mismatch from steps 3–6. Do not send photos or signing files.

### Desktop-app checklist (product owner)

Use disposable copies of `xmp-interop` and `name-collision`; record app versions,
OS, metadata preferences, and UI language. Do these steps separately in
Lightroom Classic, Capture One, and Photo Mechanic; none was installed/tested here.

1. Start with a single `IMG_0001.CR3` and no sidecar. Apply 3 stars and Green,
   explicitly save/sync metadata, and record the exact filename/case created.
   Check whether it is `IMG_0001.xmp` or `IMG_0001.CR3.xmp`.
2. In separate fresh folders, provide each candidate filename with distinguishable
   marks (2/Blue versus 4/Red). Reload/read metadata and record which is read.
   Then provide both together and record precedence/conflict behavior. Test `.XMP`
   case too. Never combine these conflicting samples with real work.
3. Repeat with `IMG_0001.CR3` plus `IMG_0001.JPG`. Test the app's RAW+JPEG pair
   preference and whether the RAW rating/label comes from the shared stem XMP;
   record whether the JPEG uses embedded metadata instead. Change marks, save,
   and note whether another sidecar is created or the originals are modified.
4. Open copies containing each named fixture. Save marks from the desktop app,
   then edit them with the S3 preserving editor (or later C3 build) and reload
   them in the app. Alternate writes in both directions. Confirm ratings/labels,
   develop settings, history, keywords, nested custom metadata, and both caption
   languages remain. Save the before/after XMP for analysis.
5. With default English label presets, check Red/Yellow/Green/Blue/Purple and
   optional Orange/Pink. Repeat with the owner's usual non-English label set;
   record actual XMP strings and displayed colors rather than assuming translation.
6. Check `clove:Reject=True` with an ordinary rating, then `Rating=-1` with and
   without that field. Record Bridge behavior too if available. Verify default
   Clove Reject does not alter another app's ordinary star rating.
7. In Lightroom Classic 15+, use a disposable image with heavy edits, save its
   metadata, and record `.ACR` naming/association. Return findings on issue #14
   so G1 and C6 can address companion-file handling before Move rejects ships.
