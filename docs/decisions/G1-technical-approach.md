# G1: Technical approach

Status: **approved by the product owner, 2026-11-09.** Decision 5 was revised on 2026-11-11 to make Reject the rating −1; [the reject-as-rating record](reject-as-rating.md) supersedes it. The matching PRD and plan edits land in the same PR.

G1 closes M1. Per [the development plan](../DEV-PLAN.md), it fixes the XMP approach, the preview strategy, the performance targets and the Duo approach. Where a result makes a PRD item infeasible, it revises that item. Sources:

| Report | Final? |
| --- | --- |
| [S1 Folder access](../spikes/S1-access.md) | Yes |
| [S2 Previews](../spikes/S2-previews.md) | Yes |
| [S3 XMP](../spikes/S3-xmp.md) | Yes |
| [S4 Embedded metadata](../spikes/S4-metadata.md) | Yes |
| [S5 Grouping](../spikes/S5-grouping.md) | Yes |
| [S6 Scan](../spikes/S6-scan.md) | Yes |
| [S7 Fold state](../spikes/S7-duo.md) | Part 1 only. The Duo run is pending ([#18](https://github.com/mimiqdev/cloveapp/issues/18)) |

All device numbers come from **one iPhone 17 Pro Max with local storage**. No SD card, SSD, iPad or Duo run has happened yet. Those checks are tracked in [#29](https://github.com/mimiqdev/cloveapp/issues/29). Every number below is a starting target, to be checked again when [#29](https://github.com/mimiqdev/cloveapp/issues/29) runs.

## 1. Focus

- **Primary input: camera files.** The owner's Sony A1 II writes ARW + `.HIF`, sometimes ARW + JPEG.
- **Supported sets:** RAW alone, RAW + JPEG, RAW + HIF, RAW + JPEG + HIF, and JPEG alone.
- **Later, only if it's really needed:**
  - HIF-only photos and iPhone HEIC. For now they appear if the system can show a preview. Their marks go to a sidecar. There's no in-file write and no extra work beyond that.
  - iPhone files in general. They wait for photo library support.
- **Not supported:** JPEG + HIF without a RAW. No special handling. Whatever the generic rules produce is acceptable.

## 2. Decided by the owner (2026-11-09)

1. **Which file is the photo.**
   - With a RAW, the RAW is the source of truth. Same-name JPEG and HIF files in the same folder are reference companions of that one photo.
   - Without a RAW, the JPEG is primary, then the HIF.
   - So RAW + JPEG + HIF is one photo with three files. *This replaces the spike proposal that made the HIF a standalone photo.*
2. **Where marks are written.**
   - If a RAW exists, marks always go in the same-name `.xmp` sidecar (`MMQ05184.ARW` → `MMQ05184.xmp`). The companions are never changed.
   - In-file metadata is considered only for a JPEG with no RAW (see §4).
3. **Order.**
   - Capture time with subseconds is the default order.
   - The grid never shows a temporary file-name order first.
   - If a photo has no capture time, use the file's creation time, then its modification time if there's no creation time. Such photos are sorted by that time but **never put in a burst group**, because a file time can drift from the real shot time.
   - *This relaxes S5/S6's "never use filesystem dates" rule, for sorting only.*
4. **Camera bodies in grouping.**
   - Photos are separated by camera model, plus the body serial when the file has one.
   - When the serial is missing, as on the A1 II, grouping falls back to the model.
   - Two bodies of the same model shooting the same scene at the same moment is not a supported case.
   - No extra work, UI or setting goes into this.
5. **Reject is the rating −1.** *(Revised 2026-11-11. The original decision kept Reject out of XMP; [the reject-as-rating record](reject-as-rating.md) supersedes it.)*
   - A photo's rating and Reject are one value: −1 is Rejected, 0 is unrated, and 1–5 are stars. The colour label stays independent.
   - Rejecting replaces the stars, and clearing Reject leaves the photo unrated. Undo restores the stars a Reject replaced.
   - Reject takes the rating's destination and never has a route of its own. A RAW set writes `xmp:Rating="-1"` to its sidecar (decision 2); a standalone JPEG/HIF keeps −1 in Clove storage (decision 6). There's no separate Reject field, no Clove namespace and no "Also write Rating −1" setting.
   - Reading −1 from a sidecar means Rejected. Other out-of-range values, such as `6` or `-2`, read as unrated and keep their bytes.
   - The move to `_Rejected` is still the durable Reject result. A moved set carries its `.xmp` with −1; undo of the move writes −1 again.
   - Other apps' handling of Reject is not a v1 goal, and there are no workarounds for Lightroom, Capture One or others.

## 3. Recommended by the spikes, accepted

| Area | Approach | Main evidence |
| --- | --- | --- |
| **XMP codec (C3)** | A validated, preserving custom editor. It changes only the fields Clove owns. It refuses malformed or ambiguous packets and keeps the requested marks so the user can retry. ImageIO whole-packet writing and the default Adobe SDK both lost data in testing, so neither is used. | S3: the only approach that kept every unknown byte, on Mac, simulator and iPhone |
| **Sidecar naming** | Replace the extension. Reuse an existing `.xmp`/`.XMP` spelling. Treat `NAME.ARW.xmp` or two competing packets as ambiguity, and never create a second packet. One sidecar per photo set; writes to it are serialized. | S3, S4, S6 |
| **Safe writes (C4)** | Write to a staging file in the same folder, sync it, then POSIX `rename`, then read the destination back. Show **Saved** only after that read-back matches. | S3: worked on local APFS. exFAT is pending in [#29](https://github.com/mimiqdev/cloveapp/issues/29) |
| **Preview, grid (I1)** | Embedded preview at about 400 px. For ARW + HIF, use the ARW's embedded preview, one cache entry per photo. Never fully decode a HIF. | S2: ARW 8.3 ms vs HIF 10.5 ms; full HIF decode 1.8 s |
| **Preview, detail (I2)** | Show the HIF's embedded preview first (1616 px, about 7 ms). Render the ARW with `CIRAWFilter` only when the zoom needs more pixels or on double-tap to 100% (about 0.53 s). | S2 |
| **Scheduling and cache** | Four grid workers, with a two-worker fallback. At most one RAW render at a time; stale work is cancelled. 64 MiB memory cache and 256 MiB disk cache for thumbnails; one 64 MiB LRU of compressed detail previews and RAW screen renders, encoded as JPEG at quality 0.9; and one native render held separately. | S2: 2,000 thumbnails take about 77 MiB on disk but about 922 MiB decoded |
| **Scan (C2)** | One `FileManager.enumerator` pass prefetching five keys (name, regular file, directory, size, modified). Skip `_Rejected` and `._` files. Match names case-insensitively within one folder. Streamed in batches of 64. Never asks the system for the file type. | S6: 22 ms for 2,000 files on Mac; the file-type key adds 178% |
| **Grouping (C9/I3)** | Separate by body, then join neighbours less than 2 s apart, then split where the Vision distance is above 0.5 (feature revision 2, 400 px previews). If Vision is unavailable, use a dHash fallback with a cut-off of 12 bits. With no usable feature, split. | S5: one 10-frame burst stayed together, and a photo 250 s later stayed separate |
| **Folder access (C11)** | Default bookmarks. Check with a real read before scanning. A stale bookmark means "refresh", not "permission lost". Never treat a same-name card as the same card. Keep a separate write status for each change. Watch for disconnects with presenters plus a 500 ms foreground poll. | S1: the iPhone local run passed. Card, reboot and disconnect checks are pending in [#29](https://github.com/mimiqdev/cloveapp/issues/29) |
| **Fold state (U1/P3/P4)** | Layout follows the available geometry. Hinge status uses the public API on iOS 27.1+, behind availability checks, so the minimum stays at **iOS 18**. Navigation and selection state live outside the layout. No hard-coded hinge position. | S7 part 1. The Duo run can still change this |

### Starting performance targets (iPhone, for M3 and Q3)

Engineering targets to evaluate, not launch promises. They are checked again when [#29](https://github.com/mimiqdev/cloveapp/issues/29)'s external-media and iPad runs happen.

| Stage | Target | Measured so far (iPhone, local) |
| --- | --- | --- |
| Scan: first photos delivered | ≤ 0.5 s | Mac: 3–8 ms |
| Scan: 2,000 files found and paired | ≤ 3 s | Mac: about 35 ms |
| Capture-time read | measure in I4 | 3.4 ms per file median, serial |
| Grid thumbnail, uncached, p95 | ≤ 150 ms | 8–11 ms median |
| Grid thumbnail, from disk cache, p95 | ≤ 20 ms | 1.7 ms median |
| Thumbnail throughput | ≥ 30/s | 288/s with 4 workers |
| First detail preview, p95 | ≤ 300 ms | 6–13 ms |
| Full RAW for focus checks, p95 | ≤ 2 s, including the wait for a cancelled render | 0.53 s, plus about 0.54 s for a cancelled render to finish |
| Vision feature per photo | measure in I3 | 3.3 ms median after a 7.5 ms preview read |

## 4. Also decided (2026-11-09)

6. **Standalone JPEG/HIF marks.** There's no `.xmp` for a JPEG or HIF without a RAW.
   - Clove reads any ratings and labels already embedded in the file.
   - New marks are kept in Clove, like Reject, with a visible "Saved in Clove only" status.
   - Why: Lightroom reads only embedded metadata for JPEG, Photo Mechanic embeds ratings in JPEG, and it's unclear whether Capture One creates a sidecar next to a JPEG. A sidecar there would mostly be read by Clove alone.
   - Writing into the JPEG (S4's lossless packet splice, task C7) is a later feature. HIF in-file writing stays out.
7. **Schedule and storage.** M2 and M3 start now. Removable media is not on the MVP critical path, and nothing waits for it.
   - The owner's camera media is a **CFexpress Type A card in a USB reader**. iOS treats that reader as an external drive, the same as an SSD. SD cards aren't the owner's workflow.
   - **G2** is the main path on the iPhone 17 Pro Max from any folder Files can open: local storage, or the CFexpress reader when it's at hand. It no longer requires an SD card or SSD.
   - The external-media checks in [#29](https://github.com/mimiqdev/cloveapp/issues/29) are non-blocking. Run them when convenient, using the CFexpress reader first.
   - The three desktop-app checks from S3 run before C3 is called done.

## 5. PRD edits that follow

- **Scan scope / Supported files.** Pairing covers RAW + JPEG, RAW + HIF and RAW + JPEG + HIF, with RAW as primary. HIF-only and iPhone HEIC are shown when possible but are deferred features. JPEG + HIF without a RAW is not supported.
- **Grid order.** Capture time, falling back to file creation time and then modification time. Fallback photos aren't grouped.
- **Rule 6 (standalone files).** Standalone JPEG/HIF get no sidecar. Clove reads their embedded marks and keeps new marks in Clove (decision 6). In-file JPEG writing is a later feature. Standalone DNG remains RAW and uses a sidecar.
- **Grouping.** Separate by model, plus serial when present. Two same-model bodies at the same moment is not supported. Starting values: 2 s gap and Vision distance 0.5.
- **Reject (P0-05, rule 5, Move rejects).** Reject is the rating value −1, written to the standard `xmp:Rating` field for a RAW set and kept in Clove for a standalone JPEG/HIF. Rejecting replaces the stars, and clearing Reject leaves the photo unrated. There is no Clove XMP field and no "Also write Rating −1" setting. A moved set carries its sidecar with −1, and undo writes −1 again. P0-07 interoperability covers the rating, Reject included, and colour labels.
- **Save status (P0-08).** "Saved" refers to XMP writes, meaning ratings (Reject included) and labels, and to the outcome of the reject move. A standalone mark confirmed in Clove is "Saved in Clove only". The third, Clove-stored Reject state is gone.
- **Open risks section.** The question "How do Bridge and Lightroom treat `Rating = -1`?" no longer blocks the design; v1 writes −1 in the standard field and adds no workarounds for other apps. The question "Can iOS write metadata without re-encoding?" is now answered: yes for JPEG via packet splice; no for HIF/HEIC through ImageIO, which drops data; no for DNG, which has no writer. The starting thresholds question is also answered.

## 6. Plan edits that follow ([`docs/DEV-PLAN.md`](../DEV-PLAN.md))

- **C1.** A photo item is a primary file plus optional JPEG and/or HIF companions and an optional sidecar. Ratings (Reject included as −1) and labels go to the sidecar for a RAW set and to Clove for a standalone JPEG/HIF, so Reject has no separate route.
- **C2.** Pairing follows decision 1. It takes over S6's handoff list, including sidecar discovery during the walk.
- **C3.** Ratings (Reject included as −1) and labels only. No Clove namespace and no separate Reject field.
- **C4.** One write path per storage: XMP writes confirmed by read-back, and standalone Clove marks confirmed by read-back. A reject's save state is the state of the storage its rating uses.
- **C6.** The move plan covers every file of a photo set: RAW, JPEG, HIF and `.xmp`. A moved RAW set carries its sidecar with −1; a standalone JPEG/HIF's stored −1 is cleared after the confirmed move, and undo writes −1 again.
- **C7.** Moved out of M2 into a later milestone: in-file JPEG writes.
- **C8.** Capture time, then file creation time, then modification time.
- **C9.** Separate by model, plus serial when present.
- **I4.** Reports whether each time comes from capture metadata or from the file system.

## 7. Still open after G1

- **[#29](https://github.com/mimiqdev/cloveapp/issues/29):** external-media, iPad and desktop-app checks. They're non-blocking, with the CFexpress Type A reader first. They can revise the C4/C11 details and the numeric targets.
- **[#18](https://github.com/mimiqdev/cloveapp/issues/18):** the S7 Duo run. It can change the fold-state approach (hinge exclusion, scene continuity).
- **[#23](https://github.com/mimiqdev/cloveapp/issues/23):** fixture provenance.
