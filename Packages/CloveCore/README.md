# CloveCore domain model

The value model implements [PRD P0-01/P0-05 and marking rules](../../docs/PRD.en.md)
and the [approved G1 decisions](../../docs/decisions/G1-technical-approach.md).
It does no file I/O and has no dependencies beyond Foundation.

- `FolderIdentity` wraps a durable opaque key established by bookmark handling.
  It must be reused when the same opened folder is restored. A volume name or
  display path alone must never establish that identity. `FolderSession` holds
  display hints separately from the key.
- `PhotoSet` accepts already paired RAW, JPEG and HIF/HEIF URLs in named slots,
  plus an optional resolved sidecar URL. It validates the single set; scanning,
  duplicate/competing-file discovery and preview support are separate concerns.
  The primary is RAW, otherwise JPEG, otherwise HIF. RAW+JPEG+HIF is one set.
  Unsupported JPEG+HIF without RAW follows the same rule: one JPEG-primary set
  with a HIF companion, with all new marks stored in Clove.
- `PhotoIdentity` combines the opaque opened-folder key, the relative containing
  folder path, and the primary's stem lowercased for case-insensitive pairing.
  The scanner supplies a consistent relative path without a trailing slash
  (empty at the opened root), preserving subfolder spelling. IDs do not depend
  on extension, display location, file dates, companion membership or sidecar
  discovery. Adding a differently cased RAW to a JPEG set keeps the ID stable.
  Image and discovered-sidecar URLs retain their actual spelling.
- `PhotoFormat.rawExtensions` is the single production RAW classification list:
  CR3, NEF, ARW, RAF, ORF, RW2 and DNG. The current PRD Supported files section
  names RAW generally rather than enumerating extensions; these seven match
  the existing fixture/scan baseline and the plan's fixture formats. They are
  not a guarantee of system decoding support. JPEG accepts JPG/JPEG and HEIF
  accepts HIF/HEIF/HEIC. Classification is case-insensitive and never requests
  content types.
- `Rating` accepts −1 to 5: −1 is Reject, 0 is unrated, and 1–5 are stars.
  `ColourLabel` preserves every external string exactly; `colour` recognizes
  only exact English names from `LabelColour`. Empty means clear. Unknown text,
  including differently cased names, remains a non-clear label. A codec must
  pass `rawValue` back unchanged when retaining that label. `PhotoMarks` holds
  one rating, which carries Reject, and one label; `isRejected` is computed.
- `photo.markPersistence` routes each mark independently. RAW rating (Reject
  included) and label writes target `xmpSidecar`, reusing a supplied sidecar URL
  or replacing the RAW extension with `.xmp`. A new standalone JPEG/HIF mark
  targets `cloveStorage`. Existing standalone embedded marks are read-only
  input. `MarkDestination` names the storage mechanism so later embedded JPEG
  writes can add a destination without replacing the routing interface.
- `fileURLs` includes only supplied image members and the resolved sidecar,
  useful for moving a complete set. A proposed XMP destination is not treated
  as a file that exists. The scanner/codec must still refuse ambiguity before
  routing a write; this model never searches for existing sidecar variants.

- `FolderScan` walks one opened folder in a single `FileManager.enumerator` pass,
  streams `ScanBatch` items in walk order, and ends with a `ScanSummary` (PRD scan
  scope, G1 scan approach). It prefetches only name, regular file, directory, size and
  modification date, and never asks for a file type or content type. Hidden entries,
  `._` files, package contents and the rejects folder are skipped;
  `ScanConfiguration.rejectsFolderName` replaces the default `_Rejected`, and
  `batchSize` is clamped to G1's 64. The caller supplies the readable folder URL and
  the `FolderIdentity`; access validation and bookmarks stay with C11.
- Pairing stays per folder and per case-folded stem, and the primary rule stays in
  `PhotoSet`; the scanner never re-derives it. A folder is reconciled only after the
  walk has left it, so every file of a stem group is known first and a set's members
  never split across batches, even when a subfolder is walked between two of them.
  Items keep the order in which each stem first appeared; display ordering is C8's.
  Two RAWs, two JPEGs or two HIF/HEIFs with one stem become `ScanItem.ambiguousStem`
  with every member URL and no set.
- `SidecarState` reports what the same walk found for a RAW set: no packet yet, one
  same-folder `<stem>.xmp` with its actual spelling, or competing packets that later
  tasks must refuse to write to. Competing means an appended-extension name such as
  `NAME.ARW.xmp` or two same-stem names on a case-sensitive volume. `.xmp` files are
  never photos and never unsupported files; a packet with no RAW in its stem group is
  counted as an orphan without an error (G1 sidecar naming, decision 6).
- `ScanItem` carries `ScannedImageFile` values, so size and modification date for each
  member come from the same walk that found it (I1's thumbnail revision). `ScanSummary`
  counts logical photos, unsupported files with their URLs, member and sidecar
  ambiguities, orphan sidecars and skipped folders, and is `complete` only when no read
  issue was recorded. `ScanIssue` keeps the failing URL and the `NSError` chain, and a
  partial walk is never reported as a complete one with fewer photos.
- `FolderScan` is an `AsyncSequence` of batches and supports cancellation: leaving the
  sequence early, or cancelling its consumer, stops the walk. Values are `Sendable`
  under Swift 6 strict concurrency and nothing is `@unchecked`.

The package uses Swift 6 and Sendable value types. Run `mise run test-core`
for domain tests and `mise run verify` for the repository acceptance gate. The scan
tests build throwaway trees; the fixture tests scan `card-basic`, `name-collision` and
`formats` when `mise run fixtures-sets` ran, and the timing test reports time to first
batch for 2,000 files without gating it.
