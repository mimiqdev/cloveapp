# S3 — How should XMP be read and written?

## Question

How should XMP be read and written? Compare ImageIO's XMP APIs, Adobe XMP
Toolkit, and custom XML parsing: read and write `xmp:Rating`, `xmp:Label`, and
the Clove-specific field; round-trip the T0.3 fixtures and check that unknown
namespaces and structures survive unchanged; do atomic write-to-temp-and-replace
on an exFAT SD card.

Part 2 of [#14](https://github.com/mimiqdev/cloveapp/issues/14), following
[PR #22](https://github.com/mimiqdev/cloveapp/pull/22). The available device run
confirms local APFS behavior. On 2026-11-09 the product owner deferred the
remaining hardware and desktop checks to
[#29](https://github.com/mimiqdev/cloveapp/issues/29). G1 remains open; this report
recommends an approach without making the gate decision. Camera files, especially
the owner's Sony A1 II ARW+HIF pairs, are the main target.

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
  from the same S3 and LabSupport sources runs the complete suite inside a new,
  disposable simulator. It uses a local temporary folder on APFS. This measures
  iOS API behavior, **not** a document provider, picker interaction, or SD-card I/O.
  The Clove Lab screen is separately built by `mise run verify`; it uses the
  shared folder picker, security-scoped access, `LabSession`, exporter, and footer.
- Physical iPhone 17 Pro Max (`iPhone19,4`), iOS 27.2, Clove Lab **26110818**,
  run 1 on local **APFS** storage: the same ten bundled XMP fixtures and 12
  replacement checks through the Lab folder picker. The selected session folder
  contained one A1 II ARW and one HIF; S3 tests bundled packets, not embedded
  metadata in those images. That build's HIF filter gap does not invalidate
  these sidecar checks and is not evidence of RAW+HIF discovery or desktop interop.
  There is **no S3 run-2 report**: the later session's ten ARW+HIF pairs add no S3
  measurement. Physical exFAT, locked/full-card, iPhone Duo, iPad Pro and desktop
  results remain deferred.

Historical part-1 evidence, kept out of git and reproduced as JSON in issue #14 comments:

| Report | UTC run time | Contents |
| --- | --- | --- |
| `clove-lab-S3-macos.json` | 2026-11-08 16:59:36 | Fixture comparison, disk read-back, new sidecars, APFS replacements |
| `clove-lab-S3-sdk.json` | See JSON `createdAt` | Separate local Adobe run, independently inspected outputs |
| `clove-lab-S3-simulator.json` | 2026-11-08 17:01:41 | Same two dependency-free approaches and replacements on iOS Simulator |

Part 1 kept local copies and trimmed command logs under `.build/xmp/`; those
artifacts are not copied into this part-2 checkout. Physical-device evidence was
read in place, with SHA-256 obtained using `shasum -a 256`:

| Evidence ID | Report filename | SHA-256 |
| --- | --- | --- |
| Run 1 | `clove-lab-S3-20261109T022019Z.json` | `16661617ba9162fd34d1870a1d1974035e41284972161d0dc560d4c69bf1dc3a` |

The owner's raw JSON is not committed. Capture timestamps, GPS, serial numbers
and personal folder paths are omitted; the filename identifies the report.
Part-2 verification output is recorded in the pull request.

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

| Physical condition | Status / evidence | What settles it |
| --- | --- | --- |
| Local APFS | **Measured — run 1** | All 12 replacements and cleanup confirmed; details below |
| exFAT SD card, normal | **Deferred — #29** | Lab JSON with `context.fileSystem` reporting exFAT and all 12 replacement results |
| Write-protected card | **Deferred — #29** | Run on locked card; capture actual error and Documents report |
| Full/nearly-full card | **Deferred — #29, if feasible** | Disposable card with little free space; capture actual write/cleanup outcome |
| Disconnect/power loss during replace | **Deferred — C4 validation** | A separate controlled fault experiment; successful rereads do not prove crash durability |

No volume was filled or remounted read-only on the shared host. S1 owns the full
error-to-product-message mapping. A protection/full-card run can fail before the
atomic loop (for example, creating scratch); that is still exported as evidence,
not counted as twelve successful replacements.

### Physical-device confirmation

All measured rows below come from **run 1**, iPhone 17 Pro Max (`iPhone19,4`),
iOS 27.2, Clove Lab 26110818, local APFS. The JSON agrees with the supervisor's
initial reading: **12/12** replacements confirmed, **0/12** staging files left,
`temporary-residue-count = 0`, `scratchRemains = false`, and a note confirming
removal of the owned scratch directory. Successful rereads establish observed
replacement/read-back and cleanup, not crash durability or on-card atomicity.

#### Device findings

“Data” and “form” use the same independent comparator definitions as the host
tables above. The JSON reports preservation booleans rather than serialized
output; the specific History/datatype diagnosis comes from part 1's inspected
XML. These are hand-written interop fixtures, not actual desktop-app round trips.

| Status / evidence | Fixture / condition | Preserving editor | ImageIO |
| --- | --- | --- | --- |
| **Measured — run 1** | `capture-one.xmp` | Marks confirmed; data/form preserved | Marks confirmed; data preserved, form changed |
| **Measured — run 1** | `custom-namespace-nested.xmp` | Marks confirmed; data/form preserved | Marks confirmed; data/form loss detected |
| **Measured — run 1** | `empty-description.xmp` | Marks confirmed; valid empty description extended | Parse refused; no output |
| **Measured — run 1** | `empty.xmp` | Marks confirmed; valid replacement packet | Marks confirmed; valid replacement packet |
| **Measured — run 1** | `label-orange.xmp` | Marks confirmed; data/form preserved | Marks confirmed; data preserved, form changed |
| **Measured — run 1** | `label-pink.xmp` | Marks confirmed; data/form preserved | Marks confirmed; data preserved, form changed |
| **Measured — run 1** | `lightroom-full.xmp` | Marks confirmed; data/form preserved | Marks confirmed; data/form loss detected |
| **Measured — run 1** | `malformed.xmp` | Refused at read; no output | Accepted/repaired; marks confirmed; invalid original cannot be compared |
| **Measured — run 1** | `photo-mechanic.xmp` | Marks confirmed; data/form preserved | Marks confirmed; data preserved, form changed |
| **Measured — run 1** | `rating-minus-one.xmp` | Initially −1; marks confirmed; data/form preserved | Initially −1; marks confirmed; data preserved, form changed |
| **Measured — run 1** | New sidecar without existing packet | Valid XMP and standard packet wrapper | Valid XMP; packet wrapper absent |
| **Measured — run 1** | Disk read-back of fixture writes | 9/9 marks confirmed; malformed input refused | 9/9 marks confirmed, including repaired malformed input; empty description refused |
| **Measured — run 1** | Replacement and cleanup | Both methods, with/without coordination: 12/12 exact-byte confirmations, no staging/scratch residue | Shared writer test, independent of ImageIO serialization |
| **Deferred — #29** | exFAT SD card / reader, locked card, full-card condition | No on-card replacement, failure or cleanup evidence | No on-card claim |
| **Deferred — #29** | iPhone Duo and iPad Pro | No device/OS confirmation | No device/OS confirmation |
| **Deferred — #29** | Lightroom Classic, Capture One, Photo Mechanic; RAW+JPEG and RAW+HIF naming/discovery | No real desktop read/sync or pair-precedence result | Fixture serialization is not a desktop interoperability check |

The preserving editor passes **9/9** valid-input preservation comparisons,
including the empty packet and empty description (which contain no unknown data),
and refuses the malformed tenth packet. ImageIO changes representation in
**7/8** comparable valid-input outputs; the eighth is the empty packet. It loses
data in **2/8**, preserves it in **6/8**, refuses the valid empty description,
and repairs the malformed input. Neither denominator includes that repaired
input. Thus confirmed rating/label/Reject read-back does not establish preservation.
Adobe was not run on device; its separate macOS comparison remains the evidence.

#### Device replacement times

Every row is **measured — run 1**; three samples per method/mode, milliseconds.
Timing includes staging write, synchronization/close and replacement; excludes
read-back. These small local samples are observations, not performance targets.

| Status / evidence | Method | NSFileCoordinator | Confirmed | Median ms | Min–max ms | Temp remains |
| --- | --- | --- | --- | --- | --- | --- |
| **Measured — run 1** | `FileManager.replaceItemAt` | No | 3/3 | 0.726 | 0.720–0.931 | 0/3 |
| **Measured — run 1** | `FileManager.replaceItemAt` | Yes | 3/3 | 1.551 | 1.446–2.199 | 0/3 |
| **Measured — run 1** | POSIX `rename` | No | 3/3 | 0.567 | 0.518–0.583 | 0/3 |
| **Measured — run 1** | POSIX `rename` | Yes | 3/3 | 1.199 | 1.138–1.202 | 0/3 |

Coordination is not needed for success on this local folder. These results do
not settle document-provider requirements, external-volume attributes, reader
write protection, interrupted writes or power-loss behavior.

### Sidecar naming and public documentation

PRD rule 3 remains the rule: **replace the primary extension**. Thus
`IMG_0001.CR3` and its paired `IMG_0001.JPG` share `IMG_0001.xmp` in the same
folder. Consistent with [S4](S4-metadata.md), Sony A1 II `MMQ05184.ARW` plus
`MMQ05184.HIF` likewise share **`MMQ05184.xmp`**, containing one rating, label
and Reject state for the pair. Neither pair member receives embedded writes,
even when the standalone embedded option is enabled. This is the recommended
pair persistence policy; actual desktop display/read behavior is still unverified.
`IMG_0001.CR3.xmp` (or `MMQ05184.ARW.xmp`) is an alternate spelling to investigate,
not a second sidecar Clove should silently start writing. Same stems in different
folders remain independent. Multiple RAW extensions with the same stem are an
ambiguity to expose during C2/C3; this spike does not invent a suffix policy.

The cache actually contains `IMG_0001.XMP`, not an appended-extension variant.
The test checks that real file by enumeration and compares the two candidate URL
rules; it does not claim the set provides an app-exported `.CR3.xmp` sample.
Recommended C2/C3 discovery is a same-directory enumeration by stem and XMP
extension, finding existing `.XMP`/case variants before creating lowercase `.xmp`.
Reuse a unique matching sidecar's actual spelling; never create a second file
solely because its extension case differs. Detect appended-extension candidates
such as `NAME.ARW.xmp` as a compatibility ambiguity. Until the desktop checks
settle their meaning, preserve them and require resolution before creating a
competing canonical file or writing either candidate. Multiple case variants or
competing packets must not be silently merged or arbitrarily overwritten.
These are production requirements, not claims that the spike's URL helper
already implements discovery or that real desktop apps use this precedence.

| App | Naming / documented read-write behavior | Evidence and remaining check |
| --- | --- | --- |
| Lightroom Classic | Expected `IMG_0001.xmp` beside proprietary RAW; explicit Save Metadata to File or automatic XMP writes; reading external changes is a separate catalog action | Adobe's [metadata basics](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/metadata-basics-actions.html) and [advanced metadata actions](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/advanced-metadata-actions.html) establish RAW sidecar storage and metadata synchronization. These pages do **not** establish whether appended-extension variants are read, or independently guarantee shared RAW+JPG behavior. Verify exact naming on desktop. |
| Capture One | `ImageName001.NEF` and `ImageName001.jpg` explicitly share `ImageName001.XMP`; Full Sync creates/updates and loads; Load is read-only synchronization | [Metadata in XMP sidecar files](https://support.captureone.com/hc/en-us/articles/360002544898-Metadata-in-XMP-sidecar-files) explicitly gives the names and shared-sidecar example. Appended-extension acceptance remains unverified. |
| Photo Mechanic | Same base filename with `.xmp` replacing the image extension; RAW sidecars are the default read/write workflow | Camera Bits [Glossary, Sidecar (XMP)](https://docs.camerabits.com/support/solutions/articles/48001206190-glossary-of-terms) defines the name; [IPTC/XMP Preferences](https://docs.camerabits.com/support/solutions/articles/48001146198-iptc-xmp-preferences) documents sidecar creation/update and RAW metadata preferences. Appended-extension acceptance and pair behavior remain desktop checks. |

Documentation was fetched on 2026-11-08. Adobe also documents that Classic 15+
can create an additional `.ACR` companion for heavy edits ([Save metadata to
external sidecar files](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/create-xmp-acr-files.html)). S3 changes no ACR file. The desktop checklist should establish whether C6's future Move rejects plan needs to include that companion; that is an open product-scope question, not a change to this spike or the PRD.

### Reproducing the local Adobe comparison

Run from the checkout root. All downloads and outputs stay in ignored `.build/xmp`.
CMake 4 requires the policy compatibility flag below. Only XMPCore is needed;
XMPFiles and its zlib dependency are not built. No SDK source patches are needed.

```sh
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
mkdir -p .build/xmp
git clone https://github.com/adobe/XMP-Toolkit-SDK.git .build/xmp/XMP-Toolkit-SDK
git -C .build/xmp/XMP-Toolkit-SDK checkout 7093513bd3caaad29da01db0f275d88a39d6bcc2
curl -fL https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz -o .build/xmp/expat-2.5.0.tar.gz
tar -xzf .build/xmp/expat-2.5.0.tar.gz -C .build/xmp
cp -R .build/xmp/expat-2.5.0/lib .build/xmp/XMP-Toolkit-SDK/third-party/expat/lib
cmake -S .build/xmp/XMP-Toolkit-SDK/XMPCore/build -B .build/xmp/sdk-core -G Xcode \
  -DCMAKE_CL_64=ON -DXMP_BUILD_STATIC=ON -DCMAKE_LIBCPP=ON \
  -DXMP_OSX_SDK=27.2 -DXMP_OSX_TARGET=15.0 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build .build/xmp/sdk-core --config Release --target XMPCoreStatic -- -jobs 2 CODE_SIGNING_ALLOWED=NO
```

Save the following as `.build/xmp/sdk-roundtrip.cpp`:

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
  -I .build/xmp/XMP-Toolkit-SDK/public/include .build/xmp/sdk-roundtrip.cpp \
  .build/xmp/XMP-Toolkit-SDK/public/libraries/macintosh/universal/Release/libXMPCoreStatic.a \
  -framework CoreFoundation -framework Foundation -o .build/xmp/sdk-roundtrip
.build/xmp/sdk-roundtrip fixtures/xmp .build/xmp/sdk-output
XMP_REPORT_DIR="$PWD/.build/xmp" XMP_SDK_OUTPUT_DIR="$PWD/.build/xmp/sdk-output" \
  mise exec -- swift test --package-path Packages/CloveLabKit --filter XMPProbeTests
```

The opt-in SDK test independently reads all ten saved outputs; its log reports
semantic/form preservation, including the repaired malformed input. Ordinary
`mise run verify` never downloads, links, or requires the SDK. The macOS JSON is
written when `XMP_REPORT_DIR` is set. The separate SDK JSON records the independently
verified mark/preservation booleans and output sizes; SDK throughput was not measured.

To reproduce the simulator data, compile the S3 and LabSupport Swift files for
`arm64-apple-ios18.0-simulator` using the installed simulator SDK (remove the
`import LabSupport` lines in temporary copies when combining into one executable).
Its `@main` calls `XMPSuite.run(in:)` on an empty temporary directory, writes the
returned `LabReport`, and removes the directory. Create a fresh iPhone 17 Pro Max
with `xcrun simctl create`, boot it, run the executable with `simctl spawn`, and
always shut down/delete that device. The run used `.build/xmp/simulator-main.swift`
and `.build/xmp/run-simulator.sh`; the attached JSON identifies this runner rather
than claiming a Clove Lab UI run.

## Conclusion

The preserving edit is the only tested approach that retains every unknown
fixture byte while refusing the malformed input. The physical-device run agrees
with the host/simulator comparison; ImageIO and the default Adobe SDK run cannot
be accepted as whole-packet writers on this corpus. Both replacement methods,
with and without coordination, succeed on local APFS on host, simulator and
physical iPhone. exFAT/provider behavior and actual desktop naming/pair reads
remain unverified and deferred, rather than inferred from local success.

## Recommendation and options for G1

Recommend a **validated preserving editor** for C3, with an independent read-back
check in C4. Extend and harden the spike's limited XML handling before using it
as the production codec: resource-qualified marks, multiple descriptions,
encoding/size limits, conflicting sidecars, and preservation diagnostics need
explicit policies and tests. Refuse ambiguous or malformed input and retain the
requested marks for retry; never silently repair another app's packet or mark a
failed/unconfirmed write Saved. No performance target is proposed from these
host/device samples.

Recommend **one same-stem sidecar per RAW+HIF or RAW+JPEG pair**, using the
naming/discovery rule above. This agrees with S4: the shared RAW sidecar avoids
the observed native JPEG/HIF metadata losses and supplies one persisted set of
pair marks. Keep original images unchanged. The recommendation holds as a
preserving Clove persistence design while the desktop checks are deferred;
it is **not yet a verified P0-07 interoperability result**. Public naming
references and the PRD support it, but the device run tests neither naming
variants nor which pair member desktop software reads.

Before **C3's discovery/compatibility policy is finalized**, the desktop check
must establish for all three apps: exact created filename/case, whether each
candidate is read, what happens when both exist, and RAW+JPEG/**RAW+HIF** grouping
and metadata precedence under the owner's preferences. It must separate the
RAW's sidecar marks from the companion's embedded marks, using distinguishable
values. If an app ignores the shared packet for a companion or expects a
different name, return that evidence to G1 for an explicit compatibility choice;
do not add a second writable sidecar or enable pair embedding silently.
Before **C7 claims desktop interoperability**, also confirm the supported
standalone JPEG embedded path's save/reload behavior and the sidecar versus
embedded precedence. S4's standalone HIF/DNG Lightroom limitation remains
visible; neither this recommendation nor the shared-pair rule resolves it.
C7 should combine S4's eligible JPEG container splicing with the preserving XMP
edit selected at G1, and exclude the lossy ImageIO whole-packet serializer.

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

For C4, recommend a unique **same-directory staging file**, validate the edited
packet, synchronize and close the staging file, then use POSIX **`rename`** for
replacement and independently read back the destination before showing Saved.
Serialize writes to the shared pair sidecar so two members cannot race. On a
failure, retain requested marks for retry, keep the previous packet whenever
replacement has not happened, and remove only the writer's owned staging file;
report cleanup failures. A read-back mismatch or interruption leaves the change
unconfirmed. Successful synchronization/read-back does not prove crash durability.

The local physical result strengthens this candidate but does not establish an
exFAT guarantee. Retain `replaceItemAt` as an alternative if destination metadata
preservation is required; C4 must explicitly handle permissions/attributes with
`rename`. Use `NSFileCoordinator` as required by the selected Files provider and
its access contract; no coordination requirement can be inferred from the local
APFS samples. #29 can change the staging/replacement/coordination implementation
or supported-storage policy if physical-card evidence differs.

## Open questions

- Physical exFAT success/timing, residue, protected/full-card errors, and whether
  coordination changes outcomes: deferred to #29; local run 1 does not settle them.
- Final namespace ownership and optional −1 restoration property: G1 decisions.
- Exact desktop naming, shared RAW+HIF/RAW+JPEG handling, embedded/sidecar
  precedence, localized label sets, extended colors, Rating −1, and behavior
  with competing sidecars: deferred desktop checks below, before C3/C7
  compatibility claims. G1 may adopt the preserving design with this limitation
  explicit; a contradictory desktop result requires returning to the gate.
- Lightroom 15+ `.ACR` companions: should the later Move rejects task preserve
  and move them too? Public documentation introduces this question; no PRD or
  shared code was changed.

## Deferred device checks

On 2026-11-09 the owner deferred these checks to
[#29](https://github.com/mimiqdev/cloveapp/issues/29). They do not block finishing
#14 with the available evidence. Run them before M3/Q3 performance targets are
fixed, or earlier if G1 needs their answers. Desktop results must settle the
C3/C7 questions above before interoperability is claimed.

| Deferred check | What it would answer | Could it change the G1 recommendation? |
| --- | --- | --- |
| exFAT SD card through the reader, both methods/modes | Actual same-directory replacement, timing, read-back, temp/scratch cleanup and provider coordination on the target storage | **Yes, writer/storage policy:** could change `rename` versus `replaceItemAt`, coordination or supported storage. It would not reverse the measured serializer losses or favor rewriting unknown XMP |
| Locked card | Whether the reader honors protection; actual failure stage/error, original integrity, cleanup and Documents export | **Could change failure handling or storage support**, not the preserving codec or shared-sidecar naming recommendation |
| Nearly-full disposable card, if feasible; interruption/crash follow-up in C4 | Whether staging/replacement failures keep the previous packet and clean owned temp files; durability needs a separate controlled experiment | **Could change writer/recovery requirements.** APFS read-back alone cannot justify crash-safety claims; do not fill the shared host or personal card |
| iPhone Duo | Whether codec, replacement and coordination results agree on that device/OS | **Could narrow device/OS support or require writer changes** if results differ; no result is assumed from the iPhone 17 Pro Max |
| iPad Pro | The same API, storage and timing confirmation on iPadOS | **Could change device/OS support or coordination**, not justify enabling a serializer already known to lose unknown content |
| Lightroom Classic, Capture One, Photo Mechanic | Exact filename/case, appended-extension acceptance, conflicts, shared RAW+JPEG/RAW+HIF read/sync and embedded precedence; real exports' preservation and marks | **Yes, naming/interop policy:** a contradictory result requires G1 to revisit compatibility before C3/C7 claims. Fixture success cannot replace this check; no extra writable sidecar or pair embedding is authorized by this report |

Camera files remain the focus. iPhone HEIC's known S4 ownership gap is recorded
in [S4](S4-metadata.md) and #29 for photo library work; it adds no S3 measurement
or blocker and is not fixed here.

### Deferred device checklist

No new device run is required for this part-2 PR. When #29 is scheduled, repeat
on **iPhone 17 Pro Max, iPad Pro, and iPhone Duo**, recording the installed
OS version in each run (the JSON records it automatically). Use a supervisor-
uploaded Clove Lab TestFlight build containing S3.

1. Connect an **exFAT SD card** using the reader. In Files, create an empty
   `Clove-S3-Test` folder on the card. Keep personal photos outside this folder.
2. Open **Clove Lab → S3 · XMP → Choose folder**, select `Clove-S3-Test` on the
   SD card, then confirm the folder selection. The chosen folder name appears.
3. Tap **Run XMP suite** and wait for Finished. Expect **12/12 replacement checks
   confirmed**, file system **exfat/exFAT** (an unexpected value must be sent
   back), and **Scratch folder remains: false**. The suite copies its bundled
   inputs into `clove-lab-xmp` and removes that folder. Expected codec comparison
   differences are in the JSON; they do not prevent the atomic checks.
4. In Files, verify `clove-lab-xmp` is gone and an S3 JSON report is present in
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
7. Attach **each S3 JSON file to [issue #29](https://github.com/mimiqdev/cloveapp/issues/29)**,
   referencing #14 and using the on-screen filename. Include the reader/card
   details, lock/full-card conditions, and any mismatch from steps 3–6. Do not
   send photos or signing files.

### Desktop-app checklist (product owner)

Deferred to #29. Use disposable copies of `xmp-interop` and `name-collision`,
plus owner-provided A1 II ARW+HIF and ARW+JPEG pair copies; do not add private
camera files to the public fixtures. Record app versions, OS, metadata preferences,
pair preferences and UI language. Do these steps separately in Lightroom Classic,
Capture One and Photo Mechanic; none was installed/tested here.

1. Start with a single `IMG_0001.CR3` and no sidecar. Apply 3 stars and Green,
   explicitly save/sync metadata, and record the exact filename/case created.
   Check whether it is `IMG_0001.xmp` or `IMG_0001.CR3.xmp`.
2. In separate fresh folders, provide each candidate filename with distinguishable
   marks (2/Blue versus 4/Red). Reload/read metadata and record which is read.
   Then provide both together and record precedence/conflict behavior. Test `.XMP`
   case too. Never combine these conflicting samples with real work.
3. Repeat with `IMG_0001.CR3` plus `IMG_0001.JPG`, then with A1 II ARW+JPEG
   and **`MMQ05184.ARW` plus `MMQ05184.HIF`**. Use distinguishable embedded
   companion marks and sidecar marks, each candidate name alone, then competing
   names together. Test grouped/separate pair preferences, explicit read/sync
   and a fresh import/reopen. Record whether RAW reads the shared stem packet,
   which marks the rendered companion displays, and whether HIF is supported by
   the app/version at all. Change marks, save, and note exact files created or
   modified. A supported RAW sidecar does not prove companion interop; an
   unsupported HIF must be recorded as such.
4. Open copies containing each named fixture. Save marks from the desktop app,
   then edit them with the S3 preserving editor (or later C3 build) and reload
   them in the app. Also test Clove-created new wrapped packets. Alternate writes
   in both directions. Confirm ratings/labels, develop settings, history,
   keywords, nested custom metadata, and both caption languages remain. Save the before/after XMP for analysis.
5. With default English label presets, check Red/Yellow/Green/Blue/Purple and
   optional Orange/Pink. Repeat with the owner's usual non-English label set;
   record actual XMP strings and displayed colors rather than assuming translation.
6. Check `clove:Reject=True` with an ordinary rating, then `Rating=-1` with and
   without that field. Record Bridge behavior too if available. Verify default
   Clove Reject does not alter another app's ordinary star rating.
7. Test standalone camera JPEG with S4's preservation-safe embedded packet
   path (or later C7 build). Give embedded and sidecar packets distinguishable
   marks; explicitly reload/read metadata, reopen and save in each app. Record
   precedence and which files change. Keep standalone HIF/DNG Lightroom
   limitations explicit; do not infer embedded-write eligibility from sidecars.
8. In Lightroom Classic 15+, use a disposable image with heavy edits, save its
   metadata, and record `.ACR` naming/association. Return findings on issue #29,
   referencing #14, so G1 and C6 can address companion-file handling before Move
   rejects ships. Return sanitized findings and before/after packets privately
   when they contain personal metadata; do not publish capture timestamps, GPS,
   serial numbers or owner folder paths.
