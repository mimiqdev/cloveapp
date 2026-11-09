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
- `Rating` accepts only 0–5. `ColourLabel` preserves every external string
  exactly; `colour` recognizes only exact English names from `LabelColour`.
  Empty means clear. Unknown text, including differently cased names, remains
  a non-clear label. A codec must pass `rawValue` back unchanged when retaining
  that label. `PhotoMarks` keeps rating, label and Reject independent.
- `photo.markPersistence` routes each mark independently. RAW rating/label
  writes target `xmpSidecar`, reusing a supplied sidecar URL or replacing the
  RAW extension with `.xmp`. Every Reject and every new standalone JPEG/HIF
  mark targets `cloveStorage`. Existing standalone embedded marks are read-only
  input. `MarkDestination` names the storage mechanism so later embedded JPEG
  writes can add a destination without replacing the routing interface.
- `fileURLs` includes only supplied image members and the resolved sidecar,
  useful for moving a complete set. A proposed XMP destination is not treated
  as a file that exists. The scanner/codec must still refuse ambiguity before
  routing a write; this model never searches for existing sidecar variants.

The package uses Swift 6 and Sendable value types. Run `mise run test-core`
for domain tests and `mise run verify` for the repository acceptance gate.
