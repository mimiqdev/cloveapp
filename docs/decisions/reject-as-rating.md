# Reject as the rating −1

Status: **approved by the product owner, 2026-11-11.** The matching [PRD](../PRD.en.md),
[G1 record](G1-technical-approach.md), plan and handoff edits land in the same pull request.
This record replaces G1 decision 5.

## Decision

A photo's rating and Reject are one value, the way Adobe Bridge stores Reject:

- `Rating` is −1 for Rejected, 0 for unrated and 1–5 for stars. `PhotoMarks` exposes
  `isRejected` as a computed property, so callers keep reading it.
- A photo is never rated and rejected at once. Rejecting replaces the stars; clearing Reject
  leaves the photo unrated; a star rating on a rejected photo replaces −1. The colour label
  stays independent.
- Reject takes the rating's storage and has no route of its own. A RAW set writes
  `xmp:Rating="-1"` to its shared sidecar through C4 and confirms it by read-back. A standalone
  JPEG/HIF keeps −1 in Clove storage, as G1 decision 6 says. One photo's marks therefore go to
  one storage.
- Reading −1 from a sidecar means Rejected. Any other out-of-range value, such as `6` or `-2`,
  keeps its old behaviour: it reads as unrated and stays on disk unchanged.
- Old Clove storage that holds a reject field still decodes, and the field is ignored. No
  migration runs, so rejects stored by TestFlight builds are dropped.

## Trade-off

- **The stars are lost on Reject.** A 3★ photo that becomes rejected has no stars any more,
  and clearing Reject leaves it unrated rather than restoring 3★. This is accepted: the two
  marks are one value, and the previous rating is not saved anywhere.
- **Undo restores the stars** a marking action replaced. Undoing a Reject returns the photo to
  the stars it had, because C5 records the marks before the action. Undoing a Move rejects
  writes −1 again; a photo kept in the move confirmation was set to 0, so its undo re-rejects
  it rather than recovering stars that the original Reject already replaced.
- **Interoperability with other apps is not a goal for v1.** Writing −1 is the standard field,
  and no workarounds are added for Lightroom, Capture One, Photo Mechanic or others. Rejected
  photos normally do not go on to another app.

## What this simplifies

- `MarkPersistence` has no reject destination, `MarkChange` has no reject field, and
  `CloveMarkStore` has no reject-only write. A RAW set's marks use the sidecar, so a reject is
  confirmed by the same read-back as any rating.
- The third save state, a reject that is confirmed in Clove but is not **Saved**, is gone.
  A reject reports the state of the storage its rating uses: **Saved** for a RAW set and
  **Saved in Clove only** for a standalone JPEG/HIF.
- Filters and counts fall out of the ordering: −1 sorts below unrated, so "N stars or higher"
  never includes a rejected photo, and a rejected photo is never unmarked.
- Coalescing merges one rating field instead of a rating and a Reject field, so a quick rating
  followed by Reject supersedes the waiting rating rather than writing both.
